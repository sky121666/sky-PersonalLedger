package repository

import (
	"fmt"
	"time"

	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

type TransactionRepository struct {
	db *gorm.DB
}

func NewTransactionRepository(db *gorm.DB) *TransactionRepository {
	return &TransactionRepository{db: db}
}

func (r *TransactionRepository) Create(tx *model.Transaction) error {
	return r.db.Create(tx).Error
}

func (r *TransactionRepository) GetByID(id string) (*model.Transaction, error) {
	var tx model.Transaction
	err := r.db.Preload("Account").Preload("Category").Preload("ToAccount").
		First(&tx, "id = ?", id).Error
	if err != nil {
		return nil, err
	}
	return &tx, nil
}

type TransactionFilter struct {
	UserID        uint
	StartDate     *time.Time
	EndDate       *time.Time
	Type          string
	AccountID     string
	CategoryID    string
	MinAmount     *float64
	MaxAmount     *float64
	Keyword       string
	IncludeSystem bool
	Page          int
	PageSize      int
}

func (r *TransactionRepository) List(filter TransactionFilter) ([]model.Transaction, int64, error) {
	var transactions []model.Transaction
	var total int64

	query := r.db.Model(&model.Transaction{}).Where("user_id = ?", filter.UserID)

	if filter.StartDate != nil {
		query = query.Where("transaction_date >= ?", filter.StartDate)
	}
	if filter.EndDate != nil {
		query = query.Where("transaction_date <= ?", filter.EndDate)
	}
	if filter.Type != "" {
		query = query.Where("type = ?", filter.Type)
	}
	if filter.AccountID != "" {
		query = query.Where("account_id = ? OR to_account_id = ?", filter.AccountID, filter.AccountID)
	}
	if filter.CategoryID != "" {
		query = query.Where("category_id = ?", filter.CategoryID)
	}
	if filter.MinAmount != nil {
		query = query.Where("amount >= ?", *filter.MinAmount)
	}
	if filter.MaxAmount != nil {
		query = query.Where("amount <= ?", *filter.MaxAmount)
	}
	if filter.Keyword != "" {
		query = query.Where("remark LIKE ?", "%"+filter.Keyword+"%")
	}
	if !filter.IncludeSystem {
		query = query.Where("COALESCE(source, '') <> ?", "system")
	}

	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	offset := (filter.Page - 1) * filter.PageSize
	err := query.Preload("Account").Preload("Category").Preload("ToAccount").
		Order("transaction_date DESC, created_at DESC").
		Offset(offset).Limit(filter.PageSize).
		Find(&transactions).Error

	return transactions, total, err
}

func (r *TransactionRepository) Update(tx *model.Transaction) error {
	return r.db.Save(tx).Error
}

func (r *TransactionRepository) Delete(id string) error {
	return r.db.Delete(&model.Transaction{}, "id = ?", id).Error
}

func (r *TransactionRepository) DeleteBatch(ids []string) error {
	return r.db.Delete(&model.Transaction{}, "id IN ?", ids).Error
}

func (r *TransactionRepository) SumByCategory(userID uint, startDate, endDate time.Time, txType string) ([]CategorySum, error) {
	var results []CategorySum
	query := r.db.Model(&model.Transaction{}).
		Select("category_id, SUM(amount) as total, COUNT(*) as count").
		Where("user_id = ? AND type = ? AND transaction_date >= ? AND transaction_date <= ?",
			userID, txType, startDate, endDate)
	err := applySpendingStatisticsScope(query).
		Group("category_id").
		Find(&results).Error
	return results, err
}

type CategorySum struct {
	CategoryID string  `json:"category_id"`
	Total      float64 `json:"total"`
	Count      int     `json:"count"`
}

type MemberExpenseSum struct {
	MemberID string  `json:"member_id"`
	Total    float64 `json:"total"`
	Count    int     `json:"count"`
}

type MemberCategoryExpenseSum struct {
	MemberID   string  `json:"member_id"`
	CategoryID string  `json:"category_id"`
	Total      float64 `json:"total"`
	Count      int     `json:"count"`
}

type AccountBalanceDeltaSum struct {
	AccountID    string  `json:"account_id"`
	BalanceDelta float64 `json:"balance_delta"`
}

func (r *TransactionRepository) SumExpenseByMember(userID uint, startDate, endDate time.Time) ([]MemberExpenseSum, error) {
	var results []MemberExpenseSum
	query := r.db.Model(&model.Transaction{}).
		Select("COALESCE(member_id, '') as member_id, SUM(amount) as total, COUNT(*) as count").
		Where("user_id = ? AND type = ? AND transaction_date >= ? AND transaction_date <= ?",
			userID, "expense", startDate, endDate)
	err := applyMemberExpenseStatisticsScope(query).
		Group("COALESCE(member_id, '')").
		Order("total DESC").
		Find(&results).Error
	return results, err
}

func (r *TransactionRepository) SumBalanceDeltaByAccount(userID uint, startDate, endDate time.Time) ([]AccountBalanceDeltaSum, error) {
	var results []AccountBalanceDeltaSum
	err := r.db.Raw(`
		SELECT account_id, SUM(balance_delta) AS balance_delta
		FROM (
			SELECT
				account_id,
				CASE
					WHEN type = 'income' THEN amount
					WHEN type = 'expense' THEN -amount
					WHEN type = 'transfer' THEN -amount
					ELSE 0
				END AS balance_delta
			FROM transactions
			WHERE user_id = ? AND transaction_date >= ? AND transaction_date <= ? AND deleted_at IS NULL
			UNION ALL
			SELECT to_account_id AS account_id, amount AS balance_delta
			FROM transactions
			WHERE user_id = ? AND transaction_date >= ? AND transaction_date <= ? AND type = 'transfer' AND to_account_id IS NOT NULL AND to_account_id <> '' AND deleted_at IS NULL
		) account_deltas
		WHERE account_id IS NOT NULL AND account_id <> ''
		GROUP BY account_id
		HAVING SUM(balance_delta) <> 0
		ORDER BY ABS(SUM(balance_delta)) DESC, account_id ASC
		LIMIT 10
	`, userID, startDate, endDate, userID, startDate, endDate).Scan(&results).Error
	return results, err
}

func (r *TransactionRepository) SumExpenseByMemberAndCategory(userID uint, startDate, endDate time.Time) ([]MemberCategoryExpenseSum, error) {
	var results []MemberCategoryExpenseSum
	query := r.db.Model(&model.Transaction{}).
		Select("COALESCE(member_id, '') as member_id, COALESCE(category_id, '') as category_id, SUM(amount) as total, COUNT(*) as count").
		Where("user_id = ? AND type = ? AND transaction_date >= ? AND transaction_date <= ?",
			userID, "expense", startDate, endDate)
	err := applyMemberExpenseStatisticsScope(query).
		Group("COALESCE(member_id, ''), COALESCE(category_id, '')").
		Find(&results).Error
	return results, err
}

func applyMemberExpenseStatisticsScope(query *gorm.DB) *gorm.DB {
	return applySpendingStatisticsScope(query)
}

func applySpendingStatisticsScope(query *gorm.DB) *gorm.DB {
	return query.
		Where("COALESCE(source, '') <> ?", "system").
		Where("(lending_id IS NULL OR lending_id = '')")
}

func (r *TransactionRepository) SumByDateRange(userID uint, startDate, endDate time.Time) (*DateRangeSum, error) {
	var result DateRangeSum
	query := r.db.Model(&model.Transaction{}).
		Select(`
			SUM(CASE WHEN type = 'income' THEN amount ELSE 0 END) as income,
			SUM(CASE WHEN type = 'expense' THEN amount ELSE 0 END) as expense,
			COUNT(*) as count
		`).
		Where("user_id = ? AND transaction_date >= ? AND transaction_date <= ?",
			userID, startDate, endDate)
	err := applySpendingStatisticsScope(query).
		Scan(&result).Error
	return &result, err
}

type DateRangeSum struct {
	Income  float64 `json:"income"`
	Expense float64 `json:"expense"`
	Count   int     `json:"count"`
}

type DailySum struct {
	Date    string  `gorm:"column:tx_date" json:"date"`
	Income  float64 `json:"income"`
	Expense float64 `json:"expense"`
}

func (r *TransactionRepository) SumByDay(userID uint, startDate, endDate time.Time) ([]DailySum, error) {
	var results []DailySum
	dayExpression := r.transactionDayExpression()
	query := r.db.Model(&model.Transaction{}).
		Select(fmt.Sprintf(`
			%s as tx_date,
			SUM(CASE WHEN type = 'income' THEN amount ELSE 0 END) as income,
			SUM(CASE WHEN type = 'expense' THEN amount ELSE 0 END) as expense
		`, dayExpression)).
		Where("user_id = ? AND transaction_date >= ? AND transaction_date <= ?",
			userID, startDate, endDate)
	err := applySpendingStatisticsScope(query).
		Group(dayExpression).
		Order(dayExpression + " ASC").
		Scan(&results).Error
	return results, err
}

func (r *TransactionRepository) SumByMonth(userID uint, startDate, endDate time.Time) ([]DailySum, error) {
	var results []DailySum
	monthExpression := r.transactionMonthExpression()
	query := r.db.Model(&model.Transaction{}).
		Select(fmt.Sprintf(`
			%s as tx_date,
			SUM(CASE WHEN type = 'income' THEN amount ELSE 0 END) as income,
			SUM(CASE WHEN type = 'expense' THEN amount ELSE 0 END) as expense
		`, monthExpression)).
		Where("user_id = ? AND transaction_date >= ? AND transaction_date <= ?",
			userID, startDate, endDate)
	err := applySpendingStatisticsScope(query).
		Group(monthExpression).
		Order(monthExpression + " ASC").
		Scan(&results).Error
	return results, err
}

func (r *TransactionRepository) SumByYear(userID uint, startDate, endDate time.Time) ([]DailySum, error) {
	var results []DailySum
	yearExpression := r.transactionYearExpression()
	query := r.db.Model(&model.Transaction{}).
		Select(fmt.Sprintf(`
			%s as tx_date,
			SUM(CASE WHEN type = 'income' THEN amount ELSE 0 END) as income,
			SUM(CASE WHEN type = 'expense' THEN amount ELSE 0 END) as expense
		`, yearExpression)).
		Where("user_id = ? AND transaction_date >= ? AND transaction_date <= ?",
			userID, startDate, endDate)
	err := applySpendingStatisticsScope(query).
		Group(yearExpression).
		Order(yearExpression + " ASC").
		Scan(&results).Error
	return results, err
}

func (r *TransactionRepository) transactionDayExpression() string {
	switch r.db.Dialector.Name() {
	case "postgres":
		return "TO_CHAR(transaction_date, 'YYYY-MM-DD')"
	case "mysql":
		return "DATE_FORMAT(transaction_date, '%Y-%m-%d')"
	default:
		return "SUBSTR(transaction_date, 1, 10)"
	}
}

func (r *TransactionRepository) transactionMonthExpression() string {
	switch r.db.Dialector.Name() {
	case "postgres":
		return "TO_CHAR(transaction_date, 'YYYY-MM')"
	case "mysql":
		return "DATE_FORMAT(transaction_date, '%Y-%m')"
	default:
		return "SUBSTR(transaction_date, 1, 7)"
	}
}

func (r *TransactionRepository) transactionYearExpression() string {
	switch r.db.Dialector.Name() {
	case "postgres":
		return "TO_CHAR(transaction_date, 'YYYY')"
	case "mysql":
		return "DATE_FORMAT(transaction_date, '%Y')"
	default:
		return "SUBSTR(transaction_date, 1, 4)"
	}
}

func (r *TransactionRepository) GetAllForExport(userID uint, startDate, endDate *time.Time) ([]model.Transaction, error) {
	var transactions []model.Transaction
	query := r.db.Where("user_id = ?", userID)

	if startDate != nil {
		query = query.Where("transaction_date >= ?", startDate)
	}
	if endDate != nil {
		query = query.Where("transaction_date <= ?", endDate)
	}

	err := query.Preload("Account").Preload("Category").Preload("ToAccount").
		Order("transaction_date DESC").
		Find(&transactions).Error
	return transactions, err
}

func (r *TransactionRepository) DeleteAllByUserID(userID uint) error {
	return r.db.Where("user_id = ?", userID).Delete(&model.Transaction{}).Error
}

func (r *TransactionRepository) DB() *gorm.DB {
	return r.db
}
