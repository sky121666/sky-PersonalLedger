package service

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/sky/personal-ledger/internal/model"
)

func (s *UploadService) IsReferenced(userID uint, relativePath string) (bool, error) {
	if s == nil || s.db == nil {
		return false, nil
	}
	references, err := s.referencedUploadPaths(userID)
	if err != nil {
		return false, err
	}
	_, referenced := references[normalizeStoredUploadReference(relativePath)]
	return referenced, nil
}

func (s *UploadService) CollectOrphanedFiles(userID uint, olderThan time.Time) ([]string, error) {
	if s == nil || s.cfg == nil || s.db == nil {
		return nil, nil
	}
	references, err := s.referencedUploadPaths(userID)
	if err != nil {
		return nil, err
	}
	userRoot := filepath.Join(s.cfg.UploadPath, fmt.Sprintf("%d", userID))
	removed := make([]string, 0)
	err = filepath.WalkDir(userRoot, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			if errors.Is(walkErr, os.ErrNotExist) {
				return nil
			}
			return walkErr
		}
		if entry.IsDir() {
			if entry.Type()&os.ModeSymlink != 0 {
				return filepath.SkipDir
			}
			return nil
		}
		if entry.Type()&os.ModeSymlink != 0 {
			return nil
		}
		info, err := entry.Info()
		if err != nil {
			return err
		}
		if info.ModTime().After(olderThan) {
			return nil
		}
		relativePath, err := filepath.Rel(s.cfg.UploadPath, path)
		if err != nil {
			return err
		}
		normalized := normalizeStoredUploadReference(relativePath)
		if _, referenced := references[normalized]; referenced {
			return nil
		}
		if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
			return err
		}
		removed = append(removed, normalized)
		return nil
	})
	if errors.Is(err, os.ErrNotExist) {
		return removed, nil
	}
	return removed, err
}

func (s *UploadService) referencedUploadPaths(userID uint) (map[string]struct{}, error) {
	references := make(map[string]struct{})
	addSingle := func(value string) {
		if normalized := normalizeStoredUploadReference(value); normalized != "" {
			references[normalized] = struct{}{}
		}
	}
	addLists := func(values []string) {
		for _, value := range values {
			for _, path := range decodeStoredUploadReferences(value) {
				addSingle(path)
			}
		}
	}

	var userAvatars []string
	if err := s.db.Model(&model.User{}).Where("id = ?", userID).Pluck("avatar", &userAvatars).Error; err != nil {
		return nil, err
	}
	for _, value := range userAvatars {
		addSingle(value)
	}

	var familyAvatars []string
	if err := s.db.Model(&model.FamilyMember{}).Where("user_id = ?", userID).Pluck("avatar", &familyAvatars).Error; err != nil {
		return nil, err
	}
	for _, value := range familyAvatars {
		addSingle(value)
	}

	for _, query := range []struct {
		model  any
		column string
	}{
		{model: &model.Transaction{}, column: "images"},
		{model: &model.Reminder{}, column: "evidence"},
		{model: &model.Lending{}, column: "evidence"},
		{model: &model.LendingRecord{}, column: "evidence"},
	} {
		var values []string
		if err := s.db.Model(query.model).Where("user_id = ?", userID).Pluck(query.column, &values).Error; err != nil {
			return nil, err
		}
		addLists(values)
	}
	return references, nil
}

func decodeStoredUploadReferences(value string) []string {
	var values []string
	if err := json.Unmarshal([]byte(value), &values); err == nil {
		return values
	}
	return strings.Split(value, ",")
}

func normalizeStoredUploadReference(value string) string {
	normalized := strings.TrimSpace(value)
	if strings.HasPrefix(normalized, "/uploads/") {
		normalized = strings.TrimPrefix(normalized, "/uploads/")
	} else if strings.Contains(normalized, "://") || strings.HasPrefix(normalized, "/") {
		return ""
	}
	if normalized == "" {
		return ""
	}
	cleaned := filepath.Clean(filepath.FromSlash(normalized))
	if cleaned == "." || cleaned == ".." || filepath.IsAbs(cleaned) || strings.HasPrefix(cleaned, ".."+string(os.PathSeparator)) {
		return ""
	}
	return filepath.ToSlash(cleaned)
}
