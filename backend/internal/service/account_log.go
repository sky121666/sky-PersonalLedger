package service

import (
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

type AccountLogService struct {
	logRepo     *repository.AccountLogRepository
	accountRepo *repository.AccountRepository
}

func NewAccountLogService(logRepo *repository.AccountLogRepository, accountRepo *repository.AccountRepository) *AccountLogService {
	return &AccountLogService{
		logRepo:     logRepo,
		accountRepo: accountRepo,
	}
}

type LogBalanceChangeRequest struct {
	UserID        uint
	AccountID     string
	Type          string // income, expense, transfer_in, transfer_out, rollback, adjustment
	Amount        float64
	TransactionID *string
	ReminderID    *string
	LendingID     *string
	Remark        string
}

func (s *AccountLogService) LogBalanceChange(req *LogBalanceChangeRequest) error {
	account, err := s.accountRepo.GetByID(req.AccountID)
	if err != nil {
		return err
	}

	balanceBefore := account.CurrentBalance

	var balanceAfter float64
	switch req.Type {
	case "income", "transfer_in", "rollback_expense":
		balanceAfter = balanceBefore + req.Amount
	case "expense", "transfer_out", "rollback_income":
		balanceAfter = balanceBefore - req.Amount
	default:
		balanceAfter = balanceBefore + req.Amount
	}

	return s.logRepo.Create(&repository.CreateAccountLogRequest{
		UserID:        req.UserID,
		AccountID:     req.AccountID,
		Type:          req.Type,
		Amount:        req.Amount,
		BalanceBefore: balanceBefore,
		BalanceAfter:  balanceAfter,
		TransactionID: req.TransactionID,
		ReminderID:    req.ReminderID,
		LendingID:     req.LendingID,
		Remark:        req.Remark,
	})
}

func (s *AccountLogService) GetByAccountID(accountID string, page, pageSize int) ([]model.AccountLog, int64, error) {
	return s.logRepo.GetByAccountID(accountID, page, pageSize)
}

func (s *AccountLogService) GetByUserID(userID uint, page, pageSize int) ([]model.AccountLog, int64, error) {
	return s.logRepo.GetByUserID(userID, page, pageSize)
}
