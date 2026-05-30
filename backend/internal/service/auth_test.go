package service

import (
	"errors"
	"path/filepath"
	"sync"
	"testing"

	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/repository"
	"github.com/sky/personal-ledger/pkg/jwt"
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
