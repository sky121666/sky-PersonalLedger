package service

import (
	"testing"
	"time"

	"github.com/sky/personal-ledger/internal/repository"
)

func TestDeleteLendingDeletesRecordsAndDetachesGeneratedTransactions(t *testing.T) {
	_, repos, userID := newTransactionTestService(t)
	accountLogSvc := NewAccountLogService(repos.AccountLog, repos.Account)
	lendingSvc := NewLendingService(
		repos.Lending,
		repos.Account,
		repos.Transaction,
		repos.Category,
		accountLogSvc,
	)
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
