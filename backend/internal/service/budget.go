package service

import (
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/money"
	"github.com/sky/personal-ledger/internal/repository"
)

var (
	ErrBudgetNotFound = errors.New("budget not found")
)

type BudgetService struct {
	budgetRepo       *repository.BudgetRepository
	txRepo           *repository.TransactionRepository
	familyMemberRepo *repository.FamilyMemberRepository
	categoryRepo     *repository.CategoryRepository
}

func NewBudgetService(
	budgetRepo *repository.BudgetRepository,
	txRepo *repository.TransactionRepository,
	familyMemberRepo *repository.FamilyMemberRepository,
	categoryRepo *repository.CategoryRepository,
) *BudgetService {
	return &BudgetService{
		budgetRepo:       budgetRepo,
		txRepo:           txRepo,
		familyMemberRepo: familyMemberRepo,
		categoryRepo:     categoryRepo,
	}
}

type BudgetItem struct {
	ID             string       `json:"id"`
	CategoryID     *string      `json:"category_id"`
	CategoryName   string       `json:"category_name,omitempty"`
	MemberID       *string      `json:"member_id,omitempty"`
	MemberName     string       `json:"member_name,omitempty"`
	Amount         money.Amount `json:"amount"`
	Spent          money.Amount `json:"spent"`
	Remaining      money.Amount `json:"remaining"`
	Percentage     int          `json:"percentage"`
	AlertThreshold int          `json:"alert_threshold"`
}

type BudgetListResponse struct {
	TotalBudget     *BudgetItem  `json:"total_budget"`
	CategoryBudgets []BudgetItem `json:"category_budgets"`
	MemberBudgets   []BudgetItem `json:"member_budgets"`
}

func (s *BudgetService) List(userID uint, month string) (*BudgetListResponse, error) {
	startDate, endDate, err := budgetMonthRange(month)
	if err != nil {
		return nil, err
	}

	budgets, err := s.budgetRepo.GetByUserID(userID)
	if err != nil {
		return nil, err
	}

	// Get spending by category
	categorySums, err := s.txRepo.SumByCategory(userID, startDate, endDate, "expense")
	if err != nil {
		return nil, err
	}

	spentMap := make(map[string]money.Amount)
	var totalSpent money.Amount
	for _, cs := range categorySums {
		spentMap[cs.CategoryID] = cs.Total
		totalSpent = totalSpent.Add(cs.Total)
	}
	memberCategorySums, err := s.txRepo.SumExpenseByMemberAndCategory(userID, startDate, endDate)
	if err != nil {
		return nil, err
	}
	memberSpentMap := make(map[string]money.Amount)
	memberCategorySpentMap := make(map[string]money.Amount)
	for _, ms := range memberCategorySums {
		memberSpentMap[ms.MemberID] = memberSpentMap[ms.MemberID].Add(ms.Total)
		memberCategorySpentMap[budgetScopeKey(ms.MemberID, ms.CategoryID)] = ms.Total
	}

	response := &BudgetListResponse{
		CategoryBudgets: []BudgetItem{},
		MemberBudgets:   []BudgetItem{},
	}

	for _, b := range budgets {
		item := BudgetItem{
			ID:             b.ID,
			CategoryID:     b.CategoryID,
			MemberID:       b.MemberID,
			Amount:         b.Amount,
			AlertThreshold: b.AlertThreshold,
		}
		if b.Member != nil {
			item.MemberName = b.Member.Name
		}

		if b.MemberID != nil {
			if b.CategoryID == nil {
				item.Spent = memberSpentMap[*b.MemberID]
			} else {
				item.Spent = memberCategorySpentMap[budgetScopeKey(*b.MemberID, *b.CategoryID)]
				if b.Category != nil {
					item.CategoryName = b.Category.Name
				}
			}
			item.Remaining = b.Amount.Sub(item.Spent)
			if b.Amount > 0 {
				item.Percentage = moneyPercentage(item.Spent, b.Amount)
			}
			response.MemberBudgets = append(response.MemberBudgets, item)
		} else if b.CategoryID == nil {
			// Total budget
			item.Spent = totalSpent
			item.Remaining = b.Amount.Sub(totalSpent)
			if b.Amount > 0 {
				item.Percentage = moneyPercentage(totalSpent, b.Amount)
			}
			response.TotalBudget = &item
		} else {
			// Category budget
			spent := spentMap[*b.CategoryID]
			item.Spent = spent
			item.Remaining = b.Amount.Sub(spent)
			if b.Amount > 0 {
				item.Percentage = moneyPercentage(spent, b.Amount)
			}
			if b.Category != nil {
				item.CategoryName = b.Category.Name
			}
			response.CategoryBudgets = append(response.CategoryBudgets, item)
		}
	}

	return response, nil
}

func budgetMonthRange(month string) (time.Time, time.Time, error) {
	var startDate time.Time
	if month != "" {
		parsed, err := time.ParseInLocation("2006-01", month, time.Local)
		if err != nil {
			return time.Time{}, time.Time{}, err
		}
		startDate = parsed
	} else {
		now := time.Now()
		startDate = time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.Local)
	}

	endDate := startDate.AddDate(0, 1, 0).Add(-time.Nanosecond)
	return startDate, endDate, nil
}

type BudgetSummary struct {
	TotalAmount          money.Amount `json:"total_amount"`
	TotalSpent           money.Amount `json:"total_spent"`
	Percentage           int          `json:"percentage"`
	DailyAvailable       money.Amount `json:"daily_available"`
	DaysRemaining        int          `json:"days_remaining"`
	OverBudgetCategories []OverLimit  `json:"over_budget_categories"`
}

type OverLimit struct {
	Name       string `json:"name"`
	Percentage int    `json:"percentage"`
}

func (s *BudgetService) GetSummary(userID uint) (*BudgetSummary, error) {
	now := time.Now()
	month := now.Format("2006-01")
	list, err := s.List(userID, month)
	if err != nil {
		return nil, err
	}

	summary := &BudgetSummary{
		OverBudgetCategories: []OverLimit{},
	}

	// Calculate days remaining in month
	firstOfNextMonth := time.Date(now.Year(), now.Month()+1, 1, 0, 0, 0, 0, time.Local)
	daysRemaining := calendarDayDifference(now, firstOfNextMonth)
	if daysRemaining < 1 {
		daysRemaining = 1
	}
	summary.DaysRemaining = daysRemaining

	if list.TotalBudget != nil {
		summary.TotalAmount = list.TotalBudget.Amount
		summary.TotalSpent = list.TotalBudget.Spent
		summary.Percentage = list.TotalBudget.Percentage
		// Calculate daily available budget
		remaining := list.TotalBudget.Amount.Sub(list.TotalBudget.Spent)
		if remaining > 0 {
			summary.DailyAvailable = remaining.Divide(int64(daysRemaining))
		}
	}

	// Find over budget categories
	for _, cat := range list.CategoryBudgets {
		if cat.Spent > cat.Amount {
			overPercent := 0
			if cat.Amount > 0 {
				overPercent = moneyPercentage(cat.Spent.Sub(cat.Amount), cat.Amount)
			}
			summary.OverBudgetCategories = append(summary.OverBudgetCategories, OverLimit{
				Name:       cat.CategoryName,
				Percentage: overPercent,
			})
		} else if cat.Percentage >= cat.AlertThreshold {
			// Also include those nearing limit
			summary.OverBudgetCategories = append(summary.OverBudgetCategories, OverLimit{
				Name:       cat.CategoryName,
				Percentage: 0, // 0 means alert but not over yet
			})
		}
	}
	// Limit to top 2
	if len(summary.OverBudgetCategories) > 2 {
		summary.OverBudgetCategories = summary.OverBudgetCategories[:2]
	}

	return summary, nil
}

type SetBudgetRequest struct {
	CategoryID     *string      `json:"category_id"`
	MemberID       *string      `json:"member_id"`
	Amount         money.Amount `json:"amount" binding:"required,gt=0"`
	AlertThreshold int          `json:"alert_threshold"`
}

func moneyPercentage(value, total money.Amount) int {
	if total.Cents() <= 0 {
		return 0
	}
	return int(value.Cents() * 100 / total.Cents())
}

func (s *BudgetService) SetTotalBudget(userID uint, req SetBudgetRequest) (*model.Budget, error) {
	if err := s.ensureFamilyMemberBelongsToUser(req.MemberID, userID); err != nil {
		return nil, err
	}

	existing, err := s.budgetRepo.GetByScope(userID, nil, req.MemberID)
	if err == nil {
		existing.Amount = req.Amount
		if req.AlertThreshold > 0 {
			existing.AlertThreshold = req.AlertThreshold
		}
		return existing, s.budgetRepo.Update(existing)
	}

	budget := &model.Budget{
		ID:             uuid.New().String(),
		UserID:         userID,
		CategoryID:     nil,
		MemberID:       req.MemberID,
		Amount:         req.Amount,
		AlertThreshold: req.AlertThreshold,
	}
	if budget.AlertThreshold == 0 {
		budget.AlertThreshold = 80
	}

	return budget, s.budgetRepo.Create(budget)
}

func (s *BudgetService) SetCategoryBudget(userID uint, req SetBudgetRequest) (*model.Budget, error) {
	if req.CategoryID == nil {
		return s.SetTotalBudget(userID, req)
	}
	if err := s.ensureCategoryBelongsToUser(req.CategoryID, userID); err != nil {
		return nil, err
	}
	if err := s.ensureFamilyMemberBelongsToUser(req.MemberID, userID); err != nil {
		return nil, err
	}

	existing, err := s.budgetRepo.GetByScope(userID, req.CategoryID, req.MemberID)
	if err == nil {
		existing.Amount = req.Amount
		if req.AlertThreshold > 0 {
			existing.AlertThreshold = req.AlertThreshold
		}
		return existing, s.budgetRepo.Update(existing)
	}

	budget := &model.Budget{
		ID:             uuid.New().String(),
		UserID:         userID,
		CategoryID:     req.CategoryID,
		MemberID:       req.MemberID,
		Amount:         req.Amount,
		AlertThreshold: req.AlertThreshold,
	}
	if budget.AlertThreshold == 0 {
		budget.AlertThreshold = 80
	}

	return budget, s.budgetRepo.Create(budget)
}

func (s *BudgetService) Delete(id string, userID uint) error {
	budget, err := s.budgetRepo.GetByID(id)
	if err != nil {
		return ErrBudgetNotFound
	}
	if budget.UserID != userID {
		return ErrBudgetNotFound
	}
	return s.budgetRepo.Delete(id)
}

func (s *BudgetService) ensureFamilyMemberBelongsToUser(memberID *string, userID uint) error {
	if memberID == nil || *memberID == "" {
		return nil
	}
	if s.familyMemberRepo == nil {
		return ErrFamilyMemberNotFound
	}
	member, err := s.familyMemberRepo.GetByID(*memberID)
	if err != nil || member.UserID != userID {
		return ErrFamilyMemberNotFound
	}
	return nil
}

func (s *BudgetService) ensureCategoryBelongsToUser(categoryID *string, userID uint) error {
	if categoryID == nil || *categoryID == "" || s.categoryRepo == nil {
		return ErrCategoryNotFound
	}
	category, err := s.categoryRepo.GetByID(*categoryID)
	if err != nil || category.UserID != userID || category.Type != "expense" {
		return ErrCategoryNotFound
	}
	return nil
}

func budgetScopeKey(memberID, categoryID string) string {
	return memberID + "\x00" + categoryID
}
