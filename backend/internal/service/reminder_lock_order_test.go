package service

import (
	"context"
	"database/sql"
	"sync"
	"testing"
	"time"

	"github.com/sky/personal-ledger/internal/repository"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

type reminderBeginObserver struct {
	gorm.ConnPool
	beginner gorm.TxBeginner
	began    chan struct{}
	once     sync.Once
}

// Inspect the server-dialect lock request while using an isolated SQLite DB.
// This checks query construction/order, not PostgreSQL/MySQL runtime behavior.
func TestReminderEditsLockReminderBeforeLinkedAccount(t *testing.T) {
	for _, method := range []string{"update", "patch"} {
		t.Run(method, func(t *testing.T) {
			_, repos, userID := newTransactionTestService(t)
			svc, _ := repaymentServices(repos)
			accountID := createAccountForTest(t, repos, userID, 0)
			r, err := svc.Create(userID, CreateReminderRequest{Name: "before", PaymentDay: 1})
			if err != nil {
				t.Fatal(err)
			}
			db := repos.Account.DB().Session(&gorm.Session{NewDB: true, Context: context.Background()})
			db.Dialector = snapshotTestDialector{Dialector: db.Dialector, name: "postgres"}
			svc.txRepo = repository.NewTransactionRepository(db)
			seenReminder, lockedReminder, accountBeforeReminder := false, false, false
			const name = "test:observe-reminder-lock-order"
			if err := db.Callback().Query().Before("gorm:query").Register(name, func(tx *gorm.DB) {
				if tx.Statement.Schema == nil {
					return
				}
				if tx.Statement.Schema.Table == "reminders" && !seenReminder {
					seenReminder = true
					lock, ok := tx.Statement.Clauses["FOR"].Expression.(clause.Locking)
					lockedReminder = ok && lock.Strength == "UPDATE"
				}
				if tx.Statement.Schema.Table == "accounts" && !seenReminder {
					accountBeforeReminder = true
				}
			}); err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { _ = db.Callback().Query().Remove(name) })
			if method == "update" {
				_, err = svc.Update(r.ID, userID, CreateReminderRequest{Name: "after", PaymentDay: 1, AccountID: &accountID})
			} else {
				_, err = svc.Patch(r.ID, userID, PatchReminderRequest{AccountID: Optional[string]{Set: true, Value: accountID}})
			}
			if err != nil {
				t.Fatal(err)
			}
			if !lockedReminder || accountBeforeReminder {
				t.Fatalf("edit lock order: reminderLocked=%v, accountBeforeReminder=%v", lockedReminder, accountBeforeReminder)
			}
		})
	}
}

func (p *reminderBeginObserver) BeginTx(ctx context.Context, opts *sql.TxOptions) (gorm.ConnPool, error) {
	p.once.Do(func() { close(p.began) })
	return p.beginner.BeginTx(ctx, opts)
}

func TestReminderEditsWaitForAttachmentBarrierBeforeOpeningFinanceTransaction(t *testing.T) {
	for _, method := range []string{"update", "patch"} {
		t.Run(method, func(t *testing.T) {
			f := newBackupIntegrityFixture(t)
			svc, _ := repaymentServices(f.repos)
			svc.WithUploadService(f.service.uploadService)
			r, err := svc.Create(f.user.ID, CreateReminderRequest{Name: "before", PaymentDay: 1})
			if err != nil {
				t.Fatal(err)
			}
			pool := &reminderBeginObserver{ConnPool: f.db.Statement.ConnPool, beginner: f.db.Statement.ConnPool.(gorm.TxBeginner), began: make(chan struct{})}
			observed := f.db.Session(&gorm.Session{NewDB: true, Context: context.Background()})
			observed.Statement.ConnPool = pool
			svc.txRepo = repository.NewTransactionRepository(observed)
			release := acquireAttachmentStorageWrite()
			done := make(chan error, 1)
			go func() {
				var err error
				if method == "update" {
					_, err = svc.Update(r.ID, f.user.ID, CreateReminderRequest{Name: "after", PaymentDay: 1})
				} else {
					_, err = svc.Patch(r.ID, f.user.ID, PatchReminderRequest{Name: Optional[string]{Set: true, Value: "after"}})
				}
				done <- err
			}()
			openedBeforeStorage := false
			select {
			case <-pool.began:
				openedBeforeStorage = true
			case <-time.After(100 * time.Millisecond):
			}
			// Always release the test barrier and drain the writer, including RED,
			// so a broken lock order cannot hang this test process or later tests.
			release()
			select {
			case err := <-done:
				if err != nil {
					t.Fatal(err)
				}
			case <-time.After(5 * time.Second):
				t.Fatal("edit did not finish after barrier release")
			}
			if openedBeforeStorage {
				t.Fatal("reminder edit opened finance transaction while attachment writer still held the barrier")
			}
			current, err := svc.GetByID(r.ID, f.user.ID)
			if err != nil || current.Name != "after" {
				t.Fatalf("edit not persisted: %+v, %v", current, err)
			}
		})
	}
}
