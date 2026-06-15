package service

import (
	"path/filepath"
	"testing"

	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

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
	return NewStatisticsService(repos.Transaction, repos.Category, repos.Account),
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
