package service

import (
	"strings"
	"time"

	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

type StatisticsService struct {
	txRepo       *repository.TransactionRepository
	categoryRepo *repository.CategoryRepository
	accountRepo  *repository.AccountRepository
	accountLogs  *repository.AccountLogRepository
}

func NewStatisticsService(
	txRepo *repository.TransactionRepository,
	categoryRepo *repository.CategoryRepository,
	accountRepo *repository.AccountRepository,
	accountLogs *repository.AccountLogRepository,
) *StatisticsService {
	return &StatisticsService{
		txRepo:       txRepo,
		categoryRepo: categoryRepo,
		accountRepo:  accountRepo,
		accountLogs:  accountLogs,
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
	return s.GetOverviewByPeriod(userID, month, "")
}

func (s *StatisticsService) GetOverviewByPeriod(userID uint, month, period string) (*OverviewResponse, error) {
	statRange, err := statisticsDateRange(month, period)
	if err != nil {
		return nil, err
	}
	startDate := statRange.Start
	endDate := statRange.End

	currentSum, err := s.txRepo.SumByDateRange(userID, startDate, endDate)
	if err != nil {
		return nil, err
	}

	prevStart, prevEnd := statRange.Previous()
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

	daysInPeriod := statRange.ElapsedDays()
	if daysInPeriod > 0 {
		response.DailyAverage = currentSum.Expense / float64(daysInPeriod)
	}
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
	return s.GetTrendByPeriod(userID, month, "")
}

func (s *StatisticsService) GetTrendByPeriod(userID uint, month, period string) (*TrendResponse, error) {
	statRange, err := statisticsDateRange(month, period)
	if err != nil {
		return nil, err
	}
	var sums []repository.DailySum
	switch statRange.Period {
	case "year":
		sums, err = s.txRepo.SumByMonth(userID, statRange.Start, statRange.End)
	case "history":
		sums, err = s.txRepo.SumByYear(userID, statRange.Start, statRange.End)
	default:
		sums, err = s.txRepo.SumByDay(userID, statRange.Start, statRange.End)
	}
	if err != nil {
		return nil, err
	}

	response := &TrendResponse{
		Items: make([]TrendItem, 0),
	}

	for _, ds := range sums {
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
	return s.GetCategoryStatsByPeriod(userID, month, "", txType)
}

func (s *StatisticsService) GetCategoryStatsByPeriod(userID uint, month, period, txType string) (*CategoryStatResponse, error) {
	statRange, err := statisticsDateRange(month, period)
	if err != nil {
		return nil, err
	}

	if txType == "" {
		txType = "expense"
	}

	sums, err := s.txRepo.SumByCategory(userID, statRange.Start, statRange.End, txType)
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
	if months > 120 {
		months = 120
	}

	accounts, err := s.accountRepo.GetByUserIDForHistory(userID)
	if err != nil {
		return nil, err
	}

	var currentAssets, currentDebts float64
	for _, acc := range accounts {
		if acc.DeletedAt.Valid {
			continue
		}
		accountAssets, accountDebts := classifyAccountBalance(acc.Type, acc.CurrentBalance)
		currentAssets += accountAssets
		currentDebts += accountDebts
	}

	response := &AssetTrendResponse{
		Items:           make([]AssetTrendItem, 0),
		CurrentAssets:   currentAssets,
		CurrentDebts:    currentDebts,
		CurrentNetWorth: currentAssets - currentDebts,
	}

	now := time.Now()
	currentMonthStart := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.Local)
	oldestMonthStart := currentMonthStart.AddDate(0, -(months - 1), 0)
	currentMonthEnd := currentMonthStart.AddDate(0, 1, 0).Add(-time.Nanosecond)
	monthlySums, err := s.txRepo.SumByMonth(userID, oldestMonthStart, currentMonthEnd)
	if err != nil {
		return nil, err
	}
	monthlyByDate := make(map[string]repository.DailySum, len(monthlySums))
	for _, sum := range monthlySums {
		monthlyByDate[sum.Date] = sum
	}

	for index := 0; index < months; index++ {
		monthStart := oldestMonthStart.AddDate(0, index, 0)
		monthKey := monthStart.Format("2006-01")
		monthSum := monthlyByDate[monthKey]
		assets := currentAssets
		debts := currentDebts
		if !monthStart.Equal(currentMonthStart) {
			monthEnd := monthStart.AddDate(0, 1, 0).Add(-time.Nanosecond)
			snapshots, err := s.accountLogs.LatestBalancesAt(userID, monthEnd)
			if err != nil {
				return nil, err
			}
			assets, debts = balancesFromAccountSnapshots(accounts, snapshots, monthEnd)
		}
		item := AssetTrendItem{
			Month:        monthKey,
			TotalAssets:  assets,
			TotalDebts:   debts,
			NetWorth:     assets - debts,
			MonthIncome:  monthSum.Income,
			MonthExpense: monthSum.Expense,
		}
		response.Items = append(response.Items, item)
	}

	return response, nil
}

func balancesFromAccountSnapshots(
	accounts []model.Account,
	snapshots []repository.AccountBalanceSnapshot,
	at time.Time,
) (float64, float64) {
	balances := make(map[string]float64, len(snapshots))
	for _, snapshot := range snapshots {
		balances[snapshot.AccountID] = snapshot.Balance
	}
	var assets, debts float64
	for _, account := range accounts {
		if !account.CreatedAt.IsZero() && account.CreatedAt.After(at) {
			continue
		}
		if account.DeletedAt.Valid && !account.DeletedAt.Time.After(at) {
			continue
		}
		balance, exists := balances[account.ID]
		if !exists {
			balance = account.InitialBalance
		}
		accountAssets, accountDebts := classifyAccountBalance(account.Type, balance)
		assets += accountAssets
		debts += accountDebts
	}
	return assets, debts
}

type statisticsRange struct {
	Period string
	Start  time.Time
	End    time.Time
}

func statisticsDateRange(month, period string) (statisticsRange, error) {
	anchor, err := statisticsAnchorMonth(month)
	if err != nil {
		return statisticsRange{}, err
	}
	normalizedPeriod := strings.ToLower(strings.TrimSpace(period))
	if normalizedPeriod == "" {
		normalizedPeriod = "month"
	}
	switch normalizedPeriod {
	case "year":
		start := time.Date(anchor.Year(), 1, 1, 0, 0, 0, 0, time.Local)
		return statisticsRange{
			Period: "year",
			Start:  start,
			End:    start.AddDate(1, 0, 0).Add(-time.Nanosecond),
		}, nil
	case "history", "past":
		currentYearStart := time.Date(anchor.Year(), 1, 1, 0, 0, 0, 0, time.Local)
		return statisticsRange{
			Period: "history",
			Start:  time.Date(1970, 1, 1, 0, 0, 0, 0, time.Local),
			End:    currentYearStart.Add(-time.Nanosecond),
		}, nil
	default:
		return statisticsRange{
			Period: "month",
			Start:  anchor,
			End:    anchor.AddDate(0, 1, 0).Add(-time.Nanosecond),
		}, nil
	}
}

func statisticsAnchorMonth(month string) (time.Time, error) {
	if strings.TrimSpace(month) == "" {
		now := time.Now()
		return time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.Local), nil
	}
	return time.ParseInLocation("2006-01", month, time.Local)
}

func (r statisticsRange) Previous() (time.Time, time.Time) {
	switch r.Period {
	case "year":
		prevStart := r.Start.AddDate(-1, 0, 0)
		return prevStart, r.Start.Add(-time.Nanosecond)
	case "history":
		return r.Start, r.Start.Add(-time.Nanosecond)
	default:
		prevStart := r.Start.AddDate(0, -1, 0)
		return prevStart, r.Start.Add(-time.Nanosecond)
	}
}

func (r statisticsRange) ElapsedDays() int {
	now := time.Now()
	end := r.End
	if now.After(r.Start) && now.Before(r.End) {
		end = now
	}
	if end.Before(r.Start) {
		return 0
	}
	return calendarDayDifference(r.Start, end) + 1
}
