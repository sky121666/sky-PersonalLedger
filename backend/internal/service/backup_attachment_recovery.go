package service

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"strconv"
	"strings"

	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

const (
	attachmentRestoreSettingPrefix = "attachment_restore:"
	attachmentRestoreSettingUpper  = "attachment_restore;"
)

type attachmentRestoreMarker struct {
	Generation        string `json:"generation"`
	StageDirectory    string `json:"stage_directory"`
	PreviousDirectory string `json:"previous_directory"`
}

func (p *attachmentRestorePlan) marker() attachmentRestoreMarker {
	return attachmentRestoreMarker{
		Generation:        p.generation,
		StageDirectory:    p.stageDirectory,
		PreviousDirectory: p.previousDirectory,
	}
}

func attachmentRestoreSettingKey(userID uint) string {
	return attachmentRestoreSettingPrefix + strconv.FormatUint(uint64(userID), 10)
}

func persistAttachmentRestoreMarkerTx(tx *gorm.DB, plan *attachmentRestorePlan) error {
	if plan == nil {
		return nil
	}
	if err := plan.validate(); err != nil {
		return err
	}
	value, err := json.Marshal(plan.marker())
	if err != nil {
		return err
	}
	setting := model.SystemSetting{
		Key:   attachmentRestoreSettingKey(plan.userID),
		Value: string(value),
	}
	return tx.Clauses(clause.OnConflict{
		Columns:   []clause.Column{{Name: "key"}},
		DoUpdates: clause.AssignmentColumns([]string{"value", "updated_at"}),
	}).Create(&setting).Error
}

// attachmentRestoreMarkerCommitted resolves the rare case where a database
// driver reports a commit error after the commit became durable. A matching
// permanent desired-generation record is the only signal that permits
// forward activation; uncertain reads leave the stage intact for startup.
func (s *BackupService) attachmentRestoreMarkerCommitted(plan *attachmentRestorePlan) (bool, error) {
	if s == nil || s.db == nil || plan == nil {
		return false, errors.New("attachment restore database is unavailable")
	}
	var setting model.SystemSetting
	err := s.db.Where("key = ?", attachmentRestoreSettingKey(plan.userID)).First(&setting).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	marker, err := decodeAttachmentRestoreMarker(plan.userID, setting.Value)
	if err != nil {
		return false, err
	}
	return marker.Generation == plan.generation &&
		marker.StageDirectory == plan.stageDirectory &&
		marker.PreviousDirectory == plan.previousDirectory, nil
}

func decodeAttachmentRestoreMarker(userID uint, value string) (attachmentRestoreMarker, error) {
	var marker attachmentRestoreMarker
	if err := json.Unmarshal([]byte(value), &marker); err != nil {
		return marker, errors.New("invalid attachment restore marker")
	}
	plan := &attachmentRestorePlan{
		userID:            userID,
		userDirectory:     strconv.FormatUint(uint64(userID), 10),
		generation:        marker.Generation,
		stageDirectory:    marker.StageDirectory,
		previousDirectory: marker.PreviousDirectory,
	}
	if err := plan.validate(); err != nil {
		return marker, fmt.Errorf("invalid attachment restore marker: %w", err)
	}
	return marker, nil
}

// RecoverAttachmentRestores must run before routes, schedulers, and upload GC.
// It follows only committed desired generations and never rolls active files
// back to a previous directory. A recovery failure blocks startup so database
// references cannot be served against an indeterminate attachment generation.
func (s *BackupService) RecoverAttachmentRestores() error {
	if s == nil || s.db == nil {
		return errors.New("backup service database is unavailable")
	}
	s.restoreMu.Lock()
	defer s.restoreMu.Unlock()
	releaseStorage := acquireAttachmentStorageWrite()
	defer releaseStorage()

	var settings []model.SystemSetting
	if err := s.db.Where("key >= ? AND key < ?", attachmentRestoreSettingPrefix, attachmentRestoreSettingUpper).Order("key ASC").Find(&settings).Error; err != nil {
		return fmt.Errorf("load attachment restore state: %w", err)
	}
	if !s.hasUploadStorage() {
		if len(settings) == 0 {
			return nil
		}
		return errors.New("committed attachment restore state exists but upload storage is unavailable")
	}

	referencedStages := make(map[string]struct{}, len(settings))
	for _, setting := range settings {
		userID, err := attachmentRestoreUserID(setting.Key)
		if err != nil {
			return err
		}
		marker, err := decodeAttachmentRestoreMarker(userID, setting.Value)
		if err != nil {
			return err
		}
		referencedStages[marker.StageDirectory] = struct{}{}

		root, err := os.OpenRoot(s.uploadService.cfg.UploadPath)
		if err != nil {
			return fmt.Errorf("open upload root for attachment recovery: %w", err)
		}
		plan := &attachmentRestorePlan{
			root:              root,
			userID:            userID,
			userDirectory:     strconv.FormatUint(uint64(userID), 10),
			generation:        marker.Generation,
			stageDirectory:    marker.StageDirectory,
			previousDirectory: marker.PreviousDirectory,
		}
		commit := s.attachmentCommit
		if commit == nil {
			commit = func(plan *attachmentRestorePlan) error { return plan.commit() }
		}
		commitErr := errors.Join(commit(plan), plan.close())
		if commitErr != nil {
			active, activeErr := s.attachmentRestoreGenerationActive(plan)
			if !errors.Is(commitErr, ErrAttachmentRecoveryPending) && active {
				s.cleanupWarning(fmt.Errorf("cleanup recovered attachment generation for user %d: %w", userID, errors.Join(commitErr, activeErr)))
				clearAttachmentRecoveryPending(userID)
				continue
			}
			markAttachmentRecoveryPending(userID)
			return fmt.Errorf("recover attachment generation for user %d: %w", userID, errors.Join(commitErr, activeErr))
		}
		clearAttachmentRecoveryPending(userID)
	}

	cleanup := s.orphanStageCleanup
	if cleanup == nil {
		cleanup = s.cleanupOrphanAttachmentStages
	}
	if err := cleanup(referencedStages); err != nil {
		// Every committed desired generation is already active and verified at
		// this point. Orphan stage removal is best-effort housekeeping; failing
		// startup here would not improve database/file consistency.
		s.cleanupWarning(fmt.Errorf("cleanup orphan attachment restore stages: %w", err))
	}
	return nil
}

func (s *BackupService) retryCommittedAttachmentRestore(original *attachmentRestorePlan) error {
	root, err := os.OpenRoot(s.uploadService.cfg.UploadPath)
	if err != nil {
		return fmt.Errorf("%w: open upload root for retry: %v", ErrAttachmentRecoveryPending, err)
	}
	retry := &attachmentRestorePlan{
		root:              root,
		userID:            original.userID,
		userDirectory:     original.userDirectory,
		generation:        original.generation,
		stageDirectory:    original.stageDirectory,
		previousDirectory: original.previousDirectory,
	}
	return retry.commit()
}

func (s *BackupService) attachmentRestoreGenerationActive(plan *attachmentRestorePlan) (active bool, returnErr error) {
	root, err := os.OpenRoot(s.uploadService.cfg.UploadPath)
	if err != nil {
		return false, err
	}
	defer func() {
		returnErr = errors.Join(returnErr, root.Close())
	}()
	generation, err := readAttachmentRestoreGeneration(root, plan.userDirectory)
	if errors.Is(err, os.ErrNotExist) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return generation == plan.generation, nil
}

func attachmentRestoreUserID(key string) (uint, error) {
	if !strings.HasPrefix(key, attachmentRestoreSettingPrefix) {
		return 0, errors.New("invalid attachment restore setting key")
	}
	value := strings.TrimPrefix(key, attachmentRestoreSettingPrefix)
	parsed, err := strconv.ParseUint(value, 10, 0)
	if err != nil || parsed == 0 {
		return 0, errors.New("invalid attachment restore setting key")
	}
	return uint(parsed), nil
}

func (s *BackupService) cleanupOrphanAttachmentStages(referenced map[string]struct{}) (returnErr error) {
	root, err := os.OpenRoot(s.uploadService.cfg.UploadPath)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil
		}
		return err
	}
	defer func() {
		returnErr = errors.Join(returnErr, root.Close())
	}()

	entries, err := fs.ReadDir(root.FS(), ".")
	if err != nil {
		return err
	}
	var cleanupErr error
	removed := false
	for _, entry := range entries {
		name := entry.Name()
		if !strings.HasPrefix(name, ".restore-stage-") {
			continue
		}
		if _, keep := referenced[name]; keep {
			continue
		}
		if err := removeRootEntry(root, name); err != nil {
			cleanupErr = errors.Join(cleanupErr, err)
			continue
		}
		removed = true
	}
	if removed {
		cleanupErr = errors.Join(cleanupErr, syncRootDirectory(root, "."))
	}
	return cleanupErr
}
