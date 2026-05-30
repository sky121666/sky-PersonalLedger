package service

import (
	"time"

	"github.com/sky/personal-ledger/internal/repository"
)

type StatisticsService struct {
	txRepo       *repository.TransactionRepository
	categoryRepo *repository.CategoryRepository
	accountRepo  *repository.AccountRepository
}

func NewStatisticsService(txRepo *repository.TransactionRepository, categoryRepo *repository.CategoryRepository, accountRepo *repository.AccountRepository) *StatisticsService {
	return &StatisticsService{
		txRepo:       txRepo,
		categoryRepo: categoryRepo,
		accountRepo:  accountRepo,
	}
}

type OverviewResponse struct {
	Income           float64 `json:"income"`
	Expense          float64 `json:"expense"`
	Balance          float64 `json:"balance"`
	IncomeChange     float64 `json:"income_change"`
	ExpenseChange    float64 `json:"expense_change"`
	DailyAverage     float64 `json:"daily_average"`
	TransactionCount int     `json:"transaction_count"`
}

func (s *StatisticsService) GetOverview(userID uint, month string) (*OverviewResponse, error) {
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

	currentSum, err := s.txRepo.SumByDateRange(userID, startDate, endDate)
	if err != nil {
		return nil, err
	}

	// Previous month for comparison
	prevStart := startDate.AddDate(0, -1, 0)
	prevEnd := startDate.Add(-time.Second)
	prevSum, err := s.txRepo.SumByDateRange(userID, prevStart, prevEnd)
	if err != nil {
		return nil, err
	}

	response := &OverviewResponse{
		Income:           currentSum.Income,
		Expense:          currentSum.Expense,
		Balance:          currentSum.Income - currentSum.Expense,
		TransactionCount: currentSum.Count,
	}

	// Calculate daily average
	daysInMonth := endDate.Day()
	if time.Now().Before(endDate) {
		daysInMonth = time.Now().Day()
	}
	if daysInMonth > 0 {
		response.DailyAverage = currentSum.Expense / float64(daysInMonth)
	}

	// Calculate change percentages
	if prevSum != nil && prevSum.Income > 0 {
		response.IncomeChange = (currentSum.Income - prevSum.Income) / prevSum.Income * 100
	}
	if prevSum != nil && prevSum.Expense > 0 {
		response.ExpenseChange = (currentSum.Expense - prevSum.Expense) / prevSum.Expense * 100
	}

	return response, nil
}

type CategoryStatItem struct {
	CategoryID   string  `json:"category_id"`
	CategoryName string  `json:"category_name"`
	Icon         string  `json:"icon"`
	Color        string  `json:"color"`
	Amount       float64 `json:"amount"`
	Percentage   float64 `json:"percentage"`
	Count        int     `json:"count"`
}

type CategoryStatResponse struct {
	Total float64            `json:"total"`
	Items []CategoryStatItem `json:"items"`
}

type TrendItem struct {
	Date    string  `json:"date"`
	Income  float64 `json:"income"`
	Expense float64 `json:"expense"`
	Balance float64 `json:"balance"`
}

type TrendResponse struct {
	Items        []TrendItem `json:"items"`
	TotalIncome  float64     `json:"total_income"`
	TotalExpense float64     `json:"total_expense"`
}

func (s *StatisticsService) GetTrend(userID uint, month string) (*TrendResponse, error) {
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

	dailySums, err := s.txRepo.SumByDay(userID, startDate, endDate)
	if err != nil {
		return nil, err
	}

	response := &TrendResponse{
		Items: make([]TrendItem, 0),
	}

	for _, ds := range dailySums {
		response.Items = append(response.Items, TrendItem{
			Date:    ds.Date,
			Income:  ds.Income,
			Expense: ds.Expense,
			Balance: ds.Income - ds.Expense,
		})
		response.TotalIncome += ds.Income
		response.TotalExpense += ds.Expense
	}

	return response, nil
}

func (s *StatisticsService) GetCategoryStats(userID uint, month, txType string) (*CategoryStatResponse, error) {
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

	if txType == "" {
		txType = "expense"
	}

	sums, err := s.txRepo.SumByCategory(userID, startDate, endDate, txType)
	if err != nil {
		return nil, err
	}

	categories, err := s.categoryRepo.GetByUserID(userID, txType)
	if err != nil {
		return nil, err
	}
	categoryMap := make(map[string]*struct {
		Name  string
		Icon  string
		Color string
	})
	for _, c := range categories {
		categoryMap[c.ID] = &struct {
			Name  string
			Icon  string
			Color string
		}{c.Name, c.Icon, c.Color}
	}

	var total float64
	for _, cs := range sums {
		total += cs.Total
	}

	response := &CategoryStatResponse{
		Total: total,
		Items: []CategoryStatItem{},
	}

	for _, cs := range sums {
		item := CategoryStatItem{
			CategoryID: cs.CategoryID,
			Amount:     cs.Total,
			Count:      cs.Count,
		}
		if total > 0 {
			item.Percentage = cs.Total / total * 100
		}
		if cat, ok := categoryMap[cs.CategoryID]; ok {
			item.CategoryName = cat.Name
			item.Icon = cat.Icon
			item.Color = cat.Color
		}
		response.Items = append(response.Items, item)
	}

	return response, nil
}

type AssetTrendItem struct {
	Month        string  `json:"month"`
	TotalAssets  float64 `json:"total_assets"`
	TotalDebts   float64 `json:"total_debts"`
	NetWorth     float64 `json:"net_worth"`
	MonthIncome  float64 `json:"month_income"`
	MonthExpense float64 `json:"month_expense"`
}

type AssetTrendResponse struct {
	Items           []AssetTrendItem `json:"items"`
	CurrentAssets   float64          `json:"current_assets"`
	CurrentDebts    float64          `json:"current_debts"`
	CurrentNetWorth float64          `json:"current_net_worth"`
}

func (s *StatisticsService) GetAssetTrend(userID uint, months int) (*AssetTrendResponse, error) {
	if months <= 0 {
		months = 12
	}

	accounts, err := s.accountRepo.GetByUserID(userID, true)
	if err != nil {
		return nil, err
	}

	var currentAssets, currentDebts float64
	for _, acc := range accounts {
		if isDebtAccountType(acc.Type) {
			currentDebts += acc.CurrentBalance
		} else {
			currentAssets += acc.CurrentBalance
		}
	}

	response := &AssetTrendResponse{
		Items:           make([]AssetTrendItem, 0),
		CurrentAssets:   currentAssets,
		CurrentDebts:    currentDebts,
		CurrentNetWorth: currentAssets - currentDebts,
	}

	now := time.Now()
	currentMonth := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.Local)

	// First pass: collect all monthly data
	type monthData struct {
		month   string
		income  float64
		expense float64
		hasData bool
	}
	monthsData := make([]monthData, months)

	for i := 0; i < months; i++ {
		monthStart := time.Date(now.Year(), now.Month()-time.Month(i), 1, 0, 0, 0, 0, time.Local)
		monthEnd := monthStart.AddDate(0, 1, 0).Add(-time.Second)

		monthSum, err := s.txRepo.SumByDateRange(userID, monthStart, monthEnd)
		if err != nil {
			return nil, err
		}

		hasData := monthSum.Income > 0 || monthSum.Expense > 0
		monthsData[i] = monthData{
			month:   monthStart.Format("2006-01"),
			income:  monthSum.Income,
			expense: monthSum.Expense,
			hasData: hasData,
		}
	}

	// Calculate net worth for each month
	// Start from current month and work backwards
	runningNetWorth := currentAssets - currentDebts

	for i := 0; i < months; i++ {
		md := monthsData[i]
		monthStart := time.Date(now.Year(), now.Month()-time.Month(i), 1, 0, 0, 0, 0, time.Local)

		item := AssetTrendItem{
			Month:        md.month,
			MonthIncome:  md.income,
			MonthExpense: md.expense,
		}

		if monthStart.Equal(currentMonth) {
			// Current month: use actual current values
			item.TotalAssets = currentAssets
			item.TotalDebts = currentDebts
			item.NetWorth = runningNetWorth
		} else if md.hasData {
			// Has transaction data: calculate based on running total
			// Subtract this month's net change to get previous month's value
			netChange := md.income - md.expense
			runningNetWorth -= netChange
			item.NetWorth = runningNetWorth
			item.TotalAssets = runningNetWorth + currentDebts
			item.TotalDebts = currentDebts
		} else {
			// No data for this month: show 0
			item.NetWorth = 0
			item.TotalAssets = 0
			item.TotalDebts = 0
		}

		response.Items = append(response.Items, item)
	}

	// Reverse to chronological order
	for i, j := 0, len(response.Items)-1; i < j; i, j = i+1, j-1 {
		response.Items[i], response.Items[j] = response.Items[j], response.Items[i]
	}

	return response, nil
}

func isDebtAccountType(accType string) bool {
	debtTypes := map[string]bool{
		"credit_card":   true,
		"mortgage":      true,
		"car_loan":      true,
		"consumer_loan": true,
		"other_debt":    true,
	}
	return debtTypes[accType]
}
