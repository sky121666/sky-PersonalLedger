package service

import (
	"path/filepath"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

func TestAssetTrendUsesSharedAccountBalanceSemantics(t *testing.T) {
	statsSvc, _, repos, userID := newStatisticsTestService(t)
	for _, account := range []model.Account{
		{ID: uuid.NewString(), UserID: userID, Name: "Cash", Type: "cash", CurrentBalance: 100},
		{ID: uuid.NewString(), UserID: userID, Name: "Overdrawn", Type: "bank_card", CurrentBalance: -25},
		{ID: uuid.NewString(), UserID: userID, Name: "Credit", Type: "credit", CurrentBalance: 80},
		{ID: uuid.NewString(), UserID: userID, Name: "Credit balance", Type: "credit", CurrentBalance: -10},
		{ID: uuid.NewString(), UserID: userID, Name: "Payable", Type: "payable", CurrentBalance: 20},
		{ID: uuid.NewString(), UserID: userID, Name: "Receivable", Type: "receivable", CurrentBalance: 30},
		{ID: uuid.NewString(), UserID: userID, Name: "Archived", Type: "cash", CurrentBalance: 999, IsArchived: true},
	} {
		account := account
		if err := repos.Account.Create(&account); err != nil {
			t.Fatalf("create %s account: %v", account.Name, err)
		}
	}

	trend, err := statsSvc.GetAssetTrend(userID, 1)
	if err != nil {
		t.Fatalf("get asset trend: %v", err)
	}
	assertFloatEqual(t, "trend current assets", trend.CurrentAssets, 1139)
	assertFloatEqual(t, "trend current debts", trend.CurrentDebts, 125)
	assertFloatEqual(t, "trend current net worth", trend.CurrentNetWorth, 1014)
}

func TestAssetTrendUsesHistoricalAccountLogSnapshotsAndCarriesEmptyMonths(t *testing.T) {
	statsSvc, txSvc, repos, userID := newStatisticsTestService(t)
	accountID := createAccountForTest(t, repos, userID, 1000)
	now := time.Now().In(time.Local)
	currentMonthStart := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.Local)
	oldestMonthStart := currentMonthStart.AddDate(0, -2, 0)
	currentMonthEnd := currentMonthStart.AddDate(0, 1, 0).Add(-500 * time.Millisecond)
	if err := repos.Account.DB().Model(&model.Account{}).Where("id = ?", accountID).Updates(map[string]any{
		"initial_balance": 1000,
		"created_at":      oldestMonthStart.AddDate(0, -1, 0),
	}).Error; err != nil {
		t.Fatalf("set account history baseline: %v", err)
	}

	createStatisticsTransaction(t, txSvc, userID, accountID, "income", 200, oldestMonthStart.AddDate(0, 0, 10).Format("2006-01-02T15:04:05"))
	createStatisticsTransaction(t, txSvc, userID, accountID, "expense", 100, currentMonthEnd.Format("2006-01-02T15:04:05.999999999"))
	if err := repos.Account.DB().Create(&model.AccountLog{
		ID: uuid.NewString(), UserID: userID, AccountID: accountID, Type: "income", Amount: 200,
		BalanceBefore: 1000, BalanceAfter: 1200, CreatedAt: oldestMonthStart.AddDate(0, 0, 10),
	}).Error; err != nil {
		t.Fatalf("seed historical account log: %v", err)
	}

	trend, err := statsSvc.GetAssetTrend(userID, 3)
	if err != nil {
		t.Fatalf("get three-month asset trend: %v", err)
	}
	if len(trend.Items) != 3 {
		t.Fatalf("trend items = %d, want 3", len(trend.Items))
	}
	oldest, gap, current := trend.Items[0], trend.Items[1], trend.Items[2]
	assertFloatEqual(t, "current month net worth", current.NetWorth, 1100)
	assertFloatEqual(t, "month before current net worth", gap.NetWorth, 1200)
	assertFloatEqual(t, "empty month carries net worth", oldest.NetWorth, 1200)
	assertFloatEqual(t, "fractional month-end expense", current.MonthExpense, 100)
	assertFloatEqual(t, "oldest month income", oldest.MonthIncome, 200)
}

func newStatisticsTestService(t *testing.T) (*StatisticsService, *TransactionService, *repository.Repositories, uint) {
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
	return NewStatisticsService(repos.Transaction, repos.Category, repos.Account, repos.AccountLog),
		NewTransactionService(repos.Transaction, repos.Account, repos.Reminder, repos.Lending, repos.FamilyMember, accountLogSvc),
		repos,
		user.ID
}

func TestStatisticsOverviewByYearAndHistoryPeriod(t *testing.T) {
	statsSvc, txSvc, repos, userID := newStatisticsTestService(t)
	accountID := createAccountForTest(t, repos, userID, 10000)

	createStatisticsTransaction(t, txSvc, userID, accountID, "income", 1200, "2026-01-08")
	createStatisticsTransaction(t, txSvc, userID, accountID, "expense", 200, "2026-06-10")
	createStatisticsTransaction(t, txSvc, userID, accountID, "expense", 90, "2025-12-25")

	yearOverview, err := statsSvc.GetOverviewByPeriod(userID, "2026-06", "year")
	if err != nil {
		t.Fatalf("year overview: %v", err)
	}
	assertFloatEqual(t, "year income", yearOverview.Income, 1200)
	assertFloatEqual(t, "year expense", yearOverview.Expense, 200)
	assertFloatEqual(t, "year balance", yearOverview.Balance, 1000)
	if yearOverview.TransactionCount != 2 {
		t.Fatalf("year transaction count = %d, want 2", yearOverview.TransactionCount)
	}

	historyOverview, err := statsSvc.GetOverviewByPeriod(userID, "2026-06", "history")
	if err != nil {
		t.Fatalf("history overview: %v", err)
	}
	assertFloatEqual(t, "history expense", historyOverview.Expense, 90)
	if historyOverview.TransactionCount != 1 {
		t.Fatalf("history transaction count = %d, want 1", historyOverview.TransactionCount)
	}
}

func TestStatisticsTrendUsesPeriodGranularity(t *testing.T) {
	statsSvc, txSvc, repos, userID := newStatisticsTestService(t)
	accountID := createAccountForTest(t, repos, userID, 10000)

	createStatisticsTransaction(t, txSvc, userID, accountID, "income", 1200, "2026-01-08")
	createStatisticsTransaction(t, txSvc, userID, accountID, "expense", 200, "2026-06-10")
	createStatisticsTransaction(t, txSvc, userID, accountID, "expense", 90, "2025-12-25")

	yearTrend, err := statsSvc.GetTrendByPeriod(userID, "2026-06", "year")
	if err != nil {
		t.Fatalf("year trend: %v", err)
	}
	if len(yearTrend.Items) != 2 {
		t.Fatalf("year trend items = %#v, want two monthly buckets", yearTrend.Items)
	}
	if yearTrend.Items[0].Date != "2026-01" || yearTrend.Items[1].Date != "2026-06" {
		t.Fatalf("year trend dates = %#v, want monthly buckets", yearTrend.Items)
	}

	historyTrend, err := statsSvc.GetTrendByPeriod(userID, "2026-06", "history")
	if err != nil {
		t.Fatalf("history trend: %v", err)
	}
	if len(historyTrend.Items) != 1 || historyTrend.Items[0].Date != "2025" {
		t.Fatalf("history trend items = %#v, want yearly bucket", historyTrend.Items)
	}
}

func createStatisticsTransaction(t *testing.T, svc *TransactionService, userID uint, accountID string, txType string, amount float64, date string) {
	t.Helper()
	if _, err := svc.Create(userID, CreateTransactionRequest{
		Type:            txType,
		Amount:          amount,
		AccountID:       accountID,
		TransactionDate: date,
	}); err != nil {
		t.Fatalf("create %s transaction on %s: %v", txType, date, err)
	}
}
