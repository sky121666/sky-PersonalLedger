package service

import (
	"encoding/json"
	"strings"
	"sync"
	"testing"

	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

func keyedTransactionRequest(t *testing.T, account, key string) CreateTransactionRequest {
	t.Helper()
	raw, _ := json.Marshal(map[string]any{"type": "expense", "amount": 10, "account_id": account,
		"transaction_date": "2026-10-19T10:00:00+08:00", "idempotency_key": key})
	var req CreateTransactionRequest
	if err := json.Unmarshal(raw, &req); err != nil {
		t.Fatal(err)
	}
	return req
}

func assertManualWriteState(t *testing.T, repos *repository.Repositories, user uint, account string, count int64, balance float64) {
	t.Helper()
	var got int64
	if err := repos.Account.DB().Model(&model.Transaction{}).Where("user_id = ?", user).Count(&got).Error; err != nil || got != count {
		t.Fatalf("transaction count = %d, want %d: %v", got, count, err)
	}
	a, err := repos.Account.GetByID(account)
	if err != nil {
		t.Fatal(err)
	}
	assertFloatEqual(t, "account balance", a.CurrentBalance, balance)
}

func TestManualTransactionRequestRetry(t *testing.T) {
	svc, repos, user := newTransactionTestService(t)
	account := createAccountForTest(t, repos, user, 100)
	req := keyedTransactionRequest(t, account, "same-intent")
	first, err := svc.Create(user, req)
	if err != nil {
		t.Fatal(err)
	}
	second, err := svc.Create(user, req)
	if err != nil || second.ID != first.ID {
		t.Fatalf("retry created another transaction: %v, %v", second, err)
	}
	assertManualWriteState(t, repos, user, account, 1, 90)
	req.Amount = 20
	if _, err := svc.Create(user, req); err == nil {
		t.Fatal("changed payload under the same key accepted")
	}
	assertManualWriteState(t, repos, user, account, 1, 90)
}

func TestManualTransactionSeparateIntentsAndLegacy(t *testing.T) {
	svc, repos, user := newTransactionTestService(t)
	account := createAccountForTest(t, repos, user, 100)
	for _, key := range []string{"one", "two", "", ""} {
		if _, err := svc.Create(user, keyedTransactionRequest(t, account, key)); err != nil {
			t.Fatal(err)
		}
	}
	assertManualWriteState(t, repos, user, account, 4, 60)
	if _, err := svc.Create(user, keyedTransactionRequest(t, account, strings.Repeat("x", 129))); err == nil {
		t.Fatal("oversized key accepted")
	}
	assertManualWriteState(t, repos, user, account, 4, 60)
}

func TestManualTransactionRetryDoesNotResurrectDeleted(t *testing.T) {
	svc, repos, user := newTransactionTestService(t)
	account := createAccountForTest(t, repos, user, 100)
	req := keyedTransactionRequest(t, account, "deleted")
	first, err := svc.Create(user, req)
	if err != nil {
		t.Fatal(err)
	}
	if err := svc.Delete(first.ID, user); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Create(user, req); err == nil {
		t.Fatal("retry of deleted write created a new transaction")
	}
	assertManualWriteState(t, repos, user, account, 0, 100)
}

func TestManualTransactionConcurrentRetry(t *testing.T) {
	svc, repos, user := newTransactionTestService(t)
	account := createAccountForTest(t, repos, user, 100)
	req := keyedTransactionRequest(t, account, "concurrent")
	var wg sync.WaitGroup
	ids := make(chan string, 8)
	for range 8 {
		wg.Go(func() {
			row, err := svc.Create(user, req)
			if err != nil {
				t.Error(err)
				return
			}
			ids <- row.ID
		})
	}
	wg.Wait()
	close(ids)
	id := ""
	for got := range ids {
		if id != "" && got != id {
			t.Errorf("concurrent retry returned different id")
		}
		id = got
	}
	assertManualWriteState(t, repos, user, account, 1, 90)
}

func manualBackupService(repos *repository.Repositories) *BackupService {
	return NewBackupService(repos.Account.DB(), repos.Account, repos.Category, repos.Transaction, repos.Budget,
		repos.Reminder, repos.Lending, repos.Template, repos.Notification, repos.Tag, repos.User, repos.FamilyMember, repos.AIReport)
}

func TestManualTransactionRetryAfterCrossUserRestore(t *testing.T) {
	source, sourceRepos, user := newTransactionTestService(t)
	account := createAccountForTest(t, sourceRepos, user, 100)
	req := keyedTransactionRequest(t, account, "restored")
	first, err := source.Create(user, req)
	if err != nil {
		t.Fatal(err)
	}
	backup, err := manualBackupService(sourceRepos).CreateBackup(user)
	if err != nil {
		t.Fatal(err)
	}
	if len(backup.RepaymentRequests) != 1 {
		t.Fatalf("request identity missing from backup: %d", len(backup.RepaymentRequests))
	}
	target, targetRepos, _ := newTransactionTestService(t)
	other := &model.User{Username: "restore-owner", PasswordHash: "synthetic"}
	if err := targetRepos.User.Create(other); err != nil {
		t.Fatal(err)
	}
	if err := manualBackupService(targetRepos).RestoreBackup(other.ID, writeBackupFile(t, backup)); err != nil {
		t.Fatal(err)
	}
	retry, err := target.Create(other.ID, req)
	if err != nil || retry.ID != first.ID {
		t.Fatalf("restored retry lost identity: %+v %v", retry, err)
	}
	assertManualWriteState(t, targetRepos, other.ID, account, 1, 90)
}

func TestManualTransactionFailedWriteReleasesKey(t *testing.T) {
	svc, repos, user := newTransactionTestService(t)
	account := createAccountForTest(t, repos, user, 100)
	req := keyedTransactionRequest(t, account, "correctable")
	req.Amount = 0
	if _, err := svc.Create(user, req); err == nil {
		t.Fatal("invalid amount accepted")
	}
	req.Amount = 10
	if _, err := svc.Create(user, req); err != nil {
		t.Fatal(err)
	}
	assertManualWriteState(t, repos, user, account, 1, 90)
}

func TestManualTransactionSameKeyDifferentUsers(t *testing.T) {
	svc, repos, user := newTransactionTestService(t)
	account := createAccountForTest(t, repos, user, 100)
	other := &model.User{Username: "other-manual-owner", PasswordHash: "synthetic"}
	if err := repos.User.Create(other); err != nil {
		t.Fatal(err)
	}
	otherAccount := createAccountForTest(t, repos, other.ID, 200)
	first, err := svc.Create(user, keyedTransactionRequest(t, account, "shared-client-key"))
	if err != nil {
		t.Fatal(err)
	}
	second, err := svc.Create(other.ID, keyedTransactionRequest(t, otherAccount, "shared-client-key"))
	if err != nil || second.ID == first.ID {
		t.Fatalf("request scope crossed users: %+v %v", second, err)
	}
	assertManualWriteState(t, repos, user, account, 1, 90)
	assertManualWriteState(t, repos, other.ID, otherAccount, 1, 190)
}

func TestManualTransactionRetryAfterAccountArchival(t *testing.T) {
	svc, repos, user := newTransactionTestService(t)
	account := createAccountForTest(t, repos, user, 100)
	req := keyedTransactionRequest(t, account, "archived")
	first, err := svc.Create(user, req)
	if err != nil {
		t.Fatal(err)
	}
	if err := repos.Account.DB().Model(&model.Account{}).Where("id = ?", account).Update("is_archived", true).Error; err != nil {
		t.Fatal(err)
	}
	retry, err := svc.Create(user, req)
	if err != nil || retry.ID != first.ID {
		t.Fatalf("archival prevented confirmation of a committed transaction: %+v %v", retry, err)
	}
	assertManualWriteState(t, repos, user, account, 1, 90)
}

func TestManualTransactionDeletedRetryAfterBackupRestore(t *testing.T) {
	svc, repos, user := newTransactionTestService(t)
	account := createAccountForTest(t, repos, user, 100)
	req := keyedTransactionRequest(t, account, "deleted-backup")
	first, err := svc.Create(user, req)
	if err != nil {
		t.Fatal(err)
	}
	if err := svc.Delete(first.ID, user); err != nil {
		t.Fatal(err)
	}
	backup, err := manualBackupService(repos).CreateBackup(user)
	if err != nil {
		t.Fatal(err)
	}
	target, targetRepos, targetUser := newTransactionTestService(t)
	if err := manualBackupService(targetRepos).RestoreBackup(targetUser, writeBackupFile(t, backup)); err != nil {
		t.Fatal(err)
	}
	if _, err := target.Create(targetUser, req); err != ErrTransactionRequestUnavailable {
		t.Fatalf("deleted retry after restore = %v", err)
	}
	assertManualWriteState(t, targetRepos, targetUser, account, 0, 100)
}
