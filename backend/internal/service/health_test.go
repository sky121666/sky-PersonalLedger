package service

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/sky/personal-ledger/internal/database"
)

func TestHealthServiceCheckPassesWithDatabaseAndStorage(t *testing.T) {
	root := t.TempDir()
	db, err := database.Init(filepath.Join(root, "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	uploads := filepath.Join(root, "uploads")
	backups := filepath.Join(root, "backups")
	if err := os.MkdirAll(uploads, 0755); err != nil {
		t.Fatalf("create uploads dir: %v", err)
	}
	if err := os.MkdirAll(backups, 0755); err != nil {
		t.Fatalf("create backups dir: %v", err)
	}

	status := NewHealthService(db, uploads, backups).Check()
	if status.Status != "ok" {
		t.Fatalf("status = %#v, want ok", status)
	}
	if status.CurrentSchemaVersion == 0 || status.DatabaseSchemaVersion == 0 {
		t.Fatalf("schema versions not populated: %#v", status)
	}
	if status.Checks["database"].Status != "ok" ||
		status.Checks["uploads"].Status != "ok" ||
		status.Checks["backups"].Status != "ok" {
		t.Fatalf("checks = %#v, want all ok", status.Checks)
	}
}

func TestHealthServiceCheckFailsWhenStorageMissing(t *testing.T) {
	root := t.TempDir()
	db, err := database.Init(filepath.Join(root, "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}

	status := NewHealthService(db, filepath.Join(root, "missing-uploads"), "").Check()
	if status.Status != "unhealthy" {
		t.Fatalf("status = %#v, want unhealthy", status)
	}
	if status.Checks["uploads"].Status != "fail" {
		t.Fatalf("uploads check = %#v, want fail", status.Checks["uploads"])
	}
	if status.Checks["uploads"].Message != "directory is not accessible" {
		t.Fatalf("uploads message = %q, want generic directory error", status.Checks["uploads"].Message)
	}
	if strings.Contains(status.Checks["uploads"].Message, root) || strings.Contains(strings.ToLower(status.Checks["uploads"].Message), "stat ") {
		t.Fatalf("uploads message exposed filesystem detail: %q", status.Checks["uploads"].Message)
	}
	if status.Checks["backups"].Status != "ok" {
		t.Fatalf("backups check = %#v, want ok for unconfigured path", status.Checks["backups"])
	}
}

func TestHealthServiceCheckDoesNotExposeDatabaseErrors(t *testing.T) {
	root := t.TempDir()
	db, err := database.Init(filepath.Join(root, "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	sqlDB, err := db.DB()
	if err != nil {
		t.Fatalf("get sql db: %v", err)
	}
	if err := sqlDB.Close(); err != nil {
		t.Fatalf("close sql db: %v", err)
	}

	status := NewHealthService(db, "", "").Check()
	if status.Status != "unhealthy" {
		t.Fatalf("status = %#v, want unhealthy", status)
	}
	if status.Checks["database"].Message != "database check failed" {
		t.Fatalf("database message = %q, want generic database error", status.Checks["database"].Message)
	}
	if strings.Contains(strings.ToLower(status.Checks["database"].Message), "sql") ||
		strings.Contains(strings.ToLower(status.Checks["database"].Message), "database is closed") {
		t.Fatalf("database message exposed internal detail: %q", status.Checks["database"].Message)
	}
}
