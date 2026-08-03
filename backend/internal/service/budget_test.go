package service

import (
	"path/filepath"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/money"
	"github.com/sky/personal-ledger/internal/repository"
)

func newBudgetTestService(t *testing.T) (*BudgetService, *FamilyMemberService, *TransactionService, *repository.Repositories, uint) {
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
	return NewBudgetService(repos.Budget, repos.Transaction, repos.FamilyMember, repos.Category),
		NewFamilyMemberService(repos.FamilyMember, repos.Transaction),
		NewTransactionService(repos.Transaction, repos.Account, repos.Reminder, repos.Lending, repos.FamilyMember, accountLogSvc),
		repos,
		user.ID
}

func TestBudgetListIncludesMemberBudgets(t *testing.T) {
	budgetSvc, familySvc, transactionSvc, repos, userID := newBudgetTestService(t)
	accountID := createAccountForTest(t, repos, userID, 500)
	categoryID := createBudgetCategoryForTest(t, repos, userID, "Food")
	member, err := familySvc.Create(userID, CreateFamilyMemberRequest{Name: "家人"})
	if err != nil {
		t.Fatalf("create member: %v", err)
	}

	if _, err := budgetSvc.SetTotalBudget(userID, SetBudgetRequest{Amount: 1000, AlertThreshold: 80}); err != nil {
		t.Fatalf("set total budget: %v", err)
	}
	if _, err := budgetSvc.SetCategoryBudget(userID, SetBudgetRequest{CategoryID: &categoryID, Amount: 500, AlertThreshold: 80}); err != nil {
		t.Fatalf("set category budget: %v", err)
	}
	if _, err := budgetSvc.SetTotalBudget(userID, SetBudgetRequest{MemberID: &member.ID, Amount: 300, AlertThreshold: 70}); err != nil {
		t.Fatalf("set member total budget: %v", err)
	}
	if _, err := budgetSvc.SetCategoryBudget(userID, SetBudgetRequest{CategoryID: &categoryID, MemberID: &member.ID, Amount: 120}); err != nil {
		t.Fatalf("set member category budget: %v", err)
	}
	createBudgetTransaction(t, transactionSvc, userID, accountID, categoryID, member.ID, 80, "2026-05-12")
	createBudgetRawTransaction(t, repos, model.Transaction{
		ID:              "budget-member-system",
		UserID:          userID,
		AccountID:       accountID,
		CategoryID:      &categoryID,
		Type:            "expense",
		Amount:          5000,
		TransactionDate: mustBudgetDate(t, "2026-05-13"),
		MemberID:        &member.ID,
		Remark:          "期初余额: 成员账户",
		Source:          "system",
	})
	lendingID := "budget-lending-id"
	createBudgetRawTransaction(t, repos, model.Transaction{
		ID:              "budget-member-lending",
		UserID:          userID,
		AccountID:       accountID,
		CategoryID:      &categoryID,
		Type:            "expense",
		Amount:          3000,
		TransactionDate: mustBudgetDate(t, "2026-05-14"),
		MemberID:        &member.ID,
		Remark:          "借出给朋友",
		Source:          "lending",
		LendingID:       &lendingID,
	})

	list, err := budgetSvc.List(userID, "2026-05")
	if err != nil {
		t.Fatalf("list budgets: %v", err)
	}
	if list.TotalBudget == nil || list.TotalBudget.Spent != 80 || list.TotalBudget.Remaining != 920 || list.TotalBudget.Percentage != 8 {
		t.Fatalf("total budget = %#v, want spent 80 remaining 920 percentage 8", list.TotalBudget)
	}
	globalCategory := findBudgetItemByScope(t, list.CategoryBudgets, &categoryID, nil)
	if globalCategory.CategoryName != "Food" || globalCategory.Spent != 80 || globalCategory.Remaining != 420 || globalCategory.Percentage != 16 {
		t.Fatalf("category budget = %#v, want Food spent 80 remaining 420 percentage 16", globalCategory)
	}
	if len(list.MemberBudgets) != 2 {
		t.Fatalf("member budgets len = %d, want 2", len(list.MemberBudgets))
	}
	total := findBudgetItemByScope(t, list.MemberBudgets, nil, &member.ID)
	if total.MemberName != "家人" || total.Spent != 80 || total.Remaining != 220 || total.Percentage != 26 {
		t.Fatalf("member total budget = %#v, want spent 80 remaining 220 percentage 26", total)
	}
	category := findBudgetItemByScope(t, list.MemberBudgets, &categoryID, &member.ID)
	if category.CategoryName != "Food" || category.Spent != 80 || category.Remaining != 40 || category.Percentage != 66 {
		t.Fatalf("member category budget = %#v, want Food spent 80 remaining 40 percentage 66", category)
	}
}

func TestSetBudgetRejectsOtherUserMember(t *testing.T) {
	budgetSvc, familySvc, _, repos, userID := newBudgetTestService(t)
	otherUser := &model.User{Username: "other", PasswordHash: "hash"}
	if err := repos.User.Create(otherUser); err != nil {
		t.Fatalf("create other user: %v", err)
	}
	otherMember, err := familySvc.Create(otherUser.ID, CreateFamilyMemberRequest{Name: "其他人"})
	if err != nil {
		t.Fatalf("create other member: %v", err)
	}

	if _, err := budgetSvc.SetTotalBudget(userID, SetBudgetRequest{MemberID: &otherMember.ID, Amount: 100}); err != ErrFamilyMemberNotFound {
		t.Fatalf("set budget err = %v, want ErrFamilyMemberNotFound", err)
	}
}

func TestSetBudgetRejectsOtherUserCategory(t *testing.T) {
	budgetSvc, _, _, repos, userID := newBudgetTestService(t)
	otherUser := &model.User{Username: "other-category-owner", PasswordHash: "hash"}
	if err := repos.User.Create(otherUser); err != nil {
		t.Fatalf("create other user: %v", err)
	}
	otherCategoryID := createBudgetCategoryForTest(t, repos, otherUser.ID, "Private")

	if _, err := budgetSvc.SetCategoryBudget(userID, SetBudgetRequest{
		CategoryID: &otherCategoryID,
		Amount:     100,
	}); err != ErrCategoryNotFound {
		t.Fatalf("set budget err = %v, want ErrCategoryNotFound", err)
	}
	list, err := budgetSvc.List(userID, "2026-05")
	if err != nil {
		t.Fatalf("list budgets: %v", err)
	}
	if len(list.CategoryBudgets) != 0 {
		t.Fatalf("category budgets = %#v, want none", list.CategoryBudgets)
	}
}

func TestSetMemberBudgetUpdatesExistingScope(t *testing.T) {
	budgetSvc, familySvc, _, _, userID := newBudgetTestService(t)
	member, err := familySvc.Create(userID, CreateFamilyMemberRequest{Name: "家人"})
	if err != nil {
		t.Fatalf("create member: %v", err)
	}

	first, err := budgetSvc.SetTotalBudget(userID, SetBudgetRequest{MemberID: &member.ID, Amount: 100})
	if err != nil {
		t.Fatalf("set first budget: %v", err)
	}
	second, err := budgetSvc.SetTotalBudget(userID, SetBudgetRequest{MemberID: &member.ID, Amount: 200, AlertThreshold: 75})
	if err != nil {
		t.Fatalf("set second budget: %v", err)
	}
	if second.ID != first.ID || second.Amount != 200 || second.AlertThreshold != 75 {
		t.Fatalf("updated budget = %#v, want same ID with amount 200 threshold 75", second)
	}
}

func TestBudgetListUsesLocalCalendarMonthBoundaries(t *testing.T) {
	previousLocal := time.Local
	local := time.FixedZone("UTC+08", 8*60*60)
	time.Local = local
	t.Cleanup(func() {
		time.Local = previousLocal
	})

	budgetSvc, _, _, repos, userID := newBudgetTestService(t)
	accountID := createAccountForTest(t, repos, userID, 500)
	categoryID := createBudgetCategoryForTest(t, repos, userID, "Food")
	startDate, endDate, err := budgetMonthRange("2026-05")
	if err != nil {
		t.Fatalf("parse budget month: %v", err)
	}
	wantStart := time.Date(2026, time.May, 1, 0, 0, 0, 0, local)
	wantEnd := time.Date(2026, time.June, 1, 0, 0, 0, 0, local).Add(-time.Nanosecond)
	if !startDate.Equal(wantStart) || startDate.Location() != local {
		t.Fatalf("month start = %v, want %v in local timezone", startDate, wantStart)
	}
	if !endDate.Equal(wantEnd) || endDate.Location() != local {
		t.Fatalf("month end = %v, want %v in local timezone", endDate, wantEnd)
	}
	if _, err := budgetSvc.SetTotalBudget(userID, SetBudgetRequest{Amount: 1000}); err != nil {
		t.Fatalf("set total budget: %v", err)
	}

	transactions := []model.Transaction{
		{
			ID:              "budget-before-local-month",
			UserID:          userID,
			AccountID:       accountID,
			CategoryID:      &categoryID,
			Type:            "expense",
			Amount:          100,
			TransactionDate: time.Date(2026, time.April, 30, 23, 59, 59, 0, local),
		},
		{
			ID:              "budget-local-month-start",
			UserID:          userID,
			AccountID:       accountID,
			CategoryID:      &categoryID,
			Type:            "expense",
			Amount:          10,
			TransactionDate: time.Date(2026, time.May, 1, 0, 0, 0, 0, local),
		},
		{
			ID:              "budget-local-month-end",
			UserID:          userID,
			AccountID:       accountID,
			CategoryID:      &categoryID,
			Type:            "expense",
			Amount:          20,
			TransactionDate: time.Date(2026, time.May, 31, 23, 59, 59, 500_000_000, local),
		},
		{
			ID:              "budget-after-local-month",
			UserID:          userID,
			AccountID:       accountID,
			CategoryID:      &categoryID,
			Type:            "expense",
			Amount:          100,
			TransactionDate: time.Date(2026, time.June, 1, 0, 0, 0, 0, local),
		},
	}
	for _, tx := range transactions {
		createBudgetRawTransaction(t, repos, tx)
	}

	list, err := budgetSvc.List(userID, "2026-05")
	if err != nil {
		t.Fatalf("list budgets: %v", err)
	}
	if list.TotalBudget == nil || list.TotalBudget.Spent != 30 {
		t.Fatalf("total budget = %#v, want local May spending 30", list.TotalBudget)
	}
}

func createBudgetCategoryForTest(t *testing.T, repos *repository.Repositories, userID uint, name string) string {
	t.Helper()
	id := uuid.NewString()
	if err := repos.Category.Create(&model.Category{
		ID:     id,
		UserID: userID,
		Name:   name,
		Type:   "expense",
	}); err != nil {
		t.Fatalf("create category: %v", err)
	}
	return id
}

func createBudgetTransaction(t *testing.T, svc *TransactionService, userID uint, accountID, categoryID, memberID string, amount float64, date string) {
	t.Helper()
	if _, err := svc.Create(userID, CreateTransactionRequest{
		Type:            "expense",
		Amount:          money.Amount(amount),
		AccountID:       accountID,
		CategoryID:      &categoryID,
		MemberID:        &memberID,
		TransactionDate: date,
	}); err != nil {
		t.Fatalf("create budget transaction: %v", err)
	}
}

func createBudgetRawTransaction(t *testing.T, repos *repository.Repositories, tx model.Transaction) {
	t.Helper()
	if err := repos.Transaction.Create(&tx); err != nil {
		t.Fatalf("create raw budget transaction %s: %v", tx.ID, err)
	}
}

func mustBudgetDate(t *testing.T, value string) time.Time {
	t.Helper()
	date, err := time.ParseInLocation("2006-01-02", value, time.Local)
	if err != nil {
		t.Fatalf("parse budget date %q: %v", value, err)
	}
	return date
}

func findBudgetItemByScope(t *testing.T, items []BudgetItem, categoryID, memberID *string) BudgetItem {
	t.Helper()
	for _, item := range items {
		if sameStringPtr(item.CategoryID, categoryID) && sameStringPtr(item.MemberID, memberID) {
			return item
		}
	}
	t.Fatalf("budget item not found for category=%v member=%v in %#v", categoryID, memberID, items)
	return BudgetItem{}
}

func sameStringPtr(a, b *string) bool {
	if a == nil || b == nil {
		return a == b
	}
	return *a == *b
}
