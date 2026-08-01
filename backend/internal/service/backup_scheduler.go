package service

import (
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/sky/personal-ledger/internal/repository"
)

var ErrAutoBackupSettingsInvalid = errors.New("invalid auto backup settings")

const (
	defaultAutoBackupFrequency = "daily"
	defaultAutoBackupHour      = 3
	defaultAutoBackupMaxFiles  = 10
	maxAutoBackupFiles         = 365
)

type BackupScheduler struct {
	backupService *BackupService
	systemRepo    *repository.SystemRepository
	userRepo      *repository.UserRepository
	backupPath    string
	stopChan      chan struct{}
	mu            sync.Mutex
	backupMu      sync.Mutex
	settingsMu    sync.Mutex
	running       bool
	createBackup  func(userID uint) (*FullBackupData, error)
	marshalBackup func(v any, prefix, indent string) ([]byte, error)
	writeBackup   func(filePath string, data []byte) error
	now           func() time.Time
}

type AutoBackupSettings struct {
	Enabled    bool   `json:"enabled"`
	Frequency  string `json:"frequency"` // daily, weekly, monthly
	Hour       int    `json:"hour"`      // 0-23
	MaxBackups int    `json:"max_backups"`
	LastBackup string `json:"last_backup,omitempty"`
}

func NewBackupScheduler(backupService *BackupService, systemRepo *repository.SystemRepository, userRepo *repository.UserRepository, backupPath string) *BackupScheduler {
	return &BackupScheduler{
		backupService: backupService,
		systemRepo:    systemRepo,
		userRepo:      userRepo,
		backupPath:    backupPath,
		stopChan:      make(chan struct{}),
		createBackup:  backupService.CreateBackup,
		marshalBackup: json.MarshalIndent,
		writeBackup:   writeFileAtomically,
		now:           time.Now,
	}
}

func (s *BackupScheduler) Start() {
	s.mu.Lock()
	if s.running {
		s.mu.Unlock()
		return
	}
	s.running = true
	s.mu.Unlock()

	go s.run()
}

func (s *BackupScheduler) Stop() {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.running {
		close(s.stopChan)
		s.running = false
	}
}

func (s *BackupScheduler) run() {
	ticker := time.NewTicker(1 * time.Hour)
	defer ticker.Stop()

	// Check immediately on start
	s.checkAndBackup()

	for {
		select {
		case <-ticker.C:
			s.checkAndBackup()
		case <-s.stopChan:
			return
		}
	}
}

func (s *BackupScheduler) checkAndBackup() {
	settings, err := s.GetSettings()
	if err != nil || !settings.Enabled {
		return
	}

	now := s.now()

	// Check if it's the right hour
	if now.Hour() != settings.Hour {
		return
	}

	// Check if we should backup based on frequency
	shouldBackup := false
	if settings.LastBackup == "" {
		shouldBackup = true
	} else {
		lastBackup, err := time.ParseInLocation("2006-01-02 15:04:05", settings.LastBackup, now.Location())
		if err != nil {
			shouldBackup = true
		} else {
			shouldBackup = autoBackupDue(now, lastBackup, settings.Frequency)
		}
	}

	if shouldBackup {
		if err := s.performBackup(settings); err != nil {
			log.Printf("Warning: automatic backup failed: %v", err)
		}
	}
}

func (s *BackupScheduler) performBackup(settings *AutoBackupSettings) error {
	s.backupMu.Lock()
	defer s.backupMu.Unlock()

	if settings == nil {
		return ErrAutoBackupSettingsInvalid
	}

	// Get all users
	users, err := s.userRepo.GetAll()
	if err != nil {
		return fmt.Errorf("list users for automatic backup: %w", err)
	}
	if len(users) == 0 {
		return errors.New("no users available for automatic backup")
	}

	// Create backup directory if not exists
	if err := os.MkdirAll(s.backupPath, 0755); err != nil {
		return fmt.Errorf("create automatic backup directory: %w", err)
	}

	createdFiles := make([]string, 0, len(users))
	rollback := func(backupErr error) error {
		if err := removeBackupFiles(createdFiles); err != nil {
			return errors.Join(backupErr, fmt.Errorf("remove incomplete automatic backup files: %w", err))
		}
		return backupErr
	}
	runTimestamp := s.now().Format("20060102_150405.000000000")

	for _, user := range users {
		backup, err := s.createBackup(user.ID)
		if err != nil {
			return rollback(fmt.Errorf("create automatic backup for user %d: %w", user.ID, err))
		}

		// Save backup to file
		filename := fmt.Sprintf("auto_backup_user%d_%s.json", user.ID, runTimestamp)
		filePath := filepath.Join(s.backupPath, filename)

		data, err := s.marshalBackup(backup, "", "  ")
		if err != nil {
			return rollback(fmt.Errorf("serialize automatic backup for user %d: %w", user.ID, err))
		}
		if err := s.validateSerializedBackupSize(data); err != nil {
			return rollback(fmt.Errorf("validate automatic backup size for user %d: %w", user.ID, err))
		}

		if err := s.writeBackup(filePath, data); err != nil {
			return rollback(fmt.Errorf("write automatic backup for user %d: %w", user.ID, err))
		}
		createdFiles = append(createdFiles, filePath)
	}

	// Merge only LastBackup into the latest persisted settings so a long-running
	// backup cannot overwrite configuration changed through the API mid-run.
	lastBackup := s.now().Format("2006-01-02 15:04:05")
	latestSettings, err := s.recordSuccessfulBackup(settings, lastBackup)
	if err != nil {
		return rollback(fmt.Errorf("save automatic backup settings: %w", err))
	}
	settings.LastBackup = lastBackup

	// Retention cleanup is best effort after the complete backup is committed.
	for _, user := range users {
		if err := s.cleanupOldBackups(user.ID, latestSettings.MaxBackups); err != nil {
			log.Printf("Warning: failed to clean up old automatic backups for user %d: %v", user.ID, err)
		}
	}
	return nil
}

func autoBackupDue(now, lastBackup time.Time, frequency string) bool {
	switch frequency {
	case "daily":
		return calendarDayDifference(lastBackup, now) >= 1
	case "weekly":
		return calendarDayDifference(lastBackup, now) >= 7
	case "monthly":
		lastMonth := lastBackup.Year()*12 + int(lastBackup.Month())
		currentMonth := now.Year()*12 + int(now.Month())
		return currentMonth > lastMonth
	default:
		return false
	}
}

func removeBackupFiles(paths []string) error {
	var cleanupErr error
	for _, path := range paths {
		if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
			cleanupErr = errors.Join(cleanupErr, err)
		}
	}
	return cleanupErr
}

func (s *BackupScheduler) cleanupOldBackups(userID uint, maxBackups int) error {
	if maxBackups <= 0 {
		maxBackups = 10
	}

	pattern := filepath.Join(s.backupPath, fmt.Sprintf("auto_backup_user%d_*.json", userID))
	files, err := filepath.Glob(pattern)
	if err != nil {
		return err
	}

	if len(files) <= maxBackups {
		return nil
	}

	// Sort by modification time (oldest first) and remove excess
	type fileInfo struct {
		path    string
		modTime time.Time
	}
	var infos []fileInfo
	var cleanupErr error
	for _, f := range files {
		info, err := os.Stat(f)
		if err != nil {
			cleanupErr = errors.Join(cleanupErr, err)
			continue
		}
		infos = append(infos, fileInfo{path: f, modTime: info.ModTime()})
	}

	// Sort by modTime ascending
	for i := 0; i < len(infos)-1; i++ {
		for j := i + 1; j < len(infos); j++ {
			if infos[i].modTime.After(infos[j].modTime) {
				infos[i], infos[j] = infos[j], infos[i]
			}
		}
	}

	// Delete oldest files
	toDelete := len(infos) - maxBackups
	for i := 0; i < toDelete; i++ {
		if err := os.Remove(infos[i].path); err != nil {
			cleanupErr = errors.Join(cleanupErr, err)
		}
	}
	return cleanupErr
}

func (s *BackupScheduler) GetSettings() (*AutoBackupSettings, error) {
	s.settingsMu.Lock()
	defer s.settingsMu.Unlock()

	settings, _, err := s.loadSettingsLocked()
	return settings, err
}

func (s *BackupScheduler) loadSettingsLocked() (*AutoBackupSettings, bool, error) {
	value, err := s.systemRepo.Get("auto_backup")
	if err != nil {
		return defaultAutoBackupSettings(), false, err
	}
	if value == "" {
		return defaultAutoBackupSettings(), false, nil
	}

	var settings AutoBackupSettings
	if err := json.Unmarshal([]byte(value), &settings); err != nil {
		return defaultAutoBackupSettings(), true, nil
	}
	if err := normalizeAutoBackupSettings(&settings, true); err != nil {
		return defaultAutoBackupSettings(), true, nil
	}

	return &settings, true, nil
}

func (s *BackupScheduler) SaveSettings(settings *AutoBackupSettings) error {
	s.settingsMu.Lock()
	defer s.settingsMu.Unlock()

	if settings == nil {
		return ErrAutoBackupSettingsInvalid
	}
	if settings.LastBackup == "" {
		current, exists, err := s.loadSettingsLocked()
		if err != nil {
			return err
		}
		if exists {
			settings.LastBackup = current.LastBackup
		}
	}
	return s.saveSettingsLocked(settings)
}

func (s *BackupScheduler) saveSettingsLocked(settings *AutoBackupSettings) error {
	if err := normalizeAutoBackupSettings(settings, false); err != nil {
		return err
	}
	data, err := json.Marshal(settings)
	if err != nil {
		return err
	}

	return s.systemRepo.Set("auto_backup", string(data))
}

func (s *BackupScheduler) recordSuccessfulBackup(fallback *AutoBackupSettings, lastBackup string) (*AutoBackupSettings, error) {
	s.settingsMu.Lock()
	defer s.settingsMu.Unlock()

	settings, exists, err := s.loadSettingsLocked()
	if err != nil {
		return nil, err
	}
	if !exists {
		if fallback == nil {
			return nil, ErrAutoBackupSettingsInvalid
		}
		copy := *fallback
		settings = &copy
	}
	settings.LastBackup = lastBackup
	if err := s.saveSettingsLocked(settings); err != nil {
		return nil, err
	}
	return settings, nil
}

func (s *BackupScheduler) TriggerBackup() error {
	settings, err := s.GetSettings()
	if err != nil {
		return err
	}
	return s.performBackup(settings)
}

func (s *BackupScheduler) CreatePreRestoreBackup(userID uint) (*BackupFileInfo, error) {
	if s.backupPath == "" {
		return nil, fmt.Errorf("backup path is empty")
	}
	if err := os.MkdirAll(s.backupPath, 0755); err != nil {
		return nil, err
	}

	backup, err := s.createBackup(userID)
	if err != nil {
		return nil, err
	}
	filename := fmt.Sprintf("pre_restore_backup_user%d_%s.json", userID, time.Now().Format("20060102_150405"))
	filePath := filepath.Join(s.backupPath, filename)
	data, err := s.marshalBackup(backup, "", "  ")
	if err != nil {
		return nil, err
	}
	if err := s.validateSerializedBackupSize(data); err != nil {
		return nil, err
	}
	if err := s.writeBackup(filePath, data); err != nil {
		return nil, err
	}
	info, err := os.Stat(filePath)
	if err != nil {
		return nil, err
	}
	return &BackupFileInfo{
		Filename:  filename,
		Size:      info.Size(),
		CreatedAt: info.ModTime().Format("2006-01-02 15:04:05"),
	}, nil
}

func (s *BackupScheduler) validateSerializedBackupSize(data []byte) error {
	if s == nil || s.backupService == nil {
		return nil
	}
	if int64(len(data)) > s.backupService.MaxRestoreBytes() {
		return ErrBackupFileTooLarge
	}
	return nil
}

func writeFileAtomically(filePath string, data []byte) error {
	dir := filepath.Dir(filePath)
	tempFile, err := os.CreateTemp(dir, "."+filepath.Base(filePath)+".tmp-*")
	if err != nil {
		return err
	}
	tempPath := tempFile.Name()
	defer func() {
		_ = tempFile.Close()
		if tempPath != "" {
			_ = os.Remove(tempPath)
		}
	}()

	if err := tempFile.Chmod(0600); err != nil {
		return err
	}
	if _, err := tempFile.Write(data); err != nil {
		return err
	}
	if err := tempFile.Sync(); err != nil {
		return err
	}
	if err := tempFile.Close(); err != nil {
		return err
	}
	if err := os.Rename(tempPath, filePath); err != nil {
		return err
	}
	tempPath = ""
	return nil
}

func (s *BackupScheduler) ListBackups() ([]BackupFileInfo, error) {
	files, err := filepath.Glob(filepath.Join(s.backupPath, "auto_backup_*.json"))
	if err != nil {
		return nil, err
	}

	var result []BackupFileInfo
	for _, f := range files {
		info, err := os.Stat(f)
		if err != nil {
			continue
		}
		result = append(result, BackupFileInfo{
			Filename:  filepath.Base(f),
			Size:      info.Size(),
			CreatedAt: info.ModTime().Format("2006-01-02 15:04:05"),
		})
	}

	return result, nil
}

type BackupFileInfo struct {
	Filename  string `json:"filename"`
	Size      int64  `json:"size"`
	CreatedAt string `json:"created_at"`
}

func defaultAutoBackupSettings() *AutoBackupSettings {
	return &AutoBackupSettings{
		Enabled:    false,
		Frequency:  defaultAutoBackupFrequency,
		Hour:       defaultAutoBackupHour,
		MaxBackups: defaultAutoBackupMaxFiles,
	}
}

func normalizeAutoBackupSettings(settings *AutoBackupSettings, allowDefaults bool) error {
	if settings == nil {
		return ErrAutoBackupSettingsInvalid
	}
	settings.Frequency = strings.TrimSpace(settings.Frequency)
	if settings.Frequency == "" && allowDefaults {
		settings.Frequency = defaultAutoBackupFrequency
	}
	switch settings.Frequency {
	case "daily", "weekly", "monthly":
	default:
		return ErrAutoBackupSettingsInvalid
	}

	if settings.Hour < 0 || settings.Hour > 23 {
		return ErrAutoBackupSettingsInvalid
	}

	if settings.MaxBackups <= 0 && allowDefaults {
		settings.MaxBackups = defaultAutoBackupMaxFiles
	}
	if settings.MaxBackups < 1 || settings.MaxBackups > maxAutoBackupFiles {
		return ErrAutoBackupSettingsInvalid
	}
	settings.LastBackup = strings.TrimSpace(settings.LastBackup)
	return nil
}
