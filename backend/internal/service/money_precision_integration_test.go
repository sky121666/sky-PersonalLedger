package service

import (
	"os"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/config"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

func TestAccountBalancePrecisionPostgresIntegration(t *testing.T) {
	runAccountBalancePrecisionIntegration(
		t,
		"postgres",
		"LEDGER_TEST_POSTGRES_DSN",
	)
}

func TestAccountBalancePrecisionMySQLIntegration(t *testing.T) {
	runAccountBalancePrecisionIntegration(t, "mysql", "LEDGER_TEST_MYSQL_DSN")
}

func runAccountBalancePrecisionIntegration(
	t *testing.T,
	driver string,
	environmentKey string,
) {
	t.Helper()
	dsn := strings.TrimSpace(os.Getenv(environmentKey))
	if dsn == "" {
		t.Skipf("set %s to run %s money precision integration test", environmentKey, driver)
	}

	db, err := database.InitWithConfig(config.DatabaseConfig{
		Driver:       driver,
		DSN:          dsn,
		MaxOpenConns: 2,
		MaxIdleConns: 1,
	})
	if err != nil {
		t.Fatalf("init %s: %v", driver, err)
	}
	sqlDB, err := db.DB()
	if err != nil {
		t.Fatalf("get %s sql db: %v", driver, err)
	}
	t.Cleanup(func() { _ = sqlDB.Close() })

	repos := repository.NewRepositories(db)
	user := &model.User{
		Username:     "mp-" + uuid.NewString(),
		PasswordHash: "integration-test-hash",
	}
	if err := repos.User.Create(user); err != nil {
		t.Fatalf("create %s user: %v", driver, err)
	}
	accountID := uuid.NewString()
	if err := repos.Account.Create(&model.Account{
		ID:             accountID,
		UserID:         user.ID,
		Name:           "Minor unit precision",
		Type:           "cash",
		CurrentBalance: 0,
	}); err != nil {
		t.Fatalf("create %s account: %v", driver, err)
	}

	accountLogSvc := NewAccountLogService(repos.AccountLog, repos.Account)
	svc := NewTransactionService(
		repos.Transaction,
		repos.Account,
		repos.Reminder,
		repos.Lending,
		repos.FamilyMember,
		accountLogSvc,
	)
	for range 100 {
		if err := svc.updateAccountBalanceTx(db, user.ID, accountID, 0.01); err != nil {
			t.Fatalf("add %s cent balance: %v", driver, err)
		}
	}
	account, err := repos.Account.GetByID(accountID)
	if err != nil {
		t.Fatalf("get %s accumulated account: %v", driver, err)
	}
	if account.CurrentBalance != 1 {
		t.Fatalf(
			"%s accumulated balance = %.17f, want 1.00",
			driver,
			account.CurrentBalance,
		)
	}

	for range 100 {
		if err := svc.updateAccountBalanceTx(db, user.ID, accountID, -0.01); err != nil {
			t.Fatalf("subtract %s cent balance: %v", driver, err)
		}
	}
	account, err = repos.Account.GetByID(accountID)
	if err != nil {
		t.Fatalf("get %s zeroed account: %v", driver, err)
	}
	if account.CurrentBalance != 0 {
		t.Fatalf(
			"%s zeroed balance = %.17f, want 0.00",
			driver,
			account.CurrentBalance,
		)
	}
}
