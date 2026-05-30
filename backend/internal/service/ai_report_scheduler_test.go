package service

import (
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

func TestAIReportSchedulerGeneratesPreviousWeekOncePerDay(t *testing.T) {
	requestCount := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestCount++
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"{\"summary\":\"automatic weekly report\"}"}}]}`))
	}))
	defer server.Close()

	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	user := &model.User{Username: "admin", PasswordHash: "hash"}
	if err := repos.User.Create(user); err != nil {
		t.Fatalf("create user: %v", err)
	}
	providerSvc := NewAIProviderService(repos.AIProvider, NewOpenAICompatibleClient(nil))
	reportSvc := NewAIReportService(repos.AIReport, repos.AIProvider, repos.Transaction, repos.Category, repos.FamilyMember, NewOpenAICompatibleClient(nil)).WithBudgetRepository(repos.Budget)
	seedAIReportFacts(t, providerSvc, user.ID, server.URL)

	scheduler := NewAIReportScheduler(reportSvc, repos.System, repos.User)
	scheduler.now = func() time.Time {
		return time.Date(2026, 5, 30, 8, 0, 0, 0, time.Local)
	}
	if err := scheduler.SaveSettings(&AIReportScheduleSettings{
		Enabled:        true,
		WeeklyEnabled:  true,
		MonthlyEnabled: false,
		Hour:           8,
	}); err != nil {
		t.Fatalf("save settings: %v", err)
	}

	results := scheduler.CheckAndGenerate()
	if len(results) != 1 {
		t.Fatalf("results len = %d, want 1", len(results))
	}
	result := results[0]
	if result.ReportType != "weekly" || result.PeriodStart != "2026-05-18" || result.PeriodEnd != "2026-05-24" {
		t.Fatalf("result period = %#v, want previous full week", result)
	}
	if result.Attempted != 1 || result.Succeeded != 1 || result.Failed != 0 || result.Skipped != 0 {
		t.Fatalf("result counts = %#v, want one success", result)
	}
	if requestCount != 1 {
		t.Fatalf("ai request count = %d, want 1", requestCount)
	}

	secondResults := scheduler.CheckAndGenerate()
	if len(secondResults) != 0 {
		t.Fatalf("second results len = %d, want 0", len(secondResults))
	}
	if requestCount != 1 {
		t.Fatalf("ai request count after second check = %d, want 1", requestCount)
	}

	reports, err := reportSvc.List(user.ID)
	if err != nil {
		t.Fatalf("list reports: %v", err)
	}
	if len(reports) != 1 {
		t.Fatalf("reports len = %d, want 1", len(reports))
	}
	if reports[0].PromptVersion != aiReportMaskedPromptVersion {
		t.Fatalf("prompt version = %q, want masked prompt version", reports[0].PromptVersion)
	}
	if strings.Contains(reports[0].SnapshotJSON, "成员A") {
		t.Fatalf("scheduled report leaked member name: %s", reports[0].SnapshotJSON)
	}
}

func TestAIReportSchedulerSkipsUsersWithoutEnabledProvider(t *testing.T) {
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	user := &model.User{Username: "admin", PasswordHash: "hash"}
	if err := repos.User.Create(user); err != nil {
		t.Fatalf("create user: %v", err)
	}
	reportSvc := NewAIReportService(repos.AIReport, repos.AIProvider, repos.Transaction, repos.Category, repos.FamilyMember, NewOpenAICompatibleClient(nil)).WithBudgetRepository(repos.Budget)
	scheduler := NewAIReportScheduler(reportSvc, repos.System, repos.User)
	scheduler.now = func() time.Time {
		return time.Date(2026, 5, 30, 8, 0, 0, 0, time.Local)
	}

	results := scheduler.generateDueReports(&AIReportScheduleSettings{
		Enabled:        true,
		WeeklyEnabled:  true,
		MonthlyEnabled: false,
		Hour:           8,
	}, scheduler.now(), true)
	if len(results) != 1 {
		t.Fatalf("results len = %d, want 1", len(results))
	}
	if results[0].Attempted != 1 || results[0].Skipped != 1 || results[0].Succeeded != 0 || results[0].Failed != 0 {
		t.Fatalf("result counts = %#v, want one skipped user", results[0])
	}
}
