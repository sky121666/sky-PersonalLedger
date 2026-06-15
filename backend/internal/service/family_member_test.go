package service

import (
	"path/filepath"
	"testing"
	"time"

	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

func newFamilyMemberTestService(t *testing.T) (*FamilyMemberService, *repository.Repositories, uint) {
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
	return NewFamilyMemberService(repos.FamilyMember, repos.Transaction), repos, user.ID
}

func TestFamilyMemberCreateFirstMemberAsDefault(t *testing.T) {
	svc, _, userID := newFamilyMemberTestService(t)

	member, err := svc.Create(userID, CreateFamilyMemberRequest{
		Name:         "我",
		Relationship: "self",
		Color:        "#0F766E",
	})
	if err != nil {
		t.Fatalf("create member: %v", err)
	}

	if member.ID == "" {
		t.Fatal("member ID should be generated")
	}
	if !member.IsDefault {
		t.Fatal("first member should be default")
	}
	if !member.IsEnabled {
		t.Fatal("new member should be enabled")
	}
	if member.SortOrder != 0 {
		t.Fatalf("sort order = %d, want 0", member.SortOrder)
	}
}

func TestFamilyMemberListOrdersDefaultAndSortOrder(t *testing.T) {
	svc, _, userID := newFamilyMemberTestService(t)

	first, err := svc.Create(userID, CreateFamilyMemberRequest{Name: "我", Relationship: "self"})
	if err != nil {
		t.Fatalf("create first member: %v", err)
	}
	second, err := svc.Create(userID, CreateFamilyMemberRequest{Name: "家人", Relationship: "spouse"})
	if err != nil {
		t.Fatalf("create second member: %v", err)
	}

	list, err := svc.List(userID)
	if err != nil {
		t.Fatalf("list members: %v", err)
	}
	if len(list) != 2 {
		t.Fatalf("list len = %d, want 2", len(list))
	}
	if list[0].ID != first.ID || list[1].ID != second.ID {
		t.Fatalf("member order = [%s %s], want [%s %s]", list[0].ID, list[1].ID, first.ID, second.ID)
	}
}

func TestFamilyMemberUpdateCanSetSingleDefault(t *testing.T) {
	svc, _, userID := newFamilyMemberTestService(t)

	first, err := svc.Create(userID, CreateFamilyMemberRequest{Name: "我", Relationship: "self"})
	if err != nil {
		t.Fatalf("create first member: %v", err)
	}
	second, err := svc.Create(userID, CreateFamilyMemberRequest{Name: "家人", Relationship: "spouse"})
	if err != nil {
		t.Fatalf("create second member: %v", err)
	}

	updated, err := svc.Update(second.ID, userID, UpdateFamilyMemberRequest{
		Name:         "家人",
		Relationship: "spouse",
		Color:        "#2563EB",
		IsDefault:    boolPtr(true),
		IsEnabled:    boolPtr(true),
	})
	if err != nil {
		t.Fatalf("update member: %v", err)
	}
	if !updated.IsDefault {
		t.Fatal("updated member should be default")
	}

	reloadedFirst, err := svc.GetByID(first.ID, userID)
	if err != nil {
		t.Fatalf("get first member: %v", err)
	}
	if reloadedFirst.IsDefault {
		t.Fatal("first member should no longer be default")
	}
}

func TestFamilyMemberDisableKeepsHistoricalRecord(t *testing.T) {
	svc, _, userID := newFamilyMemberTestService(t)

	member, err := svc.Create(userID, CreateFamilyMemberRequest{Name: "家人"})
	if err != nil {
		t.Fatalf("create member: %v", err)
	}

	if err := svc.Delete(member.ID, userID); err != nil {
		t.Fatalf("delete member: %v", err)
	}

	disabled, err := svc.GetByID(member.ID, userID)
	if err != nil {
		t.Fatalf("get disabled member: %v", err)
	}
	if disabled.IsEnabled {
		t.Fatal("deleted member should be disabled")
	}
}

func TestFamilyMemberRejectsOtherUserMember(t *testing.T) {
	svc, repos, userID := newFamilyMemberTestService(t)
	otherUser := &model.User{Username: "other", PasswordHash: "hash"}
	if err := repos.User.Create(otherUser); err != nil {
		t.Fatalf("create other user: %v", err)
	}

	otherMember, err := svc.Create(otherUser.ID, CreateFamilyMemberRequest{Name: "其他人"})
	if err != nil {
		t.Fatalf("create other member: %v", err)
	}

	if _, err := svc.GetByID(otherMember.ID, userID); err != ErrFamilyMemberNotFound {
		t.Fatalf("get other user member err = %v, want ErrFamilyMemberNotFound", err)
	}
}

func TestFamilySummaryGroupsMonthlyExpenseByMember(t *testing.T) {
	svc, repos, userID := newFamilyMemberTestService(t)
	accountID := createAccountForTest(t, repos, userID, 500)
	transactionSvc := NewTransactionService(repos.Transaction, repos.Account, repos.Reminder, repos.Lending, repos.FamilyMember, nil)
	self, err := svc.Create(userID, CreateFamilyMemberRequest{Name: "我"})
	if err != nil {
		t.Fatalf("create self member: %v", err)
	}
	family, err := svc.Create(userID, CreateFamilyMemberRequest{Name: "家人"})
	if err != nil {
		t.Fatalf("create family member: %v", err)
	}

	createSummaryTransaction(t, transactionSvc, userID, accountID, "expense", 120, "2026-05-03", &self.ID)
	createSummaryTransaction(t, transactionSvc, userID, accountID, "expense", 80, "2026-05-04", &family.ID)
	createSummaryTransaction(t, transactionSvc, userID, accountID, "income", 1000, "2026-05-05", &self.ID)
	createSummaryTransaction(t, transactionSvc, userID, accountID, "expense", 300, "2026-04-30", &self.ID)
	createSummaryRawTransaction(t, repos, model.Transaction{
		ID:              "summary-system-opening",
		UserID:          userID,
		AccountID:       accountID,
		Type:            "expense",
		Amount:          520000,
		TransactionDate: mustSummaryDate(t, "2026-05-01"),
		Remark:          "期初余额: 房贷",
		Source:          "system",
	})
	createSummaryRawTransaction(t, repos, model.Transaction{
		ID:              "summary-member-system",
		UserID:          userID,
		AccountID:       accountID,
		Type:            "expense",
		Amount:          9000,
		TransactionDate: mustSummaryDate(t, "2026-05-02"),
		MemberID:        &self.ID,
		Remark:          "期初余额: 成员账户",
		Source:          "system",
	})
	lendingID := "summary-lending-id"
	createSummaryRawTransaction(t, repos, model.Transaction{
		ID:              "summary-lending",
		UserID:          userID,
		AccountID:       accountID,
		Type:            "expense",
		Amount:          5000,
		TransactionDate: mustSummaryDate(t, "2026-05-06"),
		MemberID:        &self.ID,
		Remark:          "借出给朋友",
		Source:          "lending",
		LendingID:       &lendingID,
	})

	summary, err := svc.Summary(userID, "2026-05")
	if err != nil {
		t.Fatalf("summary: %v", err)
	}

	assertFloatEqual(t, "family total expense", summary.TotalExpense, 200)
	if len(summary.Members) != 2 {
		t.Fatalf("summary members len = %d, want 2", len(summary.Members))
	}
	if summary.Members[0].MemberID != self.ID || summary.Members[0].ExpenseTotal != 120 {
		t.Fatalf("first member summary = %#v, want self 120", summary.Members[0])
	}
	if summary.Members[1].MemberID != family.ID || summary.Members[1].ExpenseTotal != 80 {
		t.Fatalf("second member summary = %#v, want family 80", summary.Members[1])
	}
}

func TestFamilySummaryReturnsEmptyState(t *testing.T) {
	svc, _, userID := newFamilyMemberTestService(t)

	summary, err := svc.Summary(userID, "2026-05")
	if err != nil {
		t.Fatalf("summary: %v", err)
	}

	if summary.Month != "2026-05" {
		t.Fatalf("month = %q, want 2026-05", summary.Month)
	}
	if summary.TotalExpense != 0 || len(summary.Members) != 0 {
		t.Fatalf("summary = %#v, want empty totals", summary)
	}
}

func createSummaryTransaction(t *testing.T, svc *TransactionService, userID uint, accountID string, txType string, amount float64, date string, memberID *string) {
	t.Helper()
	if _, err := svc.Create(userID, CreateTransactionRequest{
		Type:            txType,
		Amount:          amount,
		AccountID:       accountID,
		MemberID:        memberID,
		TransactionDate: date,
	}); err != nil {
		t.Fatalf("create %s transaction on %s: %v", txType, date, err)
	}
}

func createSummaryRawTransaction(t *testing.T, repos *repository.Repositories, tx model.Transaction) {
	t.Helper()
	if err := repos.Transaction.Create(&tx); err != nil {
		t.Fatalf("create raw summary transaction %s: %v", tx.ID, err)
	}
}

func mustSummaryDate(t *testing.T, value string) time.Time {
	t.Helper()
	date, err := time.ParseInLocation("2006-01-02", value, time.Local)
	if err != nil {
		t.Fatalf("parse summary date %q: %v", value, err)
	}
	return date
}

func boolPtr(value bool) *bool {
	return &value
}
