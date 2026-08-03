package service

import (
	"errors"
	"fmt"
	"mime/multipart"
	"path/filepath"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/config"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/money"
	"github.com/sky/personal-ledger/internal/repository"
	"gorm.io/gorm"
)

func TestRegressionPartialAccountUpdatePreservesUnsubmittedFields(t *testing.T) {
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init database: %v", err)
	}
	repos := repository.NewRepositories(db)
	paymentDay, billingDay := 10, 3
	creditLimit, interestRate := money.Amount(20_000), 18.5
	startDate := time.Date(2025, 1, 2, 0, 0, 0, 0, time.Local)
	targetDate := time.Date(2028, 1, 2, 0, 0, 0, 0, time.Local)
	account := &model.Account{
		ID: uuid.NewString(), UserID: 7, Name: "信用卡", Type: "credit",
		PaymentDay: &paymentDay, BillingDay: &billingDay,
		CreditLimit: &creditLimit, InterestRate: &interestRate,
		StartDate: &startDate, TargetDate: &targetDate, Remark: "移动端备注",
	}
	if err := repos.Account.Create(account); err != nil {
		t.Fatalf("create account: %v", err)
	}

	updated, err := NewAccountService(repos.Account).Update(account.ID, account.UserID, UpdateAccountRequest{
		Name: "Web 改名", Icon: "card", Color: "#000000",
	})
	if err != nil {
		t.Fatalf("partial update: %v", err)
	}
	if updated.PaymentDay == nil || *updated.PaymentDay != paymentDay ||
		updated.BillingDay == nil || *updated.BillingDay != billingDay ||
		updated.CreditLimit == nil || *updated.CreditLimit != creditLimit ||
		updated.InterestRate == nil || *updated.InterestRate != interestRate ||
		updated.Remark != account.Remark || updated.StartDate == nil || updated.TargetDate == nil {
		t.Fatalf("partial update lost unsubmitted fields: %#v", updated)
	}
}

func TestRegressionDeleteReminderThenPaymentTransactionRestoresBothAccounts(t *testing.T) {
	txSvc, repos, userID := newTransactionTestService(t)
	reminderSvc := NewReminderService(
		repos.Reminder,
		repos.Account,
		repos.Transaction,
		repos.Category,
		NewAccountLogService(repos.AccountLog, repos.Account),
	)
	debtAccountID := createTypedAccountForTest(t, repos, userID, "loan", 500)
	paymentAccountID := createTypedAccountForTest(t, repos, userID, "cash", 1000)
	principal, currentBalance := money.Amount(500), money.Amount(500)
	reminder, err := reminderSvc.Create(userID, CreateReminderRequest{
		Name: "房贷", AccountID: &debtAccountID, PaymentDay: 20,
		Principal: &principal, CurrentBalance: &currentBalance,
	})
	if err != nil {
		t.Fatalf("create reminder: %v", err)
	}
	if _, err := reminderSvc.RecordPayment(reminder.ID, userID, RecordPaymentRequest{
		Amount: 120, PrincipalAmount: 100, InterestAmount: 20, AccountID: &paymentAccountID,
	}); err != nil {
		t.Fatalf("record payment: %v", err)
	}
	txID := findReminderTransactionID(t, repos, userID, reminder.ID)
	if err := reminderSvc.Delete(reminder.ID, userID); err != nil {
		t.Fatalf("delete reminder: %v", err)
	}
	if err := txSvc.Delete(txID, userID); err != nil {
		t.Fatalf("delete payment transaction: %v", err)
	}
	paymentAccount, _ := repos.Account.GetByID(paymentAccountID)
	debtAccount, _ := repos.Account.GetByID(debtAccountID)
	if paymentAccount.CurrentBalance != 1000 || debtAccount.CurrentBalance != 500 {
		t.Fatalf("balances after rollback = %.2f/%.2f, want 1000.00/500.00",
			paymentAccount.CurrentBalance, debtAccount.CurrentBalance)
	}
}

func TestRegressionFullBackupPreservesAccountLogs(t *testing.T) {
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init database: %v", err)
	}
	repos := repository.NewRepositories(db)
	user := &model.User{Username: "regression-backup", PasswordHash: "hash"}
	if err := repos.User.Create(user); err != nil {
		t.Fatalf("create user: %v", err)
	}
	account := &model.Account{ID: uuid.NewString(), UserID: user.ID, Name: "现金", Type: "cash", CurrentBalance: 80}
	if err := repos.Account.Create(account); err != nil {
		t.Fatalf("create account: %v", err)
	}
	if err := db.Create(&model.AccountLog{
		ID: uuid.NewString(), UserID: user.ID, AccountID: account.ID, Type: "adjustment",
		Amount: 20, BalanceBefore: 100, BalanceAfter: 80, Remark: "audit-history",
	}).Error; err != nil {
		t.Fatalf("create account log: %v", err)
	}
	svc := NewBackupService(
		db, repos.Account, repos.Category, repos.Transaction, repos.Budget,
		repos.Reminder, repos.Lending, repos.Template, repos.Notification,
		repos.Tag, repos.User, repos.FamilyMember, repos.AIReport,
	)
	backup, err := svc.CreateBackup(user.ID)
	if err != nil {
		t.Fatalf("create backup: %v", err)
	}
	if err := svc.RestoreBackup(user.ID, writeBackupFile(t, backup)); err != nil {
		t.Fatalf("restore backup: %v", err)
	}
	var count int64
	if err := db.Model(&model.AccountLog{}).Where("user_id = ?", user.ID).Count(&count).Error; err != nil {
		t.Fatalf("count account logs: %v", err)
	}
	if count != 1 {
		t.Fatalf("account logs after restore = %d, want 1", count)
	}
}

func TestRegressionRestoreReplacesNotificationDeduplicationHistory(t *testing.T) {
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init database: %v", err)
	}
	repos := repository.NewRepositories(db)
	user := &model.User{Username: "regression-notification-log", PasswordHash: "hash"}
	if err := repos.User.Create(user); err != nil {
		t.Fatalf("create user: %v", err)
	}
	oldID := uuid.NewString()
	if err := db.Create(&model.NotificationLog{
		ID: oldID, UserID: user.ID, Type: "payment_due", Status: "sent", CreatedAt: time.Now().Add(-time.Hour),
	}).Error; err != nil {
		t.Fatalf("create old notification log: %v", err)
	}
	svc := NewBackupService(
		db, repos.Account, repos.Category, repos.Transaction, repos.Budget,
		repos.Reminder, repos.Lending, repos.Template, repos.Notification,
		repos.Tag, repos.User, repos.FamilyMember, repos.AIReport,
	)
	backup, err := svc.CreateBackup(user.ID)
	if err != nil {
		t.Fatalf("create backup: %v", err)
	}
	newID := uuid.NewString()
	if err := db.Create(&model.NotificationLog{
		ID: newID, UserID: user.ID, Type: "payment_due", Status: "sent", CreatedAt: time.Now(),
	}).Error; err != nil {
		t.Fatalf("create newer notification log: %v", err)
	}
	if err := svc.RestoreBackup(user.ID, writeBackupFile(t, backup)); err != nil {
		t.Fatalf("restore backup: %v", err)
	}
	var logs []model.NotificationLog
	if err := db.Where("user_id = ?", user.ID).Order("id ASC").Find(&logs).Error; err != nil {
		t.Fatalf("list notification logs: %v", err)
	}
	if len(logs) != 1 || logs[0].ID != oldID {
		t.Fatalf("restored notification logs = %#v, want only %q", logs, oldID)
	}
}

func TestRegressionBackupIncludesSoftDeletedReferencedParents(t *testing.T) {
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init database: %v", err)
	}
	repos := repository.NewRepositories(db)
	user := &model.User{Username: "regression-dangling", PasswordHash: "hash"}
	if err := repos.User.Create(user); err != nil {
		t.Fatalf("create user: %v", err)
	}
	account := &model.Account{ID: uuid.NewString(), UserID: user.ID, Name: "旧账户", Type: "cash"}
	category := &model.Category{ID: uuid.NewString(), UserID: user.ID, Name: "旧分类", Type: "expense"}
	if err := repos.Account.Create(account); err != nil {
		t.Fatalf("create account: %v", err)
	}
	if err := db.Create(category).Error; err != nil {
		t.Fatalf("create category: %v", err)
	}
	tx := &model.Transaction{
		ID: uuid.NewString(), UserID: user.ID, Type: "expense", Amount: 12,
		AccountID: account.ID, CategoryID: &category.ID, TransactionDate: time.Now(),
	}
	if err := db.Create(tx).Error; err != nil {
		t.Fatalf("create transaction: %v", err)
	}
	if err := db.Delete(account).Error; err != nil {
		t.Fatalf("soft delete account: %v", err)
	}
	if err := db.Delete(category).Error; err != nil {
		t.Fatalf("soft delete category: %v", err)
	}
	svc := NewBackupService(
		db, repos.Account, repos.Category, repos.Transaction, repos.Budget,
		repos.Reminder, repos.Lending, repos.Template, repos.Notification,
		repos.Tag, repos.User, repos.FamilyMember, repos.AIReport,
	)
	backup, err := svc.CreateBackup(user.ID)
	if err != nil {
		t.Fatalf("create backup: %v", err)
	}
	if len(backup.Accounts) != 1 || len(backup.Categories) != 1 || len(backup.Transactions) != 1 {
		t.Fatalf("backup parent/transaction counts = %d/%d/%d, want 1/1/1",
			len(backup.Accounts), len(backup.Categories), len(backup.Transactions))
	}
	if err := svc.RestoreBackup(user.ID, writeBackupFile(t, backup)); err != nil {
		t.Fatalf("restore backup: %v", err)
	}
	var restoredAccount model.Account
	if err := db.Unscoped().First(&restoredAccount, "id = ? AND user_id = ?", account.ID, user.ID).Error; err != nil {
		t.Fatalf("load restored account: %v", err)
	}
	var restoredCategory model.Category
	if err := db.Unscoped().First(&restoredCategory, "id = ? AND user_id = ?", category.ID, user.ID).Error; err != nil {
		t.Fatalf("load restored category: %v", err)
	}
}

func TestRegressionConcurrentRefreshConsumesTokenOnce(t *testing.T) {
	svc, repos := newAuthServiceForTest(t)
	initial, err := svc.Init("LedgerInitPass123!")
	if err != nil {
		t.Fatalf("init: %v", err)
	}
	sqlDB, err := repos.User.DB().DB()
	if err != nil {
		t.Fatalf("sql db: %v", err)
	}
	sqlDB.SetMaxOpenConns(4)

	var arrivals atomic.Int32
	release := make(chan struct{})
	callbackName := "regression:refresh_delete_barrier"
	err = repos.User.DB().Callback().Delete().Before("gorm:begin_transaction").Register(callbackName, func(tx *gorm.DB) {
		if tx.Statement.Schema == nil || tx.Statement.Schema.Table != "refresh_tokens" {
			return
		}
		if arrivals.Add(1) == 2 {
			close(release)
		}
		select {
		case <-release:
		case <-time.After(5 * time.Second):
			tx.AddError(fmt.Errorf("refresh barrier timeout"))
		}
	})
	if err != nil {
		t.Fatalf("register callback: %v", err)
	}
	t.Cleanup(func() { _ = repos.User.DB().Callback().Delete().Remove(callbackName) })

	start := make(chan struct{})
	results := make(chan error, 2)
	var wg sync.WaitGroup
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			<-start
			_, err := svc.RefreshToken(initial.RefreshToken)
			results <- err
		}()
	}
	close(start)
	wg.Wait()
	close(results)
	successes := 0
	for err := range results {
		if err == nil {
			successes++
		}
	}
	if successes != 1 {
		t.Fatalf("successful refreshes = %d, want exactly 1", successes)
	}
}

func TestRegressionConcurrentSameNameUploadsUseUniqueDestinations(t *testing.T) {
	svc := NewUploadService(&config.StorageConfig{
		UploadPath: t.TempDir(), MaxFileSize: 1, AllowedTypes: "txt",
	})
	for round := 0; round < 12; round++ {
		const workers = 64
		files := make([]*multipart.FileHeader, workers)
		for i := range files {
			files[i] = newUploadFileHeader(t, "receipt.txt", fmt.Sprintf("round=%d worker=%d", round, i))
		}
		start := make(chan struct{})
		paths := make(chan string, workers)
		var wg sync.WaitGroup
		for i := range files {
			wg.Add(1)
			go func(index int) {
				defer wg.Done()
				<-start
				result, err := svc.Upload(7, "transactions", fmt.Sprintf("tx-%d", round), files[index])
				if err != nil {
					paths <- "ERROR:" + err.Error()
					return
				}
				paths <- result.Path
			}(i)
		}
		close(start)
		wg.Wait()
		close(paths)
		seen := map[string]struct{}{}
		for path := range paths {
			if _, exists := seen[path]; exists {
				t.Fatalf("duplicate upload destination returned: %q", path)
			}
			seen[path] = struct{}{}
		}
	}
}

func TestRegressionYearlyReportMatchesStatisticsScope(t *testing.T) {
	svc, repos, userID := newExportTestService(t)
	accountID := createAccountForTest(t, repos, userID, 0)
	year := time.Now().Year()
	txDate := time.Date(year, 6, 15, 12, 0, 0, 0, time.Local)
	lendingID := uuid.NewString()
	transactions := []model.Transaction{
		{ID: uuid.NewString(), UserID: userID, AccountID: accountID, Type: "income", Amount: 1000, TransactionDate: txDate, Source: "system"},
		{ID: uuid.NewString(), UserID: userID, AccountID: accountID, Type: "expense", Amount: 200, TransactionDate: txDate, Source: "lending", LendingID: &lendingID},
		{ID: uuid.NewString(), UserID: userID, AccountID: accountID, Type: "income", Amount: 300, TransactionDate: txDate, Source: "manual"},
		{ID: uuid.NewString(), UserID: userID, AccountID: accountID, Type: "expense", Amount: 50, TransactionDate: txDate, Source: "manual"},
	}
	if err := repos.Transaction.DB().Create(&transactions).Error; err != nil {
		t.Fatalf("create transactions: %v", err)
	}
	report, err := svc.GetYearlyReport(userID, year)
	if err != nil {
		t.Fatalf("get yearly report: %v", err)
	}
	if report.TotalIncome != 300 || report.TotalExpense != 50 || report.TransactionCount != 2 {
		t.Fatalf("yearly income/expense/count = %.2f/%.2f/%d, want 300/50/2",
			report.TotalIncome, report.TotalExpense, report.TransactionCount)
	}
}

func TestRegressionArchivedAccountStillContributesToNetWorth(t *testing.T) {
	_, repos, userID := newTransactionTestService(t)
	accountID := createAccountForTest(t, repos, userID, 321)
	svc := NewAccountService(repos.Account)
	if err := svc.Archive(accountID, userID, true); err != nil {
		t.Fatalf("archive account: %v", err)
	}
	after, err := svc.GetSummary(userID)
	if err != nil {
		t.Fatalf("summary after archive: %v", err)
	}
	if after.NetAssets != 321 {
		t.Fatalf("net assets after archive = %.2f, want 321.00", after.NetAssets)
	}
}

func TestRegressionLinkedReminderBalanceCannotDivergeFromDebtAccount(t *testing.T) {
	_, repos, userID := newTransactionTestService(t)
	reminderSvc := NewReminderService(
		repos.Reminder,
		repos.Account,
		repos.Transaction,
		repos.Category,
		NewAccountLogService(repos.AccountLog, repos.Account),
	)
	debtAccountID := createTypedAccountForTest(t, repos, userID, "loan", 500)
	paymentAccountID := createTypedAccountForTest(t, repos, userID, "cash", 1000)
	principal, currentBalance := money.Amount(500), money.Amount(500)
	reminder, err := reminderSvc.Create(userID, CreateReminderRequest{
		Name: "贷款", AccountID: &debtAccountID, LoanType: "loan", PaymentDay: 20,
		Principal: &principal, CurrentBalance: &currentBalance,
	})
	if err != nil {
		t.Fatalf("create reminder: %v", err)
	}
	if _, err := reminderSvc.RecordPayment(reminder.ID, userID, RecordPaymentRequest{
		Amount: 100, PrincipalAmount: 100, AccountID: &paymentAccountID,
	}); err != nil {
		t.Fatalf("record payment: %v", err)
	}
	manualBalance := money.Amount(475)
	_, err = reminderSvc.Update(reminder.ID, userID, CreateReminderRequest{
		Name: "贷款", AccountID: &debtAccountID, LoanType: "loan", PaymentDay: 20,
		Principal: &principal, CurrentBalance: &manualBalance,
	})
	if !errors.Is(err, ErrLinkedDebtBalanceImmutable) {
		t.Fatalf("update error = %v, want ErrLinkedDebtBalanceImmutable", err)
	}
	stored, err := reminderSvc.GetByID(reminder.ID, userID)
	if err != nil {
		t.Fatalf("reload reminder: %v", err)
	}
	if stored.CurrentBalance == nil || *stored.CurrentBalance != 400 {
		t.Fatalf("stored reminder balance = %#v, want 400", stored.CurrentBalance)
	}
}

func TestRegressionLendingOverpaymentIsRejected(t *testing.T) {
	_, repos, userID := newTransactionTestService(t)
	svc := newLendingTestService(repos)
	lending, err := svc.Create(userID, CreateLendingRequest{
		Type: "lend_out", ContactName: "超额还款", Principal: 100,
		LendDate: time.Now().Format(time.RFC3339),
	})
	if err != nil {
		t.Fatalf("create lending: %v", err)
	}
	_, err = svc.RecordRepayment(lending.ID, userID, RecordRepaymentRequest{
		Amount: 120, RecordDate: time.Now().Format(time.RFC3339),
	})
	if !errors.Is(err, ErrLendingOverpayment) {
		t.Fatalf("overpayment error = %v, want ErrLendingOverpayment", err)
	}
	var count int64
	if err := repos.Transaction.DB().Model(&model.LendingRecord{}).
		Where("user_id = ? AND lending_id = ?", userID, lending.ID).Count(&count).Error; err != nil {
		t.Fatalf("count lending records: %v", err)
	}
	if count != 0 {
		t.Fatalf("lending records after rejected overpayment = %d, want 0", count)
	}
}
