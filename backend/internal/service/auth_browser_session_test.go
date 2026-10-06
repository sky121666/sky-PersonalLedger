package service

import (
	"errors"
	"sync"
	"testing"
	"time"

	jwtlib "github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	ledgerjwt "github.com/sky/personal-ledger/pkg/jwt"
	"gorm.io/gorm"
)

func signedBrowserRefresh(t *testing.T, userID uint, sessionID, secret string, expires time.Time) string {
	t.Helper()
	token, err := jwtlib.NewWithClaims(jwtlib.SigningMethodHS256, ledgerjwt.Claims{
		UserID: userID, TokenType: "refresh", SessionID: sessionID,
		RegisteredClaims: jwtlib.RegisteredClaims{
			Issuer: "personal-ledger", Audience: jwtlib.ClaimStrings{"personal-ledger-auth"},
			ExpiresAt: jwtlib.NewNumericDate(expires), IssuedAt: jwtlib.NewNumericDate(time.Now()), ID: uuid.New().String(),
		},
	}).SignedString([]byte(secret))
	if err != nil {
		t.Fatal(err)
	}
	return token
}

func TestAuthBrowserLogoutMigratesAndRevokesLegacyRotationFamily(t *testing.T) {
	for _, plaintext := range []bool{false, true} {
		t.Run(map[bool]string{false: "hashed", true: "plaintext"}[plaintext], func(t *testing.T) {
			svc, repos := newAuthServiceForTest(t)
			independent, err := svc.Init("LedgerInitPass123!")
			if err != nil {
				t.Fatal(err)
			}
			claims, err := svc.jwtManager.ValidateRefreshToken(independent.RefreshToken)
			if err != nil {
				t.Fatal(err)
			}
			legacy := signedBrowserRefresh(t, claims.UserID, "", "test-auth-secret-with-at-least-32-chars", time.Now().Add(time.Hour))
			stored := hashRefreshToken(legacy)
			if plaintext {
				stored = legacy
			}
			if err := repos.RefreshToken.Create(&model.RefreshToken{ID: uuid.New().String(), UserID: claims.UserID, Token: stored, ExpiresAt: time.Now().Add(time.Hour)}); err != nil {
				t.Fatal(err)
			}
			first, err := svc.RefreshToken(legacy)
			if err != nil {
				t.Fatalf("legacy native token no longer rotates: %v", err)
			}
			second, err := svc.RefreshToken(first.RefreshToken)
			if err != nil {
				t.Fatal(err)
			}
			if err := svc.LogoutBrowserSession(legacy); err != nil {
				t.Fatal(err)
			}
			if _, err := svc.RefreshToken(second.RefreshToken); !errors.Is(err, ErrInvalidToken) {
				t.Fatalf("legacy descendant survived logout: %v", err)
			}
			if _, err := svc.RefreshToken(independent.RefreshToken); err != nil {
				t.Fatalf("unrelated login revoked: %v", err)
			}
		})
	}
}

func TestAuthBrowserLogoutRejectsUntrustedRevocationClaims(t *testing.T) {
	svc, _ := newAuthServiceForTest(t)
	tokens, err := svc.Init("LedgerInitPass123!")
	if err != nil {
		t.Fatal(err)
	}
	claims, err := svc.jwtManager.ValidateRefreshToken(tokens.RefreshToken)
	if err != nil {
		t.Fatal(err)
	}
	for name, token := range map[string]string{
		"missing": "", "malformed": "invalid", "access": tokens.AccessToken,
		"forged":  signedBrowserRefresh(t, claims.UserID, claims.SessionID, "wrong-signing-secret", time.Now().Add(time.Hour)),
		"expired": signedBrowserRefresh(t, claims.UserID, claims.SessionID, "test-auth-secret-with-at-least-32-chars", time.Now().Add(-time.Hour)),
	} {
		t.Run(name, func(t *testing.T) {
			if err := svc.LogoutBrowserSession(token); !errors.Is(err, ErrInvalidToken) {
				t.Fatalf("untrusted claim accepted: %v", err)
			}
		})
	}
	if _, err := svc.RefreshToken(tokens.RefreshToken); err != nil {
		t.Fatalf("invalid logout revoked valid session: %v", err)
	}
}

func TestAuthBrowserLogoutScopesFamilyDeletionToSignedUser(t *testing.T) {
	svc, repos := newAuthServiceForTest(t)
	tokens, err := svc.Init("LedgerInitPass123!")
	if err != nil {
		t.Fatal(err)
	}
	claims, err := svc.jwtManager.ValidateRefreshToken(tokens.RefreshToken)
	if err != nil {
		t.Fatal(err)
	}
	other := &model.User{Username: "other", PasswordHash: "test-only"}
	if err := repos.User.Create(other); err != nil {
		t.Fatal(err)
	}
	otherToken := signedBrowserRefresh(t, other.ID, claims.SessionID, "test-auth-secret-with-at-least-32-chars", time.Now().Add(time.Hour))
	if err := svc.LogoutBrowserSession(otherToken); !errors.Is(err, ErrInvalidToken) {
		t.Fatalf("other user's family accepted: %v", err)
	}
	if _, err := svc.RefreshToken(tokens.RefreshToken); err != nil {
		t.Fatalf("different user revoked session: %v", err)
	}
}

func TestAuthBrowserLogoutSerializesWithRefreshRotation(t *testing.T) {
	for _, first := range []string{"refresh", "logout"} {
		t.Run(first, func(t *testing.T) {
			svc, repos := newAuthServiceForTest(t)
			tokens, err := svc.Init("LedgerInitPass123!")
			if err != nil {
				t.Fatal(err)
			}
			entered, release := make(chan struct{}), make(chan struct{})
			var once sync.Once
			callback := func(db *gorm.DB) {
				if db.Statement.Table == "refresh_tokens" {
					once.Do(func() { close(entered); <-release })
				}
			}
			db := repos.User.DB()
			if first == "refresh" {
				if err := db.Callback().Create().Before("gorm:create").Register("test:hold-refresh-family", callback); err != nil {
					t.Fatal(err)
				}
				t.Cleanup(func() { _ = db.Callback().Create().Remove("test:hold-refresh-family") })
			} else {
				if err := db.Callback().Delete().Before("gorm:delete").Register("test:hold-logout-family", callback); err != nil {
					t.Fatal(err)
				}
				t.Cleanup(func() { _ = db.Callback().Delete().Remove("test:hold-logout-family") })
			}
			type result struct {
				tokens *AuthResponse
				err    error
			}
			refreshed, loggedOut := make(chan result, 1), make(chan error, 1)
			refresh := func() { value, err := svc.RefreshToken(tokens.RefreshToken); refreshed <- result{value, err} }
			logout := func() { loggedOut <- svc.LogoutBrowserSession(tokens.RefreshToken) }
			if first == "refresh" {
				go refresh()
				<-entered
				go logout()
			} else {
				go logout()
				<-entered
				go refresh()
			}
			close(release)
			r := <-refreshed
			if err := <-loggedOut; err != nil {
				t.Fatalf("logout: %v", err)
			}
			if first == "refresh" {
				if r.err != nil {
					t.Fatalf("first refresh: %v", r.err)
				}
				if _, err := svc.RefreshToken(r.tokens.RefreshToken); !errors.Is(err, ErrInvalidToken) {
					t.Fatalf("late refresh response can revive session: %v", err)
				}
			} else if !errors.Is(r.err, ErrInvalidToken) {
				t.Fatalf("refresh after logout: %v", r.err)
			}
		})
	}
}

func TestAuthBrowserRefreshConcurrentConsumesOnce(t *testing.T) {
	svc, repos := newAuthServiceForTest(t)
	tokens, err := svc.Init("LedgerInitPass123!")
	if err != nil {
		t.Fatal(err)
	}
	start := make(chan struct{})
	results := make(chan error, 8)
	for i := 0; i < 8; i++ {
		go func() { <-start; _, err := svc.RefreshToken(tokens.RefreshToken); results <- err }()
	}
	close(start)
	successes := 0
	for i := 0; i < 8; i++ {
		if err := <-results; err == nil {
			successes++
		} else if !errors.Is(err, ErrInvalidToken) {
			t.Fatalf("unexpected concurrent refresh failure: %v", err)
		}
	}
	if successes != 1 {
		t.Fatalf("successful refreshes=%d, want one", successes)
	}
	var remaining int64
	if err := repos.User.DB().Model(&model.RefreshToken{}).Count(&remaining).Error; err != nil {
		t.Fatal(err)
	}
	if remaining != 1 {
		t.Fatalf("remaining refresh families=%d, want one", remaining)
	}
}
