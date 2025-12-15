package database

import (
	"os"
	"path/filepath"

	"github.com/sky/personal-ledger/internal/model"

	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

func Init(dbPath string) (*gorm.DB, error) {
	// Ensure directory exists
	dir := filepath.Dir(dbPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return nil, err
	}

	db, err := gorm.Open(sqlite.Open(dbPath), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Info),
	})
	if err != nil {
		return nil, err
	}

	// Enable WAL mode for better concurrency
	db.Exec("PRAGMA journal_mode=WAL;")

	// Auto migrate
	if err := db.AutoMigrate(
		&model.User{},
		&model.Account{},
		&model.Category{},
		&model.Transaction{},
		&model.Budget{},
		&model.Reminder{},
		&model.RefreshToken{},
		&model.QuickTemplate{},
		&model.NotificationSetting{},
		&model.Lending{},
		&model.LendingRecord{},
		&model.NotificationLog{},
		&model.SystemSetting{},
		&model.AccountLog{},
		&model.Tag{},
		&model.RecurringTransaction{},
	); err != nil {
		return nil, err
	}

	return db, nil
}
