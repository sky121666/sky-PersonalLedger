package service

import (
	"errors"
	"fmt"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/config"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/money"
	"github.com/sky/personal-ledger/internal/repository"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

func TestDebtServerConcurrencyIntegration(t *testing.T) {
	for _, driver := range []string{"postgres", "mysql"} {
		t.Run(driver, func(t *testing.T) {
			dsn := strings.TrimSpace(os.Getenv("LEDGER_TEST_" + strings.ToUpper(driver) + "_DSN"))
			if dsn == "" {
				t.Skip("isolated database DSN not supplied")
			}
			db, err := database.InitWithConfig(config.DatabaseConfig{
				Driver: driver, DSN: dsn, MaxOpenConns: 8, MaxIdleConns: 4,
			})
			if err != nil {
				t.Fatal(err)
			}
			sqlDB, err := db.DB()
			if err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { _ = sqlDB.Close() })

			t.Run("same-key-replays", func(t *testing.T) {
				f := newDebtServerFixture(t, db)
				req := DebtPaymentRequest{AccountID: &f.debt, SourceKind: "account", SourceAccountID: &f.cash,
					Amount: 10, Allocations: []DebtPaymentPart{{PlanID: f.a, Principal: 10}}, IdempotencyKey: "simultaneous"}
				start := make(chan struct{})
				results := make(chan *model.DebtOperation, 6)
				failures := make(chan error, 6)
				var group sync.WaitGroup
				for range 6 {
					group.Add(1)
					go func() {
						defer group.Done()
						<-start
						op, err := NewDebtService(db).Pay(f.user, req)
						results <- op
						failures <- err
					}()
				}
				close(start)
				group.Wait()
				close(results)
				close(failures)
				for err := range failures {
					if err != nil {
						t.Fatalf("same-key request did not replay: %v", err)
					}
				}
				id := ""
				for op := range results {
					if op == nil || (id != "" && op.ID != id) {
						t.Fatalf("same request returned different operations: %+v", op)
					}
					id = op.ID
				}
				debtAssert(t, f, 990, 1990, 590, 300, 100, 0)
				req.Amount, req.Allocations[0].Principal = 11, 11
				if _, err := f.svc.Pay(f.user, req); !errors.Is(err, ErrIdempotencyConflict) {
					t.Fatalf("different payload reused key: %v", err)
				}
			})

			t.Run("user-lock-before-read", func(t *testing.T) {
				f := newDebtServerFixture(t, db)
				holder := db.Begin()
				if holder.Error != nil {
					t.Fatal(holder.Error)
				}
				defer holder.Rollback()
				var user model.User
				if err := holder.Clauses(clause.Locking{Strength: "UPDATE"}).First(&user, f.user).Error; err != nil {
					t.Fatal(err)
				}
				done := make(chan error, 1)
				started := make(chan struct{})
				go func() {
					close(started)
					_, err := f.svc.Pay(f.user, DebtPaymentRequest{AccountID: &f.debt, SourceKind: "external",
						Amount: 10, Allocations: []DebtPaymentPart{{PlanID: f.a, Principal: 10}}, IdempotencyKey: "held"})
					done <- err
				}()
				<-started
				select {
				case err := <-done:
					t.Fatalf("debt write passed a held user lock: %v", err)
				case <-time.After(200 * time.Millisecond):
				}
				if err := holder.Commit().Error; err != nil {
					t.Fatal(err)
				}
				select {
				case err := <-done:
					if err != nil {
						t.Fatal(err)
					}
				case <-time.After(10 * time.Second):
					t.Fatal("debt writer did not resume")
				}
				debtAssert(t, f, 990, 2000, 590, 300, 100, 0)
			})

			t.Run("allocation-and-parent-reversal", func(t *testing.T) {
				f := newDebtServerFixture(t, db)
				payment, err := f.svc.Pay(f.user, DebtPaymentRequest{AccountID: &f.debt, SourceKind: "account",
					SourceAccountID: &f.cash, Amount: 10, UnappliedAmount: 10, IdempotencyKey: "pending"})
				if err != nil {
					t.Fatal(err)
				}
				start, results := make(chan struct{}), make(chan error, 2)
				go func() {
					<-start
					_, err := f.svc.Allocate(f.user, payment.ID, DebtAllocateRequest{
						Allocations: []DebtPaymentPart{{PlanID: f.a, Principal: 10}}, IdempotencyKey: "assign"})
					results <- err
				}()
				go func() {
					<-start
					_, err := f.svc.Reverse(f.user, payment.ID, DebtReverseRequest{IdempotencyKey: "undo"})
					results <- err
				}()
				close(start)
				for range 2 {
					if err := <-results; err != nil && !errors.Is(err, ErrDebtDependency) {
						t.Fatal(err)
					}
				}
				debtAssert(t, f, 1000, 2000, 600, 300, 100, 0)
				if _, err := debtBackupService(f).CreateBackup(f.user); err != nil {
					t.Fatalf("concurrency left invalid backup evidence: %v", err)
				}
			})

			t.Run("import-rollback-honors-user-lock", func(t *testing.T) {
				f := newDebtServerFixture(t, db)
				importer := NewTransactionImportService(f.tx)
				raw := fmt.Sprintf(`{"transactions":[{"type":"transfer","account_id":%q,"to_account_id":%q,"amount":10,"transaction_date":"2026-10-18"}]}`,
					f.cash, f.debt)
				preview, err := importer.Preview(f.user, "synthetic.json", strings.NewReader(raw))
				if err != nil {
					t.Fatal(err)
				}
				if _, err := importer.Commit(f.user, preview.ID); err != nil {
					t.Fatal(err)
				}
				holder := db.Begin()
				if holder.Error != nil {
					t.Fatal(holder.Error)
				}
				defer holder.Rollback()
				var user model.User
				if err := holder.Clauses(clause.Locking{Strength: "UPDATE"}).First(&user, f.user).Error; err != nil {
					t.Fatal(err)
				}
				done := make(chan error, 1)
				go func() {
					_, err := importer.Rollback(f.user, preview.ID)
					done <- err
				}()
				select {
				case err := <-done:
					t.Fatalf("import rollback passed a held user lock: %v", err)
				case <-time.After(200 * time.Millisecond):
				}
				if err := holder.Commit().Error; err != nil {
					t.Fatal(err)
				}
				select {
				case err := <-done:
					if err != nil {
						t.Fatal(err)
					}
				case <-time.After(10 * time.Second):
					t.Fatal("import rollback did not resume")
				}
				debtAssert(t, f, 1000, 2000, 600, 300, 100, 0)
			})

			t.Run("standalone-interest-and-cancellation", func(t *testing.T) {
				f := newDebtServerFixture(t, db)
				plan, err := f.svc.CreatePlan(f.user, CreateDebtPlanRequest{Name: "Independent", Scope: "standalone",
					OriginalPrincipal: 100, OpeningPrincipal: 100, IdempotencyKey: "independent"})
				if err != nil {
					t.Fatal(err)
				}
				var opening model.DebtAllocation
				if err := db.First(&opening, "plan_id = ?", plan.ID).Error; err != nil {
					t.Fatal(err)
				}
				start, results := make(chan struct{}), make(chan error, 2)
				go func() {
					<-start
					_, err := f.svc.BookInterest(f.user, plan.ID, DebtInterestRequest{Amount: 20, IdempotencyKey: "charge"})
					results <- err
				}()
				go func() {
					<-start
					_, err := f.svc.Reverse(f.user, opening.OperationID, DebtReverseRequest{IdempotencyKey: "cancel"})
					results <- err
				}()
				close(start)
				for range 2 {
					if err := <-results; err != nil && !errors.Is(err, ErrDebtDependency) && !errors.Is(err, ErrInvalidDebtRequest) {
						t.Fatal(err)
					}
				}
				got, err := f.svc.GetPlan(f.user, plan.ID)
				if err != nil || (got.Status == "cancelled" && (got.PrincipalBalance != 0 || got.InterestBalance != 0 || got.InterestPaid != 0)) {
					t.Fatalf("cancelled plan retains amounts: %+v %v", got, err)
				}
				if _, err := debtBackupService(f).CreateBackup(f.user); err != nil {
					t.Fatal(err)
				}
			})
		})
	}
}

func newDebtServerFixture(t *testing.T, db *gorm.DB) debtFixture {
	t.Helper()
	repos := repository.NewRepositories(db)
	user := model.User{Username: "debt-" + uuid.NewString(), PasswordHash: "synthetic-test-hash"}
	if err := repos.User.Create(&user); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		for _, table := range []any{&model.DebtAllocation{}, &model.DebtOperation{}, &model.DebtPlan{},
			&model.AccountLog{}, &model.Transaction{}, &model.Category{}, &model.Account{}} {
			if err := db.Unscoped().Where("user_id = ?", user.ID).Delete(table).Error; err != nil {
				t.Error(err)
			}
		}
		if err := db.Unscoped().Delete(&model.User{}, user.ID).Error; err != nil {
			t.Error(err)
		}
	})
	account, err := NewAccountService(repos.Account).Create(user.ID, CreateAccountRequest{
		Name: "Synthetic managed card", Type: "credit", InitialBalance: 1000, DebtTrackingMode: model.DebtModeManaged,
	})
	if err != nil {
		t.Fatal(err)
	}
	f := debtFixture{svc: NewDebtService(db), repos: repos, user: user.ID, debt: account.ID,
		cash: createAccountForTest(t, repos, user.ID, 2000)}
	f.tx = NewTransactionService(repos.Transaction, repos.Account, repos.Reminder, repos.Lending,
		repos.FamilyMember, NewAccountLogService(repos.AccountLog, repos.Account))
	for i, amount := range []float64{600, 300} {
		plan, err := f.svc.CreatePlan(user.ID, CreateDebtPlanRequest{Name: "Synthetic plan", Scope: "account",
			AccountID: &f.debt, OriginalPrincipal: money.Amount(amount), OpeningPrincipal: money.Amount(amount),
			IdempotencyKey: []string{"open-A", "open-B"}[i]})
		if err != nil {
			t.Fatal(err)
		}
		if i == 0 {
			f.a = plan.ID
		} else {
			f.b = plan.ID
		}
	}
	return f
}
