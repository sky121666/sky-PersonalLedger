package service

import (
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

var (
	ErrBudgetNotFound = errors.New("budget not found")
)

type BudgetService struct {
	budgetRepo *repository.BudgetRepository
	txRepo     *repository.TransactionRepository
}

func NewBudgetService(budgetRepo *repository.BudgetRepository, txRepo *repository.TransactionRepository) *BudgetService {
	return &BudgetService{
		budgetRepo: budgetRepo,
		txRepo:     txRepo,
	}
}

type BudgetItem struct {
	ID             string  `json:"id"`
	CategoryID     *string `json:"category_id"`
	CategoryName   string  `json:"category_name,omitempty"`
	Amount         float64 `json:"amount"`
	Spent          float64 `json:"spent"`
	Remaining      float64 `json:"remaining"`
	Percentage     int     `json:"percentage"`
	AlertThreshold int     `json:"alert_threshold"`
}

type BudgetListResponse struct {
	TotalBudget     *BudgetItem  `json:"total_budget"`
	CategoryBudgets []BudgetItem `json:"category_budgets"`
}

func (s *BudgetService) List(userID uint, month string) (*BudgetListResponse, error) {
	// Parse month
	var startDate, endDate time.Time
	if month != "" {
		t, err := time.Parse("2006-01", month)
		if err != nil {
			return nil, err
		}
		startDate = t
		endDate = t.AddDate(0, 1, 0).Add(-time.Second)
	} else {
		now := time.Now()
		startDate = time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.Local)
		endDate = startDate.AddDate(0, 1, 0).Add(-time.Second)
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

	spentMap := make(map[string]float64)
	var totalSpent float64
	for _, cs := range categorySums {
		spentMap[cs.CategoryID] = cs.Total
		totalSpent += cs.Total
	}

	response := &BudgetListResponse{
		CategoryBudgets: []BudgetItem{},
	}

	for _, b := range budgets {
		item := BudgetItem{
			ID:             b.ID,
			CategoryID:     b.CategoryID,
			Amount:         b.Amount,
			AlertThreshold: b.AlertThreshold,
		}

		if b.CategoryID == nil {
			// Total budget
			item.Spent = totalSpent
			item.Remaining = b.Amount - totalSpent
			if b.Amount > 0 {
				item.Percentage = int(totalSpent / b.Amount * 100)
			}
			response.TotalBudget = &item
		} else {
			// Category budget
			spent := spentMap[*b.CategoryID]
			item.Spent = spent
			item.Remaining = b.Amount - spent
			if b.Amount > 0 {
				item.Percentage = int(spent / b.Amount * 100)
			}
			if b.Category != nil {
				item.CategoryName = b.Category.Name
			}
			response.CategoryBudgets = append(response.CategoryBudgets, item)
		}
	}

	return response, nil
}

type BudgetSummary struct {
	TotalAmount          float64     `json:"total_amount"`
	TotalSpent           float64     `json:"total_spent"`
	Percentage           int         `json:"percentage"`
	DailyAvailable       float64     `json:"daily_available"`
	DaysRemaining        int         `json:"days_remaining"`
	OverBudgetCategories []OverLimit `json:"over_budget_categories"`
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
	daysRemaining := int(firstOfNextMonth.Sub(now).Hours()/24) + 1
	if daysRemaining < 1 {
		daysRemaining = 1
	}
	summary.DaysRemaining = daysRemaining

	if list.TotalBudget != nil {
		summary.TotalAmount = list.TotalBudget.Amount
		summary.TotalSpent = list.TotalBudget.Spent
		summary.Percentage = list.TotalBudget.Percentage
		// Calculate daily available budget
		remaining := list.TotalBudget.Amount - list.TotalBudget.Spent
		if remaining > 0 {
			summary.DailyAvailable = remaining / float64(daysRemaining)
		}
	}

	// Find over budget categories
	for _, cat := range list.CategoryBudgets {
		if cat.Spent > cat.Amount {
			overPercent := 0
			if cat.Amount > 0 {
				overPercent = int((cat.Spent - cat.Amount) / cat.Amount * 100)
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
	CategoryID     *string `json:"category_id"`
	Amount         float64 `json:"amount" binding:"required,gt=0"`
	AlertThreshold int     `json:"alert_threshold"`
}

func (s *BudgetService) SetTotalBudget(userID uint, req SetBudgetRequest) (*model.Budget, error) {
	existing, err := s.budgetRepo.GetTotalBudget(userID)
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

	budget := &model.Budget{
		ID:             uuid.New().String(),
		UserID:         userID,
		CategoryID:     req.CategoryID,
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
