package service

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/money"
	"github.com/sky/personal-ledger/internal/repository"
	"gorm.io/gorm"
)

var (
	ErrAIReportNotFound          = errors.New("ai report not found")
	ErrAIReportTypeRequired      = errors.New("ai report type is required")
	ErrAIReportTypeUnsupported   = errors.New("ai report type is unsupported")
	ErrAIReportPeriodInvalid     = errors.New("ai report period is invalid")
	ErrAIReportProviderNotFound  = errors.New("enabled ai provider not found")
	ErrAIReportContentInvalid    = errors.New("AI report content is invalid; provider must return a meaningful summary and correctly typed fields")
	ErrAIReportGenerationLimited = errors.New("AI report generation limit reached; try again later")
	ErrAIReportScheduleDisabled  = errors.New("AI automatic report schedule was disabled before sending")
)

const aiReportPromptVersion = "personal-ledger-v3"
const aiReportMaskedPromptVersion = "personal-ledger-v3-masked"

var aiErrorSecretPatterns = []*regexp.Regexp{
	regexp.MustCompile(`(?i)(authorization:\s*bearer\s+)[^\s,;]+`),
	regexp.MustCompile(`(?i)((?:api[_-]?key|access[_-]?token|token)=)[^&\s]+`),
	regexp.MustCompile(`sk-[A-Za-z0-9][A-Za-z0-9_-]{8,}`),
}

type aiReportGenerationLockEntry struct {
	mu   sync.Mutex
	refs int
}

var aiReportGenerationLocks = struct {
	sync.Mutex
	entries map[string]*aiReportGenerationLockEntry
}{entries: make(map[string]*aiReportGenerationLockEntry)}

type AIReportService struct {
	repo             *repository.AIReportRepository
	providers        *repository.AIProviderRepository
	txs              *repository.TransactionRepository
	budgets          *repository.BudgetRepository
	accounts         *repository.AccountRepository
	categories       *repository.CategoryRepository
	members          *repository.FamilyMemberRepository
	client           *OpenAICompatibleClient
	credentialKeys   credentialKeyring
	generationLimits *aiReportGenerationLimits
}

func NewAIReportService(
	repo *repository.AIReportRepository,
	providers *repository.AIProviderRepository,
	txs *repository.TransactionRepository,
	categories *repository.CategoryRepository,
	members *repository.FamilyMemberRepository,
	client *OpenAICompatibleClient,
	encryptionSecrets ...string,
) *AIReportService {
	if client == nil {
		client = NewOpenAICompatibleClient(nil)
	}
	return &AIReportService{
		repo:             repo,
		providers:        providers,
		txs:              txs,
		budgets:          nil,
		accounts:         nil,
		categories:       categories,
		members:          members,
		client:           client,
		credentialKeys:   newCredentialKeyring(encryptionSecrets...),
		generationLimits: newAIReportGenerationLimits(),
	}
}

func (s *AIReportService) WithBudgetRepository(budgetRepo *repository.BudgetRepository) *AIReportService {
	s.budgets = budgetRepo
	return s
}

func (s *AIReportService) WithAccountRepository(accountRepo *repository.AccountRepository) *AIReportService {
	s.accounts = accountRepo
	return s
}

type GenerateAIReportRequest struct {
	ReportType            string `json:"report_type" binding:"required"`
	ProviderID            string `json:"provider_id"`
	PeriodStart           string `json:"period_start" binding:"required"`
	PeriodEnd             string `json:"period_end" binding:"required"`
	MaskNames             *bool  `json:"mask_names"`
	beforeProviderRequest func() error
}

type AIReportResponse struct {
	ID            string    `json:"id"`
	UserID        uint      `json:"user_id"`
	ReportType    string    `json:"report_type"`
	PeriodStart   time.Time `json:"period_start"`
	PeriodEnd     time.Time `json:"period_end"`
	Status        string    `json:"status"`
	SnapshotJSON  string    `json:"snapshot_json"`
	ContentJSON   string    `json:"content_json"`
	ProviderID    string    `json:"provider_id"`
	ProviderName  string    `json:"provider_name"`
	Model         string    `json:"model"`
	PromptVersion string    `json:"prompt_version"`
	ErrorMessage  string    `json:"error_message,omitempty"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
}

type aiReportSnapshot struct {
	Period struct {
		Start    string `json:"start"`
		End      string `json:"end"`
		Timezone string `json:"timezone"`
	} `json:"period"`
	Currency             string                     `json:"currency"`
	IncomeTotal          money.Amount               `json:"income_total"`
	ExpenseTotal         money.Amount               `json:"expense_total"`
	NetCashflow          money.Amount               `json:"net_cashflow"`
	Budget               aiReportBudgetSnapshot     `json:"budget"`
	TopExpenseCategories []aiReportCategorySnapshot `json:"top_expense_categories"`
	FamilyMembers        []aiReportMemberSnapshot   `json:"family_members"`
	AccountChanges       []aiReportAccountSnapshot  `json:"account_changes"`
}

type aiReportBudgetSnapshot struct {
	PeriodStart          string                         `json:"period_start"`
	PeriodEnd            string                         `json:"period_end"`
	SettingsBasis        string                         `json:"settings_basis"`
	MonthlyBudget        *money.Amount                  `json:"monthly_budget"`
	Spent                money.Amount                   `json:"spent"`
	Remaining            *money.Amount                  `json:"remaining"`
	UsedPercent          *int                           `json:"used_percent"`
	OverBudgetCategories []aiReportBudgetLimitSnapshot  `json:"over_budget_categories"`
	MemberBudgets        []aiReportMemberBudgetSnapshot `json:"member_budgets"`
}

type aiReportBudgetLimitSnapshot struct {
	Name       string       `json:"name"`
	Amount     money.Amount `json:"amount"`
	Spent      money.Amount `json:"spent"`
	Percentage int          `json:"percentage"`
}

type aiReportMemberBudgetSnapshot struct {
	MemberName   string       `json:"member_name"`
	CategoryName string       `json:"category_name,omitempty"`
	Amount       money.Amount `json:"amount"`
	Spent        money.Amount `json:"spent"`
	Remaining    money.Amount `json:"remaining"`
	Percentage   int          `json:"percentage"`
}

type aiReportCategorySnapshot struct {
	Name   string       `json:"name"`
	Amount money.Amount `json:"amount"`
	Count  int          `json:"count"`
}

type aiReportMemberSnapshot struct {
	DisplayName  string       `json:"display_name"`
	ExpenseTotal money.Amount `json:"expense_total"`
	Count        int          `json:"count"`
}

type aiReportAccountSnapshot struct {
	AccountName  string       `json:"account_name"`
	BalanceDelta money.Amount `json:"balance_delta"`
}

func (s *AIReportService) Generate(userID uint, req GenerateAIReportRequest) (*AIReportResponse, error) {
	reportType := strings.TrimSpace(req.ReportType)
	if reportType == "" {
		return nil, ErrAIReportTypeRequired
	}
	if !isSupportedAIReportType(reportType) {
		return nil, ErrAIReportTypeUnsupported
	}
	start, end, err := parseAIReportPeriod(req.PeriodStart, req.PeriodEnd)
	if err != nil {
		return nil, err
	}
	provider, err := s.selectProvider(userID, req.ProviderID)
	if err != nil {
		return nil, err
	}
	maskNames := shouldMaskAIReportNames(req)
	promptVersion := aiReportPromptVersionForRequest(req)
	unlock := lockAIReportGeneration(userID, reportType, start, end, provider.ID, promptVersion)
	defer unlock()
	// The selected provider may have changed or been disabled while this
	// request waited for a previous generation to finish.
	provider, err = s.selectProvider(userID, provider.ID)
	if err != nil {
		return nil, err
	}
	providerRevision := aiProviderRevision(provider)

	snapshotJSON, err := s.buildSnapshotJSON(userID, start, end, maskNames)
	if err != nil {
		return nil, err
	}
	// A report is reusable only while both its financial facts and provider
	// configuration are unchanged. Keep older reports as historical snapshots.
	cached, err := s.repo.GetReusableCompleted(userID, reportType, start, end, provider.ID, provider.Model, promptVersion)
	if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, err
	}
	if err == nil && cached.SnapshotJSON == snapshotJSON && cached.ProviderRevision == providerRevision {
		return aiReportResponse(cached), nil
	}

	report := &model.AIReport{
		UserID:           userID,
		ReportType:       reportType,
		PeriodStart:      start,
		PeriodEnd:        end,
		Status:           "running",
		SnapshotJSON:     snapshotJSON,
		ProviderID:       provider.ID,
		ProviderName:     provider.Name,
		ProviderRevision: providerRevision,
		Model:            provider.Model,
		PromptVersion:    promptVersion,
	}
	if err := s.repo.Create(report); err != nil {
		return nil, err
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	apiKey, err := revealAISecretWithKeyring(provider.APIKeyCiphertext, s.credentialKeys)
	if err != nil {
		return s.markReportFailed(report, err)
	}
	if req.beforeProviderRequest != nil {
		if err := req.beforeProviderRequest(); err != nil {
			return s.markReportFailed(report, err)
		}
	}
	releaseAttempt, err := s.generationLimits.acquire(userID)
	if err != nil {
		return s.markReportFailed(report, err)
	}
	defer releaseAttempt()
	content, err := s.client.GenerateReport(ctx, provider.BaseURL, apiKey, provider.Model, snapshotJSON, reportType)
	if err != nil {
		return s.markReportFailed(report, err)
	}

	contentJSON, err := normalizeAIReportContent(content)
	if err != nil {
		return s.markReportFailed(report, err)
	}
	report.Status = "completed"
	report.ContentJSON = contentJSON
	if err := s.repo.Update(report); err != nil {
		return nil, err
	}
	return aiReportResponse(report), nil
}

// Keep the exact generation configuration private and out of both provider
// requests and backup JSON. A timestamp cannot identify the configuration
// used when an edit races with report creation.
func aiProviderRevision(provider *model.AIProvider) string {
	configuration, _ := json.Marshal(struct {
		Name, Type, BaseURL, Model, APIKeyCiphertext string
		Enabled                                      bool
	}{provider.Name, provider.ProviderType, provider.BaseURL, provider.Model, provider.APIKeyCiphertext, provider.Enabled})
	return fmt.Sprintf("%x", sha256.Sum256(configuration))
}

func (s *AIReportService) markReportFailed(report *model.AIReport, cause error) (*AIReportResponse, error) {
	report.Status = "failed"
	report.ErrorMessage = sanitizeAIError(cause)
	response := aiReportResponse(report)
	if err := s.repo.Update(report); err != nil {
		return response, fmt.Errorf("%w; persist failed AI report state: %v", cause, err)
	}
	return response, cause
}

func aiReportPromptVersionForRequest(req GenerateAIReportRequest) string {
	if shouldMaskAIReportNames(req) {
		return aiReportMaskedPromptVersion
	}
	return aiReportPromptVersion
}

func lockAIReportGeneration(userID uint, reportType string, start time.Time, end time.Time, providerID string, promptVersion string) func() {
	key := fmt.Sprintf(
		"%d|%s|%s|%s|%s|%s",
		userID,
		reportType,
		start.Format(time.RFC3339Nano),
		end.Format(time.RFC3339Nano),
		providerID,
		promptVersion,
	)
	aiReportGenerationLocks.Lock()
	entry := aiReportGenerationLocks.entries[key]
	if entry == nil {
		entry = &aiReportGenerationLockEntry{}
		aiReportGenerationLocks.entries[key] = entry
	}
	entry.refs++
	aiReportGenerationLocks.Unlock()

	entry.mu.Lock()
	return func() {
		entry.mu.Unlock()
		aiReportGenerationLocks.Lock()
		entry.refs--
		if entry.refs == 0 && aiReportGenerationLocks.entries[key] == entry {
			delete(aiReportGenerationLocks.entries, key)
		}
		aiReportGenerationLocks.Unlock()
	}
}

func shouldMaskAIReportNames(req GenerateAIReportRequest) bool {
	return req.MaskNames == nil || *req.MaskNames
}

func isSupportedAIReportType(reportType string) bool {
	switch reportType {
	case "weekly", "monthly", "family", "budget", "anomaly":
		return true
	default:
		return false
	}
}

func (s *AIReportService) List(userID uint) ([]AIReportResponse, error) {
	reports, err := s.repo.GetByUserID(userID)
	if err != nil {
		return nil, err
	}
	responses := make([]AIReportResponse, 0, len(reports))
	for i := range reports {
		responses = append(responses, *aiReportResponse(&reports[i]))
	}
	return responses, nil
}

func (s *AIReportService) Get(id string, userID uint) (*AIReportResponse, error) {
	report, err := s.getOwnedReport(id, userID)
	if err != nil {
		return nil, err
	}
	return aiReportResponse(report), nil
}

func (s *AIReportService) Delete(id string, userID uint) error {
	report, err := s.getOwnedReport(id, userID)
	if err != nil {
		return err
	}
	return s.repo.Delete(report)
}

func (s *AIReportService) selectProvider(userID uint, providerID string) (*model.AIProvider, error) {
	if strings.TrimSpace(providerID) != "" {
		provider, err := s.providers.GetByID(providerID)
		if err != nil || provider.UserID != userID || !provider.Enabled {
			return nil, ErrAIReportProviderNotFound
		}
		return provider, nil
	}
	providers, err := s.providers.GetByUserID(userID)
	if err != nil {
		return nil, err
	}
	for i := range providers {
		if providers[i].Enabled {
			return &providers[i], nil
		}
	}
	return nil, ErrAIReportProviderNotFound
}

func (s *AIReportService) buildSnapshotJSON(userID uint, start time.Time, end time.Time, maskNames bool) (string, error) {
	var snapshot string
	err := withConsistentReadSnapshot(s.txs.DB(), func(db *gorm.DB) error {
		reader := *s
		reader.txs = repository.NewTransactionRepository(db)
		reader.categories = repository.NewCategoryRepository(db)
		reader.members = repository.NewFamilyMemberRepository(db)
		if s.budgets != nil {
			reader.budgets = repository.NewBudgetRepository(db)
		}
		if s.accounts != nil {
			reader.accounts = repository.NewAccountRepository(db)
		}
		var err error
		snapshot, err = reader.buildSnapshotFromRepositories(userID, start, end, maskNames)
		return err
	})
	return snapshot, err
}

func (s *AIReportService) buildSnapshotFromRepositories(userID uint, start time.Time, end time.Time, maskNames bool) (string, error) {
	sum, err := s.txs.SumByDateRange(userID, start, end)
	if err != nil {
		return "", err
	}
	snapshot := aiReportSnapshot{
		Currency:       "CNY",
		IncomeTotal:    sum.Income,
		ExpenseTotal:   sum.Expense,
		NetCashflow:    sum.Income.Sub(sum.Expense),
		Budget:         aiReportBudgetSnapshot{OverBudgetCategories: []aiReportBudgetLimitSnapshot{}, MemberBudgets: []aiReportMemberBudgetSnapshot{}},
		AccountChanges: []aiReportAccountSnapshot{},
	}
	snapshot.Period.Start = start.Format("2006-01-02")
	snapshot.Period.End = end.Format("2006-01-02")
	snapshot.Period.Timezone = time.Local.String()

	if err := s.appendCategorySnapshot(userID, start, end, &snapshot); err != nil {
		return "", err
	}
	memberNames, err := s.snapshotMemberNames(userID, maskNames)
	if err != nil {
		return "", err
	}
	if err := s.appendMemberSnapshot(userID, start, end, memberNames, &snapshot); err != nil {
		return "", err
	}
	if err := s.appendAccountSnapshot(userID, start, end, maskNames, &snapshot); err != nil {
		return "", err
	}
	if err := s.appendBudgetSnapshot(userID, end, memberNames, &snapshot); err != nil {
		return "", err
	}

	data, err := json.Marshal(snapshot)
	if err != nil {
		return "", err
	}
	return string(data), nil
}

func (s *AIReportService) appendBudgetSnapshot(userID uint, end time.Time, memberNames map[string]string, snapshot *aiReportSnapshot) error {
	// Budgets recur monthly. A weekly or cross-month report must not subtract
	// only its own period's spending from a whole month's allowance.
	start := time.Date(end.Year(), end.Month(), 1, 0, 0, 0, 0, end.Location())
	snapshot.Budget.PeriodStart = start.Format("2006-01-02")
	snapshot.Budget.PeriodEnd = end.Format("2006-01-02")
	snapshot.Budget.SettingsBasis = "current_budget_settings"
	categorySums, err := s.txs.SumByCategory(userID, start, end, "expense")
	if err != nil {
		return err
	}
	categorySpent := make(map[string]money.Amount, len(categorySums))
	var totalSpent money.Amount
	for _, sum := range categorySums {
		categorySpent[sum.CategoryID] = sum.Total
		totalSpent = totalSpent.Add(sum.Total)
	}
	// Spending remains a known fact even when no allowance is configured.
	snapshot.Budget.Spent = totalSpent
	if s.budgets == nil {
		return nil
	}
	budgets, err := s.budgets.GetByUserID(userID)
	if err != nil {
		return err
	}
	if len(budgets) == 0 {
		return nil
	}
	sort.Slice(budgets, func(i, j int) bool { return budgets[i].ID < budgets[j].ID })
	memberCategorySums, err := s.txs.SumExpenseByMemberAndCategory(userID, start, end)
	if err != nil {
		return err
	}
	memberSpent := make(map[string]money.Amount)
	memberCategorySpent := make(map[string]money.Amount)
	for _, sum := range memberCategorySums {
		memberSpent[sum.MemberID] = memberSpent[sum.MemberID].Add(sum.Total)
		memberCategorySpent[budgetScopeKey(sum.MemberID, sum.CategoryID)] = sum.Total
	}

	for _, budget := range budgets {
		if !budget.IsActive {
			continue
		}
		if budget.MemberID == nil && budget.CategoryID == nil {
			snapshot.Budget.MonthlyBudget = moneyAmountPtr(budget.Amount)
			snapshot.Budget.Spent = totalSpent
			snapshot.Budget.Remaining = moneyAmountPtr(budget.Amount.Sub(totalSpent))
			snapshot.Budget.UsedPercent = percentPtr(totalSpent, budget.Amount)
			continue
		}
		if budget.MemberID == nil && budget.CategoryID != nil {
			spent := categorySpent[*budget.CategoryID]
			percentage := percentValue(spent, budget.Amount)
			if spent > budget.Amount || percentage >= budget.AlertThreshold {
				name := "未分类"
				if budget.Category != nil && budget.Category.Name != "" {
					name = budget.Category.Name
				}
				snapshot.Budget.OverBudgetCategories = append(snapshot.Budget.OverBudgetCategories, aiReportBudgetLimitSnapshot{
					Name:       name,
					Amount:     budget.Amount,
					Spent:      spent,
					Percentage: percentage,
				})
			}
			continue
		}
		if budget.MemberID != nil {
			spent := memberSpent[*budget.MemberID]
			categoryName := ""
			if budget.CategoryID != nil {
				spent = memberCategorySpent[budgetScopeKey(*budget.MemberID, *budget.CategoryID)]
				if budget.Category != nil {
					categoryName = budget.Category.Name
				}
			}
			memberName := memberNames[*budget.MemberID]
			if memberName == "" {
				memberName = "成员"
			}
			snapshot.Budget.MemberBudgets = append(snapshot.Budget.MemberBudgets, aiReportMemberBudgetSnapshot{
				MemberName:   memberName,
				CategoryName: categoryName,
				Amount:       budget.Amount,
				Spent:        spent,
				Remaining:    budget.Amount.Sub(spent),
				Percentage:   percentValue(spent, budget.Amount),
			})
		}
	}
	if len(snapshot.Budget.OverBudgetCategories) > 5 {
		snapshot.Budget.OverBudgetCategories = snapshot.Budget.OverBudgetCategories[:5]
	}
	if len(snapshot.Budget.MemberBudgets) > 8 {
		snapshot.Budget.MemberBudgets = snapshot.Budget.MemberBudgets[:8]
	}
	return nil
}

func (s *AIReportService) appendAccountSnapshot(userID uint, start time.Time, end time.Time, maskNames bool, snapshot *aiReportSnapshot) error {
	if s.accounts == nil {
		return nil
	}
	sums, err := s.txs.SumBalanceDeltaByAccount(userID, start, end)
	if err != nil {
		return err
	}
	accounts, err := s.accounts.GetByUserID(userID, true)
	if err != nil {
		return err
	}
	accountNames := make(map[string]string, len(accounts))
	for _, account := range accounts {
		accountNames[account.ID] = account.Name
	}
	for _, sum := range sums {
		name := accountNames[sum.AccountID]
		if name == "" {
			name = "账户"
		}
		if maskNames {
			name = anonymizedAccountLabel(len(snapshot.AccountChanges) + 1)
		}
		snapshot.AccountChanges = append(snapshot.AccountChanges, aiReportAccountSnapshot{
			AccountName:  name,
			BalanceDelta: sum.BalanceDelta,
		})
	}
	return nil
}

func (s *AIReportService) appendCategorySnapshot(userID uint, start time.Time, end time.Time, snapshot *aiReportSnapshot) error {
	sums, err := s.txs.SumByCategory(userID, start, end, "expense")
	if err != nil {
		return err
	}
	categories, err := s.categories.GetByUserID(userID, "expense")
	if err != nil {
		return err
	}
	categoryNames := make(map[string]string, len(categories))
	for _, category := range categories {
		categoryNames[category.ID] = category.Name
	}
	sort.Slice(sums, func(i, j int) bool {
		if sums[i].Total == sums[j].Total {
			return sums[i].CategoryID < sums[j].CategoryID
		}
		return sums[i].Total > sums[j].Total
	})
	for _, sum := range sums {
		name := categoryNames[sum.CategoryID]
		if name == "" {
			name = "未分类"
		}
		snapshot.TopExpenseCategories = append(snapshot.TopExpenseCategories, aiReportCategorySnapshot{
			Name:   name,
			Amount: sum.Total,
			Count:  sum.Count,
		})
	}
	return nil
}

func (s *AIReportService) snapshotMemberNames(userID uint, maskNames bool) (map[string]string, error) {
	members, err := s.members.GetByUserID(userID)
	if err != nil {
		return nil, err
	}
	memberNames := make(map[string]string, len(members))
	sort.Slice(members, func(i, j int) bool { return members[i].ID < members[j].ID })
	for i, member := range members {
		name := member.Name
		if maskNames {
			name = anonymizedMemberLabel(i + 1)
		}
		memberNames[member.ID] = name
	}
	return memberNames, nil
}

func (s *AIReportService) appendMemberSnapshot(userID uint, start time.Time, end time.Time, memberNames map[string]string, snapshot *aiReportSnapshot) error {
	sums, err := s.txs.SumExpenseByMember(userID, start, end)
	if err != nil {
		return err
	}
	sort.Slice(sums, func(i, j int) bool {
		if sums[i].Total == sums[j].Total {
			return sums[i].MemberID < sums[j].MemberID
		}
		return sums[i].Total > sums[j].Total
	})
	for _, sum := range sums {
		if sum.MemberID == "" {
			continue
		}
		name := memberNames[sum.MemberID]
		if name == "" {
			name = "成员"
		}
		snapshot.FamilyMembers = append(snapshot.FamilyMembers, aiReportMemberSnapshot{
			DisplayName:  name,
			ExpenseTotal: sum.Total,
			Count:        sum.Count,
		})
	}
	return nil
}

func anonymizedMemberLabel(index int) string {
	return fmt.Sprintf("成员%d", index)
}

func anonymizedAccountLabel(index int) string {
	return fmt.Sprintf("账户%d", index)
}

func (s *AIReportService) getOwnedReport(id string, userID uint) (*model.AIReport, error) {
	report, err := s.repo.GetByID(id)
	if err != nil || report.UserID != userID {
		return nil, ErrAIReportNotFound
	}
	return report, nil
}

func parseAIReportPeriod(startText string, endText string) (time.Time, time.Time, error) {
	start, err := time.ParseInLocation("2006-01-02", strings.TrimSpace(startText), time.Local)
	if err != nil {
		return time.Time{}, time.Time{}, ErrAIReportPeriodInvalid
	}
	end, err := time.ParseInLocation("2006-01-02", strings.TrimSpace(endText), time.Local)
	if err != nil || end.Before(start) {
		return time.Time{}, time.Time{}, ErrAIReportPeriodInvalid
	}
	end = endOfCalendarDay(end)
	return start, end, nil
}

func sanitizeAIError(err error) string {
	message := strings.TrimSpace(err.Error())
	lowerMessage := strings.ToLower(message)
	if strings.Contains(message, "://") ||
		strings.Contains(lowerMessage, "dial tcp") ||
		strings.Contains(lowerMessage, "connect:") ||
		strings.Contains(lowerMessage, "connection refused") ||
		strings.Contains(lowerMessage, "no such host") ||
		strings.Contains(lowerMessage, "lookup ") {
		return "AI provider request failed; check provider configuration or network"
	}
	for _, pattern := range aiErrorSecretPatterns {
		message = pattern.ReplaceAllString(message, "${1}[redacted]")
	}
	return message
}

func moneyAmountPtr(value money.Amount) *money.Amount {
	return &value
}

func percentPtr(spent, amount money.Amount) *int {
	value := percentValue(spent, amount)
	return &value
}

func percentValue(spent, amount money.Amount) int {
	if amount.Cents() <= 0 {
		return 0
	}
	return int(spent.Cents() * 100 / amount.Cents())
}

func aiReportResponse(report *model.AIReport) *AIReportResponse {
	return &AIReportResponse{
		ID:            report.ID,
		UserID:        report.UserID,
		ReportType:    report.ReportType,
		PeriodStart:   report.PeriodStart,
		PeriodEnd:     report.PeriodEnd,
		Status:        report.Status,
		SnapshotJSON:  report.SnapshotJSON,
		ContentJSON:   report.ContentJSON,
		ProviderID:    report.ProviderID,
		ProviderName:  report.ProviderName,
		Model:         report.Model,
		PromptVersion: report.PromptVersion,
		ErrorMessage:  report.ErrorMessage,
		CreatedAt:     report.CreatedAt,
		UpdatedAt:     report.UpdatedAt,
	}
}
