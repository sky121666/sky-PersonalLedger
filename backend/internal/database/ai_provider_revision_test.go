package database

import (
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

// This is the persisted report schema through v10, deliberately independent of
// the evolving model so upgrade fixtures cannot add the new column prematurely.
// The same table was created by v1 and remained unchanged by migrations 2-10.
type legacyAIReportV10 struct {
	ID            string `gorm:"primaryKey;size:36"`
	UserID        uint   `gorm:"not null;index"`
	ReportType    string `gorm:"size:30;not null;index"`
	PeriodStart   time.Time
	PeriodEnd     time.Time
	Status        string `gorm:"size:30;not null;default:pending"`
	SnapshotJSON  string `gorm:"type:text"`
	ContentJSON   string `gorm:"type:text"`
	ProviderID    string `gorm:"size:36;index"`
	ProviderName  string `gorm:"size:100"`
	Model         string `gorm:"size:100"`
	PromptVersion string `gorm:"size:30"`
	ErrorMessage  string `gorm:"type:text"`
	CreatedAt     time.Time
	UpdatedAt     time.Time
	DeletedAt     gorm.DeletedAt `gorm:"index"`
}

func (legacyAIReportV10) TableName() string { return "ai_reports" }

func TestAIProviderRevisionMigrationPreservesV10HistoryAndIsIdempotent(t *testing.T) {
	path := filepath.Join(t.TempDir(), "v10-ledger.db")
	legacy, err := gorm.Open(sqlite.Open(path), &gorm.Config{})
	if err != nil {
		t.Fatal(err)
	}
	if err := legacy.AutoMigrate(&schemaMigration{}, &legacyAIReportV10{}); err != nil {
		t.Fatal(err)
	}
	if legacy.Migrator().HasColumn(&model.AIReport{}, "ProviderRevision") {
		t.Fatal("legacy fixture must not contain provider_revision")
	}
	now := time.Date(2026, 8, 31, 12, 0, 0, 0, time.UTC)
	old := legacyAIReportV10{
		ID: "v10-historical-ai-report", UserID: 42, ReportType: "weekly",
		PeriodStart: now.AddDate(0, 0, -6), PeriodEnd: now, Status: "completed",
		SnapshotJSON: `{"expense_total":12.34}`, ContentJSON: `{"summary":"historical report"}`,
		ProviderID: "historical-provider", ProviderName: "Previous provider", Model: "previous-model",
		PromptVersion: "personal-ledger-v1", CreatedAt: now, UpdatedAt: now,
	}
	if err := legacy.Create(&old).Error; err != nil {
		t.Fatal(err)
	}
	if err := legacy.Create(&schemaMigration{Version: 10, Name: "expand_notification_endpoint_columns", AppliedAt: now}).Error; err != nil {
		t.Fatal(err)
	}
	oldSQL, err := legacy.DB()
	if err != nil {
		t.Fatal(err)
	}
	if err := oldSQL.Close(); err != nil {
		t.Fatal(err)
	}

	db, err := Init(path)
	if err != nil {
		t.Fatal(err)
	}
	var got model.AIReport
	if err := db.First(&got, "id = ?", old.ID).Error; err != nil {
		t.Fatal(err)
	}
	if got.ProviderRevision != "" || got.ContentJSON != old.ContentJSON || got.SnapshotJSON != old.SnapshotJSON ||
		got.ProviderName != old.ProviderName || got.Model != old.Model || got.Status != old.Status ||
		!got.CreatedAt.Equal(old.CreatedAt) || !got.UpdatedAt.Equal(old.UpdatedAt) {
		t.Fatalf("v11 migration changed historical report data: %+v", got)
	}
	if version, err := latestSchemaVersion(db); err != nil || version != 11 {
		t.Fatalf("upgraded version=%d err=%v", version, err)
	}
	// A restart must retain a revision written after the migration, not backfill
	// it from the current provider or reset it to the legacy default.
	wantRevision := strings.Repeat("a", 64)
	if err := db.Model(&model.AIReport{}).Where("id = ?", old.ID).UpdateColumn("provider_revision", wantRevision).Error; err != nil {
		t.Fatal(err)
	}
	sqlDB, err := db.DB()
	if err != nil {
		t.Fatal(err)
	}
	if err := sqlDB.Close(); err != nil {
		t.Fatal(err)
	}
	db, err = Init(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := db.First(&got, "id = ?", old.ID).Error; err != nil {
		t.Fatal(err)
	}
	if got.ProviderRevision != wantRevision {
		t.Fatal("repeated startup lost the persisted revision")
	}
	var migrations []schemaMigration
	if err := db.Order("version ASC").Find(&migrations).Error; err != nil {
		t.Fatal(err)
	}
	if len(migrations) != 2 || migrations[0].Version != 10 || migrations[1].Version != 11 || migrations[1].Name != "ai_report_provider_revision" {
		t.Fatalf("upgrade reran historical migrations or duplicated v11: %+v", migrations)
	}
}
