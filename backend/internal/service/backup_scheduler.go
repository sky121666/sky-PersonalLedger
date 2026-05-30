package service

import (
	"encoding/json"
	"errors"
	"fmt"
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
	running       bool
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

	now := time.Now()

	// Check if it's the right hour
	if now.Hour() != settings.Hour {
		return
	}

	// Check if we should backup based on frequency
	shouldBackup := false
	if settings.LastBackup == "" {
		shouldBackup = true
	} else {
		lastBackup, err := time.Parse("2006-01-02 15:04:05", settings.LastBackup)
		if err != nil {
			shouldBackup = true
		} else {
			switch settings.Frequency {
			case "daily":
				shouldBackup = now.Sub(lastBackup) >= 23*time.Hour
			case "weekly":
				shouldBackup = now.Sub(lastBackup) >= 6*24*time.Hour
			case "monthly":
				shouldBackup = now.Sub(lastBackup) >= 29*24*time.Hour
			}
		}
	}

	if shouldBackup {
		s.performBackup(settings)
	}
}

func (s *BackupScheduler) performBackup(settings *AutoBackupSettings) {
	// Get all users
	users, err := s.userRepo.GetAll()
	if err != nil {
		return
	}

	// Create backup directory if not exists
	if err := os.MkdirAll(s.backupPath, 0755); err != nil {
		return
	}

	for _, user := range users {
		backup, err := s.backupService.CreateBackup(user.ID)
		if err != nil {
			continue
		}

		// Save backup to file
		filename := fmt.Sprintf("auto_backup_user%d_%s.json", user.ID, time.Now().Format("20060102_150405"))
		filePath := filepath.Join(s.backupPath, filename)

		data, err := json.MarshalIndent(backup, "", "  ")
		if err != nil {
			continue
		}

		if err := os.WriteFile(filePath, data, 0644); err != nil {
			continue
		}

		// Clean up old backups
		s.cleanupOldBackups(user.ID, settings.MaxBackups)
	}

	// Update last backup time
	settings.LastBackup = time.Now().Format("2006-01-02 15:04:05")
	s.SaveSettings(settings)
}

func (s *BackupScheduler) cleanupOldBackups(userID uint, maxBackups int) {
	if maxBackups <= 0 {
		maxBackups = 10
	}

	pattern := filepath.Join(s.backupPath, fmt.Sprintf("auto_backup_user%d_*.json", userID))
	files, err := filepath.Glob(pattern)
	if err != nil {
		return
	}

	if len(files) <= maxBackups {
		return
	}

	// Sort by modification time (oldest first) and remove excess
	type fileInfo struct {
		path    string
		modTime time.Time
	}
	var infos []fileInfo
	for _, f := range files {
		info, err := os.Stat(f)
		if err == nil {
			infos = append(infos, fileInfo{path: f, modTime: info.ModTime()})
		}
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
		os.Remove(infos[i].path)
	}
}

func (s *BackupScheduler) GetSettings() (*AutoBackupSettings, error) {
	value, err := s.systemRepo.Get("auto_backup")
	if err != nil || value == "" {
		return defaultAutoBackupSettings(), nil
	}

	var settings AutoBackupSettings
	if err := json.Unmarshal([]byte(value), &settings); err != nil {
		return defaultAutoBackupSettings(), nil
	}
	if err := normalizeAutoBackupSettings(&settings, true); err != nil {
		return defaultAutoBackupSettings(), nil
	}

	return &settings, nil
}

func (s *BackupScheduler) SaveSettings(settings *AutoBackupSettings) error {
	if err := normalizeAutoBackupSettings(settings, false); err != nil {
		return err
	}
	data, err := json.Marshal(settings)
	if err != nil {
		return err
	}

	return s.systemRepo.Set("auto_backup", string(data))
}

func (s *BackupScheduler) TriggerBackup() error {
	settings, err := s.GetSettings()
	if err != nil {
		settings = defaultAutoBackupSettings()
	}
	s.performBackup(settings)
	return nil
}

func (s *BackupScheduler) CreatePreRestoreBackup(userID uint) (*BackupFileInfo, error) {
	if s.backupPath == "" {
		return nil, fmt.Errorf("backup path is empty")
	}
	if err := os.MkdirAll(s.backupPath, 0755); err != nil {
		return nil, err
	}

	backup, err := s.backupService.CreateBackup(userID)
	if err != nil {
		return nil, err
	}
	filename := fmt.Sprintf("pre_restore_backup_user%d_%s.json", userID, time.Now().Format("20060102_150405"))
	filePath := filepath.Join(s.backupPath, filename)
	data, err := json.MarshalIndent(backup, "", "  ")
	if err != nil {
		return nil, err
	}
	if err := os.WriteFile(filePath, data, 0600); err != nil {
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
