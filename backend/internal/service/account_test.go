package service

import (
	"encoding/json"
	"errors"
	"path/filepath"
	"testing"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"gorm.io/gorm"
)

func TestAccountPatchDistinguishesOmittedNullAndEmptyValues(t *testing.T) {
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init database: %v", err)
	}
	repos := repository.NewRepositories(db)
	billingDay := 8
	creditLimit := 12_000.0
	account := &model.Account{
		ID: uuid.NewString(), UserID: 7, Name: "Card", Type: "credit",
		BillingDay: &billingDay, CreditLimit: &creditLimit, Remark: "clear me",
	}
	if err := repos.Account.Create(account); err != nil {
		t.Fatalf("create account: %v", err)
	}
	var request PatchAccountRequest
	if err := json.Unmarshal([]byte(`{"name":"Renamed","billing_day":null,"remark":""}`), &request); err != nil {
		t.Fatalf("decode patch: %v", err)
	}
	updated, err := NewAccountService(repos.Account).Patch(account.ID, account.UserID, request)
	if err != nil {
		t.Fatalf("patch account: %v", err)
	}
	if updated.Name != "Renamed" || updated.BillingDay != nil || updated.Remark != "" {
		t.Fatalf("patched account = %#v", updated)
	}
	if updated.CreditLimit == nil || *updated.CreditLimit != creditLimit {
		t.Fatalf("omitted credit limit changed: %#v", updated.CreditLimit)
	}
}

func TestAccountPatchRejectsInvalidDate(t *testing.T) {
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init database: %v", err)
	}
	repos := repository.NewRepositories(db)
	account := &model.Account{ID: uuid.NewString(), UserID: 7, Name: "Cash", Type: "cash"}
	if err := repos.Account.Create(account); err != nil {
		t.Fatalf("create account: %v", err)
	}
	var request PatchAccountRequest
	if err := json.Unmarshal([]byte(`{"start_date":"not-a-date"}`), &request); err != nil {
		t.Fatalf("decode patch: %v", err)
	}
	if _, err := NewAccountService(repos.Account).Patch(account.ID, account.UserID, request); !errors.Is(err, ErrInvalidLocalDate) {
		t.Fatalf("patch error = %v, want ErrInvalidLocalDate", err)
	}
}

func TestAccountCreateRollsBackWhenInitialBalanceTransactionFails(t *testing.T) {
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init database: %v", err)
	}
	repos := repository.NewRepositories(db)
	svc := NewAccountService(repos.Account)
	forcedErr := errors.New("forced initial transaction failure")
	callbackName := "test:fail_initial_balance_transaction"
	if err := db.Callback().Create().Before("gorm:create").Register(callbackName, func(txdb *gorm.DB) {
		if txdb.Statement.Schema != nil && txdb.Statement.Schema.Table == "transactions" {
			txdb.AddError(forcedErr)
		}
	}); err != nil {
		t.Fatalf("register create callback: %v", err)
	}
	t.Cleanup(func() { _ = db.Callback().Create().Remove(callbackName) })

	_, err = svc.Create(7, CreateAccountRequest{
		Name:           "Cash",
		Type:           "cash",
		InitialBalance: 100,
	})
	if !errors.Is(err, forcedErr) {
		t.Fatalf("create account error = %v, want forced failure", err)
	}

	var accountCount int64
	if err := db.Model(&model.Account{}).Where("user_id = ?", 7).Count(&accountCount).Error; err != nil {
		t.Fatalf("count accounts: %v", err)
	}
	if accountCount != 0 {
		t.Fatalf("accounts after rollback = %d, want 0", accountCount)
	}
	var categoryCount int64
	if err := db.Model(&model.Category{}).Where("user_id = ? AND name = ?", 7, "期初余额").Count(&categoryCount).Error; err != nil {
		t.Fatalf("count initial categories: %v", err)
	}
	if categoryCount != 0 {
		t.Fatalf("initial categories after rollback = %d, want 0", categoryCount)
	}
}

func TestAccountMetadataUpdatesDoNotOverwriteFinancialState(t *testing.T) {
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init database: %v", err)
	}
	repos := repository.NewRepositories(db)
	account := &model.Account{
		ID:             uuid.NewString(),
		UserID:         7,
		Name:           "Cash",
		Type:           "cash",
		InitialBalance: 50,
		CurrentBalance: 125,
		TotalPaid:      30,
	}
	if err := repos.Account.Create(account); err != nil {
		t.Fatalf("create account: %v", err)
	}
	if err := repos.Account.UpdateMetadataForUser(account.ID, account.UserID, map[string]any{"current_balance": 999}); !errors.Is(err, repository.ErrUnsafeAccountFieldUpdate) {
		t.Fatalf("unsafe metadata update error = %v, want ErrUnsafeAccountFieldUpdate", err)
	}
	svc := NewAccountService(repos.Account)

	updated, err := svc.Update(account.ID, account.UserID, UpdateAccountRequest{
		Name:   "Daily Cash",
		Remark: "metadata only",
	})
	if err != nil {
		t.Fatalf("update account metadata: %v", err)
	}
	if updated.CurrentBalance != 125 || updated.InitialBalance != 50 || updated.TotalPaid != 30 || updated.Type != "cash" {
		t.Fatalf("financial fields changed during metadata update: %#v", updated)
	}

	if err := svc.Archive(account.ID, account.UserID, true); err != nil {
		t.Fatalf("archive account: %v", err)
	}
	archived, err := svc.GetByID(account.ID, account.UserID)
	if err != nil {
		t.Fatalf("load archived account: %v", err)
	}
	if !archived.IsArchived || archived.CurrentBalance != 125 || archived.TotalPaid != 30 {
		t.Fatalf("archive changed financial state: %#v", archived)
	}
}

func TestAccountDeleteUsesAtomicOwnershipAndBalanceGuard(t *testing.T) {
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init database: %v", err)
	}
	repos := repository.NewRepositories(db)
	svc := NewAccountService(repos.Account)
	account := &model.Account{
		ID:             uuid.NewString(),
		UserID:         7,
		Name:           "Cash",
		Type:           "cash",
		CurrentBalance: 1,
	}
	if err := repos.Account.Create(account); err != nil {
		t.Fatalf("create account: %v", err)
	}

	if err := svc.Delete(account.ID, 8); !errors.Is(err, ErrAccountNotFound) {
		t.Fatalf("cross-user delete error = %v, want ErrAccountNotFound", err)
	}
	if err := svc.Delete(account.ID, 7); !errors.Is(err, ErrAccountHasBalance) {
		t.Fatalf("non-zero delete error = %v, want ErrAccountHasBalance", err)
	}
	if err := db.Model(&model.Account{}).Where("id = ? AND user_id = ?", account.ID, 7).Update("current_balance", 0).Error; err != nil {
		t.Fatalf("zero account balance: %v", err)
	}
	if err := svc.Delete(account.ID, 7); err != nil {
		t.Fatalf("delete zero-balance account: %v", err)
	}
	if _, err := svc.GetByID(account.ID, 7); !errors.Is(err, ErrAccountNotFound) {
		t.Fatalf("deleted account lookup error = %v, want ErrAccountNotFound", err)
	}
}

func TestAccountSummaryClassifiesDebtCreditsAndNegativeAssets(t *testing.T) {
	_, repos, userID := newTransactionTestService(t)
	svc := NewAccountService(repos.Account)

	accounts := []struct {
		accountType string
		balance     float64
	}{
		{accountType: "cash", balance: 100},
		{accountType: "bank_card", balance: -25},
		{accountType: "credit", balance: 80},
		{accountType: "credit", balance: -10},
		{accountType: "payable", balance: 20},
		{accountType: "receivable", balance: 30},
	}
	for index, item := range accounts {
		if err := repos.Account.Create(&model.Account{
			ID:             uuid.NewString(),
			UserID:         userID,
			Name:           item.accountType + string(rune('A'+index)),
			Type:           item.accountType,
			CurrentBalance: item.balance,
		}); err != nil {
			t.Fatalf("create %s account: %v", item.accountType, err)
		}
	}

	if !IsDebtAccount("payable") {
		t.Fatal("payable account should be classified as debt")
	}
	if IsDebtAccount("receivable") {
		t.Fatal("receivable account should be classified as asset")
	}

	summary, err := svc.GetSummary(userID)
	if err != nil {
		t.Fatalf("get account summary: %v", err)
	}
	assertFloatEqual(t, "summary assets", summary.TotalAssets, 140)
	assertFloatEqual(t, "summary liabilities", summary.TotalLiabilities, 125)
	assertFloatEqual(t, "summary net assets", summary.NetAssets, 15)
}
