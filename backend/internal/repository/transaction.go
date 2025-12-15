package repository

import (
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
	UserID     uint
	StartDate  *time.Time
	EndDate    *time.Time
	Type       string
	AccountID  string
	CategoryID string
	MinAmount  *float64
	MaxAmount  *float64
	Keyword    string
	Page       int
	PageSize   int
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
	err := r.db.Model(&model.Transaction{}).
		Select("category_id, SUM(amount) as total, COUNT(*) as count").
		Where("user_id = ? AND type = ? AND transaction_date >= ? AND transaction_date <= ?",
			userID, txType, startDate, endDate).
		Group("category_id").
		Find(&results).Error
	return results, err
}

type CategorySum struct {
	CategoryID string  `json:"category_id"`
	Total      float64 `json:"total"`
	Count      int     `json:"count"`
}

func (r *TransactionRepository) SumByDateRange(userID uint, startDate, endDate time.Time) (*DateRangeSum, error) {
	var result DateRangeSum
	err := r.db.Model(&model.Transaction{}).
		Select(`
			SUM(CASE WHEN type = 'income' THEN amount ELSE 0 END) as income,
			SUM(CASE WHEN type = 'expense' THEN amount ELSE 0 END) as expense,
			COUNT(*) as count
		`).
		Where("user_id = ? AND transaction_date >= ? AND transaction_date <= ?",
			userID, startDate, endDate).
		Scan(&result).Error
	return &result, err
}

type DateRangeSum struct {
	Income  float64 `json:"income"`
	Expense float64 `json:"expense"`
	Count   int     `json:"count"`
}

type DailySum struct {
	Date    string  `json:"date"`
	Income  float64 `json:"income"`
	Expense float64 `json:"expense"`
}

func (r *TransactionRepository) SumByDay(userID uint, startDate, endDate time.Time) ([]DailySum, error) {
	var results []DailySum
	err := r.db.Model(&model.Transaction{}).
		Select(`
			DATE(transaction_date) as date,
			SUM(CASE WHEN type = 'income' THEN amount ELSE 0 END) as income,
			SUM(CASE WHEN type = 'expense' THEN amount ELSE 0 END) as expense
		`).
		Where("user_id = ? AND transaction_date >= ? AND transaction_date <= ?",
			userID, startDate, endDate).
		Group("DATE(transaction_date)").
		Order("date ASC").
		Scan(&results).Error
	return results, err
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
