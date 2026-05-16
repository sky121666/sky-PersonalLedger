package service

import (
	"path/filepath"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

func newTransactionTestService(t *testing.T) (*TransactionService, *repository.Repositories, uint) {
	t.Helper()
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	user := &model.User{Username: "admin", PasswordHash: "hash"}
	if err := repos.User.Create(user); err != nil {
		t.Fatalf("create user: %v", err)
	}
	accountLogSvc := NewAccountLogService(repos.AccountLog, repos.Account)
	return NewTransactionService(repos.Transaction, repos.Account, repos.Reminder, repos.Lending, accountLogSvc), repos, user.ID
}

func createAccountForTest(t *testing.T, repos *repository.Repositories, userID uint, balance float64) string {
	t.Helper()
	id := uuid.NewString()
	if err := repos.Account.Create(&model.Account{
		ID:             id,
		UserID:         userID,
		Name:           "Wallet",
		Type:           "cash",
		CurrentBalance: balance,
	}); err != nil {
		t.Fatalf("create account: %v", err)
	}
	return id
}

func TestCreateTransferRollsBackWhenTargetAccountDoesNotExist(t *testing.T) {
	svc, repos, userID := newTransactionTestService(t)
	sourceID := createAccountForTest(t, repos, userID, 100)
	missingTargetID := uuid.NewString()

	_, err := svc.Create(userID, CreateTransactionRequest{
		Type:            "transfer",
		Amount:          30,
		AccountID:       sourceID,
		ToAccountID:     &missingTargetID,
		TransactionDate: time.Now().Format(time.RFC3339),
	})
	if err == nil {
		t.Fatal("expected error for missing transfer target")
	}

	source, err := repos.Account.GetByID(sourceID)
	if err != nil {
		t.Fatalf("get source: %v", err)
	}
	if source.CurrentBalance != 100 {
		t.Fatalf("source balance = %v, want 100", source.CurrentBalance)
	}

	list, total, err := repos.Transaction.List(repository.TransactionFilter{UserID: userID, Page: 1, PageSize: 20})
	if err != nil {
		t.Fatalf("list transactions: %v", err)
	}
	if total != 0 || len(list) != 0 {
		t.Fatalf("transaction was persisted despite failed transfer: total=%d len=%d", total, len(list))
	}
}

func TestUpdateRejectsTransferWithoutTargetAccount(t *testing.T) {
	svc, repos, userID := newTransactionTestService(t)
	accountID := createAccountForTest(t, repos, userID, 100)
	tx, err := svc.Create(userID, CreateTransactionRequest{
		Type:            "expense",
		Amount:          10,
		AccountID:       accountID,
		TransactionDate: time.Now().Format(time.RFC3339),
	})
	if err != nil {
		t.Fatalf("create expense: %v", err)
	}

	if _, err := svc.Update(tx.ID, userID, CreateTransactionRequest{
		Type:            "transfer",
		Amount:          10,
		AccountID:       accountID,
		TransactionDate: time.Now().Format(time.RFC3339),
	}); err == nil {
		t.Fatal("expected transfer update without target to fail")
	}
}
