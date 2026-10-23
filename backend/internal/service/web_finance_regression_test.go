package service

import (
	"encoding/json"
	"errors"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/money"
	"github.com/sky/personal-ledger/internal/repository"
)

func TestAccountDeleteRejectsHistoricalAndBusinessReferences(t *testing.T) {
	for _, kind := range []string{"transaction", "transfer_target", "deleted_transaction", "account_log", "reminder", "deleted_reminder", "lending", "lending_record", "template", "recurring"} {
		t.Run(kind, func(t *testing.T) {
			_, repos, userID := newTransactionTestService(t)
			db := repos.Account.DB()
			id := createAccountForTest(t, repos, userID, 0)
			var row any
			switch kind {
			case "transaction", "deleted_transaction", "transfer_target":
				tx := &model.Transaction{ID: uuid.NewString(), UserID: userID, AccountID: id, Type: "expense", Amount: 1, TransactionDate: time.Now()}
				if kind == "transfer_target" {
					tx.AccountID = createAccountForTest(t, repos, userID, 0)
					tx.ToAccountID = &id
					tx.Type = "transfer"
				}
				row = tx
			case "account_log":
				row = &model.AccountLog{ID: uuid.NewString(), UserID: userID, AccountID: id, Type: "adjustment"}
			case "reminder", "deleted_reminder":
				row = &model.Reminder{ID: uuid.NewString(), UserID: userID, AccountID: &id, PaymentDay: 15}
			case "lending":
				row = &model.Lending{ID: uuid.NewString(), UserID: userID, AccountID: &id, Type: "borrow_in", ContactName: "test", Principal: 1, LendDate: time.Now()}
			case "lending_record":
				lending := &model.Lending{ID: uuid.NewString(), UserID: userID, Type: "borrow_in", ContactName: "test", Principal: 1, LendDate: time.Now()}
				if err := db.Create(lending).Error; err != nil {
					t.Fatal(err)
				}
				row = &model.LendingRecord{ID: uuid.NewString(), UserID: userID, LendingID: lending.ID, AccountID: &id, Type: "repay", Amount: 1, RecordDate: time.Now()}
			case "template":
				row = &model.QuickTemplate{ID: uuid.NewString(), UserID: userID, AccountID: id, Name: "test", Type: "expense"}
			case "recurring":
				row = &model.RecurringTransaction{ID: uuid.NewString(), UserID: userID, AccountID: id, Name: "test", Type: "expense", Frequency: "monthly", StartDate: time.Now()}
			}
			if err := db.Create(row).Error; err != nil {
				t.Fatal(err)
			}
			if strings.HasPrefix(kind, "deleted_") {
				if err := db.Delete(row).Error; err != nil {
					t.Fatal(err)
				}
			}
			if err := NewAccountService(repos.Account).Delete(id, userID); err == nil {
				t.Fatal("referenced account was deleted")
			}
			if _, err := repos.Account.GetByID(id); err != nil {
				t.Fatalf("account disappeared: %v", err)
			}
		})
	}
}

func repaymentServices(repos *repository.Repositories) (*ReminderService, *LendingService) {
	logs := NewAccountLogService(repos.AccountLog, repos.Account)
	return NewReminderService(repos.Reminder, repos.Account, repos.Transaction, repos.Category, logs), NewLendingService(repos.Lending, repos.Account, repos.Transaction, repos.Category, logs)
}

func TestReminderPaymentIdempotencySurvivesRetryAndRejectsChangedPayload(t *testing.T) {
	_, repos, userID := newTransactionTestService(t)
	svc, _ := repaymentServices(repos)
	cash := createAccountForTest(t, repos, userID, 1000)
	debt := createTypedAccountForTest(t, repos, userID, "loan", 500)
	balance := money.Amount(500)
	r, err := svc.Create(userID, CreateReminderRequest{Name: "loan", PaymentDay: 31, AccountID: &debt, Principal: &balance, CurrentBalance: &balance})
	if err != nil {
		t.Fatal(err)
	}
	var req RecordPaymentRequest
	if err := json.Unmarshal([]byte(`{"amount":120,"principal_amount":100,"interest_amount":20,"account_id":"`+cash+`","idempotency_key":"retry-1"}`), &req); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 2; i++ {
		svc, _ = repaymentServices(repos)
		if _, err := svc.RecordPayment(r.ID, userID, req); err != nil {
			t.Fatal(err)
		}
	}
	a, _ := repos.Account.GetByID(cash)
	if a.CurrentBalance != 880 {
		t.Fatalf("cash balance = %v, want 880 after duplicate retry", a.CurrentBalance)
	}
	req.Amount = 130
	req.InterestAmount = 30
	if _, err := svc.RecordPayment(r.ID, userID, req); !errors.Is(err, ErrIdempotencyConflict) {
		t.Fatalf("changed payload error = %v, want idempotency conflict", err)
	}
}

func TestLendingRepaymentIdempotencySurvivesSettlement(t *testing.T) {
	_, repos, userID := newTransactionTestService(t)
	_, svc := repaymentServices(repos)
	cash := createAccountForTest(t, repos, userID, 1000)
	lending, err := svc.Create(userID, CreateLendingRequest{Type: "borrow_in", ContactName: "test", Principal: 100, LendDate: "2026-04-01"})
	if err != nil {
		t.Fatal(err)
	}
	var req RecordRepaymentRequest
	if err := json.Unmarshal([]byte(`{"amount":100,"record_date":"2026-04-30","account_id":"`+cash+`","create_transaction":true,"idempotency_key":"retry-1"}`), &req); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 2; i++ {
		_, svc = repaymentServices(repos)
		if _, err := svc.RecordRepayment(lending.ID, userID, req); err != nil {
			t.Fatalf("attempt %d: %v", i, err)
		}
	}
	a, _ := repos.Account.GetByID(cash)
	if a.CurrentBalance != 900 {
		t.Fatalf("cash balance = %v, want 900", a.CurrentBalance)
	}
	req.Amount = 99
	if _, err := svc.RecordRepayment(lending.ID, userID, req); !errors.Is(err, ErrIdempotencyConflict) {
		t.Fatalf("changed payload error = %v, want idempotency conflict", err)
	}
}

func TestAIAccountChangesIncludeRepaymentPrincipalWithoutDoubleCounting(t *testing.T) {
	svc, provider, userID := newAIReportTestServices(t)
	repos := repository.NewRepositories(provider.repo.DB())
	reminders, _ := repaymentServices(repos)
	cash := createAccountForTest(t, repos, userID, 1000)
	debt := createTypedAccountForTest(t, repos, userID, "loan", 500)
	balance := money.Amount(500)
	r, err := reminders.Create(userID, CreateReminderRequest{Name: "loan", PaymentDay: 31, AccountID: &debt, Principal: &balance, CurrentBalance: &balance})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := reminders.RecordPayment(r.ID, userID, RecordPaymentRequest{Amount: 120, PrincipalAmount: 100, InterestAmount: 20, AccountID: &cash}); err != nil {
		t.Fatal(err)
	}
	var snapshot aiReportSnapshot
	if err := svc.appendAccountSnapshot(userID, time.Now().Add(-time.Hour), time.Now().Add(time.Hour), false, &snapshot); err != nil {
		t.Fatal(err)
	}
	changes := map[string]money.Amount{}
	for _, change := range snapshot.AccountChanges {
		changes[change.AccountName] = change.BalanceDelta
	}
	if changes["Wallet cash"] != -120 || changes["Wallet loan"] != -100 {
		t.Fatalf("account changes = %v, want cash -120 and loan -100", changes)
	}
	txSvc := NewTransactionService(repos.Transaction, repos.Account, repos.Reminder, repos.Lending, repos.FamilyMember, NewAccountLogService(repos.AccountLog, repos.Account))
	if err := txSvc.Delete(findReminderTransactionID(t, repos, userID, r.ID), userID); err != nil {
		t.Fatal(err)
	}
	snapshot.AccountChanges = nil
	if err := svc.appendAccountSnapshot(userID, time.Now().Add(-time.Hour), time.Now().Add(time.Hour), false, &snapshot); err != nil {
		t.Fatal(err)
	}
	if len(snapshot.AccountChanges) != 0 {
		t.Fatalf("reversed payment still counted: %+v", snapshot.AccountChanges)
	}
	if _, err := reminders.RecordPayment(r.ID, userID, RecordPaymentRequest{Amount: 120, PrincipalAmount: 100, InterestAmount: 20}); err != nil {
		t.Fatal(err)
	}
	if err := svc.appendAccountSnapshot(userID, time.Now().Add(-time.Hour), time.Now().Add(time.Hour), false, &snapshot); err != nil {
		t.Fatal(err)
	}
	if len(snapshot.AccountChanges) != 1 || snapshot.AccountChanges[0].AccountName != "Wallet loan" || snapshot.AccountChanges[0].BalanceDelta != -100 {
		t.Fatalf("payment without source account = %+v, want only loan -100", snapshot.AccountChanges)
	}
}

func TestReminderDebtSummaryClampsPaymentDayToMonthEnd(t *testing.T) {
	_, repos, userID := newTransactionTestService(t)
	svc, _ := repaymentServices(repos)
	if _, err := svc.Create(userID, CreateReminderRequest{Name: "month end", PaymentDay: 31}); err != nil {
		t.Fatal(err)
	}
	for _, test := range []struct {
		now  time.Time
		want int
	}{
		{time.Date(2026, 4, 30, 15, 0, 0, 0, time.Local), 0},
		{time.Date(2026, 4, 29, 15, 0, 0, 0, time.Local), 1},
		{time.Date(2028, 2, 29, 15, 0, 0, 0, time.Local), 0},
	} {
		summary, err := svc.getDebtSummaryAt(userID, test.now)
		if err != nil {
			t.Fatal(err)
		}
		if summary.DaysUntilNext != test.want {
			t.Errorf("%v days_until_next = %d, want %d", test.now, summary.DaysUntilNext, test.want)
		}
	}
}

func TestReminderNextMonthAfterThirtyFirstDoesNotSkipFebruary(t *testing.T) {
	if got := daysUntilNextMonthDay(time.Date(2026, 1, 31, 15, 0, 0, 0, time.Local), 1); got != 1 {
		t.Fatalf("January 31 to February 1 = %d days, want 1", got)
	}
}

func TestRepaymentIdempotencyConcurrentRequestsAndRollback(t *testing.T) {
	_, repos, userID := newTransactionTestService(t)
	svc, _ := repaymentServices(repos)
	cash := createAccountForTest(t, repos, userID, 1000)
	r, err := svc.Create(userID, CreateReminderRequest{Name: "loan", PaymentDay: 1})
	if err != nil {
		t.Fatal(err)
	}
	req := RecordPaymentRequest{Amount: 10, AccountID: &cash, IdempotencyKey: "parallel"}
	var wg sync.WaitGroup
	errs := make(chan error, 6)
	for i := 0; i < 6; i++ {
		wg.Add(1)
		go func() { defer wg.Done(); _, err := svc.RecordPayment(r.ID, userID, req); errs <- err }()
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		if err != nil {
			t.Fatal(err)
		}
	}
	a, _ := repos.Account.GetByID(cash)
	if a.CurrentBalance != 990 {
		t.Fatalf("concurrent balance = %v, want 990", a.CurrentBalance)
	}
	missing := uuid.NewString()
	req.IdempotencyKey = "rollback"
	req.AccountID = &missing
	if _, err := svc.RecordPayment(r.ID, userID, req); !errors.Is(err, ErrAccountNotFound) {
		t.Fatalf("missing account error = %v", err)
	}
	req.AccountID = &cash
	if _, err := svc.RecordPayment(r.ID, userID, req); err != nil {
		t.Fatalf("failed request consumed its key: %v", err)
	}
	a, _ = repos.Account.GetByID(cash)
	if a.CurrentBalance != 980 {
		t.Fatalf("retry balance = %v, want 980", a.CurrentBalance)
	}
}

func TestRepaymentIdempotencyBackupRoundTrip(t *testing.T) {
	f := newBackupIntegrityFixture(t)
	svc, _ := repaymentServices(f.repos)
	r, err := svc.Create(f.user.ID, CreateReminderRequest{Name: "loan", PaymentDay: 1})
	if err != nil {
		t.Fatal(err)
	}
	req := RecordPaymentRequest{Amount: 10, IdempotencyKey: "backup-retry"}
	if _, err := svc.RecordPayment(r.ID, f.user.ID, req); err != nil {
		t.Fatal(err)
	}
	backup, err := f.service.CreateBackup(f.user.ID)
	if err != nil {
		t.Fatal(err)
	}
	if err := f.db.Where("user_id = ?", f.user.ID).Delete(&model.RepaymentRequest{}).Error; err != nil {
		t.Fatal(err)
	}
	if _, err := svc.RecordPayment(r.ID, f.user.ID, RecordPaymentRequest{Amount: 20, IdempotencyKey: "after-backup"}); err != nil {
		t.Fatal(err)
	}
	if err := f.service.RestoreBackup(f.user.ID, writeBackupFile(t, backup)); err != nil {
		t.Fatal(err)
	}
	result, err := svc.RecordPayment(r.ID, f.user.ID, req)
	if err != nil {
		t.Fatal(err)
	}
	if result.TotalPaid != 10 {
		t.Fatalf("restored retry total paid = %v, want 10", result.TotalPaid)
	}
	var count int64
	if err := f.db.Model(&model.RepaymentRequest{}).Where("user_id = ?", f.user.ID).Count(&count).Error; err != nil || count != 1 {
		t.Fatalf("restore did not replace claims: count=%d, %v", count, err)
	}
	backup.RepaymentRequests = nil
	if err := f.service.RestoreBackup(f.user.ID, writeBackupFile(t, backup)); err != nil {
		t.Fatalf("legacy backup without claims: %v", err)
	}
	if err := f.db.Model(&model.RepaymentRequest{}).Where("user_id = ?", f.user.ID).Count(&count).Error; err != nil || count != 0 {
		t.Fatalf("legacy restore kept stale claims: count=%d, %v", count, err)
	}
}

func TestRepaymentReplayAfterDeletedTargetBackupCannotApplyAgain(t *testing.T) {
	f := newBackupIntegrityFixture(t)
	svc, _ := repaymentServices(f.repos)
	r, err := svc.Create(f.user.ID, CreateReminderRequest{Name: "loan", PaymentDay: 1})
	if err != nil {
		t.Fatal(err)
	}
	req := RecordPaymentRequest{Amount: 10, IdempotencyKey: "deleted-target"}
	if _, err := svc.RecordPayment(r.ID, f.user.ID, req); err != nil {
		t.Fatal(err)
	}
	if err := svc.Delete(r.ID, f.user.ID); err != nil {
		t.Fatal(err)
	}
	backup, err := f.service.CreateBackup(f.user.ID)
	if err != nil {
		t.Fatal(err)
	}
	if err := f.service.RestoreBackup(f.user.ID, writeBackupFile(t, backup)); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.RecordPayment(r.ID, f.user.ID, req); !errors.Is(err, ErrReminderNotFound) {
		t.Fatalf("deleted target replay = %v", err)
	}
	var restored model.Reminder
	if err := f.db.Unscoped().First(&restored, "id = ?", r.ID).Error; err != nil || !restored.DeletedAt.Valid || restored.TotalPaid != 10 {
		t.Fatalf("replay changed deleted target: %+v, %v", restored, err)
	}
}

func TestRepaymentKeyScopeAndLegacyRequests(t *testing.T) {
	_, repos, userID := newTransactionTestService(t)
	svc, lendingSvc := repaymentServices(repos)
	for i := 0; i < 2; i++ {
		r, err := svc.Create(userID, CreateReminderRequest{Name: "loan", PaymentDay: 1})
		if err != nil {
			t.Fatal(err)
		}
		for _, key := range []string{"shared", "", ""} {
			if _, err := svc.RecordPayment(r.ID, userID, RecordPaymentRequest{Amount: 10, IdempotencyKey: key}); err != nil {
				t.Fatal(err)
			}
		}
		current, _ := svc.GetByID(r.ID, userID)
		if current.TotalPaid != 30 {
			t.Fatalf("target %d total = %v, want 30", i, current.TotalPaid)
		}
	}
	lending, err := lendingSvc.Create(userID, CreateLendingRequest{Type: "borrow_in", ContactName: "test", Principal: 100, LendDate: "2026-04-01"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := lendingSvc.RecordRepayment(lending.ID, userID, RecordRepaymentRequest{Amount: 10, RecordDate: "2026-04-30", IdempotencyKey: "shared"}); err != nil {
		t.Fatal(err)
	}
}

func TestBackupRejectsInvalidRepaymentRequests(t *testing.T) {
	for _, kind := range []string{"other_owner", "missing_target", "invalid_operation", "bad_hash", "duplicate"} {
		t.Run(kind, func(t *testing.T) {
			f := newBackupIntegrityFixture(t)
			svc, _ := repaymentServices(f.repos)
			r, err := svc.Create(f.user.ID, CreateReminderRequest{Name: "loan", PaymentDay: 1})
			if err != nil {
				t.Fatal(err)
			}
			if _, err := svc.RecordPayment(r.ID, f.user.ID, RecordPaymentRequest{Amount: 10, IdempotencyKey: "saved"}); err != nil {
				t.Fatal(err)
			}
			backup, err := f.service.CreateBackup(f.user.ID)
			if err != nil {
				t.Fatal(err)
			}
			switch kind {
			case "other_owner":
				backup.RepaymentRequests[0].UserID++
			case "missing_target":
				backup.RepaymentRequests[0].TargetID = uuid.NewString()
			case "invalid_operation":
				backup.RepaymentRequests[0].Operation = "invalid"
			case "bad_hash":
				backup.RepaymentRequests[0].PayloadHash = "bad"
			case "duplicate":
				backup.RepaymentRequests = append(backup.RepaymentRequests, backup.RepaymentRequests[0])
			}
			if err := f.service.RestoreBackup(f.user.ID, writeBackupFile(t, backup)); err == nil {
				t.Fatal("invalid repayment request restored")
			}
			current, err := svc.GetByID(r.ID, f.user.ID)
			if err != nil || current.TotalPaid != 10 {
				t.Fatalf("rejected restore changed balance: %+v, %v", current, err)
			}
		})
	}
}
