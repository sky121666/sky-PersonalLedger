package service

import (
	"encoding/json"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

func TestBackupDoesNotExportSecurityCredentials(t *testing.T) {
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	backupSvc := NewBackupService(db, repos.Account, repos.Category, repos.Transaction, repos.Budget, repos.Reminder, repos.Lending, repos.Template, repos.Notification, repos.Tag, repos.User)

	user := &model.User{
		Username:     "admin",
		PasswordHash: "secret-password-hash",
		Nickname:     "Ledger Admin",
		Email:        "admin@example.com",
	}
	if err := repos.User.Create(user); err != nil {
		t.Fatalf("create user: %v", err)
	}

	if err := db.Create(&model.RefreshToken{
		ID:        "refresh-token-id",
		UserID:    user.ID,
		Token:     "secret-refresh-token-hash",
		ExpiresAt: time.Now().Add(time.Hour),
	}).Error; err != nil {
		t.Fatalf("create refresh token: %v", err)
	}
	if err := db.Create(&model.APIToken{
		UserID:      user.ID,
		Name:        "mobile",
		Token:       "secret-api-token-hash",
		TokenPrefix: "secrettk",
	}).Error; err != nil {
		t.Fatalf("create api token: %v", err)
	}

	backup, err := backupSvc.CreateBackup(user.ID)
	if err != nil {
		t.Fatalf("create backup: %v", err)
	}
	data, err := json.Marshal(backup)
	if err != nil {
		t.Fatalf("marshal backup: %v", err)
	}
	payload := string(data)

	if backup.UserProfile == nil {
		t.Fatal("user profile missing")
	}
	if backup.UserProfile.Email != "admin@example.com" {
		t.Fatalf("profile email = %q, want exported display email", backup.UserProfile.Email)
	}
	for _, forbidden := range []string{
		"secret-password-hash",
		"secret-refresh-token-hash",
		"secret-api-token-hash",
		"secrettk",
	} {
		if strings.Contains(payload, forbidden) {
			t.Fatalf("backup payload leaked credential value %q: %s", forbidden, payload)
		}
	}
}
