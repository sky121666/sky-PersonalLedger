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

type AccountBalanceSnapshot struct {
	AccountID string  `gorm:"column:account_id"`
	Balance   float64 `gorm:"column:balance"`
}

func (r *AccountLogRepository) LatestBalancesAt(userID uint, at time.Time) ([]AccountBalanceSnapshot, error) {
	var snapshots []AccountBalanceSnapshot
	err := r.db.Raw(`
		SELECT current_log.account_id, current_log.balance_after AS balance
		FROM account_logs AS current_log
		WHERE current_log.user_id = ?
		  AND current_log.created_at <= ?
		  AND NOT EXISTS (
			SELECT 1
			FROM account_logs AS newer_log
			WHERE newer_log.user_id = current_log.user_id
			  AND newer_log.account_id = current_log.account_id
			  AND newer_log.created_at <= ?
			  AND (
				newer_log.created_at > current_log.created_at
				OR (newer_log.created_at = current_log.created_at AND newer_log.id > current_log.id)
			  )
		  )
		ORDER BY current_log.account_id ASC
	`, userID, at, at).Scan(&snapshots).Error
	return snapshots, err
}

func (r *AccountLogRepository) Create(req *CreateAccountLogRequest) error {
	return r.CreateWithDB(r.db, req)
}

func (r *AccountLogRepository) CreateWithDB(db *gorm.DB, req *CreateAccountLogRequest) error {
	var accountCount int64
	if err := db.Model(&model.Account{}).
		Where("id = ? AND user_id = ?", req.AccountID, req.UserID).
		Count(&accountCount).Error; err != nil {
		return err
	}
	if accountCount != 1 {
		return gorm.ErrRecordNotFound
	}

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
	return db.Create(log).Error
}

func (r *AccountLogRepository) GetByAccountID(userID uint, accountID string, page, pageSize int) ([]model.AccountLog, int64, error) {
	var logs []model.AccountLog
	var total int64

	query := r.db.Model(&model.AccountLog{}).
		Where("user_id = ? AND account_id = ?", userID, accountID)
	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

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
	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	offset := (page - 1) * pageSize
	err := query.Order("created_at DESC").
		Preload("Account", "user_id = ?", userID).
		Offset(offset).
		Limit(pageSize).
		Find(&logs).Error

	return logs, total, err
}

func (r *AccountLogRepository) GetByTransactionID(userID uint, transactionID string) ([]model.AccountLog, error) {
	var logs []model.AccountLog
	err := r.db.Where("user_id = ? AND transaction_id = ?", userID, transactionID).
		Order("created_at DESC").
		Find(&logs).Error
	return logs, err
}
