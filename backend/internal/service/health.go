package service

import (
	"fmt"
	"os"

	"github.com/sky/personal-ledger/internal/database"
	"gorm.io/gorm"
)

type HealthService struct {
	db         *gorm.DB
	uploadPath string
	backupPath string
}

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
		status.Checks["database"] = HealthCheck{Status: "fail", Message: err.Error()}
	} else {
		status.Checks["database"] = HealthCheck{Status: "ok"}
	}

	status.Checks["uploads"] = checkDirectory(s.uploadPath)
	status.Checks["backups"] = checkDirectory(s.backupPath)
	for _, check := range status.Checks {
		if check.Status == "fail" {
			status.Status = "unhealthy"
			break
		}
	}
	return status
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
		return HealthCheck{Status: "fail", Message: err.Error()}
	}
	if !info.IsDir() {
		return HealthCheck{Status: "fail", Message: "not a directory"}
	}
	return HealthCheck{Status: "ok"}
}
