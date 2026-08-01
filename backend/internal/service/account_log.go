package service

import (
	"errors"

	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"gorm.io/gorm"
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
	account, err := s.getAccountForUser(req.UserID, req.AccountID)
	if err != nil {
		return err
	}

	balanceBefore := account.CurrentBalance

	var cashFlowDelta float64
	switch req.Type {
	case "income", "transfer_in", "rollback_expense":
		cashFlowDelta = req.Amount
	case "expense", "transfer_out", "rollback_income":
		cashFlowDelta = -req.Amount
	default:
		cashFlowDelta = req.Amount
	}
	balanceDelta := cashFlowDelta
	if IsDebtAccount(account.Type) {
		balanceDelta = -cashFlowDelta
	}
	balanceAfter := roundMoney(balanceBefore + balanceDelta)

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

func (s *AccountLogService) GetByAccountID(userID uint, accountID string, page, pageSize int) ([]model.AccountLog, int64, error) {
	if _, err := s.getAccountForUser(userID, accountID); err != nil {
		return nil, 0, err
	}
	return s.logRepo.GetByAccountID(userID, accountID, page, pageSize)
}

func (s *AccountLogService) GetByUserID(userID uint, page, pageSize int) ([]model.AccountLog, int64, error) {
	return s.logRepo.GetByUserID(userID, page, pageSize)
}

func (s *AccountLogService) getAccountForUser(userID uint, accountID string) (*model.Account, error) {
	if userID == 0 {
		return nil, ErrAccountNotFound
	}

	account, err := s.accountRepo.GetByID(accountID)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrAccountNotFound
		}
		return nil, err
	}
	if account.UserID != userID {
		return nil, ErrAccountNotFound
	}
	return account, nil
}
