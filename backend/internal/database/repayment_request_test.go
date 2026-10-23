package database

import (
	"path/filepath"
	"strings"
	"testing"

	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

func TestRepaymentRequestMigrationPreservesV11AndSurvivesRestart(t *testing.T) {
	path := filepath.Join(t.TempDir(), "v11.db")
	db, err := gorm.Open(sqlite.Open(path), &gorm.Config{})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.AutoMigrate(&schemaMigration{}, &model.Account{}); err != nil {
		t.Fatal(err)
	}
	if err := db.Create(&schemaMigration{Version: 11, Name: "ai_report_provider_revision"}).Error; err != nil {
		t.Fatal(err)
	}
	if err := db.Create(&model.Account{ID: "existing", UserID: 1, Name: "cash", Type: "cash", CurrentBalance: 77}).Error; err != nil {
		t.Fatal(err)
	}
	conn, _ := db.DB()
	if err := conn.Close(); err != nil {
		t.Fatal(err)
	}
	db, err = Init(path)
	if err != nil {
		t.Fatal(err)
	}
	var account model.Account
	if err := db.First(&account, "id = ?", "existing").Error; err != nil || account.CurrentBalance != 77 {
		t.Fatalf("migration changed account: %+v, %v", account, err)
	}
	request := model.RepaymentRequest{UserID: 1, Operation: "reminder", TargetID: "target", KeyHash: strings.Repeat("a", 64), PayloadHash: strings.Repeat("b", 64)}
	if err := db.Create(&request).Error; err != nil {
		t.Fatal(err)
	}
	if err := db.Create(&request).Error; err == nil {
		t.Fatal("duplicate idempotency scope accepted")
	}
	conn, _ = db.DB()
	if err := conn.Close(); err != nil {
		t.Fatal(err)
	}
	db, err = Init(path)
	if err != nil {
		t.Fatal(err)
	}
	var restored model.RepaymentRequest
	if err := db.First(&restored).Error; err != nil || restored.PayloadHash != request.PayloadHash {
		t.Fatalf("restart lost idempotency record: %+v, %v", restored, err)
	}
	var count int64
	if err := db.Model(&schemaMigration{}).Where("version = ?", 12).Count(&count).Error; err != nil || count != 1 {
		t.Fatalf("migration count = %d, %v", count, err)
	}
}
