package service

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/money"
	"gorm.io/gorm"
)

func newCountingAIReportServer(t *testing.T) (*httptest.Server, *atomic.Int32) {
	t.Helper()
	count := &atomic.Int32{}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		count.Add(1)
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"{\"summary\":\"report fixture\"}"}}]}`))
	}))
	t.Cleanup(server.Close)
	return server, count
}

func TestAIReportRegeneratesChangedFactsAndPreservesHistory(t *testing.T) {
	server, count := newCountingAIReportServer(t)
	svc, providers, userID := newAIReportTestServices(t)
	seedAIReportFacts(t, providers, userID, server.URL)
	req := GenerateAIReportRequest{ReportType: "weekly", PeriodStart: "2026-05-18", PeriodEnd: "2026-05-24"}
	first, err := svc.Generate(userID, req)
	if err != nil {
		t.Fatal(err)
	}
	db := providers.repo.DB()
	if err := db.Model(&model.Transaction{}).Where("user_id = ? AND type = ?", userID, "expense").Update("amount_cents", 50000).Error; err != nil {
		t.Fatal(err)
	}
	second, err := svc.Generate(userID, req)
	if err != nil {
		t.Fatal(err)
	}
	var snapshot aiReportSnapshot
	if err := json.Unmarshal([]byte(second.SnapshotJSON), &snapshot); err != nil {
		t.Fatal(err)
	}
	if snapshot.ExpenseTotal.Cents() != 50000 || first.ID == second.ID || count.Load() != 2 {
		t.Fatalf("edited facts were not regenerated: expense=%v same_report=%v calls=%d", snapshot.ExpenseTotal, first.ID == second.ID, count.Load())
	}
	third, err := svc.Generate(userID, req)
	if err != nil {
		t.Fatal(err)
	}
	if third.ID != second.ID || count.Load() != 2 {
		t.Fatal("unchanged facts must reuse the latest report")
	}
	old, err := svc.Get(first.ID, userID)
	if err != nil {
		t.Fatal(err)
	}
	if old.SnapshotJSON != first.SnapshotJSON {
		t.Fatal("regeneration changed historical report")
	}
	if err := db.Model(&model.Budget{}).Where("user_id = ? AND category_id IS NULL AND member_id IS NULL", userID).Update("amount_cents", 80000).Error; err != nil {
		t.Fatal(err)
	}
	fourth, err := svc.Generate(userID, req)
	if err != nil {
		t.Fatal(err)
	}
	if fourth.ID == third.ID || count.Load() != 3 {
		t.Fatal("changed budget must invalidate report reuse")
	}
}

func TestAIReportRegeneratesAfterProviderConfigurationChange(t *testing.T) {
	server, count := newCountingAIReportServer(t)
	svc, providers, userID := newAIReportTestServices(t)
	seedAIReportFacts(t, providers, userID, server.URL)
	req := GenerateAIReportRequest{ReportType: "weekly", PeriodStart: "2026-05-18", PeriodEnd: "2026-05-24"}
	first, err := svc.Generate(userID, req)
	if err != nil {
		t.Fatal(err)
	}
	if err := providers.repo.DB().Model(&model.AIProvider{}).Where("id = ?", first.ProviderID).
		Updates(map[string]any{"name": "Changed provider", "updated_at": first.CreatedAt.Add(time.Second)}).Error; err != nil {
		t.Fatal(err)
	}
	second, err := svc.Generate(userID, req)
	if err != nil {
		t.Fatal(err)
	}
	if second.ID == first.ID || second.ProviderName != "Changed provider" || count.Load() != 2 {
		t.Fatal("provider changes must not silently reuse the old provider report")
	}
}

func TestAIReportCacheReadFailureDoesNotCallProvider(t *testing.T) {
	server, count := newCountingAIReportServer(t)
	svc, providers, userID := newAIReportTestServices(t)
	seedAIReportFacts(t, providers, userID, server.URL)
	failure := errors.New("report storage unavailable")
	if err := providers.repo.DB().Callback().Query().Before("gorm:query").Register("test:failed_report_lookup", func(db *gorm.DB) {
		if db.Statement.Table == "ai_reports" {
			db.AddError(failure)
		}
	}); err != nil {
		t.Fatal(err)
	}
	_, err := svc.Generate(userID, GenerateAIReportRequest{ReportType: "weekly", PeriodStart: "2026-05-18", PeriodEnd: "2026-05-24"})
	if !errors.Is(err, failure) || count.Load() != 0 {
		t.Fatalf("lookup failure=%v calls=%d", err, count.Load())
	}
}

func addAIExpenseFixture(t *testing.T, db *gorm.DB, userID uint, amount money.Amount, date time.Time) {
	t.Helper()
	var expense model.Transaction
	if err := db.Where("user_id = ? AND type = ?", userID, "expense").First(&expense).Error; err != nil {
		t.Fatal(err)
	}
	expense.ID = uuid.NewString()
	expense.Amount = amount
	expense.TransactionDate = date
	if err := db.Create(&expense).Error; err != nil {
		t.Fatal(err)
	}
}

func readAIReportSnapshot(t *testing.T, svc *AIReportService, userID uint, startText, endText string) aiReportSnapshot {
	t.Helper()
	start, end, err := parseAIReportPeriod(startText, endText)
	if err != nil {
		t.Fatal(err)
	}
	raw, err := svc.buildSnapshotJSON(userID, start, end, true)
	if err != nil {
		t.Fatal(err)
	}
	var snapshot aiReportSnapshot
	if err := json.Unmarshal([]byte(raw), &snapshot); err != nil {
		t.Fatal(err)
	}
	return snapshot
}

func TestAIWeeklyBudgetIncludesPriorWeeksAndExcludesLaterDays(t *testing.T) {
	svc, providers, userID := newAIReportTestServices(t)
	seedAIReportFacts(t, providers, userID, "https://example.com")
	db := providers.repo.DB()
	addAIExpenseFixture(t, db, userID, 1000, time.Date(2026, 5, 5, 12, 0, 0, 0, time.Local))
	addAIExpenseFixture(t, db, userID, 9000, time.Date(2026, 5, 30, 12, 0, 0, 0, time.Local))
	snapshot := readAIReportSnapshot(t, svc, userID, "2026-05-18", "2026-05-24")
	if snapshot.ExpenseTotal.Cents() != 12000 {
		t.Fatalf("weekly expense=%v", snapshot.ExpenseTotal)
	}
	budget := snapshot.Budget
	if budget.Spent.Cents() != 112000 || budget.Remaining == nil || budget.Remaining.Cents() != -82000 || budget.UsedPercent == nil || *budget.UsedPercent != 373 {
		t.Fatalf("monthly budget must include prior weeks only through cutoff: %+v", budget)
	}
	if budget.PeriodStart != "2026-05-01" || budget.PeriodEnd != "2026-05-24" || budget.SettingsBasis != "current_budget_settings" {
		t.Fatalf("budget period=%+v", budget)
	}
	if len(budget.OverBudgetCategories) != 1 || budget.OverBudgetCategories[0].Spent.Cents() != 112000 || budget.MemberBudgets[0].Spent.Cents() != 112000 {
		t.Fatalf("category/member budgets must use the same month scope: %+v", budget)
	}
}

func TestAIReportCrossMonthBudgetUsesExplicitEndingMonth(t *testing.T) {
	svc, providers, userID := newAIReportTestServices(t)
	seedAIReportFacts(t, providers, userID, "https://example.com")
	addAIExpenseFixture(t, providers.repo.DB(), userID, 1000, time.Date(2026, 4, 30, 12, 0, 0, 0, time.Local))
	snapshot := readAIReportSnapshot(t, svc, userID, "2026-04-27", "2026-05-03")
	if snapshot.ExpenseTotal.Cents() != 100000 || snapshot.Budget.Spent.Cents() != 0 || snapshot.Budget.Remaining.Cents() != 30000 || snapshot.Budget.PeriodStart != "2026-05-01" {
		t.Fatalf("cross-month report mixed months: %+v", snapshot)
	}
}

func TestAIReportWithoutBudgetStillIncludesMonthlySpending(t *testing.T) {
	for _, repositoryAvailable := range []bool{true, false} {
		name := "no_budget_settings"
		if !repositoryAvailable {
			name = "no_budget_repository"
		}
		t.Run(name, func(t *testing.T) {
			svc, providers, userID := newAIReportTestServices(t)
			seedAIReportFacts(t, providers, userID, "https://example.com")
			db := providers.repo.DB()
			if err := db.Where("user_id = ?", userID).Delete(&model.Budget{}).Error; err != nil {
				t.Fatal(err)
			}
			if !repositoryAvailable {
				svc.budgets = nil
			}
			addAIExpenseFixture(t, db, userID, 1000, time.Date(2026, 5, 5, 12, 0, 0, 0, time.Local))
			snapshot := readAIReportSnapshot(t, svc, userID, "2026-05-18", "2026-05-24")
			if snapshot.ExpenseTotal.Cents() != 12000 || snapshot.Budget.Spent.Cents() != 112000 {
				t.Fatalf("missing allowance hid real monthly spending: %+v", snapshot)
			}
			if snapshot.Budget.MonthlyBudget != nil || snapshot.Budget.Remaining != nil || snapshot.Budget.UsedPercent != nil {
				t.Fatalf("missing allowance must remain unknown: %+v", snapshot.Budget)
			}
		})
	}
}

func TestAIReportUsesSameMaskedMemberAcrossSpendingAndBudgets(t *testing.T) {
	svc, providers, userID := newAIReportTestServices(t)
	seedAIReportFacts(t, providers, userID, "https://example.com")
	db := providers.repo.DB()
	var member model.FamilyMember
	var category model.Category
	if err := db.Where("user_id = ?", userID).First(&member).Error; err != nil {
		t.Fatal(err)
	}
	if err := db.Where("user_id = ?", userID).First(&category).Error; err != nil {
		t.Fatal(err)
	}
	if err := db.Create(&model.Budget{ID: uuid.NewString(), UserID: userID, MemberID: &member.ID, CategoryID: &category.ID, Amount: 50, IsActive: true}).Error; err != nil {
		t.Fatal(err)
	}
	if err := db.Model(&model.Budget{}).Where("user_id = ? AND member_id IS NULL AND category_id IS NULL", userID).Update("is_active", false).Error; err != nil {
		t.Fatal(err)
	}
	snapshot := readAIReportSnapshot(t, svc, userID, "2026-05-18", "2026-05-24")
	if len(snapshot.Budget.MemberBudgets) != 2 {
		t.Fatal("member budget fixtures missing")
	}
	for _, budget := range snapshot.Budget.MemberBudgets {
		if budget.MemberName != snapshot.FamilyMembers[0].DisplayName || budget.MemberName == member.Name {
			t.Fatalf("one member was assigned different masked identities: %+v", snapshot)
		}
	}
	if snapshot.Budget.MonthlyBudget != nil || snapshot.Budget.UsedPercent != nil {
		t.Fatal("inactive total budget must not imply an active allowance")
	}
}
