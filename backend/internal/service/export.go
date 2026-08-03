package service

import (
	"bytes"
	"encoding/csv"
	"fmt"
	"time"

	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/money"
	"github.com/sky/personal-ledger/internal/repository"
)

const transactionExportPageSize = 10000

type ExportService struct {
	txRepo       *repository.TransactionRepository
	categoryRepo *repository.CategoryRepository
	accountRepo  *repository.AccountRepository
}

func NewExportService(
	txRepo *repository.TransactionRepository,
	categoryRepo *repository.CategoryRepository,
	accountRepo *repository.AccountRepository,
) *ExportService {
	return &ExportService{
		txRepo:       txRepo,
		categoryRepo: categoryRepo,
		accountRepo:  accountRepo,
	}
}

type ExportFilter struct {
	StartDate string
	EndDate   string
	Type      string
	AccountID string
}

// ExportTransactionsCSV exports transactions to CSV format
func (s *ExportService) ExportTransactionsCSV(userID uint, filter ExportFilter) ([]byte, error) {
	startDate, endDate, err := exportDateRange(filter.StartDate, filter.EndDate)
	if err != nil {
		return nil, err
	}

	transactions, err := s.listTransactionsForExport(
		userID,
		filter,
		startDate,
		endDate,
		transactionExportPageSize,
	)
	if err != nil {
		return nil, err
	}

	// Create CSV
	var buf bytes.Buffer
	// Add BOM for Excel UTF-8 compatibility
	buf.Write([]byte{0xEF, 0xBB, 0xBF})

	writer := csv.NewWriter(&buf)

	// Write header
	header := []string{"日期", "类型", "分类", "金额", "账户", "备注"}
	if err := writer.Write(header); err != nil {
		return nil, err
	}

	// Write data
	for _, tx := range transactions {
		typeStr := "支出"
		if tx.Type == "income" {
			typeStr = "收入"
		} else if tx.Type == "transfer" {
			typeStr = "转账"
		}

		categoryName := ""
		if tx.Category != nil {
			categoryName = tx.Category.Name
		}

		accountName := ""
		if tx.Account != nil {
			accountName = tx.Account.Name
		}

		row := []string{
			tx.TransactionDate.Format("2006-01-02 15:04"),
			typeStr,
			categoryName,
			fmt.Sprintf("%.2f", tx.Amount.Float64()),
			accountName,
			tx.Remark,
		}
		if err := writer.Write(row); err != nil {
			return nil, err
		}
	}

	writer.Flush()
	return buf.Bytes(), nil
}

func (s *ExportService) listTransactionsForExport(
	userID uint,
	filter ExportFilter,
	startDate, endDate *time.Time,
	pageSize int,
) ([]model.Transaction, error) {
	if pageSize <= 0 {
		pageSize = transactionExportPageSize
	}

	transactions := make([]model.Transaction, 0)
	for page := 1; ; page++ {
		batch, total, err := s.txRepo.List(repository.TransactionFilter{
			UserID:    userID,
			StartDate: startDate,
			EndDate:   endDate,
			Type:      filter.Type,
			AccountID: filter.AccountID,
			Page:      page,
			PageSize:  pageSize,
		})
		if err != nil {
			return nil, err
		}
		transactions = append(transactions, batch...)
		if len(batch) == 0 || int64(len(transactions)) >= total {
			return transactions, nil
		}
	}
}

func exportDateRange(startValue, endValue string) (*time.Time, *time.Time, error) {
	var startDate, endDate *time.Time
	if startValue != "" {
		parsed, err := time.ParseInLocation("2006-01-02", startValue, time.Local)
		if err != nil {
			return nil, nil, err
		}
		startDate = &parsed
	}
	if endValue != "" {
		parsed, err := time.ParseInLocation("2006-01-02", endValue, time.Local)
		if err != nil {
			return nil, nil, err
		}
		endOfDay := parsed.AddDate(0, 0, 1).Add(-time.Nanosecond)
		endDate = &endOfDay
	}
	return startDate, endDate, nil
}

// YearlyReport represents annual statistics
type YearlyReport struct {
	Year             int            `json:"year"`
	TotalIncome      money.Amount   `json:"total_income"`
	TotalExpense     money.Amount   `json:"total_expense"`
	NetSavings       money.Amount   `json:"net_savings"`
	SavingsRate      float64        `json:"savings_rate"`
	MonthlyData      []MonthlyData  `json:"monthly_data"`
	TopExpenses      []CategoryStat `json:"top_expenses"`
	TopIncomes       []CategoryStat `json:"top_incomes"`
	TransactionCount int            `json:"transaction_count"`
	AverageExpense   money.Amount   `json:"average_expense"`
	AverageIncome    money.Amount   `json:"average_income"`
	MaxExpenseMonth  string         `json:"max_expense_month"`
	MinExpenseMonth  string         `json:"min_expense_month"`
	BestSavingsMonth string         `json:"best_savings_month"`
	MaxSingleExpense money.Amount   `json:"max_single_expense"`
	MaxExpenseRemark string         `json:"max_expense_remark"`
	ActiveDays       int            `json:"active_days"`
	DailyAvgExpense  money.Amount   `json:"daily_avg_expense"`
}

type MonthlyData struct {
	Month   string       `json:"month"`
	Income  money.Amount `json:"income"`
	Expense money.Amount `json:"expense"`
	Balance money.Amount `json:"balance"`
}

type CategoryStat struct {
	CategoryID   string       `json:"category_id"`
	CategoryName string       `json:"category_name"`
	CategoryIcon string       `json:"category_icon"`
	Amount       money.Amount `json:"amount"`
	Percentage   float64      `json:"percentage"`
	Count        int          `json:"count"`
}

// GetYearlyReport generates an annual report from bounded SQL aggregates.
func (s *ExportService) GetYearlyReport(userID uint, year int) (*YearlyReport, error) {
	startDate := time.Date(year, 1, 1, 0, 0, 0, 0, time.Local)
	endDate := startDate.AddDate(1, 0, 0).Add(-time.Nanosecond)

	totals, err := s.txRepo.SumByDateRange(userID, startDate, endDate)
	if err != nil {
		return nil, err
	}
	monthlySums, err := s.txRepo.SumByMonth(userID, startDate, endDate)
	if err != nil {
		return nil, err
	}
	expenseCategories, err := s.txRepo.SumByCategoryForReport(userID, startDate, endDate, "expense")
	if err != nil {
		return nil, err
	}
	incomeCategories, err := s.txRepo.SumByCategoryForReport(userID, startDate, endDate, "income")
	if err != nil {
		return nil, err
	}
	activeDays, err := s.txRepo.CountDistinctDays(userID, startDate, endDate)
	if err != nil {
		return nil, err
	}
	maxSingleExpense, err := s.txRepo.MaxExpenseForReport(userID, startDate, endDate)
	if err != nil {
		return nil, err
	}

	report := &YearlyReport{
		Year:             year,
		TotalIncome:      totals.Income,
		TotalExpense:     totals.Expense,
		TransactionCount: totals.Count,
		ActiveDays:       activeDays,
		MaxSingleExpense: maxSingleExpense.Amount,
		MonthlyData:      make([]MonthlyData, 12),
	}
	monthNames := []string{"1月", "2月", "3月", "4月", "5月", "6月", "7月", "8月", "9月", "10月", "11月", "12月"}
	for index := range report.MonthlyData {
		report.MonthlyData[index] = MonthlyData{Month: monthNames[index]}
	}
	for _, monthly := range monthlySums {
		parsedMonth, err := time.Parse("2006-01", monthly.Date)
		if err != nil || parsedMonth.Year() != year {
			continue
		}
		index := int(parsedMonth.Month()) - 1
		report.MonthlyData[index].Income = monthly.Income
		report.MonthlyData[index].Expense = monthly.Expense
	}

	var maxExpense money.Amount
	var minExpense money.Amount
	maxMonth := 0
	minMonth := 0
	var bestSavings money.Amount
	bestSavingsSet := false
	bestSavingsMonth := 0
	for index := range report.MonthlyData {
		monthly := &report.MonthlyData[index]
		monthly.Balance = monthly.Income.Sub(monthly.Expense)
		if monthly.Expense > maxExpense {
			maxExpense = monthly.Expense
			maxMonth = index
		}
		if monthly.Expense > 0 && (minExpense == 0 || monthly.Expense < minExpense) {
			minExpense = monthly.Expense
			minMonth = index
		}
		if !bestSavingsSet || monthly.Balance > bestSavings {
			bestSavings = monthly.Balance
			bestSavingsMonth = index
			bestSavingsSet = true
		}
	}

	report.NetSavings = report.TotalIncome.Sub(report.TotalExpense)
	if report.TotalIncome > 0 {
		report.SavingsRate = float64(report.NetSavings.Cents()) / float64(report.TotalIncome.Cents()) * 100
	}
	report.AverageExpense = report.TotalExpense.Divide(12)
	report.AverageIncome = report.TotalIncome.Divide(12)
	report.MaxExpenseMonth = monthNames[maxMonth]
	report.MinExpenseMonth = monthNames[minMonth]
	report.BestSavingsMonth = monthNames[bestSavingsMonth]
	report.MaxExpenseRemark = maxSingleExpense.Remark
	if maxSingleExpense.CategoryName != "" {
		report.MaxExpenseRemark = maxSingleExpense.CategoryName
		if maxSingleExpense.Remark != "" {
			report.MaxExpenseRemark += ": " + maxSingleExpense.Remark
		}
	}
	if report.ActiveDays > 0 {
		report.DailyAvgExpense = report.TotalExpense.Divide(int64(report.ActiveDays))
	}
	report.TopExpenses = reportCategorySumsToStats(expenseCategories, report.TotalExpense, 10)
	report.TopIncomes = reportCategorySumsToStats(incomeCategories, report.TotalIncome, 10)
	return report, nil
}

func reportCategorySumsToStats(sums []repository.ReportCategorySum, total money.Amount, limit int) []CategoryStat {
	if limit > 0 && len(sums) > limit {
		sums = sums[:limit]
	}
	result := make([]CategoryStat, 0, len(sums))
	for _, sum := range sums {
		item := CategoryStat{
			CategoryID: sum.CategoryID, CategoryName: sum.CategoryName, CategoryIcon: sum.CategoryIcon,
			Amount: sum.Total, Count: sum.Count,
		}
		if total > 0 {
			item.Percentage = float64(sum.Total.Cents()) / float64(total.Cents()) * 100
		}
		result = append(result, item)
	}
	return result
}

// GetAvailableYears returns years that have transactions
func (s *ExportService) GetAvailableYears(userID uint) ([]int, error) {
	return s.txRepo.DistinctStatisticsYears(userID)
}
