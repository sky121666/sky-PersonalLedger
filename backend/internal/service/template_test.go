package service

import (
	"errors"
	"path/filepath"
	"testing"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/money"
	"github.com/sky/personal-ledger/internal/repository"
	"gorm.io/gorm"
)

func newTemplateTestService(t *testing.T) (*TemplateService, *repository.Repositories, uint) {
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
	accountLogService := NewAccountLogService(repos.AccountLog, repos.Account)
	transactionService := NewTransactionService(repos.Transaction, repos.Account, repos.Reminder, repos.Lending, repos.FamilyMember, accountLogService)
	return NewTemplateService(repos.Template, transactionService), repos, user.ID
}

func createTemplateAccount(t *testing.T, repos *repository.Repositories, userID uint, balance float64) string {
	t.Helper()
	account := &model.Account{
		ID:             uuid.NewString(),
		UserID:         userID,
		Name:           "Wallet",
		Type:           "cash",
		CurrentBalance: money.Amount(balance),
	}
	if err := repos.Account.Create(account); err != nil {
		t.Fatalf("create account: %v", err)
	}
	return account.ID
}

func createTemplateCategory(t *testing.T, repos *repository.Repositories, userID uint, categoryType string) string {
	t.Helper()
	category := &model.Category{
		ID:     uuid.NewString(),
		UserID: userID,
		Name:   "Category",
		Type:   categoryType,
	}
	if err := repos.Category.Create(category); err != nil {
		t.Fatalf("create category: %v", err)
	}
	return category.ID
}

func createTemplateFixture(t *testing.T, svc *TemplateService, repos *repository.Repositories, userID uint, balance float64) (*model.QuickTemplate, string) {
	t.Helper()
	accountID := createTemplateAccount(t, repos, userID, balance)
	categoryID := createTemplateCategory(t, repos, userID, "expense")
	template, err := svc.Create(userID, CreateTemplateRequest{
		Name:       "Lunch",
		Type:       "expense",
		Amount:     25,
		AccountID:  accountID,
		CategoryID: &categoryID,
		Remark:     "template expense",
	})
	if err != nil {
		t.Fatalf("create template: %v", err)
	}
	return template, accountID
}

func TestCreateTemplateValidatesOwnershipAndCategoryType(t *testing.T) {
	t.Run("other user account", func(t *testing.T) {
		svc, repos, userID := newTemplateTestService(t)
		other := &model.User{Username: "other", PasswordHash: "hash"}
		if err := repos.User.Create(other); err != nil {
			t.Fatalf("create other user: %v", err)
		}
		accountID := createTemplateAccount(t, repos, other.ID, 100)

		_, err := svc.Create(userID, CreateTemplateRequest{Name: "Invalid", Type: "expense", Amount: 10, AccountID: accountID})
		if !errors.Is(err, ErrAccountNotFound) {
			t.Fatalf("err = %v, want ErrAccountNotFound", err)
		}
	})

	t.Run("other user category", func(t *testing.T) {
		svc, repos, userID := newTemplateTestService(t)
		accountID := createTemplateAccount(t, repos, userID, 100)
		other := &model.User{Username: "other", PasswordHash: "hash"}
		if err := repos.User.Create(other); err != nil {
			t.Fatalf("create other user: %v", err)
		}
		categoryID := createTemplateCategory(t, repos, other.ID, "expense")

		_, err := svc.Create(userID, CreateTemplateRequest{Name: "Invalid", Type: "expense", Amount: 10, AccountID: accountID, CategoryID: &categoryID})
		if !errors.Is(err, ErrCategoryNotFound) {
			t.Fatalf("err = %v, want ErrCategoryNotFound", err)
		}
	})

	t.Run("category type mismatch", func(t *testing.T) {
		svc, repos, userID := newTemplateTestService(t)
		accountID := createTemplateAccount(t, repos, userID, 100)
		categoryID := createTemplateCategory(t, repos, userID, "income")

		_, err := svc.Create(userID, CreateTemplateRequest{Name: "Invalid", Type: "expense", Amount: 10, AccountID: accountID, CategoryID: &categoryID})
		if !errors.Is(err, ErrCategoryTypeMismatch) {
			t.Fatalf("err = %v, want ErrCategoryTypeMismatch", err)
		}
	})
}

func TestApplyTemplateCommitsTransactionBalanceLogAndUsageTogether(t *testing.T) {
	svc, repos, userID := newTemplateTestService(t)
	template, accountID := createTemplateFixture(t, svc, repos, userID, 100)

	tx, err := svc.Apply(template.ID, userID, ApplyTemplateRequest{TransactionDate: "2026-07-13"})
	if err != nil {
		t.Fatalf("apply template: %v", err)
	}
	if tx.Source != "template" {
		t.Fatalf("source = %q, want template", tx.Source)
	}
	if tx.UserID != userID || tx.AccountID != accountID || tx.Amount != 25 {
		t.Fatalf("unexpected transaction: %#v", tx)
	}

	account, err := repos.Account.GetByID(accountID)
	if err != nil {
		t.Fatalf("get account: %v", err)
	}
	if account.CurrentBalance != 75 {
		t.Fatalf("balance = %.2f, want 75", account.CurrentBalance)
	}
	log := requireAccountLog(t, repos, userID, tx.ID, accountID, "expense")
	if log.BalanceBefore != 100 || log.BalanceAfter != 75 {
		t.Fatalf("account log = before %.2f after %.2f, want 100 -> 75", log.BalanceBefore, log.BalanceAfter)
	}
	reloaded, err := repos.Template.GetByIDForUser(template.ID, userID)
	if err != nil {
		t.Fatalf("get template: %v", err)
	}
	if reloaded.UsedCount != 1 || reloaded.LastUsedAt == nil {
		t.Fatalf("template usage = count %d last %v, want count 1 with timestamp", reloaded.UsedCount, reloaded.LastUsedAt)
	}
}

func TestApplyTemplateValidationFailureLeavesNoMutation(t *testing.T) {
	for _, test := range []struct {
		name string
		req  ApplyTemplateRequest
	}{
		{name: "invalid date", req: ApplyTemplateRequest{TransactionDate: "not-a-date"}},
		{name: "zero amount", req: ApplyTemplateRequest{TransactionDate: "2026-07-13", Amount: float64Pointer(0)}},
		{name: "negative amount", req: ApplyTemplateRequest{TransactionDate: "2026-07-13", Amount: float64Pointer(-1)}},
	} {
		t.Run(test.name, func(t *testing.T) {
			svc, repos, userID := newTemplateTestService(t)
			template, accountID := createTemplateFixture(t, svc, repos, userID, 100)

			if _, err := svc.Apply(template.ID, userID, test.req); err == nil {
				t.Fatal("expected apply to fail")
			}
			assertTemplateApplyState(t, repos, userID, template.ID, accountID, 100, 0)
		})
	}
}

func TestApplyTemplateRollsBackWhenUsageUpdateFails(t *testing.T) {
	svc, repos, userID := newTemplateTestService(t)
	template, accountID := createTemplateFixture(t, svc, repos, userID, 100)
	db := repos.Account.DB()
	callbackName := "test:fail_template_usage_update"
	forcedErr := errors.New("forced template usage update failure")
	if err := db.Callback().Update().Before("gorm:update").Register(callbackName, func(tx *gorm.DB) {
		if tx.Statement.Schema != nil && tx.Statement.Schema.Table == "quick_templates" {
			tx.AddError(forcedErr)
		}
	}); err != nil {
		t.Fatalf("register callback: %v", err)
	}
	t.Cleanup(func() {
		_ = db.Callback().Update().Remove(callbackName)
	})

	_, err := svc.Apply(template.ID, userID, ApplyTemplateRequest{TransactionDate: "2026-07-13"})
	if !errors.Is(err, forcedErr) {
		t.Fatalf("err = %v, want forced callback error", err)
	}
	assertTemplateApplyState(t, repos, userID, template.ID, accountID, 100, 0)
}

func TestApplyTemplateRollsBackWhenTransactionReloadFails(t *testing.T) {
	svc, repos, userID := newTemplateTestService(t)
	template, accountID := createTemplateFixture(t, svc, repos, userID, 100)
	db := repos.Account.DB()
	callbackName := "test:fail_transaction_reload"
	forcedErr := errors.New("forced transaction reload failure")
	failed := false
	if err := db.Callback().Query().Before("gorm:query").Register(callbackName, func(tx *gorm.DB) {
		if !failed && tx.Statement.Schema != nil && tx.Statement.Schema.Table == "transactions" {
			failed = true
			tx.AddError(forcedErr)
		}
	}); err != nil {
		t.Fatalf("register callback: %v", err)
	}
	t.Cleanup(func() {
		_ = db.Callback().Query().Remove(callbackName)
	})

	_, err := svc.Apply(template.ID, userID, ApplyTemplateRequest{TransactionDate: "2026-07-13"})
	if !errors.Is(err, forcedErr) {
		t.Fatalf("err = %v, want forced callback error", err)
	}
	assertTemplateApplyState(t, repos, userID, template.ID, accountID, 100, 0)
}

func TestBalanceAccountIDsAreSortedForDeterministicLocking(t *testing.T) {
	fromID := "z-account"
	toID := "a-account"
	got := balanceAccountIDs(&model.Transaction{
		Type:        "transfer",
		AccountID:   fromID,
		ToAccountID: &toID,
	})

	if len(got) != 2 || got[0] != toID || got[1] != fromID {
		t.Fatalf("balance account lock order = %v, want [%s %s]", got, toID, fromID)
	}
}

func TestApplyTemplateCannotUseAnotherUsersTemplate(t *testing.T) {
	svc, repos, userID := newTemplateTestService(t)
	other := &model.User{Username: "other", PasswordHash: "hash"}
	if err := repos.User.Create(other); err != nil {
		t.Fatalf("create other user: %v", err)
	}
	template, accountID := createTemplateFixture(t, svc, repos, other.ID, 100)

	_, err := svc.Apply(template.ID, userID, ApplyTemplateRequest{TransactionDate: "2026-07-13"})
	if !errors.Is(err, ErrTemplateNotFound) {
		t.Fatalf("err = %v, want ErrTemplateNotFound", err)
	}
	assertTemplateApplyState(t, repos, other.ID, template.ID, accountID, 100, 0)
}

func assertTemplateApplyState(t *testing.T, repos *repository.Repositories, userID uint, templateID, accountID string, balance float64, usedCount int) {
	t.Helper()
	account, err := repos.Account.GetByID(accountID)
	if err != nil {
		t.Fatalf("get account: %v", err)
	}
	if account.CurrentBalance != money.Amount(balance) {
		t.Fatalf("balance = %.2f, want %.2f", account.CurrentBalance, balance)
	}
	var transactionCount int64
	if err := repos.Transaction.DB().Model(&model.Transaction{}).Where("user_id = ?", userID).Count(&transactionCount).Error; err != nil {
		t.Fatalf("count transactions: %v", err)
	}
	if transactionCount != 0 {
		t.Fatalf("transaction count = %d, want 0", transactionCount)
	}
	var logCount int64
	if err := repos.Account.DB().Model(&model.AccountLog{}).Where("user_id = ?", userID).Count(&logCount).Error; err != nil {
		t.Fatalf("count account logs: %v", err)
	}
	if logCount != 0 {
		t.Fatalf("account log count = %d, want 0", logCount)
	}
	template, err := repos.Template.GetByIDForUser(templateID, userID)
	if err != nil {
		t.Fatalf("get template: %v", err)
	}
	if template.UsedCount != usedCount || template.LastUsedAt != nil {
		t.Fatalf("template usage = count %d last %v, want count %d and nil timestamp", template.UsedCount, template.LastUsedAt, usedCount)
	}
}

func float64Pointer(value float64) *money.Amount {
	amount := money.Amount(value)
	return &amount
}
