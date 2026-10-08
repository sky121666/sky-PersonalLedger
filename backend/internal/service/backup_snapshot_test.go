package service

import (
	"errors"
	"sync/atomic"
	"testing"
	"time"

	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

func TestCreateBackupUsesOneSnapshotAcrossConcurrentLedgerWrites(t *testing.T) {
	transactions, repos, userID := newTransactionTestService(t)
	accountID := createAccountForTest(t, repos, userID, 100)
	db := repos.User.DB()
	if err := db.Model(&model.User{}).Where("id = ?", userID).Update("nickname", "Before").Error; err != nil {
		t.Fatal(err)
	}
	if err := repos.Notification.Create(&model.NotificationSetting{UserID: userID, AdvanceDays: 3}); err != nil {
		t.Fatal(err)
	}
	svc := NewBackupService(db, repos.Account, repos.Category, repos.Transaction, repos.Budget, repos.Reminder, repos.Lending, repos.Template, repos.Notification, repos.Tag, repos.User, repos.FamilyMember, repos.AIReport)
	var wrote atomic.Bool
	var writeErr error
	name := "test:commit-ledger-after-backup-account-read"
	if err := db.Callback().Query().After("gorm:query").Register(name, func(query *gorm.DB) {
		if query.Statement.Table != "accounts" || !wrote.CompareAndSwap(false, true) {
			return
		}
		// The snapshot owns one connection; normal services use another WAL
		// connection and commit before the remaining backup queries continue.
		_, writeErr = transactions.Create(userID, CreateTransactionRequest{
			Type: "expense", Amount: 10, AccountID: accountID, TransactionDate: time.Now().Format(time.RFC3339),
		})
		if writeErr == nil {
			writeErr = db.Model(&model.User{}).Where("id = ?", userID).Update("nickname", "After").Error
		}
		if writeErr == nil {
			writeErr = db.Model(&model.NotificationSetting{}).Where("user_id = ?", userID).Update("advance_days", 9).Error
		}
	}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = db.Callback().Query().Remove(name) })
	backup, err := svc.CreateBackup(userID)
	if err != nil || writeErr != nil || !wrote.Load() {
		t.Fatalf("backup=%v writer=%v wrote=%v", err, writeErr, wrote.Load())
	}
	live, err := repos.Account.GetByID(accountID)
	if err != nil {
		t.Fatal(err)
	}
	if live.CurrentBalance != 90 {
		t.Fatalf("concurrent expense did not commit: balance=%v", live.CurrentBalance)
	}
	if len(backup.Accounts) != 1 || backup.Accounts[0].CurrentBalance != 100 ||
		len(backup.Transactions) != 0 || len(backup.AccountLogs) != 0 ||
		backup.UserProfile == nil || backup.UserProfile.Nickname != "Before" ||
		backup.NotificationSettings == nil || backup.NotificationSettings.AdvanceDays != 3 {
		t.Fatal("backup mixed data from before and after concurrent commits")
	}
	if err := svc.RestoreBackup(userID, writeBackupFile(t, backup)); err != nil {
		t.Fatalf("restore consistent snapshot: %v", err)
	}
	account, err := repos.Account.GetByID(accountID)
	if err != nil || account.CurrentBalance != 100 {
		t.Fatalf("restored account=%v err=%v", account, err)
	}
	var count int64
	if err := db.Model(&model.Transaction{}).Where("user_id = ?", userID).Count(&count).Error; err != nil {
		t.Fatal(err)
	}
	if count != 0 {
		t.Fatalf("restored snapshot has %d later transactions", count)
	}
}

func TestCreateBackupWaitsForConcurrentUploadUntilSnapshotFinishes(t *testing.T) {
	fixture := newBackupIntegrityFixture(t)
	enteredSnapshot := make(chan struct{})
	finishSnapshot := make(chan struct{})
	var firstRead atomic.Bool
	name := "test:pause-backup-snapshot"
	if err := fixture.db.Callback().Query().After("gorm:query").Register(name, func(query *gorm.DB) {
		if query.Statement.Table == "accounts" && firstRead.CompareAndSwap(false, true) {
			close(enteredSnapshot)
			<-finishSnapshot
		}
	}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = fixture.db.Callback().Query().Remove(name) })
	type backupResult struct {
		backup *FullBackupData
		err    error
	}
	finished := make(chan backupResult, 1)
	go func() {
		backup, err := fixture.service.CreateBackup(fixture.user.ID)
		finished <- backupResult{backup, err}
	}()
	<-enteredSnapshot
	uploadFile := newUploadFileHeader(t, "later.txt", "later attachment")
	started := make(chan struct{})
	uploadDone := make(chan error, 1)
	go func() {
		close(started)
		_, err := fixture.service.uploadService.Upload(fixture.user.ID, "transactions", "later", uploadFile)
		uploadDone <- err
	}()
	<-started
	var crossed bool
	select {
	case <-uploadDone:
		crossed = true
	case <-time.After(100 * time.Millisecond):
	}
	close(finishSnapshot)
	result := <-finished
	if crossed {
		t.Fatal("upload mutated attachment files while backup snapshot was open")
	}
	if err := <-uploadDone; err != nil {
		t.Fatalf("upload after backup: %v", err)
	}
	if result.err != nil || len(result.backup.Attachments) != 0 {
		t.Fatalf("backup unexpectedly included later upload: err=%v", result.err)
	}
}

func TestCreateBackupPropagatesProfileReadFailure(t *testing.T) {
	fixture := newBackupIntegrityFixture(t)
	forcedErr := errors.New("forced backup profile read failure")
	name := "test:fail-backup-profile"
	if err := fixture.db.Callback().Query().Before("gorm:query").Register(name, func(query *gorm.DB) {
		if query.Statement.Table == "users" {
			query.AddError(forcedErr)
		}
	}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = fixture.db.Callback().Query().Remove(name) })
	backup, err := fixture.service.CreateBackup(fixture.user.ID)
	if !errors.Is(err, forcedErr) || backup != nil {
		t.Fatalf("partial backup returned after failed profile query: err=%v", err)
	}
}
