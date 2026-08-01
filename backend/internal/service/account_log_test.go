package service

import (
	"errors"
	"path/filepath"
	"testing"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

func TestAccountLogServiceGetByAccountIDEnforcesOwnership(t *testing.T) {
	svc, repos, owner, other, ownerAccount := newAccountLogServiceTestFixture(t)
	if err := repos.AccountLog.Create(&repository.CreateAccountLogRequest{
		UserID:        owner.ID,
		AccountID:     ownerAccount.ID,
		Type:          "income",
		Amount:        20,
		BalanceBefore: 100,
		BalanceAfter:  120,
	}); err != nil {
		t.Fatalf("create owner account log: %v", err)
	}

	logs, total, err := svc.GetByAccountID(owner.ID, ownerAccount.ID, 1, 50)
	if err != nil {
		t.Fatalf("get owner account logs: %v", err)
	}
	if total != 1 || len(logs) != 1 || logs[0].UserID != owner.ID {
		t.Fatalf("owner logs = %#v, total = %d; want one owner log", logs, total)
	}

	_, _, foreignErr := svc.GetByAccountID(other.ID, ownerAccount.ID, 1, 50)
	if !errors.Is(foreignErr, ErrAccountNotFound) {
		t.Fatalf("cross-user error = %v, want ErrAccountNotFound", foreignErr)
	}
	_, _, missingErr := svc.GetByAccountID(owner.ID, uuid.NewString(), 1, 50)
	if !errors.Is(missingErr, ErrAccountNotFound) {
		t.Fatalf("missing-account error = %v, want ErrAccountNotFound", missingErr)
	}
	_, _, unauthenticatedErr := svc.GetByAccountID(0, ownerAccount.ID, 1, 50)
	if !errors.Is(unauthenticatedErr, ErrAccountNotFound) {
		t.Fatalf("missing-user error = %v, want ErrAccountNotFound", unauthenticatedErr)
	}
}

func TestAccountLogServiceLogBalanceChangeEnforcesAccountOwnership(t *testing.T) {
	svc, repos, owner, other, ownerAccount := newAccountLogServiceTestFixture(t)

	err := svc.LogBalanceChange(&LogBalanceChangeRequest{
		UserID:    other.ID,
		AccountID: ownerAccount.ID,
		Type:      "income",
		Amount:    20,
	})
	if !errors.Is(err, ErrAccountNotFound) {
		t.Fatalf("cross-user balance log error = %v, want ErrAccountNotFound", err)
	}

	logs, total, err := repos.AccountLog.GetByAccountID(owner.ID, ownerAccount.ID, 1, 50)
	if err != nil {
		t.Fatalf("get logs after rejected write: %v", err)
	}
	if total != 0 || len(logs) != 0 {
		t.Fatalf("logs after rejected write = %#v, total = %d; want empty", logs, total)
	}

	if err := svc.LogBalanceChange(&LogBalanceChangeRequest{
		UserID:    owner.ID,
		AccountID: ownerAccount.ID,
		Type:      "income",
		Amount:    20,
	}); err != nil {
		t.Fatalf("log owner balance change: %v", err)
	}
	logs, total, err = repos.AccountLog.GetByAccountID(owner.ID, ownerAccount.ID, 1, 50)
	if err != nil {
		t.Fatalf("get logs after owner write: %v", err)
	}
	if total != 1 || len(logs) != 1 {
		t.Fatalf("owner logs = %#v, total = %d; want one", logs, total)
	}
	if logs[0].BalanceBefore != 100 || logs[0].BalanceAfter != 120 {
		t.Fatalf("balances = %.2f -> %.2f, want 100 -> 120", logs[0].BalanceBefore, logs[0].BalanceAfter)
	}
}

func TestAccountLogServiceUsesDebtBalanceDirection(t *testing.T) {
	svc, repos, owner, _, account := newAccountLogServiceTestFixture(t)
	if err := repos.Account.UpdateMetadataForUser(account.ID, owner.ID, map[string]any{"type": "credit"}); err == nil {
		t.Fatal("account type should not be mutable through metadata updates")
	}
	if err := repos.Account.DB().Model(&model.Account{}).
		Where("id = ? AND user_id = ?", account.ID, owner.ID).
		Update("type", "credit").Error; err != nil {
		t.Fatalf("set debt account fixture type: %v", err)
	}

	if err := svc.LogBalanceChange(&LogBalanceChangeRequest{
		UserID:    owner.ID,
		AccountID: account.ID,
		Type:      "expense",
		Amount:    40,
	}); err != nil {
		t.Fatalf("log debt expense: %v", err)
	}
	logs, total, err := svc.GetByAccountID(owner.ID, account.ID, 1, 20)
	if err != nil || total != 1 || len(logs) != 1 {
		t.Fatalf("get debt account log: total=%d logs=%#v err=%v", total, logs, err)
	}
	if logs[0].BalanceBefore != 100 || logs[0].BalanceAfter != 140 {
		t.Fatalf("debt balances = %.2f -> %.2f, want 100 -> 140", logs[0].BalanceBefore, logs[0].BalanceAfter)
	}
}

func newAccountLogServiceTestFixture(t *testing.T) (*AccountLogService, *repository.Repositories, *model.User, *model.User, *model.Account) {
	t.Helper()
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	owner := &model.User{Username: "account-log-owner", PasswordHash: "hash"}
	other := &model.User{Username: "account-log-other", PasswordHash: "hash"}
	if err := repos.User.Create(owner); err != nil {
		t.Fatalf("create owner: %v", err)
	}
	if err := repos.User.Create(other); err != nil {
		t.Fatalf("create other user: %v", err)
	}
	account := &model.Account{
		ID:             uuid.NewString(),
		UserID:         owner.ID,
		Name:           "Wallet",
		Type:           "cash",
		CurrentBalance: 100,
	}
	if err := repos.Account.Create(account); err != nil {
		t.Fatalf("create owner account: %v", err)
	}
	return NewAccountLogService(repos.AccountLog, repos.Account), repos, owner, other, account
}
