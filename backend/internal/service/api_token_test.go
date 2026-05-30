package service

import (
	"errors"
	"path/filepath"
	"testing"
	"time"

	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"gorm.io/gorm"
)

func newAPITokenTestService(t *testing.T) (*APITokenService, *repository.Repositories, uint) {
	t.Helper()
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	user := &model.User{Username: "admin", PasswordHash: "hash"}
	if err := repos.User.Create(user); err != nil {
		t.Fatalf("create user: %v", err)
	}
	return NewAPITokenService(repos.APIToken), repos, user.ID
}

func TestAPITokenGenerateStoresOnlyHashAndValidatesRawToken(t *testing.T) {
	svc, repos, userID := newAPITokenTestService(t)

	created, err := svc.GenerateToken(userID, "mobile", 30)
	if err != nil {
		t.Fatalf("generate token: %v", err)
	}
	if created.Token == "" {
		t.Fatal("created token should return raw token once")
	}

	stored, err := repos.APIToken.FindByUserID(userID)
	if err != nil {
		t.Fatalf("list stored tokens: %v", err)
	}
	if len(stored) != 1 {
		t.Fatalf("stored tokens = %d, want 1", len(stored))
	}
	if stored[0].Token == created.Token {
		t.Fatal("stored api token is raw token, want hash")
	}
	if stored[0].Token != hashAPIToken(created.Token) {
		t.Fatalf("stored token = %q, want token hash", stored[0].Token)
	}
	if stored[0].TokenPrefix != created.Token[:8] {
		t.Fatalf("token prefix = %q, want raw token prefix", stored[0].TokenPrefix)
	}

	validUserID, err := svc.ValidateToken(created.Token)
	if err != nil {
		t.Fatalf("validate token: %v", err)
	}
	if validUserID != userID {
		t.Fatalf("validated user id = %d, want %d", validUserID, userID)
	}
}

func TestAPITokenValidateMigratesLegacyPlaintextToken(t *testing.T) {
	svc, repos, userID := newAPITokenTestService(t)
	legacyToken := "legacy-api-token-32-characters-minimum"
	apiToken := &model.APIToken{
		UserID:      userID,
		Name:        "legacy",
		Token:       legacyToken,
		TokenPrefix: legacyToken[:8],
	}
	if err := repos.APIToken.Create(apiToken); err != nil {
		t.Fatalf("create legacy token: %v", err)
	}

	validUserID, err := svc.ValidateToken(legacyToken)
	if err != nil {
		t.Fatalf("validate legacy token: %v", err)
	}
	if validUserID != userID {
		t.Fatalf("validated user id = %d, want %d", validUserID, userID)
	}

	var migrated model.APIToken
	if err := repos.APIToken.DB().First(&migrated, apiToken.ID).Error; err != nil {
		t.Fatalf("load migrated token: %v", err)
	}
	if migrated.Token != hashAPIToken(legacyToken) {
		t.Fatalf("migrated token = %q, want hash", migrated.Token)
	}
}

func TestAPITokenValidateRejectsExpiredToken(t *testing.T) {
	svc, repos, userID := newAPITokenTestService(t)
	rawToken := "expired-api-token-32-characters-minimum"
	expiredAt := time.Now().Add(-time.Hour)
	if err := repos.APIToken.Create(&model.APIToken{
		UserID:      userID,
		Name:        "expired",
		Token:       hashAPIToken(rawToken),
		TokenPrefix: rawToken[:8],
		ExpiresAt:   &expiredAt,
	}); err != nil {
		t.Fatalf("create expired token: %v", err)
	}

	if _, err := svc.ValidateToken(rawToken); err == nil || err.Error() != "token expired" {
		t.Fatalf("validate expired token err = %v, want token expired", err)
	}
}

func TestAPITokenValidateRejectsUnknownToken(t *testing.T) {
	svc, _, _ := newAPITokenTestService(t)

	_, err := svc.ValidateToken("missing-token")
	if err == nil || errors.Is(err, gorm.ErrRecordNotFound) {
		t.Fatalf("validate unknown token err = %v, want sanitized invalid token error", err)
	}
	if err.Error() != "invalid token" {
		t.Fatalf("validate unknown token err = %v, want invalid token", err)
	}
}
