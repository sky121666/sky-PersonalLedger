package service

import (
	"encoding/json"
	"errors"
	"path/filepath"
	"reflect"
	"strings"
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
	if !strings.HasPrefix(created.Token, "plk_") {
		t.Fatalf("created token = %q, want plk_ prefix", created.Token)
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
	if stored[0].TokenPrefix != created.Token[:12] {
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

func TestAPITokenScopesAreNormalizedStoredAndValidated(t *testing.T) {
	svc, repos, userID := newAPITokenTestService(t)

	created, err := svc.GenerateToken(userID, "read-only", 30, []string{
		" LEDGER:READ ",
		"ledger:read",
		"report:read",
	})
	if err != nil {
		t.Fatalf("generate scoped token: %v", err)
	}
	wantScopes := []string{"ledger:read", "report:read"}
	if !reflect.DeepEqual(created.Scopes, wantScopes) {
		t.Fatalf("created scopes = %#v, want %#v", created.Scopes, wantScopes)
	}

	stored, err := repos.APIToken.FindByUserID(userID)
	if err != nil || len(stored) != 1 {
		t.Fatalf("stored tokens = %#v, err = %v", stored, err)
	}
	var storedScopes []string
	if err := json.Unmarshal([]byte(stored[0].Scopes), &storedScopes); err != nil {
		t.Fatalf("decode stored scopes: %v", err)
	}
	if !reflect.DeepEqual(storedScopes, wantScopes) {
		t.Fatalf("stored scopes = %#v, want %#v", storedScopes, wantScopes)
	}

	principal, err := svc.ValidatePrincipal(created.Token)
	if err != nil {
		t.Fatalf("validate principal: %v", err)
	}
	if !reflect.DeepEqual(principal.Scopes, wantScopes) {
		t.Fatalf("validated scopes = %#v, want %#v", principal.Scopes, wantScopes)
	}
}

func TestAPITokenGenerateRejectsUnknownScope(t *testing.T) {
	svc, _, userID := newAPITokenTestService(t)

	if _, err := svc.GenerateToken(userID, "unsafe", 30, []string{"admin:*"}); !errors.Is(err, ErrInvalidAPITokenScopes) {
		t.Fatalf("generate token err = %v, want ErrInvalidAPITokenScopes", err)
	}
}

func TestAPITokenGenerateValidatesNameAndExpiry(t *testing.T) {
	svc, _, userID := newAPITokenTestService(t)

	if _, err := svc.GenerateToken(userID, "   ", 30); !errors.Is(err, ErrInvalidAPITokenName) {
		t.Fatalf("blank name err = %v, want ErrInvalidAPITokenName", err)
	}
	if _, err := svc.GenerateToken(userID, "mobile", -1); !errors.Is(err, ErrInvalidAPITokenExpiry) {
		t.Fatalf("negative expiry err = %v, want ErrInvalidAPITokenExpiry", err)
	}
	if _, err := svc.GenerateToken(userID, "mobile", maxAPITokenExpiryDays+1); !errors.Is(err, ErrInvalidAPITokenExpiry) {
		t.Fatalf("oversized expiry err = %v, want ErrInvalidAPITokenExpiry", err)
	}
}

func TestAPITokenListReturnsNormalizedScopesWithoutSecretMaterial(t *testing.T) {
	svc, _, userID := newAPITokenTestService(t)
	created, err := svc.GenerateToken(userID, "reports", 30, []string{"report:read"})
	if err != nil {
		t.Fatalf("generate token: %v", err)
	}

	tokens, err := svc.ListTokens(userID)
	if err != nil {
		t.Fatalf("list tokens: %v", err)
	}
	if len(tokens) != 1 || !reflect.DeepEqual(tokens[0].Scopes, []string{"report:read"}) {
		t.Fatalf("tokens = %#v, want report scope", tokens)
	}
	encoded, err := json.Marshal(tokens[0])
	if err != nil {
		t.Fatalf("encode token summary: %v", err)
	}
	if strings.Contains(string(encoded), created.Token) || strings.Contains(string(encoded), hashAPIToken(created.Token)) {
		t.Fatalf("token summary exposed secret material: %s", encoded)
	}
}

func TestAPITokenLastUsedWriteIsThrottled(t *testing.T) {
	svc, repos, userID := newAPITokenTestService(t)
	created, err := svc.GenerateToken(userID, "mobile", 30)
	if err != nil {
		t.Fatalf("generate token: %v", err)
	}
	recent := time.Now().Add(-time.Minute).Truncate(time.Second)
	if err := repos.APIToken.DB().Model(&model.APIToken{}).
		Where("id = ?", created.ID).Update("last_used_at", recent).Error; err != nil {
		t.Fatalf("seed recent last-used timestamp: %v", err)
	}

	if _, err := svc.ValidateToken(created.Token); err != nil {
		t.Fatalf("validate token: %v", err)
	}
	var stored model.APIToken
	if err := repos.APIToken.DB().First(&stored, created.ID).Error; err != nil {
		t.Fatalf("load token: %v", err)
	}
	if stored.LastUsedAt == nil || !stored.LastUsedAt.Equal(recent) {
		t.Fatalf("last_used_at = %v, want throttled timestamp %v", stored.LastUsedAt, recent)
	}
}

func TestAPITokenDeleteMissingReturnsDomainNotFound(t *testing.T) {
	svc, _, userID := newAPITokenTestService(t)
	if err := svc.DeleteToken(999, userID); !errors.Is(err, ErrAPITokenNotFound) {
		t.Fatalf("delete missing err = %v, want ErrAPITokenNotFound", err)
	}
}

func TestAPITokenRevokeRejectsTokenAndHidesItFromActiveList(t *testing.T) {
	svc, repos, userID := newAPITokenTestService(t)
	created, err := svc.GenerateToken(userID, "revoke-me", 30)
	if err != nil {
		t.Fatalf("generate token: %v", err)
	}

	if err := svc.DeleteToken(created.ID, userID); err != nil {
		t.Fatalf("revoke token: %v", err)
	}
	if _, err := svc.ValidatePrincipal(created.Token); err == nil || err.Error() != "invalid token" {
		t.Fatalf("validate revoked token err = %v, want invalid token", err)
	}
	active, err := repos.APIToken.FindByUserID(userID)
	if err != nil {
		t.Fatalf("list active tokens: %v", err)
	}
	if len(active) != 0 {
		t.Fatalf("active tokens = %d, want 0", len(active))
	}
	var persisted model.APIToken
	if err := repos.APIToken.DB().First(&persisted, created.ID).Error; err != nil {
		t.Fatalf("load revoked token: %v", err)
	}
	if persisted.RevokedAt == nil {
		t.Fatal("revoked_at is nil, want retained revocation audit record")
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
