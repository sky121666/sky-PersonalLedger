package service

import (
	"fmt"
	"os"
	"sync"
	"time"

	"github.com/sky/personal-ledger/internal/database"
	"gorm.io/gorm"
)

type HealthService struct {
	db                *gorm.DB
	uploadPath        string
	backupPath        string
	storageMu         sync.Mutex
	lastStorageCheck  time.Time
	cachedUploadCheck HealthCheck
	cachedBackupCheck HealthCheck
}

const storageReadinessCacheTTL = 5 * time.Second

type HealthStatus struct {
	Status                string                 `json:"status"`
	CurrentSchemaVersion  int                    `json:"current_schema_version"`
	DatabaseSchemaVersion int                    `json:"database_schema_version"`
	Checks                map[string]HealthCheck `json:"checks"`
}

type HealthCheck struct {
	Status  string `json:"status"`
	Message string `json:"message,omitempty"`
}

func NewHealthService(db *gorm.DB, uploadPath string, backupPath string) *HealthService {
	return &HealthService{
		db:         db,
		uploadPath: uploadPath,
		backupPath: backupPath,
	}
}

func (s *HealthService) Check() HealthStatus {
	status := HealthStatus{
		Status:               "ok",
		CurrentSchemaVersion: database.CurrentSchemaVersion(),
		Checks:               make(map[string]HealthCheck),
	}

	if err := s.checkDatabase(&status); err != nil {
		status.Status = "unhealthy"
		status.Checks["database"] = HealthCheck{Status: "fail", Message: "database check failed"}
	} else {
		status.Checks["database"] = HealthCheck{Status: "ok"}
	}

	status.Checks["uploads"], status.Checks["backups"] = s.checkStorageDirectories()
	for _, check := range status.Checks {
		if check.Status == "fail" {
			status.Status = "unhealthy"
			break
		}
	}
	return status
}

func (s *HealthService) checkStorageDirectories() (HealthCheck, HealthCheck) {
	s.storageMu.Lock()
	defer s.storageMu.Unlock()

	now := time.Now()
	cacheAge := now.Sub(s.lastStorageCheck)
	if !s.lastStorageCheck.IsZero() && cacheAge >= 0 && cacheAge < storageReadinessCacheTTL {
		return s.cachedUploadCheck, s.cachedBackupCheck
	}
	s.cachedUploadCheck = checkDirectory(s.uploadPath)
	s.cachedBackupCheck = checkDirectory(s.backupPath)
	s.lastStorageCheck = now
	return s.cachedUploadCheck, s.cachedBackupCheck
}

func (s *HealthService) checkDatabase(status *HealthStatus) error {
	sqlDB, err := s.db.DB()
	if err != nil {
		return err
	}
	if err := sqlDB.Ping(); err != nil {
		return err
	}

	version, err := database.LatestSchemaVersion(s.db)
	if err != nil {
		return err
	}
	status.DatabaseSchemaVersion = version
	if version > database.CurrentSchemaVersion() {
		return fmt.Errorf("database schema version %d is newer than application schema version %d", version, database.CurrentSchemaVersion())
	}
	return nil
}

func checkDirectory(path string) HealthCheck {
	if path == "" {
		return HealthCheck{Status: "ok", Message: "not configured"}
	}
	info, err := os.Stat(path)
	if err != nil {
		return HealthCheck{Status: "fail", Message: "directory is not accessible"}
	}
	if !info.IsDir() {
		return HealthCheck{Status: "fail", Message: "not a directory"}
	}
	if err := probeDirectoryWrite(path); err != nil {
		return HealthCheck{Status: "fail", Message: "directory is not writable"}
	}
	return HealthCheck{Status: "ok"}
}

func probeDirectoryWrite(path string) error {
	file, err := os.CreateTemp(path, ".ledger-readiness-*")
	if err != nil {
		return err
	}
	probePath := file.Name()
	defer func() {
		_ = file.Close()
		_ = os.Remove(probePath)
	}()

	if err := file.Chmod(0600); err != nil {
		return err
	}
	if _, err := file.Write([]byte{0}); err != nil {
		return err
	}
	if err := file.Sync(); err != nil {
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	return os.Remove(probePath)
}
