package repository

import (
	"errors"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/config"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

func TestUserProfileIdempotentUpdateMySQLIntegration(t *testing.T) {
	dsn := strings.TrimSpace(os.Getenv("LEDGER_TEST_MYSQL_DSN"))
	if dsn == "" {
		t.Skip("set LEDGER_TEST_MYSQL_DSN to run MySQL idempotent profile update integration test")
	}
	db, err := database.InitWithConfig(config.DatabaseConfig{Driver: "mysql", DSN: dsn, MaxOpenConns: 2, MaxIdleConns: 1})
	if err != nil {
		t.Fatal(err)
	}
	sqlDB, err := db.DB()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = sqlDB.Close() })
	// Match the storage clock exactly so updated_at cannot hide MySQL's
	// changed-row semantics behind an incidental timestamp difference.
	fixedTime := time.Date(2026, 9, 8, 0, 0, 0, 0, time.UTC)
	db = db.Session(&gorm.Session{NowFunc: func() time.Time { return fixedTime }})
	repo := NewUserRepository(db)
	user := &model.User{Username: "profile-" + uuid.NewString(), PasswordHash: "fixture-hash", Nickname: "Before"}
	if err := repo.Create(user); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := db.Unscoped().Delete(&model.User{}, "id = ?", user.ID).Error; err != nil {
			t.Errorf("clean profile fixture: %v", err)
		}
	})
	user.Nickname = "After"
	user.Email = "profile@example.test"
	for attempt := 0; attempt < 2; attempt++ {
		if err := repo.UpdateProfile(user); err != nil {
			t.Fatalf("save identical profile attempt %d: %v", attempt+1, err)
		}
	}
	stored, err := repo.GetByID(user.ID)
	if err != nil || stored.Nickname != "After" || stored.Email != user.Email || stored.PasswordHash != "fixture-hash" {
		t.Fatalf("stored profile after repeated save: user=%v err=%v", stored, err)
	}
	// An unchanging password/login-state update must also remain idempotent.
	if err := repo.UpdatePasswordHash(user.ID, "fixture-hash"); err != nil {
		t.Fatalf("unchanged password hash: %v", err)
	}
	if err := repo.RecordFailedLogin(user.ID, 0, nil); err != nil {
		t.Fatalf("unchanged failure state: %v", err)
	}
	if err := db.Delete(&model.User{}, "id = ?", user.ID).Error; err != nil {
		t.Fatal(err)
	}
	if err := repo.UpdateProfile(user); !errors.Is(err, gorm.ErrRecordNotFound) {
		t.Fatalf("soft-deleted user update=%v, want record not found", err)
	}
	if err := db.Unscoped().Delete(&model.User{}, "id = ?", user.ID).Error; err != nil {
		t.Fatal(err)
	}
	if err := repo.UpdateProfile(user); !errors.Is(err, gorm.ErrRecordNotFound) {
		t.Fatalf("missing user update=%v, want record not found", err)
	}
	t.Log("identical profile/password/login-state updates succeed; removed users still return record not found")
}
