package service

import (
	"errors"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"github.com/sky/personal-ledger/pkg/jwt"
	"golang.org/x/crypto/bcrypt"
)

func newAuthServiceForTest(t *testing.T) (*AuthService, *repository.Repositories) {
	t.Helper()
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	jwtManager := jwt.NewManager("test-auth-secret-with-at-least-32-chars", 15, 60)
	return NewAuthService(repos.User, repos.RefreshToken, repos.Category, repos.Account, jwtManager), repos
}

func TestAuthStoresOnlyRefreshTokenHashAndRefreshesRawToken(t *testing.T) {
	svc, repos := newAuthServiceForTest(t)

	result, err := svc.Init("LedgerInitPass123!")
	if err != nil {
		t.Fatalf("init: %v", err)
	}

	var stored model.RefreshToken
	if err := repos.User.DB().First(&stored).Error; err != nil {
		t.Fatalf("get stored refresh token: %v", err)
	}
	if stored.Token == result.RefreshToken {
		t.Fatal("stored refresh token matches raw token, want hash")
	}
	if stored.Token != hashRefreshToken(result.RefreshToken) {
		t.Fatalf("stored refresh token = %q, want hash", stored.Token)
	}

	refreshed, err := svc.RefreshToken(result.RefreshToken)
	if err != nil {
		t.Fatalf("refresh raw token: %v", err)
	}
	if refreshed.RefreshToken == "" || refreshed.RefreshToken == result.RefreshToken {
		t.Fatalf("refreshed token = %q, want new token", refreshed.RefreshToken)
	}
}

func TestAuthRefreshRejectsAccessTokenEvenIfStoredAsRefreshToken(t *testing.T) {
	svc, repos := newAuthServiceForTest(t)

	result, err := svc.Init("LedgerInitPass123!")
	if err != nil {
		t.Fatalf("init: %v", err)
	}
	users, err := repos.User.GetAll()
	if err != nil || len(users) != 1 {
		t.Fatalf("get initialized user: users=%d err=%v", len(users), err)
	}

	if err := repos.RefreshToken.Create(&model.RefreshToken{
		ID:        uuid.New().String(),
		UserID:    users[0].ID,
		Token:     hashRefreshToken(result.AccessToken),
		ExpiresAt: time.Now().Add(time.Hour),
	}); err != nil {
		t.Fatalf("store access token in refresh table: %v", err)
	}

	if _, err := svc.RefreshToken(result.AccessToken); !errors.Is(err, ErrInvalidToken) {
		t.Fatalf("refresh with access token error = %v, want %v", err, ErrInvalidToken)
	}
}

func TestAuthRefreshRotationRejectsOldRefreshToken(t *testing.T) {
	svc, _ := newAuthServiceForTest(t)

	result, err := svc.Init("LedgerInitPass123!")
	if err != nil {
		t.Fatalf("init: %v", err)
	}
	rotated, err := svc.RefreshToken(result.RefreshToken)
	if err != nil {
		t.Fatalf("rotate refresh token: %v", err)
	}
	if rotated.RefreshToken == result.RefreshToken {
		t.Fatal("rotation returned the old refresh token")
	}

	if _, err := svc.RefreshToken(result.RefreshToken); !errors.Is(err, ErrInvalidToken) {
		t.Fatalf("reuse rotated refresh token error = %v, want %v", err, ErrInvalidToken)
	}
	if _, err := svc.RefreshToken(rotated.RefreshToken); err != nil {
		t.Fatalf("refresh with rotated token: %v", err)
	}
}

func TestAuthLogoutInvalidatesRefreshToken(t *testing.T) {
	svc, _ := newAuthServiceForTest(t)

	result, err := svc.Init("LedgerInitPass123!")
	if err != nil {
		t.Fatalf("init: %v", err)
	}
	claims, err := svc.jwtManager.ValidateAccessToken(result.AccessToken)
	if err != nil {
		t.Fatalf("validate access token: %v", err)
	}
	if err := svc.Logout(claims.UserID); err != nil {
		t.Fatalf("logout: %v", err)
	}

	if _, err := svc.RefreshToken(result.RefreshToken); !errors.Is(err, ErrInvalidToken) {
		t.Fatalf("refresh after logout error = %v, want %v", err, ErrInvalidToken)
	}
}

func TestAuthRefreshMigratesLegacyPlaintextRefreshToken(t *testing.T) {
	svc, repos := newAuthServiceForTest(t)
	passwordHash, err := bcrypt.GenerateFromPassword([]byte("LedgerInitPass123!"), 12)
	if err != nil {
		t.Fatalf("hash password: %v", err)
	}
	user := &model.User{Username: "admin", PasswordHash: string(passwordHash)}
	if err := repos.User.Create(user); err != nil {
		t.Fatalf("create user: %v", err)
	}

	rawToken, expiresAt, err := svc.jwtManager.GenerateRefreshToken(user.ID)
	if err != nil {
		t.Fatalf("generate refresh token: %v", err)
	}
	legacy := &model.RefreshToken{
		ID:        uuid.New().String(),
		UserID:    user.ID,
		Token:     rawToken,
		ExpiresAt: expiresAt.Add(time.Hour),
	}
	if err := repos.RefreshToken.Create(legacy); err != nil {
		t.Fatalf("create legacy refresh token: %v", err)
	}

	if _, err := svc.RefreshToken(rawToken); err != nil {
		t.Fatalf("refresh legacy plaintext token: %v", err)
	}

	var count int64
	if err := repos.User.DB().Model(&model.RefreshToken{}).Where("token = ?", rawToken).Count(&count).Error; err != nil {
		t.Fatalf("count plaintext refresh token: %v", err)
	}
	if count != 0 {
		t.Fatalf("plaintext refresh token rows = %d, want migrated/deleted", count)
	}
}

func TestAuthInitConcurrentRequestsCreateOnlyOneInitialUser(t *testing.T) {
	svc, repos := newAuthServiceForTest(t)

	const attempts = 8
	results := make(chan error, attempts)
	var wg sync.WaitGroup
	for i := 0; i < attempts; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, err := svc.Init("LedgerInitPass123!")
			results <- err
		}()
	}
	wg.Wait()
	close(results)

	successes := 0
	alreadyInitialized := 0
	for err := range results {
		switch {
		case err == nil:
			successes++
		case errors.Is(err, ErrUserExists):
			alreadyInitialized++
		default:
			t.Fatalf("unexpected init error: %v", err)
		}
	}
	if successes != 1 {
		t.Fatalf("successful init calls = %d, want 1", successes)
	}
	if alreadyInitialized != attempts-1 {
		t.Fatalf("already initialized errors = %d, want %d", alreadyInitialized, attempts-1)
	}

	userCount, err := repos.User.Count()
	if err != nil {
		t.Fatalf("count users: %v", err)
	}
	if userCount != 1 {
		t.Fatalf("user count = %d, want 1", userCount)
	}

	users, err := repos.User.GetAll()
	if err != nil {
		t.Fatalf("list users: %v", err)
	}
	categories, err := repos.Category.GetByUserID(users[0].ID, "")
	if err != nil {
		t.Fatalf("list categories: %v", err)
	}
	if len(categories) != 12 {
		t.Fatalf("default categories = %d, want 12", len(categories))
	}
	accounts, err := repos.Account.GetByUserID(users[0].ID, true)
	if err != nil {
		t.Fatalf("list accounts: %v", err)
	}
	if len(accounts) != 4 {
		t.Fatalf("default accounts = %d, want 4", len(accounts))
	}
}
