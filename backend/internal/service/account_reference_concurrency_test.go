package service

import (
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

// Pause after validation, before the reference write. Deletion must wait for
// the writer and reject its committed reference, or win before validation and
// make the writer reject the deleted account; both succeeding is an orphan.
func TestAccountDeletionCannotRaceReferenceCreation(t *testing.T) {
	for _, kind := range []string{"reminder_create", "reminder_update", "reminder_patch", "lending", "template", "transaction"} {
		t.Run(kind, func(t *testing.T) {
			txSvc, repos, userID := newTransactionTestService(t)
			reminders, lendings := repaymentServices(repos)
			accountID := createAccountForTest(t, repos, userID, 0)
			db := repos.Account.DB()
			var reminderID string
			if kind == "reminder_update" || kind == "reminder_patch" {
				r, err := reminders.Create(userID, CreateReminderRequest{Name: "before", PaymentDay: 1})
				if err != nil {
					t.Fatal(err)
				}
				reminderID = r.ID
			}
			entered, release := make(chan struct{}), make(chan struct{})
			var once sync.Once
			callback := func(tx *gorm.DB) {
				if tx.Statement.Schema != nil && ((kind == "transaction" && tx.Statement.Schema.Table == "transactions") || (kind == "lending" && tx.Statement.Schema.Table == "lendings") || (kind == "template" && tx.Statement.Schema.Table == "quick_templates") || (kind != "lending" && kind != "template" && kind != "transaction" && tx.Statement.Schema.Table == "reminders")) {
					once.Do(func() { close(entered); <-release })
				}
			}
			const name = "test:pause-reference-write"
			if err := db.Callback().Create().Before("gorm:create").Register(name, callback); err != nil {
				t.Fatal(err)
			}
			if err := db.Callback().Update().Before("gorm:update").Register(name, callback); err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { _ = db.Callback().Create().Remove(name); _ = db.Callback().Update().Remove(name) })
			created := make(chan error, 1)
			go func() {
				var err error
				switch kind {
				case "reminder_create":
					_, err = reminders.Create(userID, CreateReminderRequest{Name: "loan", PaymentDay: 1, AccountID: &accountID})
				case "reminder_update":
					_, err = reminders.Update(reminderID, userID, CreateReminderRequest{Name: "loan", PaymentDay: 1, AccountID: &accountID})
				case "reminder_patch":
					_, err = reminders.Patch(reminderID, userID, PatchReminderRequest{AccountID: Optional[string]{Set: true, Value: accountID}})
				case "lending":
					_, err = lendings.Create(userID, CreateLendingRequest{Type: "borrow_in", ContactName: "test", Principal: 10, LendDate: "2026-04-30", AccountID: &accountID})
				case "template":
					_, err = NewTemplateService(repos.Template, txSvc).Create(userID, CreateTemplateRequest{Name: "test", Type: "expense", AccountID: accountID})
				case "transaction":
					_, err = txSvc.Create(userID, CreateTransactionRequest{Type: "expense", AccountID: accountID, Amount: 1, TransactionDate: "2026-04-30"})
				}
				created <- err
			}()
			select {
			case <-entered:
			case <-time.After(5 * time.Second):
				t.Fatal("reference write never reached barrier")
			}
			deleted := make(chan error, 1)
			go func() { deleted <- NewAccountService(repos.Account).Delete(accountID, userID) }()
			var deleteErr error
			select {
			case deleteErr = <-deleted:
				close(release)
			case <-time.After(100 * time.Millisecond):
				close(release)
				deleteErr = <-deleted
			}
			createErr := <-created
			if createErr == nil && deleteErr == nil {
				t.Fatal("reference creation and account deletion both succeeded")
			}
			if createErr != nil {
				t.Fatalf("writer holding account validation must complete: %v", createErr)
			}
			if !errors.Is(deleteErr, ErrAccountHasHistory) {
				t.Fatalf("delete after reference commit=%v, want history rejection", deleteErr)
			}
			var account model.Account
			if err := db.First(&account, "id = ?", accountID).Error; err != nil {
				t.Fatalf("referenced account disappeared: %v", err)
			}
		})
	}
}

func TestReferenceCreationRechecksAccountAfterWaitingForDeletion(t *testing.T) {
	for _, kind := range []string{"reminder", "lending", "template", "transaction"} {
		t.Run(kind, func(t *testing.T) {
			txSvc, repos, userID := newTransactionTestService(t)
			reminders, lendings := repaymentServices(repos)
			accountID := createAccountForTest(t, repos, userID, 0)
			db := repos.Account.DB()
			entered, release := make(chan struct{}), make(chan struct{})
			const name = "test:pause-account-deletion"
			if err := db.Callback().Delete().Before("gorm:delete").Register(name, func(tx *gorm.DB) {
				if tx.Statement.Schema != nil && tx.Statement.Schema.Table == "accounts" {
					close(entered)
					<-release
				}
			}); err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { _ = db.Callback().Delete().Remove(name) })
			deleted := make(chan error, 1)
			go func() { deleted <- NewAccountService(repos.Account).Delete(accountID, userID) }()
			select {
			case <-entered:
			case <-time.After(5 * time.Second):
				t.Fatal("delete barrier not reached")
			}
			created := make(chan error, 1)
			go func() {
				var err error
				switch kind {
				case "reminder":
					_, err = reminders.Create(userID, CreateReminderRequest{Name: "test", PaymentDay: 1, AccountID: &accountID})
				case "lending":
					_, err = lendings.Create(userID, CreateLendingRequest{Type: "borrow_in", ContactName: "test", Principal: 10, LendDate: "2026-04-30", AccountID: &accountID})
				case "template":
					_, err = NewTemplateService(repos.Template, txSvc).Create(userID, CreateTemplateRequest{Name: "test", Type: "expense", AccountID: accountID})
				case "transaction":
					_, err = txSvc.Create(userID, CreateTransactionRequest{Type: "expense", AccountID: accountID, Amount: 1, TransactionDate: "2026-04-30"})
				}
				created <- err
			}()
			close(release)
			if err := <-deleted; err != nil {
				t.Fatalf("delete holding account lock: %v", err)
			}
			if err := <-created; !errors.Is(err, ErrAccountNotFound) {
				t.Fatalf("new reference after deletion=%v, want missing account", err)
			}
		})
	}
}
