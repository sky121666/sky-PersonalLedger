package service

import (
	"path/filepath"
	"testing"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
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
	return NewBudgetService(repos.Budget, repos.Transaction, repos.FamilyMember),
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

	if _, err := budgetSvc.SetTotalBudget(userID, SetBudgetRequest{MemberID: &member.ID, Amount: 300, AlertThreshold: 70}); err != nil {
		t.Fatalf("set member total budget: %v", err)
	}
	if _, err := budgetSvc.SetCategoryBudget(userID, SetBudgetRequest{CategoryID: &categoryID, MemberID: &member.ID, Amount: 120}); err != nil {
		t.Fatalf("set member category budget: %v", err)
	}
	createBudgetTransaction(t, transactionSvc, userID, accountID, categoryID, member.ID, 80, "2026-05-12")

	list, err := budgetSvc.List(userID, "2026-05")
	if err != nil {
		t.Fatalf("list budgets: %v", err)
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
		Amount:          amount,
		AccountID:       accountID,
		CategoryID:      &categoryID,
		MemberID:        &memberID,
		TransactionDate: date,
	}); err != nil {
		t.Fatalf("create budget transaction: %v", err)
	}
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
