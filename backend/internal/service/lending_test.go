package service

import (
	"encoding/json"
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/money"
	"github.com/sky/personal-ledger/internal/repository"
	"gorm.io/gorm"
)

func TestLendingPatchPreservesOmittedAndClearsExplicitNull(t *testing.T) {
	_, repos, userID := newTransactionTestService(t)
	svc := newLendingTestService(repos)
	dueDate := time.Now().AddDate(0, 1, 0).Format(time.RFC3339)
	interestRate := 3.5
	lending, err := svc.Create(userID, CreateLendingRequest{
		Type: "lend_out", ContactName: "Original", ContactPhone: "123",
		Principal: 100, InterestRate: &interestRate, LendDate: time.Now().Format(time.RFC3339), DueDate: &dueDate,
	})
	if err != nil {
		t.Fatalf("create lending: %v", err)
	}
	var request PatchLendingRequest
	if err := json.Unmarshal([]byte(`{"contact_name":"Renamed","due_date":null,"contact_phone":""}`), &request); err != nil {
		t.Fatalf("decode patch: %v", err)
	}
	updated, err := svc.Patch(lending.ID, userID, request)
	if err != nil {
		t.Fatalf("patch lending: %v", err)
	}
	if updated.ContactName != "Renamed" || updated.ContactPhone != "" || updated.DueDate != nil {
		t.Fatalf("patched lending = %#v", updated)
	}
	if updated.InterestRate == nil || *updated.InterestRate != interestRate {
		t.Fatalf("omitted interest rate changed: %#v", updated.InterestRate)
	}
}

func TestLendingGeneratedTransactionsUseDebtAccountDirectionAndRollback(t *testing.T) {
	tests := []struct {
		name        string
		lendingType string
		wantBalance float64
	}{
		{name: "lend out expense increases debt", lendingType: "lend_out", wantBalance: 150},
		{name: "borrow in income reduces debt", lendingType: "borrow_in", wantBalance: 50},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			txSvc, repos, userID := newTransactionTestService(t)
			lendingSvc := newLendingTestService(repos)
			accountID := createTypedAccountForTest(t, repos, userID, "credit", 100)

			lending, err := lendingSvc.Create(userID, CreateLendingRequest{
				Type:              tt.lendingType,
				ContactName:       "Debt account flow",
				Principal:         50,
				LendDate:          "2026-07-31T10:00:00",
				AccountID:         &accountID,
				CreateTransaction: true,
			})
			if err != nil {
				t.Fatalf("create lending: %v", err)
			}
			account, err := repos.Account.GetByID(accountID)
			if err != nil {
				t.Fatalf("get debt account: %v", err)
			}
			assertFloatEqual(t, "debt balance after lending transaction", account.CurrentBalance, tt.wantBalance)

			txIDs := findLendingTransactionIDs(t, repos, userID, lending.ID)
			if len(txIDs) != 1 {
				t.Fatalf("generated transactions = %d, want 1", len(txIDs))
			}
			logs, err := repos.AccountLog.GetByTransactionID(userID, txIDs[0])
			if err != nil || len(logs) != 1 {
				t.Fatalf("generated account logs = %#v, err=%v", logs, err)
			}
			assertFloatEqual(t, "generated log balance after", logs[0].BalanceAfter, tt.wantBalance)

			if err := txSvc.Delete(txIDs[0], userID); err != nil {
				t.Fatalf("delete generated transaction: %v", err)
			}
			account, err = repos.Account.GetByID(accountID)
			if err != nil {
				t.Fatalf("get debt account after rollback: %v", err)
			}
			assertFloatEqual(t, "debt balance after rollback", account.CurrentBalance, 100)
		})
	}
}

func TestDeleteLendingPreservesHistoryAndLinkedTransactionCanStillRollback(t *testing.T) {
	txSvc, repos, userID := newTransactionTestService(t)
	lendingSvc := newLendingTestService(repos)
	accountID := createAccountForTest(t, repos, userID, 1000)

	lending, err := lendingSvc.Create(userID, CreateLendingRequest{
		Type:              "lend_out",
		ContactName:       "张三",
		Principal:         300,
		LendDate:          time.Now().Format(time.RFC3339),
		AccountID:         &accountID,
		CreateTransaction: true,
	})
	if err != nil {
		t.Fatalf("create lending: %v", err)
	}

	if _, err := lendingSvc.RecordRepayment(lending.ID, userID, RecordRepaymentRequest{
		Amount:            100,
		RecordDate:        time.Now().Format(time.RFC3339),
		AccountID:         &accountID,
		CreateTransaction: true,
	}); err != nil {
		t.Fatalf("record repayment: %v", err)
	}
	txIDs := findLendingTransactionIDs(t, repos, userID, lending.ID)
	if len(txIDs) != 2 {
		t.Fatalf("linked lending transactions = %d, want 2", len(txIDs))
	}
	repaymentRecord := requireSingleLendingRecord(t, repos, lending.ID)
	if repaymentRecord.TransactionID == nil {
		t.Fatal("repayment transaction id is nil")
	}

	if err := lendingSvc.Delete(lending.ID, userID); err != nil {
		t.Fatalf("delete lending: %v", err)
	}

	records, err := repos.Lending.GetRecordsByLendingID(lending.ID)
	if err != nil {
		t.Fatalf("get lending records after delete: %v", err)
	}
	if len(records) != 1 {
		t.Fatalf("lending records after delete = %d, want 1", len(records))
	}

	for _, txID := range txIDs {
		tx, err := repos.Transaction.GetByID(txID)
		if err != nil {
			t.Fatalf("get generated transaction after lending delete: %v", err)
		}
		if tx.LendingID == nil || *tx.LendingID != lending.ID {
			t.Fatalf("transaction %s lending_id = %v, want %q", tx.ID, tx.LendingID, lending.ID)
		}
	}
	if err := txSvc.Delete(*repaymentRecord.TransactionID, userID); err != nil {
		t.Fatalf("delete repayment after lending delete: %v", err)
	}

	account, err := repos.Account.GetByID(accountID)
	if err != nil {
		t.Fatalf("get account: %v", err)
	}
	assertFloatEqual(t, "account balance", account.CurrentBalance, 700)
	var archived model.Lending
	if err := repos.Transaction.DB().Unscoped().First(&archived, "id = ? AND user_id = ?", lending.ID, userID).Error; err != nil {
		t.Fatalf("load archived lending: %v", err)
	}
	assertFloatEqual(t, "archived lending balance", archived.CurrentBalance, 300)
}

func TestDeleteLendOutRepaymentTransactionDeletesRepaymentRecord(t *testing.T) {
	txSvc, repos, userID := newTransactionTestService(t)
	lendingSvc := newLendingTestService(repos)
	accountID := createAccountForTest(t, repos, userID, 1000)

	lending, err := lendingSvc.Create(userID, CreateLendingRequest{
		Type:        "lend_out",
		ContactName: "张三",
		Principal:   300,
		LendDate:    time.Now().Format(time.RFC3339),
	})
	if err != nil {
		t.Fatalf("create lending: %v", err)
	}

	if _, err := lendingSvc.RecordRepayment(lending.ID, userID, RecordRepaymentRequest{
		Amount:            100,
		RecordDate:        time.Now().Format(time.RFC3339),
		AccountID:         &accountID,
		CreateTransaction: true,
	}); err != nil {
		t.Fatalf("record repayment: %v", err)
	}
	record := requireSingleLendingRecord(t, repos, lending.ID)
	if record.TransactionID == nil {
		t.Fatal("repayment record transaction_id = nil, want generated transaction")
	}

	if err := txSvc.Delete(*record.TransactionID, userID); err != nil {
		t.Fatalf("delete repayment transaction: %v", err)
	}

	records, err := repos.Lending.GetRecordsByLendingID(lending.ID)
	if err != nil {
		t.Fatalf("get lending records after transaction delete: %v", err)
	}
	if len(records) != 0 {
		t.Fatalf("lending records after transaction delete = %d, want 0", len(records))
	}

	rolledBackLending, err := lendingSvc.GetByID(lending.ID, userID)
	if err != nil {
		t.Fatalf("get rolled back lending: %v", err)
	}
	assertFloatEqual(t, "rolled back current balance", rolledBackLending.CurrentBalance, 300)
	assertFloatEqual(t, "rolled back total repaid", rolledBackLending.TotalRepaid, 0)

	account, err := repos.Account.GetByID(accountID)
	if err != nil {
		t.Fatalf("get account: %v", err)
	}
	assertFloatEqual(t, "account balance", account.CurrentBalance, 1000)
}

func TestDeleteBorrowInRepaymentTransactionRestoresPayable(t *testing.T) {
	txSvc, repos, userID := newTransactionTestService(t)
	lendingSvc := newLendingTestService(repos)
	accountID := createAccountForTest(t, repos, userID, 1000)

	lending, err := lendingSvc.Create(userID, CreateLendingRequest{
		Type:        "borrow_in",
		ContactName: "李四",
		Principal:   500,
		LendDate:    time.Now().Format(time.RFC3339),
	})
	if err != nil {
		t.Fatalf("create lending: %v", err)
	}

	if _, err := lendingSvc.RecordRepayment(lending.ID, userID, RecordRepaymentRequest{
		Amount:            150,
		RecordDate:        time.Now().Format(time.RFC3339),
		AccountID:         &accountID,
		CreateTransaction: true,
	}); err != nil {
		t.Fatalf("record repayment: %v", err)
	}
	record := requireSingleLendingRecord(t, repos, lending.ID)
	if record.TransactionID == nil {
		t.Fatal("repayment record transaction_id = nil, want generated transaction")
	}

	if err := txSvc.Delete(*record.TransactionID, userID); err != nil {
		t.Fatalf("delete repayment transaction: %v", err)
	}

	records, err := repos.Lending.GetRecordsByLendingID(lending.ID)
	if err != nil {
		t.Fatalf("get lending records after transaction delete: %v", err)
	}
	if len(records) != 0 {
		t.Fatalf("lending records after transaction delete = %d, want 0", len(records))
	}

	rolledBackLending, err := lendingSvc.GetByID(lending.ID, userID)
	if err != nil {
		t.Fatalf("get rolled back lending: %v", err)
	}
	assertFloatEqual(t, "rolled back current balance", rolledBackLending.CurrentBalance, 500)
	assertFloatEqual(t, "rolled back total repaid", rolledBackLending.TotalRepaid, 0)

	account, err := repos.Account.GetByID(accountID)
	if err != nil {
		t.Fatalf("get account: %v", err)
	}
	assertFloatEqual(t, "account balance", account.CurrentBalance, 1000)
}

func TestCreateLendingRejectsMissingAccountWithoutCreatingRows(t *testing.T) {
	_, repos, userID := newTransactionTestService(t)
	lendingSvc := newLendingTestService(repos)
	missingAccountID := "missing-account"

	if _, err := lendingSvc.Create(userID, CreateLendingRequest{
		Type:              "lend_out",
		ContactName:       "张三",
		Principal:         300,
		LendDate:          time.Now().Format(time.RFC3339),
		AccountID:         &missingAccountID,
		CreateTransaction: true,
	}); err == nil {
		t.Fatal("expected missing account to fail")
	}

	lendings, err := repos.Lending.GetByUserID(userID, true)
	if err != nil {
		t.Fatalf("list lendings: %v", err)
	}
	if len(lendings) != 0 {
		t.Fatalf("lendings after failed create = %d, want 0", len(lendings))
	}

	transactions, total, err := repos.Transaction.List(repository.TransactionFilter{
		UserID:   userID,
		Page:     1,
		PageSize: 20,
	})
	if err != nil {
		t.Fatalf("list transactions: %v", err)
	}
	if total != 0 || len(transactions) != 0 {
		t.Fatalf("transactions after failed create = total %d len %d, want 0", total, len(transactions))
	}
}

func TestCreateLendingRejectsOtherUserAccountWithoutMutatingAccount(t *testing.T) {
	_, repos, userID := newTransactionTestService(t)
	otherUser := &model.User{Username: "other", PasswordHash: "hash"}
	if err := repos.User.Create(otherUser); err != nil {
		t.Fatalf("create other user: %v", err)
	}
	lendingSvc := newLendingTestService(repos)
	otherAccountID := createAccountForTest(t, repos, otherUser.ID, 1000)

	if _, err := lendingSvc.Create(userID, CreateLendingRequest{
		Type:              "borrow_in",
		ContactName:       "李四",
		Principal:         300,
		LendDate:          time.Now().Format(time.RFC3339),
		AccountID:         &otherAccountID,
		CreateTransaction: true,
	}); err == nil {
		t.Fatal("expected other user's account to fail")
	}

	lendings, err := repos.Lending.GetByUserID(userID, true)
	if err != nil {
		t.Fatalf("list lendings: %v", err)
	}
	if len(lendings) != 0 {
		t.Fatalf("lendings after failed create = %d, want 0", len(lendings))
	}

	otherAccount, err := repos.Account.GetByID(otherAccountID)
	if err != nil {
		t.Fatalf("get other account: %v", err)
	}
	assertFloatEqual(t, "other account balance", otherAccount.CurrentBalance, 1000)
}

func TestRecordRepaymentRejectsMissingAccountWithoutMutatingLending(t *testing.T) {
	_, repos, userID := newTransactionTestService(t)
	lendingSvc := newLendingTestService(repos)
	missingAccountID := "missing-account"

	lending, err := lendingSvc.Create(userID, CreateLendingRequest{
		Type:        "lend_out",
		ContactName: "张三",
		Principal:   300,
		LendDate:    time.Now().Format(time.RFC3339),
	})
	if err != nil {
		t.Fatalf("create lending: %v", err)
	}

	if _, err := lendingSvc.RecordRepayment(lending.ID, userID, RecordRepaymentRequest{
		Amount:            100,
		RecordDate:        time.Now().Format(time.RFC3339),
		AccountID:         &missingAccountID,
		CreateTransaction: true,
	}); err == nil {
		t.Fatal("expected missing account to fail")
	}

	unchangedLending, err := lendingSvc.GetByID(lending.ID, userID)
	if err != nil {
		t.Fatalf("get unchanged lending: %v", err)
	}
	assertFloatEqual(t, "current balance", unchangedLending.CurrentBalance, 300)
	assertFloatEqual(t, "total repaid", unchangedLending.TotalRepaid, 0)
	if unchangedLending.IsSettled {
		t.Fatal("lending should not be settled")
	}

	records, err := repos.Lending.GetRecordsByLendingID(lending.ID)
	if err != nil {
		t.Fatalf("get records: %v", err)
	}
	if len(records) != 0 {
		t.Fatalf("records after failed repayment = %d, want 0", len(records))
	}

	transactions, total, err := repos.Transaction.List(repository.TransactionFilter{
		UserID:   userID,
		Page:     1,
		PageSize: 20,
	})
	if err != nil {
		t.Fatalf("list transactions: %v", err)
	}
	if total != 0 || len(transactions) != 0 {
		t.Fatalf("transactions after failed repayment = total %d len %d, want 0", total, len(transactions))
	}
}

func TestRecordRepaymentRejectsOtherUserAccountWithoutMutatingLending(t *testing.T) {
	_, repos, userID := newTransactionTestService(t)
	otherUser := &model.User{Username: "other", PasswordHash: "hash"}
	if err := repos.User.Create(otherUser); err != nil {
		t.Fatalf("create other user: %v", err)
	}
	lendingSvc := newLendingTestService(repos)
	otherAccountID := createAccountForTest(t, repos, otherUser.ID, 1000)

	lending, err := lendingSvc.Create(userID, CreateLendingRequest{
		Type:        "borrow_in",
		ContactName: "李四",
		Principal:   300,
		LendDate:    time.Now().Format(time.RFC3339),
	})
	if err != nil {
		t.Fatalf("create lending: %v", err)
	}

	if _, err := lendingSvc.RecordRepayment(lending.ID, userID, RecordRepaymentRequest{
		Amount:            100,
		RecordDate:        time.Now().Format(time.RFC3339),
		AccountID:         &otherAccountID,
		CreateTransaction: true,
	}); err == nil {
		t.Fatal("expected other user's account to fail")
	}

	unchangedLending, err := lendingSvc.GetByID(lending.ID, userID)
	if err != nil {
		t.Fatalf("get unchanged lending: %v", err)
	}
	assertFloatEqual(t, "current balance", unchangedLending.CurrentBalance, 300)
	assertFloatEqual(t, "total repaid", unchangedLending.TotalRepaid, 0)
	if unchangedLending.IsSettled {
		t.Fatal("lending should not be settled")
	}

	otherAccount, err := repos.Account.GetByID(otherAccountID)
	if err != nil {
		t.Fatalf("get other account: %v", err)
	}
	assertFloatEqual(t, "other account balance", otherAccount.CurrentBalance, 1000)

	records, err := repos.Lending.GetRecordsByLendingID(lending.ID)
	if err != nil {
		t.Fatalf("get records: %v", err)
	}
	if len(records) != 0 {
		t.Fatalf("records after failed repayment = %d, want 0", len(records))
	}
}

func TestRecordRepaymentConcurrentRequestsRejectOverpaymentAgainstLatestBalance(t *testing.T) {
	_, repos, userID := newTransactionTestService(t)
	lendingSvc := newLendingTestService(repos)
	accountID := createAccountForTest(t, repos, userID, 1000)

	lending, err := lendingSvc.Create(userID, CreateLendingRequest{
		Type:        "lend_out",
		ContactName: "并发还款",
		Principal:   100,
		LendDate:    time.Now().Format(time.RFC3339),
	})
	if err != nil {
		t.Fatalf("create lending: %v", err)
	}

	start := make(chan struct{})
	errorsByCall := make(chan error, 2)
	var wg sync.WaitGroup
	for range 2 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			<-start
			_, err := lendingSvc.RecordRepayment(lending.ID, userID, RecordRepaymentRequest{
				Amount:            80,
				RecordDate:        time.Now().Format(time.RFC3339),
				AccountID:         &accountID,
				CreateTransaction: true,
			})
			errorsByCall <- err
		}()
	}
	close(start)
	wg.Wait()
	close(errorsByCall)
	var successCount, overpaymentCount int
	for err := range errorsByCall {
		switch {
		case err == nil:
			successCount++
		case errors.Is(err, ErrLendingOverpayment):
			overpaymentCount++
		default:
			t.Fatalf("concurrent repayment: %v", err)
		}
	}
	if successCount != 1 || overpaymentCount != 1 {
		t.Fatalf("success/overpayment counts = %d/%d, want 1/1", successCount, overpaymentCount)
	}

	updated, err := lendingSvc.GetByID(lending.ID, userID)
	if err != nil {
		t.Fatalf("get updated lending: %v", err)
	}
	assertFloatEqual(t, "current balance", updated.CurrentBalance, 20)
	assertFloatEqual(t, "total repaid", updated.TotalRepaid, 80)
	if updated.IsSettled {
		t.Fatal("lending should remain unsettled")
	}

	records, err := repos.Lending.GetRecordsByLendingID(lending.ID)
	if err != nil {
		t.Fatalf("get repayment records: %v", err)
	}
	if len(records) != 1 {
		t.Fatalf("repayment records = %d, want 1", len(records))
	}
	var recordedTotal money.Amount
	for _, record := range records {
		if record.Amount <= 0 {
			t.Fatalf("repayment record amount = %.2f, want positive", record.Amount)
		}
		recordedTotal = recordedTotal.Add(record.Amount)
	}
	assertFloatEqual(t, "recorded repayment total", recordedTotal, 80)

	account, err := repos.Account.GetByID(accountID)
	if err != nil {
		t.Fatalf("get repayment account: %v", err)
	}
	assertFloatEqual(t, "repayment account balance", account.CurrentBalance, 1080)

	txIDs := findLendingTransactionIDs(t, repos, userID, lending.ID)
	if len(txIDs) != 1 {
		t.Fatalf("repayment transactions = %d, want 1", len(txIDs))
	}
	var transactionTotal money.Amount
	for _, txID := range txIDs {
		tx, err := repos.Transaction.GetByID(txID)
		if err != nil {
			t.Fatalf("get repayment transaction: %v", err)
		}
		transactionTotal = transactionTotal.Add(tx.Amount)
	}
	assertFloatEqual(t, "transaction repayment total", transactionTotal, 80)
}

func TestRecordRepaymentRollsBackLateRecordFailure(t *testing.T) {
	_, repos, userID := newTransactionTestService(t)
	lendingSvc := newLendingTestService(repos)
	accountID := createAccountForTest(t, repos, userID, 1000)

	lending, err := lendingSvc.Create(userID, CreateLendingRequest{
		Type:        "lend_out",
		ContactName: "回滚测试",
		Principal:   300,
		LendDate:    time.Now().Format(time.RFC3339),
	})
	if err != nil {
		t.Fatalf("create lending: %v", err)
	}

	forcedErr := errors.New("forced lending record failure")
	callbackName := "test:fail_lending_record_create"
	db := repos.Transaction.DB()
	if err := db.Callback().Create().Before("gorm:create").Register(callbackName, func(txdb *gorm.DB) {
		if txdb.Statement.Schema != nil && txdb.Statement.Schema.Table == "lending_records" {
			txdb.AddError(forcedErr)
		}
	}); err != nil {
		t.Fatalf("register create callback: %v", err)
	}
	t.Cleanup(func() {
		_ = db.Callback().Create().Remove(callbackName)
	})

	_, err = lendingSvc.RecordRepayment(lending.ID, userID, RecordRepaymentRequest{
		Amount:            100,
		RecordDate:        time.Now().Format(time.RFC3339),
		AccountID:         &accountID,
		CreateTransaction: true,
	})
	if !errors.Is(err, forcedErr) {
		t.Fatalf("record repayment error = %v, want forced failure", err)
	}

	unchanged, err := lendingSvc.GetByID(lending.ID, userID)
	if err != nil {
		t.Fatalf("get lending after rollback: %v", err)
	}
	assertFloatEqual(t, "rolled back current balance", unchanged.CurrentBalance, 300)
	assertFloatEqual(t, "rolled back total repaid", unchanged.TotalRepaid, 0)
	if unchanged.IsSettled {
		t.Fatal("lending should not be settled after rollback")
	}

	account, err := repos.Account.GetByID(accountID)
	if err != nil {
		t.Fatalf("get account after rollback: %v", err)
	}
	assertFloatEqual(t, "rolled back account balance", account.CurrentBalance, 1000)

	records, err := repos.Lending.GetRecordsByLendingID(lending.ID)
	if err != nil {
		t.Fatalf("get records after rollback: %v", err)
	}
	if len(records) != 0 {
		t.Fatalf("records after rollback = %d, want 0", len(records))
	}
	if txIDs := findLendingTransactionIDs(t, repos, userID, lending.ID); len(txIDs) != 0 {
		t.Fatalf("transactions after rollback = %d, want 0", len(txIDs))
	}
}

func newLendingTestService(repos *repository.Repositories) *LendingService {
	accountLogSvc := NewAccountLogService(repos.AccountLog, repos.Account)
	return NewLendingService(
		repos.Lending,
		repos.Account,
		repos.Transaction,
		repos.Category,
		accountLogSvc,
	)
}

func requireSingleLendingRecord(t *testing.T, repos *repository.Repositories, lendingID string) *model.LendingRecord {
	t.Helper()
	records, err := repos.Lending.GetRecordsByLendingID(lendingID)
	if err != nil {
		t.Fatalf("get lending records: %v", err)
	}
	if len(records) != 1 {
		t.Fatalf("lending records = %d, want 1", len(records))
	}
	return records[0]
}

func findLendingTransactionIDs(t *testing.T, repos *repository.Repositories, userID uint, lendingID string) []string {
	t.Helper()
	transactions, _, err := repos.Transaction.List(repository.TransactionFilter{
		UserID:   userID,
		Page:     1,
		PageSize: 20,
	})
	if err != nil {
		t.Fatalf("list transactions: %v", err)
	}

	var ids []string
	for _, tx := range transactions {
		if tx.LendingID != nil && *tx.LendingID == lendingID {
			ids = append(ids, tx.ID)
		}
	}
	return ids
}
