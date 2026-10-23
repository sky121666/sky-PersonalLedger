package repository

import (
	"fmt"
	"strconv"
	"time"

	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/money"
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
	err := r.db.Preload("Account").Preload("Category", func(db *gorm.DB) *gorm.DB {
		return db.Unscoped().Where("user_id = (SELECT user_id FROM transactions WHERE id = ?)", id)
	}).Preload("ToAccount").
		First(&tx, "id = ?", id).Error
	if err != nil {
		return nil, err
	}
	return &tx, nil
}

func (r *TransactionRepository) GetByIDForUser(id string, userID uint) (*model.Transaction, error) {
	return r.GetByIDForUserWithDB(r.db, id, userID)
}

func (r *TransactionRepository) GetByIDForUserWithDB(db *gorm.DB, id string, userID uint) (*model.Transaction, error) {
	var tx model.Transaction
	err := db.Preload("Account").Preload("Category", func(db *gorm.DB) *gorm.DB {
		return db.Unscoped().Where("user_id = ?", userID)
	}).Preload("ToAccount").
		First(&tx, "id = ? AND user_id = ?", id, userID).Error
	if err != nil {
		return nil, err
	}
	return &tx, nil
}

type TransactionFilter struct {
	UserID          uint
	StartDate       *time.Time
	EndDate         *time.Time
	Type            string
	AccountID       string
	CategoryID      string
	MinAmount       *money.Amount
	MaxAmount       *money.Amount
	Keyword         string
	IncludeSystem   bool
	StatisticsScope bool
	Page            int
	PageSize        int
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
		query = query.Where("amount_cents >= ?", filter.MinAmount.Cents())
	}
	if filter.MaxAmount != nil {
		query = query.Where("amount_cents <= ?", filter.MaxAmount.Cents())
	}
	if filter.Keyword != "" {
		query = query.Where("remark LIKE ?", "%"+filter.Keyword+"%")
	}
	if filter.StatisticsScope {
		query = applySpendingStatisticsScope(query)
	} else if !filter.IncludeSystem {
		query = query.Where("COALESCE(source, '') <> ?", "system")
	}

	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	offset := (filter.Page - 1) * filter.PageSize
	err := query.Preload("Account").Preload("Category", func(db *gorm.DB) *gorm.DB {
		return db.Unscoped().Where("user_id = ?", filter.UserID)
	}).Preload("ToAccount").
		Order("transaction_date DESC, created_at DESC").
		Offset(offset).Limit(filter.PageSize).
		Find(&transactions).Error

	return transactions, total, err
}

func (r *TransactionRepository) Update(tx *model.Transaction) error {
	return r.db.Save(tx).Error
}

// UpdateImagesForUserWithDB updates only attachment metadata. It intentionally
// bypasses Save and model hooks so balance-bearing transaction fields and
// ledger audit rows cannot be changed by an attachment reconciliation request.
func (r *TransactionRepository) UpdateImagesForUserWithDB(db *gorm.DB, id string, userID uint, images string) error {
	return db.Model(&model.Transaction{}).
		Where("id = ? AND user_id = ?", id, userID).
		UpdateColumn("images", images).Error
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
		Select("category_id, SUM(amount_cents) as total, COUNT(*) as count").
		Where("user_id = ? AND type = ? AND transaction_date >= ? AND transaction_date <= ?",
			userID, txType, startDate, endDate)
	err := applySpendingStatisticsScope(query).
		Group("category_id").
		Find(&results).Error
	return results, err
}

type CategorySum struct {
	CategoryID string       `json:"category_id"`
	Total      money.Amount `json:"total"`
	Count      int          `json:"count"`
}

type ReportCategorySum struct {
	CategoryID   string       `gorm:"column:category_id"`
	CategoryName string       `gorm:"column:category_name"`
	CategoryIcon string       `gorm:"column:category_icon"`
	Total        money.Amount `gorm:"column:total"`
	Count        int          `gorm:"column:count"`
}

type MaxExpenseSummary struct {
	Amount       money.Amount `gorm:"column:amount"`
	Remark       string       `gorm:"column:remark"`
	CategoryName string       `gorm:"column:category_name"`
}

func (r *TransactionRepository) SumByCategoryForReport(userID uint, startDate, endDate time.Time, txType string) ([]ReportCategorySum, error) {
	var results []ReportCategorySum
	query := r.db.Model(&model.Transaction{}).
		Select(`
			transactions.category_id AS category_id,
			COALESCE(categories.name, '') AS category_name,
			COALESCE(categories.icon, '') AS category_icon,
			SUM(transactions.amount_cents) AS total,
			COUNT(*) AS count
		`).
		Joins("LEFT JOIN categories ON categories.id = transactions.category_id AND categories.user_id = transactions.user_id").
		Where("transactions.user_id = ? AND transactions.type = ? AND transactions.transaction_date >= ? AND transactions.transaction_date <= ?", userID, txType, startDate, endDate).
		Where("transactions.category_id IS NOT NULL AND transactions.category_id <> ''")
	err := applySpendingStatisticsScope(query).
		Group("transactions.category_id, categories.name, categories.icon").
		Order("total DESC, transactions.category_id ASC").
		Scan(&results).Error
	return results, err
}

func (r *TransactionRepository) CountDistinctDays(userID uint, startDate, endDate time.Time) (int, error) {
	var result struct {
		Count int `gorm:"column:count"`
	}
	dayExpression := r.transactionDayExpression()
	query := r.db.Model(&model.Transaction{}).
		Select(fmt.Sprintf("COUNT(DISTINCT %s) AS count", dayExpression)).
		Where("user_id = ? AND transaction_date >= ? AND transaction_date <= ?", userID, startDate, endDate)
	err := applySpendingStatisticsScope(query).Scan(&result).Error
	return result.Count, err
}

func (r *TransactionRepository) MaxExpenseForReport(userID uint, startDate, endDate time.Time) (MaxExpenseSummary, error) {
	var result MaxExpenseSummary
	query := r.db.Model(&model.Transaction{}).
		Select("transactions.amount_cents AS amount, transactions.remark, COALESCE(categories.name, '') AS category_name").
		Joins("LEFT JOIN categories ON categories.id = transactions.category_id AND categories.user_id = transactions.user_id").
		Where("transactions.user_id = ? AND transactions.type = ? AND transactions.transaction_date >= ? AND transactions.transaction_date <= ?", userID, "expense", startDate, endDate)
	err := applySpendingStatisticsScope(query).
		Order("transactions.amount_cents DESC, transactions.transaction_date DESC, transactions.id ASC").
		Limit(1).
		Scan(&result).Error
	return result, err
}

func (r *TransactionRepository) DistinctStatisticsYears(userID uint) ([]int, error) {
	var rows []struct {
		Year string `gorm:"column:tx_year"`
	}
	yearExpression := r.transactionYearExpression()
	query := r.db.Model(&model.Transaction{}).
		Select(fmt.Sprintf("DISTINCT %s AS tx_year", yearExpression)).
		Where("user_id = ?", userID)
	if err := applySpendingStatisticsScope(query).Order("tx_year DESC").Scan(&rows).Error; err != nil {
		return nil, err
	}
	years := make([]int, 0, len(rows))
	for _, row := range rows {
		year, err := strconv.Atoi(row.Year)
		if err == nil {
			years = append(years, year)
		}
	}
	return years, nil
}

type MemberExpenseSum struct {
	MemberID string       `json:"member_id"`
	Total    money.Amount `json:"total"`
	Count    int          `json:"count"`
}

type MemberCategoryExpenseSum struct {
	MemberID   string       `json:"member_id"`
	CategoryID string       `json:"category_id"`
	Total      money.Amount `json:"total"`
	Count      int          `json:"count"`
}

type AccountBalanceDeltaSum struct {
	AccountID    string       `json:"account_id"`
	BalanceDelta money.Amount `json:"balance_delta"`
}

func (r *TransactionRepository) SumExpenseByMember(userID uint, startDate, endDate time.Time) ([]MemberExpenseSum, error) {
	var results []MemberExpenseSum
	query := r.db.Model(&model.Transaction{}).
		Select("COALESCE(member_id, '') as member_id, SUM(amount_cents) as total, COUNT(*) as count").
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
	// External debt payments have no transaction projection. Include only their
	// active debt-side balance effects; even deleted projections block fallback.
	err := r.db.Raw(`
		SELECT account_totals.account_id, account_totals.balance_delta
		FROM (
		SELECT
			account_deltas.account_id,
			SUM(
				CASE
					WHEN account_deltas.direct_balance = 1 THEN account_deltas.cash_flow_delta
					WHEN accounts.type IN ? THEN -account_deltas.cash_flow_delta
					ELSE account_deltas.cash_flow_delta
				END
			) AS balance_delta
		FROM (
			SELECT
				account_id,
				CASE
					WHEN type = 'income' THEN amount_cents
					WHEN type = 'expense' THEN -amount_cents
					WHEN type = 'transfer' THEN -amount_cents
					ELSE 0
				END AS cash_flow_delta, 0 AS direct_balance
			FROM transactions
			WHERE user_id = ? AND transaction_date >= ? AND transaction_date <= ? AND deleted_at IS NULL
			UNION ALL
			SELECT to_account_id AS account_id, amount_cents AS cash_flow_delta, 0 AS direct_balance
			FROM transactions
			WHERE user_id = ? AND transaction_date >= ? AND transaction_date <= ? AND type = 'transfer' AND to_account_id IS NOT NULL AND to_account_id <> '' AND deleted_at IS NULL
			UNION ALL
			SELECT logs.account_id, logs.balance_after_cents - logs.balance_before_cents AS cash_flow_delta, 1 AS direct_balance
			FROM account_logs logs
			LEFT JOIN transactions payment ON payment.id = logs.transaction_id AND payment.user_id = logs.user_id
			WHERE logs.user_id = ? AND logs.reminder_id IS NOT NULL AND logs.type = 'adjustment'
			  AND (
			    ((logs.transaction_id IS NULL OR logs.transaction_id = '') AND logs.created_at >= ? AND logs.created_at <= ?)
			    OR (payment.id IS NOT NULL AND payment.deleted_at IS NULL AND payment.transaction_date >= ? AND payment.transaction_date <= ?
			      AND logs.account_id <> payment.account_id AND (payment.to_account_id IS NULL OR logs.account_id <> payment.to_account_id))
			  )
			UNION ALL
			SELECT logs.account_id, logs.balance_after_cents - logs.balance_before_cents AS cash_flow_delta, 1 AS direct_balance
			FROM account_logs logs
			JOIN debt_operations operation ON operation.id = logs.debt_operation_id AND operation.user_id = logs.user_id
			WHERE logs.user_id = ? AND logs.type = 'adjustment' AND logs.debt_effect_role = 'debt'
			  AND operation.kind = 'payment' AND operation.source_kind = 'external' AND operation.reversed_by IS NULL
			  AND (operation.source_account_id IS NULL OR operation.source_account_id = '')
			  AND logs.account_id = operation.account_id
			  AND operation.occurred_at >= ? AND operation.occurred_at <= ?
			  AND NOT EXISTS (
			    SELECT 1 FROM transactions projection
			    WHERE projection.user_id = logs.user_id AND projection.debt_operation_id = operation.id
			      AND (projection.account_id = logs.account_id OR projection.to_account_id = logs.account_id)
			  )
		) account_deltas
		JOIN accounts ON accounts.id = account_deltas.account_id AND accounts.user_id = ?
		WHERE account_deltas.account_id IS NOT NULL AND account_deltas.account_id <> ''
		GROUP BY account_deltas.account_id
		HAVING SUM(
			CASE
				WHEN account_deltas.direct_balance = 1 THEN account_deltas.cash_flow_delta
					WHEN accounts.type IN ? THEN -account_deltas.cash_flow_delta
				ELSE account_deltas.cash_flow_delta
			END
		) <> 0
		) account_totals
		ORDER BY ABS(account_totals.balance_delta) DESC, account_totals.account_id ASC
		LIMIT 10
	`, model.DebtAccountTypeValues(), userID, startDate, endDate, userID, startDate, endDate, userID, startDate, endDate, startDate, endDate,
		userID, startDate, endDate, userID, model.DebtAccountTypeValues()).Scan(&results).Error
	return results, err
}

func (r *TransactionRepository) SumExpenseByMemberAndCategory(userID uint, startDate, endDate time.Time) ([]MemberCategoryExpenseSum, error) {
	var results []MemberCategoryExpenseSum
	query := r.db.Model(&model.Transaction{}).
		Select("COALESCE(member_id, '') as member_id, COALESCE(category_id, '') as category_id, SUM(amount_cents) as total, COUNT(*) as count").
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
		Where("COALESCE(source, '') <> ?", "debt_principal").
		Where("(lending_id IS NULL OR lending_id = '')")
}

func (r *TransactionRepository) SumByDateRange(userID uint, startDate, endDate time.Time) (*DateRangeSum, error) {
	var result DateRangeSum
	query := r.db.Model(&model.Transaction{}).
		Select(`
			SUM(CASE WHEN type = 'income' THEN amount_cents ELSE 0 END) as income,
			SUM(CASE WHEN type = 'expense' THEN amount_cents ELSE 0 END) as expense,
			COUNT(*) as count
		`).
		Where("user_id = ? AND transaction_date >= ? AND transaction_date <= ?",
			userID, startDate, endDate)
	err := applySpendingStatisticsScope(query).
		Scan(&result).Error
	return &result, err
}

type DateRangeSum struct {
	Income  money.Amount `json:"income"`
	Expense money.Amount `json:"expense"`
	Count   int          `json:"count"`
}

type DailySum struct {
	Date    string       `gorm:"column:tx_date" json:"date"`
	Income  money.Amount `json:"income"`
	Expense money.Amount `json:"expense"`
}

func (r *TransactionRepository) SumByDay(userID uint, startDate, endDate time.Time) ([]DailySum, error) {
	var results []DailySum
	dayExpression := r.transactionDayExpression()
	query := r.db.Model(&model.Transaction{}).
		Select(fmt.Sprintf(`
			%s as tx_date,
			SUM(CASE WHEN type = 'income' THEN amount_cents ELSE 0 END) as income,
			SUM(CASE WHEN type = 'expense' THEN amount_cents ELSE 0 END) as expense
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
			SUM(CASE WHEN type = 'income' THEN amount_cents ELSE 0 END) as income,
			SUM(CASE WHEN type = 'expense' THEN amount_cents ELSE 0 END) as expense
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
			SUM(CASE WHEN type = 'income' THEN amount_cents ELSE 0 END) as income,
			SUM(CASE WHEN type = 'expense' THEN amount_cents ELSE 0 END) as expense
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
