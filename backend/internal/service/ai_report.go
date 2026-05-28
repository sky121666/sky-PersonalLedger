package service

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"time"

	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

var (
	ErrAIReportNotFound         = errors.New("ai report not found")
	ErrAIReportTypeRequired     = errors.New("ai report type is required")
	ErrAIReportPeriodInvalid    = errors.New("ai report period is invalid")
	ErrAIReportProviderNotFound = errors.New("enabled ai provider not found")
)

const aiReportPromptVersion = "personal-ledger-v1"

type AIReportService struct {
	repo       *repository.AIReportRepository
	providers  *repository.AIProviderRepository
	txs        *repository.TransactionRepository
	budgets    *repository.BudgetRepository
	categories *repository.CategoryRepository
	members    *repository.FamilyMemberRepository
	client     *OpenAICompatibleClient
	secret     string
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
	secret := ""
	if len(encryptionSecrets) > 0 {
		secret = encryptionSecrets[0]
	}
	return &AIReportService{
		repo:       repo,
		providers:  providers,
		txs:        txs,
		budgets:    nil,
		categories: categories,
		members:    members,
		client:     client,
		secret:     secret,
	}
}

func (s *AIReportService) WithBudgetRepository(budgetRepo *repository.BudgetRepository) *AIReportService {
	s.budgets = budgetRepo
	return s
}

type GenerateAIReportRequest struct {
	ReportType  string `json:"report_type" binding:"required"`
	ProviderID  string `json:"provider_id"`
	PeriodStart string `json:"period_start" binding:"required"`
	PeriodEnd   string `json:"period_end" binding:"required"`
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
	IncomeTotal          float64                    `json:"income_total"`
	ExpenseTotal         float64                    `json:"expense_total"`
	NetCashflow          float64                    `json:"net_cashflow"`
	Budget               aiReportBudgetSnapshot     `json:"budget"`
	TopExpenseCategories []aiReportCategorySnapshot `json:"top_expense_categories"`
	FamilyMembers        []aiReportMemberSnapshot   `json:"family_members"`
	AccountChanges       []any                      `json:"account_changes"`
}

type aiReportBudgetSnapshot struct {
	MonthlyBudget        *float64                       `json:"monthly_budget"`
	Spent                float64                        `json:"spent"`
	Remaining            *float64                       `json:"remaining"`
	UsedPercent          *int                           `json:"used_percent"`
	OverBudgetCategories []aiReportBudgetLimitSnapshot  `json:"over_budget_categories"`
	MemberBudgets        []aiReportMemberBudgetSnapshot `json:"member_budgets"`
}

type aiReportBudgetLimitSnapshot struct {
	Name       string  `json:"name"`
	Amount     float64 `json:"amount"`
	Spent      float64 `json:"spent"`
	Percentage int     `json:"percentage"`
}

type aiReportMemberBudgetSnapshot struct {
	MemberName   string  `json:"member_name"`
	CategoryName string  `json:"category_name,omitempty"`
	Amount       float64 `json:"amount"`
	Spent        float64 `json:"spent"`
	Remaining    float64 `json:"remaining"`
	Percentage   int     `json:"percentage"`
}

type aiReportCategorySnapshot struct {
	Name   string  `json:"name"`
	Amount float64 `json:"amount"`
	Count  int     `json:"count"`
}

type aiReportMemberSnapshot struct {
	DisplayName  string  `json:"display_name"`
	ExpenseTotal float64 `json:"expense_total"`
	Count        int     `json:"count"`
}

func (s *AIReportService) Generate(userID uint, req GenerateAIReportRequest) (*AIReportResponse, error) {
	reportType := strings.TrimSpace(req.ReportType)
	if reportType == "" {
		return nil, ErrAIReportTypeRequired
	}
	start, end, err := parseAIReportPeriod(req.PeriodStart, req.PeriodEnd)
	if err != nil {
		return nil, err
	}
	provider, err := s.selectProvider(userID, req.ProviderID)
	if err != nil {
		return nil, err
	}

	snapshotJSON, err := s.buildSnapshotJSON(userID, start, end)
	if err != nil {
		return nil, err
	}

	report := &model.AIReport{
		UserID:        userID,
		ReportType:    reportType,
		PeriodStart:   start,
		PeriodEnd:     end,
		Status:        "running",
		SnapshotJSON:  snapshotJSON,
		ProviderID:    provider.ID,
		ProviderName:  provider.Name,
		Model:         provider.Model,
		PromptVersion: aiReportPromptVersion,
	}
	if err := s.repo.Create(report); err != nil {
		return nil, err
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	apiKey, err := revealAISecret(provider.APIKeyCiphertext, s.secret)
	if err != nil {
		report.Status = "failed"
		report.ErrorMessage = sanitizeAIError(err)
		_ = s.repo.Update(report)
		return aiReportResponse(report), err
	}
	content, err := s.client.GenerateReport(ctx, provider.BaseURL, apiKey, provider.Model, snapshotJSON)
	if err != nil {
		report.Status = "failed"
		report.ErrorMessage = sanitizeAIError(err)
		_ = s.repo.Update(report)
		return aiReportResponse(report), err
	}

	report.Status = "completed"
	report.ContentJSON = normalizeAIReportContent(content)
	if err := s.repo.Update(report); err != nil {
		return nil, err
	}
	return aiReportResponse(report), nil
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

func (s *AIReportService) buildSnapshotJSON(userID uint, start time.Time, end time.Time) (string, error) {
	sum, err := s.txs.SumByDateRange(userID, start, end)
	if err != nil {
		return "", err
	}
	snapshot := aiReportSnapshot{
		Currency:       "CNY",
		IncomeTotal:    sum.Income,
		ExpenseTotal:   sum.Expense,
		NetCashflow:    sum.Income - sum.Expense,
		Budget:         aiReportBudgetSnapshot{OverBudgetCategories: []aiReportBudgetLimitSnapshot{}, MemberBudgets: []aiReportMemberBudgetSnapshot{}},
		AccountChanges: []any{},
	}
	snapshot.Period.Start = start.Format("2006-01-02")
	snapshot.Period.End = end.Format("2006-01-02")
	snapshot.Period.Timezone = time.Local.String()

	if err := s.appendCategorySnapshot(userID, start, end, &snapshot); err != nil {
		return "", err
	}
	if err := s.appendMemberSnapshot(userID, start, end, &snapshot); err != nil {
		return "", err
	}
	if err := s.appendBudgetSnapshot(userID, start, end, &snapshot); err != nil {
		return "", err
	}

	data, err := json.Marshal(snapshot)
	if err != nil {
		return "", err
	}
	return string(data), nil
}

func (s *AIReportService) appendBudgetSnapshot(userID uint, start time.Time, end time.Time, snapshot *aiReportSnapshot) error {
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
	categorySums, err := s.txs.SumByCategory(userID, start, end, "expense")
	if err != nil {
		return err
	}
	memberCategorySums, err := s.txs.SumExpenseByMemberAndCategory(userID, start, end)
	if err != nil {
		return err
	}
	categorySpent := make(map[string]float64, len(categorySums))
	for _, sum := range categorySums {
		categorySpent[sum.CategoryID] = sum.Total
	}
	memberSpent := make(map[string]float64)
	memberCategorySpent := make(map[string]float64)
	for _, sum := range memberCategorySums {
		memberSpent[sum.MemberID] += sum.Total
		memberCategorySpent[budgetScopeKey(sum.MemberID, sum.CategoryID)] = sum.Total
	}

	for _, budget := range budgets {
		if budget.MemberID == nil && budget.CategoryID == nil {
			snapshot.Budget.MonthlyBudget = float64Ptr(budget.Amount)
			snapshot.Budget.Spent = snapshot.ExpenseTotal
			snapshot.Budget.Remaining = float64Ptr(budget.Amount - snapshot.ExpenseTotal)
			snapshot.Budget.UsedPercent = percentPtr(snapshot.ExpenseTotal, budget.Amount)
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
			memberName := "成员"
			if budget.Member != nil && budget.Member.Name != "" {
				memberName = budget.Member.Name
			}
			snapshot.Budget.MemberBudgets = append(snapshot.Budget.MemberBudgets, aiReportMemberBudgetSnapshot{
				MemberName:   memberName,
				CategoryName: categoryName,
				Amount:       budget.Amount,
				Spent:        spent,
				Remaining:    budget.Amount - spent,
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

func (s *AIReportService) appendMemberSnapshot(userID uint, start time.Time, end time.Time, snapshot *aiReportSnapshot) error {
	sums, err := s.txs.SumExpenseByMember(userID, start, end)
	if err != nil {
		return err
	}
	members, err := s.members.GetByUserID(userID)
	if err != nil {
		return err
	}
	memberNames := make(map[string]string, len(members))
	for _, member := range members {
		memberNames[member.ID] = member.Name
	}
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
	end = time.Date(end.Year(), end.Month(), end.Day(), 23, 59, 59, 0, time.Local)
	return start, end, nil
}

func normalizeAIReportContent(content string) string {
	content = strings.TrimSpace(content)
	if json.Valid([]byte(content)) {
		return content
	}
	data, _ := json.Marshal(map[string]string{"summary": content})
	return string(data)
}

func sanitizeAIError(err error) string {
	return strings.TrimSpace(err.Error())
}

func float64Ptr(value float64) *float64 {
	return &value
}

func percentPtr(spent float64, amount float64) *int {
	value := percentValue(spent, amount)
	return &value
}

func percentValue(spent float64, amount float64) int {
	if amount <= 0 {
		return 0
	}
	return int(spent / amount * 100)
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
