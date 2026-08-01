package service

import (
	"fmt"
	"path/filepath"
	"testing"
	"time"

	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

func TestExportDateRangeUsesEntireLocalCalendarDay(t *testing.T) {
	previousLocal := time.Local
	local := time.FixedZone("UTC+08", 8*60*60)
	time.Local = local
	t.Cleanup(func() { time.Local = previousLocal })

	start, end, err := exportDateRange("2026-05-01", "2026-05-31")
	if err != nil {
		t.Fatalf("parse export range: %v", err)
	}
	wantStart := time.Date(2026, time.May, 1, 0, 0, 0, 0, local)
	wantEnd := time.Date(2026, time.June, 1, 0, 0, 0, 0, local).Add(-time.Nanosecond)
	if start == nil || !start.Equal(wantStart) || start.Location() != local {
		t.Fatalf("start = %v, want %v in local timezone", start, wantStart)
	}
	if end == nil || !end.Equal(wantEnd) || end.Location() != local {
		t.Fatalf("end = %v, want %v in local timezone", end, wantEnd)
	}
}

func TestExportTransactionsCSVRejectsInvalidDate(t *testing.T) {
	service, _, _ := newExportTestService(t)
	if _, err := service.ExportTransactionsCSV(1, ExportFilter{StartDate: "not-a-date"}); err == nil {
		t.Fatal("expected invalid export start date to fail")
	}
	if _, err := service.ExportTransactionsCSV(1, ExportFilter{EndDate: "2026-02-30"}); err == nil {
		t.Fatal("expected invalid export end date to fail")
	}
}

func TestListTransactionsForExportLoadsEveryPage(t *testing.T) {
	service, repos, userID := newExportTestService(t)
	accountID := createAccountForTest(t, repos, userID, 100)
	for index := 0; index < 3; index++ {
		transaction := &model.Transaction{
			ID:              fmt.Sprintf("paged-export-%d", index),
			UserID:          userID,
			AccountID:       accountID,
			Type:            "expense",
			Amount:          float64(index + 1),
			TransactionDate: time.Date(2026, time.May, index+1, 12, 0, 0, 0, time.Local),
			Source:          "manual",
		}
		if err := repos.Transaction.Create(transaction); err != nil {
			t.Fatalf("create transaction %d: %v", index, err)
		}
	}

	transactions, err := service.listTransactionsForExport(
		userID,
		ExportFilter{},
		nil,
		nil,
		2,
	)
	if err != nil {
		t.Fatalf("list paged export transactions: %v", err)
	}
	if len(transactions) != 3 {
		t.Fatalf("export transaction count = %d, want 3", len(transactions))
	}
}

func TestYearlyReportIncludesSubsecondAtEndOfYearOnly(t *testing.T) {
	previousLocal := time.Local
	local := time.FixedZone("UTC+08", 8*60*60)
	time.Local = local
	t.Cleanup(func() { time.Local = previousLocal })

	service, repos, userID := newExportTestService(t)
	accountID := createAccountForTest(t, repos, userID, 100)
	for _, transaction := range []*model.Transaction{
		{
			ID:              "year-end-subsecond",
			UserID:          userID,
			AccountID:       accountID,
			Type:            "expense",
			Amount:          10,
			TransactionDate: time.Date(2026, time.December, 31, 23, 59, 59, 500_000_000, local),
			Source:          "manual",
		},
		{
			ID:              "next-year-start",
			UserID:          userID,
			AccountID:       accountID,
			Type:            "expense",
			Amount:          20,
			TransactionDate: time.Date(2027, time.January, 1, 0, 0, 0, 0, local),
			Source:          "manual",
		},
	} {
		if err := repos.Transaction.Create(transaction); err != nil {
			t.Fatalf("create transaction %s: %v", transaction.ID, err)
		}
	}

	report, err := service.GetYearlyReport(userID, 2026)
	if err != nil {
		t.Fatalf("get yearly report: %v", err)
	}
	if report.TransactionCount != 1 || report.TotalExpense != 10 {
		t.Fatalf("yearly report count=%d expense=%.2f, want 1 and 10.00", report.TransactionCount, report.TotalExpense)
	}
}

func TestYearlyReportKeepsSoftDeletedCategoryMetadataInAggregates(t *testing.T) {
	service, repos, userID := newExportTestService(t)
	accountID := createAccountForTest(t, repos, userID, 100)
	category := &model.Category{
		ID: "yearly-soft-deleted-category", UserID: userID, Name: "历史餐饮", Type: "expense", Icon: "utensils",
	}
	if err := repos.Category.Create(category); err != nil {
		t.Fatalf("create category: %v", err)
	}
	for index, amount := range []float64{10, 30} {
		categoryID := category.ID
		if err := repos.Transaction.Create(&model.Transaction{
			ID: fmt.Sprintf("yearly-category-%d", index), UserID: userID, AccountID: accountID,
			CategoryID: &categoryID, Type: "expense", Amount: amount,
			TransactionDate: time.Date(2026, time.March, 12, 12+index, 0, 0, 0, time.Local),
			Source:          "manual", Remark: "午餐",
		}); err != nil {
			t.Fatalf("create transaction: %v", err)
		}
	}
	if err := repos.Category.Delete(category.ID); err != nil {
		t.Fatalf("soft delete category: %v", err)
	}

	report, err := service.GetYearlyReport(userID, 2026)
	if err != nil {
		t.Fatalf("get yearly report: %v", err)
	}
	if report.TransactionCount != 2 || report.ActiveDays != 1 || report.TotalExpense != 40 {
		t.Fatalf("report aggregates = count:%d days:%d expense:%.2f", report.TransactionCount, report.ActiveDays, report.TotalExpense)
	}
	if len(report.TopExpenses) != 1 || report.TopExpenses[0].CategoryName != "历史餐饮" || report.TopExpenses[0].Count != 2 {
		t.Fatalf("top expenses = %#v", report.TopExpenses)
	}
	if report.MaxSingleExpense != 30 || report.MaxExpenseRemark != "历史餐饮: 午餐" {
		t.Fatalf("max expense = %.2f %q", report.MaxSingleExpense, report.MaxExpenseRemark)
	}
}

func TestAvailableYearsUsesDistinctStatisticsScope(t *testing.T) {
	service, repos, userID := newExportTestService(t)
	accountID := createAccountForTest(t, repos, userID, 100)
	lendingID := "excluded-lending"
	transactions := []*model.Transaction{
		{ID: "year-2024", UserID: userID, AccountID: accountID, Type: "expense", Amount: 1, TransactionDate: time.Date(2024, 1, 1, 0, 0, 0, 0, time.Local), Source: "manual"},
		{ID: "year-2026", UserID: userID, AccountID: accountID, Type: "income", Amount: 1, TransactionDate: time.Date(2026, 1, 1, 0, 0, 0, 0, time.Local), Source: "manual"},
		{ID: "year-system-2027", UserID: userID, AccountID: accountID, Type: "income", Amount: 1, TransactionDate: time.Date(2027, 1, 1, 0, 0, 0, 0, time.Local), Source: "system"},
		{ID: "year-lending-2025", UserID: userID, AccountID: accountID, Type: "expense", Amount: 1, TransactionDate: time.Date(2025, 1, 1, 0, 0, 0, 0, time.Local), Source: "lending", LendingID: &lendingID},
	}
	for _, transaction := range transactions {
		if err := repos.Transaction.Create(transaction); err != nil {
			t.Fatalf("create transaction %s: %v", transaction.ID, err)
		}
	}

	years, err := service.GetAvailableYears(userID)
	if err != nil {
		t.Fatalf("get available years: %v", err)
	}
	if fmt.Sprint(years) != "[2026 2024]" {
		t.Fatalf("years = %#v, want [2026 2024]", years)
	}
}

func TestYearlyReportAggregatesMoreThanLegacyHundredThousandLimit(t *testing.T) {
	service, repos, userID := newExportTestService(t)
	accountID := createAccountForTest(t, repos, userID, 100)
	if err := repos.Transaction.DB().Exec(`
		WITH digits(d) AS (
			VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)
		), numbers(n) AS (
			SELECT a.d + b.d*10 + c.d*100 + d.d*1000 + e.d*10000 + f.d*100000
			FROM digits a CROSS JOIN digits b CROSS JOIN digits c
			CROSS JOIN digits d CROSS JOIN digits e CROSS JOIN digits f
		)
		INSERT INTO transactions (
			id, user_id, account_id, type, amount, transaction_date, source, created_at, updated_at
		)
		SELECT printf('bulk-%06d', n), ?, ?, 'expense', 1, '2026-06-15 12:00:00', 'manual', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
		FROM numbers
		WHERE n BETWEEN 1 AND 100001
	`, userID, accountID).Error; err != nil {
		t.Fatalf("seed large yearly dataset: %v", err)
	}

	report, err := service.GetYearlyReport(userID, 2026)
	if err != nil {
		t.Fatalf("get large yearly report: %v", err)
	}
	if report.TransactionCount != 100001 || report.TotalExpense != 100001 {
		t.Fatalf("large report count=%d expense=%.2f, want 100001", report.TransactionCount, report.TotalExpense)
	}
}

func newExportTestService(t *testing.T) (*ExportService, *repository.Repositories, uint) {
	t.Helper()
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	user := &model.User{Username: "export-user", PasswordHash: "hash"}
	if err := repos.User.Create(user); err != nil {
		t.Fatalf("create user: %v", err)
	}
	return NewExportService(repos.Transaction, repos.Category, repos.Account), repos, user.ID
}
