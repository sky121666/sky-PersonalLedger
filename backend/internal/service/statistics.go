package service

import (
	"strings"
	"time"

	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/money"
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
	Income           money.Amount `json:"income"`
	Expense          money.Amount `json:"expense"`
	Balance          money.Amount `json:"balance"`
	IncomeChange     float64      `json:"income_change"`
	ExpenseChange    float64      `json:"expense_change"`
	DailyAverage     money.Amount `json:"daily_average"`
	TransactionCount int          `json:"transaction_count"`
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
		Balance:          currentSum.Income.Sub(currentSum.Expense),
		TransactionCount: currentSum.Count,
	}

	daysInPeriod := statRange.ElapsedDays()
	if daysInPeriod > 0 {
		response.DailyAverage = currentSum.Expense.Divide(int64(daysInPeriod))
	}
	if prevSum != nil && prevSum.Income > 0 {
		response.IncomeChange = moneyChangePercentage(currentSum.Income, prevSum.Income)
	}
	if prevSum != nil && prevSum.Expense > 0 {
		response.ExpenseChange = moneyChangePercentage(currentSum.Expense, prevSum.Expense)
	}

	return response, nil
}

type CategoryStatItem struct {
	CategoryID   string       `json:"category_id"`
	CategoryName string       `json:"category_name"`
	Icon         string       `json:"icon"`
	Color        string       `json:"color"`
	Amount       money.Amount `json:"amount"`
	Percentage   float64      `json:"percentage"`
	Count        int          `json:"count"`
}

type CategoryStatResponse struct {
	Total money.Amount       `json:"total"`
	Items []CategoryStatItem `json:"items"`
}

type TrendItem struct {
	Date    string       `json:"date"`
	Income  money.Amount `json:"income"`
	Expense money.Amount `json:"expense"`
	Balance money.Amount `json:"balance"`
}

type TrendResponse struct {
	Items        []TrendItem  `json:"items"`
	TotalIncome  money.Amount `json:"total_income"`
	TotalExpense money.Amount `json:"total_expense"`
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
			Balance: ds.Income.Sub(ds.Expense),
		})
		response.TotalIncome = response.TotalIncome.Add(ds.Income)
		response.TotalExpense = response.TotalExpense.Add(ds.Expense)
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

	var total money.Amount
	for _, cs := range sums {
		total = total.Add(cs.Total)
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
			item.Percentage = moneyRatioPercentage(cs.Total, total)
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
	Month        string       `json:"month"`
	TotalAssets  money.Amount `json:"total_assets"`
	TotalDebts   money.Amount `json:"total_debts"`
	NetWorth     money.Amount `json:"net_worth"`
	MonthIncome  money.Amount `json:"month_income"`
	MonthExpense money.Amount `json:"month_expense"`
}

type AssetTrendResponse struct {
	Items           []AssetTrendItem `json:"items"`
	CurrentAssets   money.Amount     `json:"current_assets"`
	CurrentDebts    money.Amount     `json:"current_debts"`
	CurrentNetWorth money.Amount     `json:"current_net_worth"`
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

	var currentAssets, currentDebts money.Amount
	for _, acc := range accounts {
		if acc.DeletedAt.Valid {
			continue
		}
		accountAssets, accountDebts := classifyAccountBalance(acc.Type, acc.CurrentBalance)
		currentAssets = currentAssets.Add(accountAssets)
		currentDebts = currentDebts.Add(accountDebts)
	}

	response := &AssetTrendResponse{
		Items:           make([]AssetTrendItem, 0),
		CurrentAssets:   currentAssets,
		CurrentDebts:    currentDebts,
		CurrentNetWorth: currentAssets.Sub(currentDebts),
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
			NetWorth:     assets.Sub(debts),
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
) (money.Amount, money.Amount) {
	balances := make(map[string]money.Amount, len(snapshots))
	for _, snapshot := range snapshots {
		balances[snapshot.AccountID] = snapshot.Balance
	}
	var assets, debts money.Amount
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
		assets = assets.Add(accountAssets)
		debts = debts.Add(accountDebts)
	}
	return assets, debts
}

func moneyRatioPercentage(value, total money.Amount) float64 {
	if total.Cents() == 0 {
		return 0
	}
	return float64(value.Cents()) / float64(total.Cents()) * 100
}

func moneyChangePercentage(current, previous money.Amount) float64 {
	return moneyRatioPercentage(current.Sub(previous), previous)
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
