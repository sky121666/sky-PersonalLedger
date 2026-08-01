package database

import (
	"bytes"
	"strings"
	"testing"

	"github.com/sky/personal-ledger/internal/config"
	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

func TestGORMLoggerNeverWritesBoundSecrets(t *testing.T) {
	var output bytes.Buffer
	db, err := gorm.Open(sqlite.Open(":memory:"), &gorm.Config{
		Logger: newGORMLogger(&output, config.LogConfig{Level: "debug"}),
	})
	if err != nil {
		t.Fatalf("open database: %v", err)
	}
	if err := db.AutoMigrate(&model.User{}, &model.RefreshToken{}, &model.APIToken{}); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	user := &model.User{Username: "log-sentinel-user", PasswordHash: "secret-password-hash"}
	if err := db.Create(user).Error; err != nil {
		t.Fatalf("create user: %v", err)
	}
	if err := db.Create(&model.RefreshToken{
		ID: "refresh-log-sentinel", UserID: user.ID, Token: "secret-refresh-token-hash",
	}).Error; err == nil {
		// ExpiresAt is intentionally absent. The write may succeed on SQLite or
		// fail on stricter drivers; either path must keep bound values redacted.
	}
	if err := db.Create(&model.APIToken{
		UserID: user.ID, Name: "log-sentinel", Token: "secret-api-token-hash",
	}).Error; err != nil {
		t.Fatalf("create api token: %v", err)
	}

	logged := output.String()
	for _, secret := range []string{
		"secret-password-hash",
		"secret-refresh-token-hash",
		"secret-api-token-hash",
	} {
		if strings.Contains(logged, secret) {
			t.Fatalf("gorm log exposed %q: %s", secret, logged)
		}
	}
}
