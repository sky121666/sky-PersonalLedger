package service

import (
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/config"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"gorm.io/gorm"
)

func TestConsistentReadSnapshotPostgresIntegration(t *testing.T) {
	runConsistentReadSnapshotIntegration(t, "postgres", "LEDGER_TEST_POSTGRES_DSN")
}

func TestConsistentReadSnapshotMySQLIntegration(t *testing.T) {
	runConsistentReadSnapshotIntegration(t, "mysql", "LEDGER_TEST_MYSQL_DSN")
}

func runConsistentReadSnapshotIntegration(t *testing.T, driver, environmentKey string) {
	t.Helper()
	dsn := strings.TrimSpace(os.Getenv(environmentKey))
	if dsn == "" {
		t.Skipf("set %s to run %s snapshot integration test", environmentKey, driver)
	}
	db, err := database.InitWithConfig(config.DatabaseConfig{
		Driver: driver, DSN: dsn, MaxOpenConns: 4, MaxIdleConns: 2,
	})
	if err != nil {
		t.Fatalf("init %s: %v", driver, err)
	}
	sqlDB, err := db.DB()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = sqlDB.Close() })
	repos := repository.NewRepositories(db)
	user := &model.User{Username: "snapshot-" + uuid.NewString(), PasswordHash: "integration-test-hash"}
	if err := repos.User.Create(user); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		for _, table := range []any{&model.AccountLog{}, &model.Transaction{}, &model.Account{}, &model.User{}} {
			query := db.Unscoped().Where("user_id = ?", user.ID)
			if _, isUser := table.(*model.User); isUser {
				query = db.Unscoped().Where("id = ?", user.ID)
			}
			if err := query.Delete(table).Error; err != nil {
				t.Errorf("clean %s snapshot fixture: %v", driver, err)
			}
		}
	})
	accountID := uuid.NewString()
	if err := repos.Account.Create(&model.Account{
		ID: accountID, UserID: user.ID, Name: "Snapshot balance", Type: "cash", InitialBalance: 100, CurrentBalance: 100,
	}); err != nil {
		t.Fatal(err)
	}
	transactions := NewTransactionService(repos.Transaction, repos.Account, repos.Reminder, repos.Lending,
		repos.FamilyMember, NewAccountLogService(repos.AccountLog, repos.Account))

	err = db.Connection(func(connection *gorm.DB) error {
		// Make the default deliberately insufficient on the exact connection
		// that opens the snapshot, including MySQL whose usual default is RR.
		statement := "SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED"
		if driver == "postgres" {
			statement = "SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL READ COMMITTED"
		}
		if err := connection.Exec(statement).Error; err != nil {
			return err
		}
		return withConsistentReadSnapshot(connection, func(snapshot *gorm.DB) error {
			var before model.Account
			if err := snapshot.First(&before, "id = ? AND user_id = ?", accountID, user.ID).Error; err != nil {
				return err
			}
			if before.CurrentBalance != 100 {
				return fmt.Errorf("initial snapshot balance=%v, want 100", before.CurrentBalance)
			}
			// While the reader transaction stays open, a separate pooled
			// connection commits the ordinary transaction+balance+log mutation.
			writerDone := make(chan error, 1)
			go func() {
				_, err := transactions.Create(user.ID, CreateTransactionRequest{
					Type: "expense", Amount: 10, AccountID: accountID, TransactionDate: time.Now().UTC().Format(time.RFC3339),
				})
				writerDone <- err
			}()
			select {
			case err := <-writerDone:
				if err != nil {
					return fmt.Errorf("concurrent ledger write: %w", err)
				}
			case <-time.After(10 * time.Second):
				return fmt.Errorf("snapshot prevented concurrent writer from committing")
			}
			var after model.Account
			if err := snapshot.First(&after, "id = ? AND user_id = ?", accountID, user.ID).Error; err != nil {
				return err
			}
			if after.CurrentBalance != before.CurrentBalance {
				return fmt.Errorf("snapshot changed balance from %v to %v", before.CurrentBalance, after.CurrentBalance)
			}
			for _, table := range []any{&model.Transaction{}, &model.AccountLog{}} {
				var count int64
				if err := snapshot.Model(table).Where("user_id = ?", user.ID).Count(&count).Error; err != nil {
					return err
				}
				if count != 0 {
					return fmt.Errorf("snapshot included %d records from later write in %T", count, table)
				}
			}
			return nil
		})
	})
	if err != nil {
		t.Fatalf("%s snapshot isolation: %v", driver, err)
	}
	live, err := repos.Account.GetByID(accountID)
	if err != nil || live.CurrentBalance != 90 {
		t.Fatalf("%s live balance after snapshot: account=%v err=%v", driver, live, err)
	}
	for _, table := range []any{&model.Transaction{}, &model.AccountLog{}} {
		var count int64
		if err := db.Model(table).Where("user_id = ?", user.ID).Count(&count).Error; err != nil {
			t.Fatal(err)
		}
		if count != 1 {
			t.Fatalf("%s live %T count=%d, want committed record", driver, table, count)
		}
	}
	t.Logf("%s: explicit snapshot kept balance 100 and no later transactions/logs while concurrent writer committed balance 90 and one transaction/log", driver)
}
