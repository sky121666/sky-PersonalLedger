package service

import (
	"testing"
	"time"

	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

func TestDeleteLendingDeletesRecordsAndDetachesGeneratedTransactions(t *testing.T) {
	_, repos, userID := newTransactionTestService(t)
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

	if err := lendingSvc.Delete(lending.ID, userID); err != nil {
		t.Fatalf("delete lending: %v", err)
	}

	records, err := repos.Lending.GetRecordsByLendingID(lending.ID)
	if err != nil {
		t.Fatalf("get lending records after delete: %v", err)
	}
	if len(records) != 0 {
		t.Fatalf("lending records after delete = %d, want 0", len(records))
	}

	for _, txID := range txIDs {
		tx, err := repos.Transaction.GetByID(txID)
		if err != nil {
			t.Fatalf("get generated transaction after lending delete: %v", err)
		}
		if tx.LendingID != nil {
			t.Fatalf("transaction %s lending_id = %q, want nil", tx.ID, *tx.LendingID)
		}
	}

	account, err := repos.Account.GetByID(accountID)
	if err != nil {
		t.Fatalf("get account: %v", err)
	}
	assertFloatEqual(t, "account balance", account.CurrentBalance, 800)
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
