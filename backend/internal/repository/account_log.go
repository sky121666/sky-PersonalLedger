package repository

import (
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

type AccountLogRepository struct {
	db *gorm.DB
}

func NewAccountLogRepository(db *gorm.DB) *AccountLogRepository {
	return &AccountLogRepository{db: db}
}

type CreateAccountLogRequest struct {
	UserID        uint
	AccountID     string
	Type          string // income, expense, transfer_in, transfer_out, rollback, adjustment
	Amount        float64
	BalanceBefore float64
	BalanceAfter  float64
	TransactionID *string
	ReminderID    *string
	LendingID     *string
	Remark        string
}

func (r *AccountLogRepository) Create(req *CreateAccountLogRequest) error {
	log := &model.AccountLog{
		ID:            uuid.New().String(),
		UserID:        req.UserID,
		AccountID:     req.AccountID,
		Type:          req.Type,
		Amount:        req.Amount,
		BalanceBefore: req.BalanceBefore,
		BalanceAfter:  req.BalanceAfter,
		TransactionID: req.TransactionID,
		ReminderID:    req.ReminderID,
		LendingID:     req.LendingID,
		Remark:        req.Remark,
		CreatedAt:     time.Now(),
	}
	return r.db.Create(log).Error
}

func (r *AccountLogRepository) GetByAccountID(accountID string, page, pageSize int) ([]model.AccountLog, int64, error) {
	var logs []model.AccountLog
	var total int64

	query := r.db.Model(&model.AccountLog{}).Where("account_id = ?", accountID)
	query.Count(&total)

	offset := (page - 1) * pageSize
	err := query.Order("created_at DESC").
		Offset(offset).
		Limit(pageSize).
		Find(&logs).Error

	return logs, total, err
}

func (r *AccountLogRepository) GetByUserID(userID uint, page, pageSize int) ([]model.AccountLog, int64, error) {
	var logs []model.AccountLog
	var total int64

	query := r.db.Model(&model.AccountLog{}).Where("user_id = ?", userID)
	query.Count(&total)

	offset := (page - 1) * pageSize
	err := query.Order("created_at DESC").
		Preload("Account").
		Offset(offset).
		Limit(pageSize).
		Find(&logs).Error

	return logs, total, err
}

func (r *AccountLogRepository) GetByTransactionID(transactionID string) ([]model.AccountLog, error) {
	var logs []model.AccountLog
	err := r.db.Where("transaction_id = ?", transactionID).
		Order("created_at DESC").
		Find(&logs).Error
	return logs, err
}
