package model

import "time"

// TransactionImportBatch persists the short-lived import workflow so a server
// restart cannot lose a validated preview or its rollback window. Payload is an
// internal JSON document stored as binary data; leaving its database type to
// GORM keeps the migration portable across SQLite, PostgreSQL, and MySQL.
type TransactionImportBatch struct {
	ID             string    `gorm:"primaryKey;size:36"`
	UserID         uint      `gorm:"not null;index:idx_transaction_import_batches_user_expiry,priority:1"`
	Filename       string    `gorm:"size:255;not null"`
	Format         string    `gorm:"size:10;not null"`
	FileDigest     string    `gorm:"size:64;not null"`
	Status         string    `gorm:"size:20;not null;index"`
	TotalRows      int       `gorm:"not null;default:0"`
	ValidRows      int       `gorm:"not null;default:0"`
	InvalidRows    int       `gorm:"not null;default:0"`
	DuplicateRows  int       `gorm:"not null;default:0"`
	CreatedRows    int       `gorm:"not null;default:0"`
	RolledBackRows int       `gorm:"not null;default:0"`
	Payload        []byte    `gorm:"not null"`
	CreatedAt      time.Time `gorm:"not null"`
	UpdatedAt      time.Time `gorm:"not null"`
	ExpiresAt      time.Time `gorm:"not null;index:idx_transaction_import_batches_user_expiry,priority:2"`
	CommittedAt    *time.Time
	RolledBackAt   *time.Time
}
