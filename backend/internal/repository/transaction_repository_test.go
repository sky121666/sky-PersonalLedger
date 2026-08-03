package repository

import (
	"errors"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/money"
	"gorm.io/gorm"
)

func TestTransactionRepositoryScopesListsAndFinancialAggregates(t *testing.T) {
	repos, owner, other := newRepositoryTestFixture(t)
	primary := &model.Account{ID: uuid.NewString(), UserID: owner.ID, Name: "Wallet", Type: "cash"}
	secondary := &model.Account{ID: uuid.NewString(), UserID: owner.ID, Name: "Bank", Type: "bank"}
	otherAccount := &model.Account{ID: uuid.NewString(), UserID: other.ID, Name: "Other", Type: "cash"}
	if err := repos.Account.CreateBatch([]model.Account{*primary, *secondary, *otherAccount}); err != nil {
		t.Fatalf("create accounts: %v", err)
	}
	category := &model.Category{ID: uuid.NewString(), UserID: owner.ID, Name: "Food", Type: "expense", Icon: "meal"}
	if err := repos.Category.Create(category); err != nil {
		t.Fatalf("create category: %v", err)
	}
	member := &model.FamilyMember{UserID: owner.ID, Name: "Owner"}
	if err := repos.FamilyMember.Create(member); err != nil {
		t.Fatalf("create member: %v", err)
	}

	start := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	end := time.Date(2026, 12, 31, 23, 59, 59, 0, time.UTC)
	toAccountID := secondary.ID
	categoryID := category.ID
	memberID := member.ID
	lendingID := uuid.NewString()
	transactions := []*model.Transaction{
		{ID: "expense", UserID: owner.ID, AccountID: primary.ID, CategoryID: &categoryID, MemberID: &memberID, Type: "expense", Amount: 1000, TransactionDate: start.Add(4 * 24 * time.Hour), Remark: "grocery", Source: "manual"},
		{ID: "income", UserID: owner.ID, AccountID: primary.ID, Type: "income", Amount: 5000, TransactionDate: start.Add(5 * 24 * time.Hour), Remark: "salary", Source: "manual"},
		{ID: "transfer", UserID: owner.ID, AccountID: primary.ID, ToAccountID: &toAccountID, Type: "transfer", Amount: 200, TransactionDate: start.Add(6 * 24 * time.Hour), Remark: "move", Source: "manual"},
		{ID: "system", UserID: owner.ID, AccountID: primary.ID, CategoryID: &categoryID, Type: "expense", Amount: 9999, TransactionDate: start.Add(7 * 24 * time.Hour), Remark: "generated", Source: "system"},
		{ID: "lending", UserID: owner.ID, AccountID: primary.ID, CategoryID: &categoryID, Type: "expense", Amount: 777, TransactionDate: start.Add(8 * 24 * time.Hour), Remark: "repayment", Source: "manual", LendingID: &lendingID},
		{ID: "other-user", UserID: other.ID, AccountID: otherAccount.ID, Type: "expense", Amount: 8888, TransactionDate: start.Add(4 * 24 * time.Hour), Remark: "private", Source: "manual"},
	}
	for _, transaction := range transactions {
		if err := repos.Transaction.Create(transaction); err != nil {
			t.Fatalf("create transaction %s: %v", transaction.ID, err)
		}
	}

	loaded, err := repos.Transaction.GetByID("expense")
	if err != nil || loaded.Account == nil || loaded.Category == nil {
		t.Fatalf("preloaded transaction = %#v, err=%v", loaded, err)
	}
	if _, err := repos.Transaction.GetByIDForUser("expense", other.ID); !errors.Is(err, gorm.ErrRecordNotFound) {
		t.Fatalf("cross-user transaction read error = %v", err)
	}
	if _, err := repos.Transaction.GetByIDForUserWithDB(repos.Transaction.DB(), "expense", owner.ID); err != nil {
		t.Fatalf("transaction read with db: %v", err)
	}

	assertTransactionList(t, repos.Transaction, TransactionFilter{UserID: owner.ID, Page: 1, PageSize: 20}, 4, 4)
	assertTransactionList(t, repos.Transaction, TransactionFilter{UserID: owner.ID, IncludeSystem: true, Page: 1, PageSize: 20}, 5, 5)
	assertTransactionList(t, repos.Transaction, TransactionFilter{UserID: owner.ID, StatisticsScope: true, Page: 1, PageSize: 20}, 3, 3)
	minAmount := money.Amount(900)
	maxAmount := money.Amount(1100)
	assertTransactionList(t, repos.Transaction, TransactionFilter{
		UserID: owner.ID, StartDate: &start, EndDate: &end, Type: "expense", AccountID: primary.ID,
		CategoryID: category.ID, MinAmount: &minAmount, MaxAmount: &maxAmount, Keyword: "groc", Page: 1, PageSize: 10,
	}, 1, 1)
	assertTransactionList(t, repos.Transaction, TransactionFilter{UserID: owner.ID, AccountID: secondary.ID, Page: 1, PageSize: 10}, 1, 1)

	categorySums, err := repos.Transaction.SumByCategory(owner.ID, start, end, "expense")
	if err != nil || len(categorySums) != 1 || categorySums[0].Total != 1000 || categorySums[0].Count != 1 {
		t.Fatalf("category sums = %#v, err=%v", categorySums, err)
	}
	reportSums, err := repos.Transaction.SumByCategoryForReport(owner.ID, start, end, "expense")
	if err != nil || len(reportSums) != 1 || reportSums[0].CategoryName != "Food" || reportSums[0].Total != 1000 {
		t.Fatalf("report category sums = %#v, err=%v", reportSums, err)
	}
	days, err := repos.Transaction.CountDistinctDays(owner.ID, start, end)
	if err != nil || days != 3 {
		t.Fatalf("distinct days = %d, err=%v; want 3", days, err)
	}
	maximum, err := repos.Transaction.MaxExpenseForReport(owner.ID, start, end)
	if err != nil || maximum.Amount != 1000 || maximum.CategoryName != "Food" {
		t.Fatalf("maximum expense = %#v, err=%v", maximum, err)
	}
	years, err := repos.Transaction.DistinctStatisticsYears(owner.ID)
	if err != nil || len(years) != 1 || years[0] != 2026 {
		t.Fatalf("statistics years = %#v, err=%v", years, err)
	}
	memberSums, err := repos.Transaction.SumExpenseByMember(owner.ID, start, end)
	if err != nil || len(memberSums) != 1 || memberSums[0].MemberID != member.ID || memberSums[0].Total != 1000 {
		t.Fatalf("member sums = %#v, err=%v", memberSums, err)
	}
	memberCategorySums, err := repos.Transaction.SumExpenseByMemberAndCategory(owner.ID, start, end)
	if err != nil || len(memberCategorySums) != 1 || memberCategorySums[0].CategoryID != category.ID || memberCategorySums[0].Total != 1000 {
		t.Fatalf("member category sums = %#v, err=%v", memberCategorySums, err)
	}
	balances, err := repos.Transaction.SumBalanceDeltaByAccount(owner.ID, start, end)
	if err != nil || len(balances) != 2 {
		t.Fatalf("balance deltas = %#v, err=%v", balances, err)
	}
	// Balance reconstruction includes every cash-flow event, including system
	// adjustments and lending repayments that analytics intentionally exclude.
	assertBalanceDelta(t, balances, primary.ID, -6976)
	assertBalanceDelta(t, balances, secondary.ID, 200)

	rangeSum, err := repos.Transaction.SumByDateRange(owner.ID, start, end)
	if err != nil || rangeSum.Income != 5000 || rangeSum.Expense != 1000 || rangeSum.Count != 3 {
		t.Fatalf("date range sum = %#v, err=%v", rangeSum, err)
	}
	daily, err := repos.Transaction.SumByDay(owner.ID, start, end)
	if err != nil || len(daily) != 3 {
		t.Fatalf("daily sums = %#v, err=%v", daily, err)
	}
	monthly, err := repos.Transaction.SumByMonth(owner.ID, start, end)
	if err != nil || len(monthly) != 1 || monthly[0].Income != 5000 || monthly[0].Expense != 1000 {
		t.Fatalf("monthly sums = %#v, err=%v", monthly, err)
	}
	yearly, err := repos.Transaction.SumByYear(owner.ID, start, end)
	if err != nil || len(yearly) != 1 || yearly[0].Income != 5000 || yearly[0].Expense != 1000 {
		t.Fatalf("yearly sums = %#v, err=%v", yearly, err)
	}

	exported, err := repos.Transaction.GetAllForExport(owner.ID, &start, &end)
	if err != nil || len(exported) != 5 {
		t.Fatalf("exported transactions = %#v, err=%v", exported, err)
	}
	loaded.Remark = "updated"
	if err := repos.Transaction.Update(loaded); err != nil {
		t.Fatalf("update transaction: %v", err)
	}
	if err := repos.Transaction.Delete("system"); err != nil {
		t.Fatalf("delete transaction: %v", err)
	}
	if err := repos.Transaction.DeleteBatch([]string{"lending", "transfer"}); err != nil {
		t.Fatalf("delete transaction batch: %v", err)
	}
	if err := repos.Transaction.DeleteAllByUserID(owner.ID); err != nil {
		t.Fatalf("delete owner transactions: %v", err)
	}
}

func assertTransactionList(t *testing.T, repository *TransactionRepository, filter TransactionFilter, wantLength, wantTotal int) {
	t.Helper()
	transactions, total, err := repository.List(filter)
	if err != nil || len(transactions) != wantLength || total != int64(wantTotal) {
		t.Fatalf("transaction list filter=%#v length=%d total=%d err=%v; want length=%d total=%d", filter, len(transactions), total, err, wantLength, wantTotal)
	}
}

func assertBalanceDelta(t *testing.T, balances []AccountBalanceDeltaSum, accountID string, want money.Amount) {
	t.Helper()
	for _, balance := range balances {
		if balance.AccountID == accountID {
			if balance.BalanceDelta != want {
				t.Fatalf("account %s balance delta = %v, want %v", accountID, balance.BalanceDelta, want)
			}
			return
		}
	}
	t.Fatalf("account %s missing from balance deltas %#v", accountID, balances)
}
