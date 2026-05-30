package service

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

func TestAIReportGenerateStoresAggregatedSnapshotAndContent(t *testing.T) {
	var requestPayload map[string]any
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := json.NewDecoder(r.Body).Decode(&requestPayload); err != nil {
			t.Fatalf("decode ai request: %v", err)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"{\"title\":\"本周财务总结\",\"summary\":\"支出可控\",\"highlights\":[\"净现金流为正\"],\"risks\":[],\"suggestions\":[\"继续记录\"]}"}}]}`))
	}))
	defer server.Close()

	svc, providerSvc, userID := newAIReportTestServices(t)
	seedAIReportFacts(t, providerSvc, userID, server.URL)

	report, err := svc.Generate(userID, GenerateAIReportRequest{
		ReportType:  "weekly",
		ProviderID:  "",
		PeriodStart: "2026-05-18",
		PeriodEnd:   "2026-05-24",
	})
	if err != nil {
		t.Fatalf("generate report: %v", err)
	}
	if report.Status != "completed" {
		t.Fatalf("status = %q, want completed", report.Status)
	}
	if report.ProviderName != "Fake AI" || report.Model != "deepseek-chat" {
		t.Fatalf("provider/model = %q/%q", report.ProviderName, report.Model)
	}
	if !strings.Contains(report.ContentJSON, "本周财务总结") {
		t.Fatalf("content json missing ai output: %s", report.ContentJSON)
	}
	if strings.Contains(report.SnapshotJSON, "secret dinner remark") {
		t.Fatalf("snapshot leaked raw transaction remark: %s", report.SnapshotJSON)
	}

	var snapshot map[string]any
	if err := json.Unmarshal([]byte(report.SnapshotJSON), &snapshot); err != nil {
		t.Fatalf("decode snapshot: %v", err)
	}
	if snapshot["expense_total"].(float64) != 120 {
		t.Fatalf("expense_total = %v, want 120", snapshot["expense_total"])
	}
	if snapshot["income_total"].(float64) != 500 {
		t.Fatalf("income_total = %v, want 500", snapshot["income_total"])
	}
	budget := snapshot["budget"].(map[string]any)
	if budget["monthly_budget"].(float64) != 300 {
		t.Fatalf("monthly_budget = %v, want 300", budget["monthly_budget"])
	}
	if budget["used_percent"].(float64) != 40 {
		t.Fatalf("used_percent = %v, want 40", budget["used_percent"])
	}
	overBudgetCategories := budget["over_budget_categories"].([]any)
	if len(overBudgetCategories) != 1 {
		t.Fatalf("over_budget_categories len = %d, want 1", len(overBudgetCategories))
	}
	memberBudgets := budget["member_budgets"].([]any)
	if len(memberBudgets) != 1 {
		t.Fatalf("member_budgets len = %d, want 1", len(memberBudgets))
	}
	accountChanges := snapshot["account_changes"].([]any)
	if len(accountChanges) != 1 {
		t.Fatalf("account_changes len = %d, want 1", len(accountChanges))
	}
	accountChange := accountChanges[0].(map[string]any)
	if accountChange["account_name"] != "账户1" {
		t.Fatalf("account_name = %v, want masked account label", accountChange["account_name"])
	}
	if accountChange["balance_delta"].(float64) != 380 {
		t.Fatalf("balance_delta = %v, want 380", accountChange["balance_delta"])
	}

	messages := requestPayload["messages"].([]any)
	userMessage := messages[1].(map[string]any)["content"].(string)
	if strings.Contains(userMessage, "secret dinner remark") {
		t.Fatalf("ai request leaked raw transaction remark: %s", userMessage)
	}
}

func TestAIReportGenerateReusesCompletedReportForSameScope(t *testing.T) {
	requestCount := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestCount++
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"{\"summary\":\"cached weekly report\"}"}}]}`))
	}))
	defer server.Close()

	svc, providerSvc, userID := newAIReportTestServices(t)
	seedAIReportFacts(t, providerSvc, userID, server.URL)
	req := GenerateAIReportRequest{
		ReportType:  "weekly",
		PeriodStart: "2026-05-18",
		PeriodEnd:   "2026-05-24",
	}

	first, err := svc.Generate(userID, req)
	if err != nil {
		t.Fatalf("first generate report: %v", err)
	}
	second, err := svc.Generate(userID, req)
	if err != nil {
		t.Fatalf("second generate report: %v", err)
	}
	if second.ID != first.ID {
		t.Fatalf("second report id = %s, want cached report %s", second.ID, first.ID)
	}
	if requestCount != 1 {
		t.Fatalf("ai request count = %d, want 1", requestCount)
	}
}

func TestAIReportGenerateSerializesConcurrentSameScopeRequests(t *testing.T) {
	requestCount := 0
	var requestMu sync.Mutex
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestMu.Lock()
		requestCount++
		requestMu.Unlock()
		time.Sleep(50 * time.Millisecond)
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"{\"summary\":\"single concurrent report\"}"}}]}`))
	}))
	defer server.Close()

	svc, providerSvc, userID := newAIReportTestServices(t)
	seedAIReportFacts(t, providerSvc, userID, server.URL)
	req := GenerateAIReportRequest{
		ReportType:  "weekly",
		PeriodStart: "2026-05-18",
		PeriodEnd:   "2026-05-24",
	}

	const attempts = 6
	reports := make(chan *AIReportResponse, attempts)
	errs := make(chan error, attempts)
	var wg sync.WaitGroup
	for i := 0; i < attempts; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			report, err := svc.Generate(userID, req)
			if err != nil {
				errs <- err
				return
			}
			reports <- report
		}()
	}
	wg.Wait()
	close(reports)
	close(errs)

	for err := range errs {
		t.Fatalf("concurrent generate returned error: %v", err)
	}
	var firstID string
	count := 0
	for report := range reports {
		count++
		if firstID == "" {
			firstID = report.ID
		}
		if report.ID != firstID {
			t.Fatalf("report id = %s, want shared cached report %s", report.ID, firstID)
		}
	}
	if count != attempts {
		t.Fatalf("reports = %d, want %d", count, attempts)
	}
	requestMu.Lock()
	gotRequests := requestCount
	requestMu.Unlock()
	if gotRequests != 1 {
		t.Fatalf("ai request count = %d, want 1", gotRequests)
	}
}

func TestAIReportGenerateMasksNamesAndUsesSeparateCache(t *testing.T) {
	requestCount := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestCount++
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"{\"summary\":\"masked report\"}"}}]}`))
	}))
	defer server.Close()

	svc, providerSvc, userID := newAIReportTestServices(t)
	seedAIReportFacts(t, providerSvc, userID, server.URL)
	req := GenerateAIReportRequest{
		ReportType:  "weekly",
		PeriodStart: "2026-05-18",
		PeriodEnd:   "2026-05-24",
		MaskNames:   boolPtr(false),
	}

	unmasked, err := svc.Generate(userID, req)
	if err != nil {
		t.Fatalf("generate unmasked report: %v", err)
	}
	masked, err := svc.Generate(userID, GenerateAIReportRequest{
		ReportType:  "weekly",
		PeriodStart: "2026-05-18",
		PeriodEnd:   "2026-05-24",
		MaskNames:   boolPtr(true),
	})
	if err != nil {
		t.Fatalf("generate masked report: %v", err)
	}
	if masked.ID == unmasked.ID {
		t.Fatal("masked report reused unmasked cache entry")
	}
	if strings.Contains(masked.SnapshotJSON, "成员A") {
		t.Fatalf("masked snapshot leaked member name: %s", masked.SnapshotJSON)
	}
	if !strings.Contains(masked.SnapshotJSON, "成员1") {
		t.Fatalf("masked snapshot missing anonymized member label: %s", masked.SnapshotJSON)
	}
	if strings.Contains(masked.SnapshotJSON, "现金") {
		t.Fatalf("masked snapshot leaked account name: %s", masked.SnapshotJSON)
	}
	if !strings.Contains(masked.SnapshotJSON, "账户1") {
		t.Fatalf("masked snapshot missing anonymized account label: %s", masked.SnapshotJSON)
	}
	if requestCount != 2 {
		t.Fatalf("ai request count = %d, want separate unmasked and masked requests", requestCount)
	}
}

func TestAIReportGenerateMasksNamesByDefault(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"{\"summary\":\"default masked report\"}"}}]}`))
	}))
	defer server.Close()

	svc, providerSvc, userID := newAIReportTestServices(t)
	seedAIReportFacts(t, providerSvc, userID, server.URL)
	report, err := svc.Generate(userID, GenerateAIReportRequest{
		ReportType:  "weekly",
		PeriodStart: "2026-05-18",
		PeriodEnd:   "2026-05-24",
	})
	if err != nil {
		t.Fatalf("generate default report: %v", err)
	}
	if report.PromptVersion != aiReportMaskedPromptVersion {
		t.Fatalf("prompt version = %q, want masked prompt version", report.PromptVersion)
	}
	if strings.Contains(report.SnapshotJSON, "成员A") {
		t.Fatalf("default snapshot leaked member name: %s", report.SnapshotJSON)
	}
}

func TestAIReportGenerateAggregatesTransferAccountChanges(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"{\"summary\":\"transfer report\"}"}}]}`))
	}))
	defer server.Close()

	svc, providerSvc, userID := newAIReportTestServices(t)
	db := providerSvc.repo.DB()
	source := model.Account{
		ID:             uuid.NewString(),
		UserID:         userID,
		Name:           "现金",
		Type:           "cash",
		CurrentBalance: 1000,
	}
	target := model.Account{
		ID:             uuid.NewString(),
		UserID:         userID,
		Name:           "储蓄卡",
		Type:           "bank",
		CurrentBalance: 2000,
	}
	if err := db.Create(&[]model.Account{source, target}).Error; err != nil {
		t.Fatalf("create accounts: %v", err)
	}
	if err := db.Create(&model.Transaction{
		ID:              uuid.NewString(),
		UserID:          userID,
		AccountID:       source.ID,
		ToAccountID:     &target.ID,
		Type:            "transfer",
		Amount:          200,
		TransactionDate: time.Date(2026, 5, 22, 12, 0, 0, 0, time.Local),
	}).Error; err != nil {
		t.Fatalf("create transfer: %v", err)
	}
	if _, err := providerSvc.Create(userID, SaveAIProviderRequest{
		Name:    "Fake AI",
		BaseURL: server.URL,
		APIKey:  "sk-test",
		Model:   "deepseek-chat",
		Enabled: true,
	}); err != nil {
		t.Fatalf("create provider: %v", err)
	}

	report, err := svc.Generate(userID, GenerateAIReportRequest{
		ReportType:  "weekly",
		PeriodStart: "2026-05-18",
		PeriodEnd:   "2026-05-24",
		MaskNames:   boolPtr(false),
	})
	if err != nil {
		t.Fatalf("generate report: %v", err)
	}

	var snapshot struct {
		AccountChanges []struct {
			AccountName  string  `json:"account_name"`
			BalanceDelta float64 `json:"balance_delta"`
		} `json:"account_changes"`
	}
	if err := json.Unmarshal([]byte(report.SnapshotJSON), &snapshot); err != nil {
		t.Fatalf("decode snapshot: %v", err)
	}
	changes := make(map[string]float64, len(snapshot.AccountChanges))
	for _, change := range snapshot.AccountChanges {
		changes[change.AccountName] = change.BalanceDelta
	}
	if changes["现金"] != -200 {
		t.Fatalf("source balance delta = %v, want -200", changes["现金"])
	}
	if changes["储蓄卡"] != 200 {
		t.Fatalf("target balance delta = %v, want 200", changes["储蓄卡"])
	}
}

func TestAIReportGenerateRejectsUnsupportedType(t *testing.T) {
	svc, _, userID := newAIReportTestServices(t)

	_, err := svc.Generate(userID, GenerateAIReportRequest{
		ReportType:  "unsupported",
		PeriodStart: "2026-05-18",
		PeriodEnd:   "2026-05-24",
	})
	if !errors.Is(err, ErrAIReportTypeUnsupported) {
		t.Fatalf("err = %v, want ErrAIReportTypeUnsupported", err)
	}
}

func TestAIReportFailureMessageDoesNotExposeProviderEndpointDetails(t *testing.T) {
	svc, providerSvc, userID := newAIReportTestServices(t)
	if _, err := providerSvc.Create(userID, SaveAIProviderRequest{
		Name:    "Local Gateway",
		BaseURL: "http://127.0.0.1:1/private-ai-gateway",
		APIKey:  "sk-provider-secret",
		Model:   "deepseek-chat",
		Enabled: true,
	}); err != nil {
		t.Fatalf("create provider: %v", err)
	}

	report, err := svc.Generate(userID, GenerateAIReportRequest{
		ReportType:  "weekly",
		PeriodStart: "2026-05-18",
		PeriodEnd:   "2026-05-24",
	})
	if err == nil {
		t.Fatal("expected ai provider request failure")
	}
	if report == nil {
		t.Fatal("failed report response should be returned")
	}
	if report.Status != "failed" {
		t.Fatalf("status = %q, want failed", report.Status)
	}
	for _, leaked := range []string{
		"127.0.0.1",
		"private-ai-gateway",
		"sk-provider-secret",
		"connect",
		"dial",
	} {
		if strings.Contains(strings.ToLower(report.ErrorMessage), strings.ToLower(leaked)) {
			t.Fatalf("ai report error message leaked %q: %s", leaked, report.ErrorMessage)
		}
	}
	if !strings.Contains(report.ErrorMessage, "AI provider request failed") {
		t.Fatalf("error message = %q, want generic provider request failure", report.ErrorMessage)
	}
}

func TestSanitizeAIErrorRedactsCredentialLikeValues(t *testing.T) {
	err := errors.New("request failed Authorization: Bearer sk-secret-token-123 api_key=sk-query-secret&access_token=plain-token token=other-token")

	message := sanitizeAIError(err)

	for _, leaked := range []string{"sk-secret-token-123", "sk-query-secret", "plain-token", "other-token"} {
		if strings.Contains(message, leaked) {
			t.Fatalf("sanitized message leaked %q: %s", leaked, message)
		}
	}
	if strings.Count(message, "[redacted]") < 4 {
		t.Fatalf("sanitized message = %q, want redacted placeholders", message)
	}
}

func newAIReportTestServices(t *testing.T) (*AIReportService, *AIProviderService, uint) {
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
	providerSvc := NewAIProviderService(repos.AIProvider, NewOpenAICompatibleClient(nil))
	reportSvc := NewAIReportService(repos.AIReport, repos.AIProvider, repos.Transaction, repos.Category, repos.FamilyMember, NewOpenAICompatibleClient(nil)).
		WithBudgetRepository(repos.Budget).
		WithAccountRepository(repos.Account)
	return reportSvc, providerSvc, user.ID
}

func seedAIReportFacts(t *testing.T, providerSvc *AIProviderService, userID uint, baseURL string) {
	t.Helper()
	db := providerSvc.repo.DB()

	category := model.Category{
		ID:     uuid.NewString(),
		UserID: userID,
		Name:   "餐饮",
		Type:   "expense",
	}
	if err := db.Create(&category).Error; err != nil {
		t.Fatalf("create category: %v", err)
	}
	account := model.Account{
		ID:             uuid.NewString(),
		UserID:         userID,
		Name:           "现金",
		Type:           "cash",
		CurrentBalance: 1000,
	}
	if err := db.Create(&account).Error; err != nil {
		t.Fatalf("create account: %v", err)
	}
	member := model.FamilyMember{
		ID:        uuid.NewString(),
		UserID:    userID,
		Name:      "成员A",
		Color:     "#111111",
		IsEnabled: true,
	}
	if err := db.Create(&member).Error; err != nil {
		t.Fatalf("create family member: %v", err)
	}
	if err := db.Create(&model.Budget{
		ID:             uuid.NewString(),
		UserID:         userID,
		Amount:         300,
		AlertThreshold: 80,
		IsActive:       true,
	}).Error; err != nil {
		t.Fatalf("create total budget: %v", err)
	}
	if err := db.Create(&model.Budget{
		ID:             uuid.NewString(),
		UserID:         userID,
		CategoryID:     &category.ID,
		Amount:         100,
		AlertThreshold: 80,
		IsActive:       true,
	}).Error; err != nil {
		t.Fatalf("create category budget: %v", err)
	}
	if err := db.Create(&model.Budget{
		ID:             uuid.NewString(),
		UserID:         userID,
		MemberID:       &member.ID,
		Amount:         180,
		AlertThreshold: 80,
		IsActive:       true,
	}).Error; err != nil {
		t.Fatalf("create member budget: %v", err)
	}

	expenseDate := time.Date(2026, 5, 20, 12, 0, 0, 0, time.Local)
	incomeDate := time.Date(2026, 5, 21, 12, 0, 0, 0, time.Local)
	transactions := []model.Transaction{
		{
			ID:              uuid.NewString(),
			UserID:          userID,
			AccountID:       account.ID,
			CategoryID:      &category.ID,
			Type:            "expense",
			Amount:          120,
			TransactionDate: expenseDate,
			Remark:          "secret dinner remark",
			MemberID:        &member.ID,
		},
		{
			ID:              uuid.NewString(),
			UserID:          userID,
			AccountID:       account.ID,
			Type:            "income",
			Amount:          500,
			TransactionDate: incomeDate,
			Remark:          "private salary remark",
		},
	}
	if err := db.Create(&transactions).Error; err != nil {
		t.Fatalf("create transactions: %v", err)
	}

	if _, err := providerSvc.Create(userID, SaveAIProviderRequest{
		Name:    "Fake AI",
		BaseURL: baseURL,
		APIKey:  "sk-test",
		Model:   "deepseek-chat",
		Enabled: true,
	}); err != nil {
		t.Fatalf("create provider: %v", err)
	}
}
