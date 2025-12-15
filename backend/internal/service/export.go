package service

import (
	"bytes"
	"encoding/csv"
	"fmt"
	"time"

	"github.com/sky/personal-ledger/internal/repository"
)

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
	// Parse dates
	var startDate, endDate *time.Time
	if filter.StartDate != "" {
		t, err := time.Parse("2006-01-02", filter.StartDate)
		if err == nil {
			startDate = &t
		}
	}
	if filter.EndDate != "" {
		t, err := time.Parse("2006-01-02", filter.EndDate)
		if err == nil {
			// Set to end of day (23:59:59)
			endOfDay := t.Add(23*time.Hour + 59*time.Minute + 59*time.Second)
			endDate = &endOfDay
		}
	}

	// Get transactions
	transactions, _, err := s.txRepo.List(repository.TransactionFilter{
		UserID:    userID,
		StartDate: startDate,
		EndDate:   endDate,
		Type:      filter.Type,
		AccountID: filter.AccountID,
		PageSize:  10000, // Large limit for export
	})
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
			fmt.Sprintf("%.2f", tx.Amount),
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

// YearlyReport represents annual statistics
type YearlyReport struct {
	Year             int            `json:"year"`
	TotalIncome      float64        `json:"total_income"`
	TotalExpense     float64        `json:"total_expense"`
	NetSavings       float64        `json:"net_savings"`
	SavingsRate      float64        `json:"savings_rate"`
	MonthlyData      []MonthlyData  `json:"monthly_data"`
	TopExpenses      []CategoryStat `json:"top_expenses"`
	TopIncomes       []CategoryStat `json:"top_incomes"`
	TransactionCount int            `json:"transaction_count"`
	AverageExpense   float64        `json:"average_expense"`
	AverageIncome    float64        `json:"average_income"`
	MaxExpenseMonth  string         `json:"max_expense_month"`
	MinExpenseMonth  string         `json:"min_expense_month"`
	BestSavingsMonth string         `json:"best_savings_month"`
	MaxSingleExpense float64        `json:"max_single_expense"`
	MaxExpenseRemark string         `json:"max_expense_remark"`
	ActiveDays       int            `json:"active_days"`
	DailyAvgExpense  float64        `json:"daily_avg_expense"`
}

type MonthlyData struct {
	Month   string  `json:"month"`
	Income  float64 `json:"income"`
	Expense float64 `json:"expense"`
	Balance float64 `json:"balance"`
}

type CategoryStat struct {
	CategoryID   string  `json:"category_id"`
	CategoryName string  `json:"category_name"`
	CategoryIcon string  `json:"category_icon"`
	Amount       float64 `json:"amount"`
	Percentage   float64 `json:"percentage"`
	Count        int     `json:"count"`
}

// GetYearlyReport generates annual report
func (s *ExportService) GetYearlyReport(userID uint, year int) (*YearlyReport, error) {
	startDate := time.Date(year, 1, 1, 0, 0, 0, 0, time.Local)
	endDate := time.Date(year, 12, 31, 23, 59, 59, 0, time.Local)

	// Get all transactions for the year
	transactions, _, err := s.txRepo.List(repository.TransactionFilter{
		UserID:    userID,
		StartDate: &startDate,
		EndDate:   &endDate,
		PageSize:  100000,
	})
	if err != nil {
		return nil, err
	}

	report := &YearlyReport{
		Year:        year,
		MonthlyData: make([]MonthlyData, 12),
	}

	// Initialize monthly data
	monthNames := []string{"1月", "2月", "3月", "4月", "5月", "6月", "7月", "8月", "9月", "10月", "11月", "12月"}
	for i := 0; i < 12; i++ {
		report.MonthlyData[i] = MonthlyData{Month: monthNames[i]}
	}

	// Category aggregation maps
	expenseByCategory := make(map[string]*CategoryStat)
	incomeByCategory := make(map[string]*CategoryStat)

	var maxExpense, minExpense float64 = 0, 999999999
	var maxMonth, minMonth int = 0, 0
	var maxSingleExpense float64 = 0
	var maxExpenseRemark string = ""
	activeDays := make(map[string]bool)

	// Process transactions
	for _, tx := range transactions {
		// Track active days
		dayKey := tx.TransactionDate.Format("2006-01-02")
		activeDays[dayKey] = true
		month := int(tx.TransactionDate.Month()) - 1
		report.TransactionCount++

		if tx.Type == "income" {
			report.TotalIncome += tx.Amount
			report.MonthlyData[month].Income += tx.Amount

			if tx.CategoryID != nil {
				if _, ok := incomeByCategory[*tx.CategoryID]; !ok {
					incomeByCategory[*tx.CategoryID] = &CategoryStat{
						CategoryID: *tx.CategoryID,
					}
					if tx.Category != nil {
						incomeByCategory[*tx.CategoryID].CategoryName = tx.Category.Name
						incomeByCategory[*tx.CategoryID].CategoryIcon = tx.Category.Icon
					}
				}
				incomeByCategory[*tx.CategoryID].Amount += tx.Amount
				incomeByCategory[*tx.CategoryID].Count++
			}
		} else if tx.Type == "expense" {
			report.TotalExpense += tx.Amount
			report.MonthlyData[month].Expense += tx.Amount

			// Track max single expense
			if tx.Amount > maxSingleExpense {
				maxSingleExpense = tx.Amount
				maxExpenseRemark = tx.Remark
				if tx.Category != nil {
					maxExpenseRemark = tx.Category.Name
					if tx.Remark != "" {
						maxExpenseRemark += ": " + tx.Remark
					}
				}
			}

			if tx.CategoryID != nil {
				if _, ok := expenseByCategory[*tx.CategoryID]; !ok {
					expenseByCategory[*tx.CategoryID] = &CategoryStat{
						CategoryID: *tx.CategoryID,
					}
					if tx.Category != nil {
						expenseByCategory[*tx.CategoryID].CategoryName = tx.Category.Name
						expenseByCategory[*tx.CategoryID].CategoryIcon = tx.Category.Icon
					}
				}
				expenseByCategory[*tx.CategoryID].Amount += tx.Amount
				expenseByCategory[*tx.CategoryID].Count++
			}
		}
	}

	// Calculate monthly balance and find max/min
	var bestSavings float64 = -999999999
	var bestSavingsMonth int = 0
	for i := 0; i < 12; i++ {
		report.MonthlyData[i].Balance = report.MonthlyData[i].Income - report.MonthlyData[i].Expense
		if report.MonthlyData[i].Expense > maxExpense {
			maxExpense = report.MonthlyData[i].Expense
			maxMonth = i
		}
		if report.MonthlyData[i].Expense < minExpense && report.MonthlyData[i].Expense > 0 {
			minExpense = report.MonthlyData[i].Expense
			minMonth = i
		}
		if report.MonthlyData[i].Balance > bestSavings {
			bestSavings = report.MonthlyData[i].Balance
			bestSavingsMonth = i
		}
	}

	// Calculate totals
	report.NetSavings = report.TotalIncome - report.TotalExpense
	if report.TotalIncome > 0 {
		report.SavingsRate = (report.NetSavings / report.TotalIncome) * 100
	}
	if report.TransactionCount > 0 {
		report.AverageExpense = report.TotalExpense / 12
	}
	report.MaxExpenseMonth = monthNames[maxMonth]
	report.MinExpenseMonth = monthNames[minMonth]
	report.BestSavingsMonth = monthNames[bestSavingsMonth]
	report.MaxSingleExpense = maxSingleExpense
	report.MaxExpenseRemark = maxExpenseRemark
	report.ActiveDays = len(activeDays)
	report.AverageIncome = report.TotalIncome / 12
	if report.ActiveDays > 0 {
		report.DailyAvgExpense = report.TotalExpense / float64(report.ActiveDays)
	}

	// Convert maps to sorted slices (top 10)
	report.TopExpenses = mapToSortedSlice(expenseByCategory, report.TotalExpense, 10)
	report.TopIncomes = mapToSortedSlice(incomeByCategory, report.TotalIncome, 10)

	return report, nil
}

func mapToSortedSlice(m map[string]*CategoryStat, total float64, limit int) []CategoryStat {
	result := make([]CategoryStat, 0, len(m))
	for _, v := range m {
		if total > 0 {
			v.Percentage = (v.Amount / total) * 100
		}
		result = append(result, *v)
	}

	// Sort by amount descending
	for i := 0; i < len(result)-1; i++ {
		for j := i + 1; j < len(result); j++ {
			if result[j].Amount > result[i].Amount {
				result[i], result[j] = result[j], result[i]
			}
		}
	}

	if len(result) > limit {
		return result[:limit]
	}
	return result
}

// GetAvailableYears returns years that have transactions
func (s *ExportService) GetAvailableYears(userID uint) ([]int, error) {
	// Get transactions and extract distinct years
	transactions, _, err := s.txRepo.List(repository.TransactionFilter{
		UserID:   userID,
		PageSize: 100000,
	})
	if err != nil {
		return nil, err
	}

	yearMap := make(map[int]bool)
	for _, tx := range transactions {
		yearMap[tx.TransactionDate.Year()] = true
	}

	years := make([]int, 0, len(yearMap))
	for y := range yearMap {
		years = append(years, y)
	}

	// Sort descending
	for i := 0; i < len(years)-1; i++ {
		for j := i + 1; j < len(years); j++ {
			if years[j] > years[i] {
				years[i], years[j] = years[j], years[i]
			}
		}
	}

	return years, nil
}
