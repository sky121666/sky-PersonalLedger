package repository

import (
	"errors"
	"path/filepath"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

func TestAccountLogRepositoryScopesAccountReadsByUser(t *testing.T) {
	repos, owner, other := newAccountLogRepositoryTestFixture(t)
	ownerAccount := createAccountLogRepositoryTestAccount(t, repos, owner.ID)
	otherAccount := createAccountLogRepositoryTestAccount(t, repos, other.ID)

	ownerLogID := createAccountLogRepositoryTestLog(t, repos, owner.ID, ownerAccount.ID)
	createAccountLogRepositoryTestLog(t, repos, other.ID, otherAccount.ID)

	logs, total, err := repos.AccountLog.GetByAccountID(owner.ID, ownerAccount.ID, 1, 50)
	if err != nil {
		t.Fatalf("get owner's account logs: %v", err)
	}
	if total != 1 || len(logs) != 1 || logs[0].ID != ownerLogID {
		t.Fatalf("owner logs = %#v, total = %d; want only %s", logs, total, ownerLogID)
	}

	logs, total, err = repos.AccountLog.GetByAccountID(other.ID, ownerAccount.ID, 1, 50)
	if err != nil {
		t.Fatalf("get account logs as other user: %v", err)
	}
	if total != 0 || len(logs) != 0 {
		t.Fatalf("cross-user logs = %#v, total = %d; want empty", logs, total)
	}
}

func TestAccountLogRepositoryRejectsCrossUserAccountWrite(t *testing.T) {
	repos, owner, other := newAccountLogRepositoryTestFixture(t)
	ownerAccount := createAccountLogRepositoryTestAccount(t, repos, owner.ID)

	err := repos.AccountLog.Create(&CreateAccountLogRequest{
		UserID:        other.ID,
		AccountID:     ownerAccount.ID,
		Type:          "adjustment",
		Amount:        10,
		BalanceBefore: 0,
		BalanceAfter:  10,
	})
	if !errors.Is(err, gorm.ErrRecordNotFound) {
		t.Fatalf("create cross-user account log error = %v, want record not found", err)
	}

	var count int64
	if err := repos.Account.DB().Model(&model.AccountLog{}).Count(&count).Error; err != nil {
		t.Fatalf("count account logs: %v", err)
	}
	if count != 0 {
		t.Fatalf("account log count = %d, want 0", count)
	}
}

func TestAccountLogRepositoryReturnsLatestBalanceAtBoundaryPerAccount(t *testing.T) {
	repos, owner, other := newAccountLogRepositoryTestFixture(t)
	ownerAccount := createAccountLogRepositoryTestAccount(t, repos, owner.ID)
	otherAccount := createAccountLogRepositoryTestAccount(t, repos, other.ID)
	boundary := time.Date(2026, 6, 30, 23, 59, 59, 0, time.UTC)
	for _, log := range []model.AccountLog{
		{ID: "owner-old", UserID: owner.ID, AccountID: ownerAccount.ID, Type: "income", BalanceBefore: 0, BalanceAfter: 100, CreatedAt: boundary.Add(-time.Hour)},
		{ID: "owner-latest", UserID: owner.ID, AccountID: ownerAccount.ID, Type: "income", BalanceBefore: 100, BalanceAfter: 125, CreatedAt: boundary},
		{ID: "owner-future", UserID: owner.ID, AccountID: ownerAccount.ID, Type: "income", BalanceBefore: 125, BalanceAfter: 150, CreatedAt: boundary.Add(time.Second)},
		{ID: "other", UserID: other.ID, AccountID: otherAccount.ID, Type: "income", BalanceBefore: 0, BalanceAfter: 999, CreatedAt: boundary},
	} {
		log := log
		if err := repos.Account.DB().Create(&log).Error; err != nil {
			t.Fatalf("create log %s: %v", log.ID, err)
		}
	}

	snapshots, err := repos.AccountLog.LatestBalancesAt(owner.ID, boundary)
	if err != nil {
		t.Fatalf("get snapshots: %v", err)
	}
	if len(snapshots) != 1 || snapshots[0].AccountID != ownerAccount.ID || snapshots[0].Balance != 125 {
		t.Fatalf("snapshots = %#v, want owner balance 125", snapshots)
	}
}

func newAccountLogRepositoryTestFixture(t *testing.T) (*Repositories, *model.User, *model.User) {
	t.Helper()
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := NewRepositories(db)
	owner := &model.User{Username: "account-log-owner", PasswordHash: "hash"}
	other := &model.User{Username: "account-log-other", PasswordHash: "hash"}
	if err := repos.User.Create(owner); err != nil {
		t.Fatalf("create owner: %v", err)
	}
	if err := repos.User.Create(other); err != nil {
		t.Fatalf("create other user: %v", err)
	}
	return repos, owner, other
}

func createAccountLogRepositoryTestAccount(t *testing.T, repos *Repositories, userID uint) *model.Account {
	t.Helper()
	account := &model.Account{
		ID:             uuid.NewString(),
		UserID:         userID,
		Name:           "Wallet",
		Type:           "cash",
		CurrentBalance: 100,
	}
	if err := repos.Account.Create(account); err != nil {
		t.Fatalf("create account: %v", err)
	}
	return account
}

func createAccountLogRepositoryTestLog(t *testing.T, repos *Repositories, userID uint, accountID string) string {
	t.Helper()
	if err := repos.AccountLog.Create(&CreateAccountLogRequest{
		UserID:        userID,
		AccountID:     accountID,
		Type:          "income",
		Amount:        25,
		BalanceBefore: 100,
		BalanceAfter:  125,
	}); err != nil {
		t.Fatalf("create account log: %v", err)
	}
	logs, _, err := repos.AccountLog.GetByAccountID(userID, accountID, 1, 1)
	if err != nil || len(logs) != 1 {
		t.Fatalf("read created account log: logs=%#v err=%v", logs, err)
	}
	return logs[0].ID
}
