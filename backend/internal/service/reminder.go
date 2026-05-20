package service

import (
	"errors"
	"fmt"
	"math"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"gorm.io/gorm"
)

var (
	ErrReminderNotFound = errors.New("reminder not found")
)

type ReminderService struct {
	repo          *repository.ReminderRepository
	accountRepo   *repository.AccountRepository
	txRepo        *repository.TransactionRepository
	categoryRepo  *repository.CategoryRepository
	accountLogSvc *AccountLogService
}

func NewReminderService(
	repo *repository.ReminderRepository,
	accountRepo *repository.AccountRepository,
	txRepo *repository.TransactionRepository,
	categoryRepo *repository.CategoryRepository,
	accountLogSvc *AccountLogService,
) *ReminderService {
	return &ReminderService{
		repo:          repo,
		accountRepo:   accountRepo,
		txRepo:        txRepo,
		categoryRepo:  categoryRepo,
		accountLogSvc: accountLogSvc,
	}
}

type CreateReminderRequest struct {
	Name           string   `json:"name"`
	AccountID      *string  `json:"account_id"`
	LoanType       string   `json:"loan_type"`
	PaymentDay     int      `json:"payment_day" binding:"required,min=1,max=31"`
	BillingDay     *int     `json:"billing_day"`
	AdvanceDays    int      `json:"advance_days"`
	Amount         *float64 `json:"amount"`
	Principal      *float64 `json:"principal"`
	CurrentBalance *float64 `json:"current_balance"`
	InterestRate   *float64 `json:"interest_rate"`
	TotalInterest  *float64 `json:"total_interest"`
	StartDate      *string  `json:"start_date"`
	TargetDate     *string  `json:"target_date"`
	Color          string   `json:"color"`
	Remark         string   `json:"remark"`
	Evidence       string   `json:"evidence"`
}

func (s *ReminderService) Create(userID uint, req CreateReminderRequest) (*model.Reminder, error) {
	reminder := &model.Reminder{
		ID:             uuid.New().String(),
		UserID:         userID,
		Name:           req.Name,
		AccountID:      req.AccountID,
		LoanType:       req.LoanType,
		PaymentDay:     req.PaymentDay,
		BillingDay:     req.BillingDay,
		AdvanceDays:    req.AdvanceDays,
		Amount:         req.Amount,
		Principal:      req.Principal,
		CurrentBalance: req.CurrentBalance,
		InterestRate:   req.InterestRate,
		TotalInterest:  req.TotalInterest,
		Color:          req.Color,
		Remark:         req.Remark,
		Evidence:       req.Evidence,
		IsEnabled:      true,
	}

	if reminder.LoanType == "" {
		reminder.LoanType = "other"
	}
	if reminder.AdvanceDays == 0 {
		reminder.AdvanceDays = 3
	}
	if req.StartDate != nil {
		if t, err := time.Parse("2006-01-02", *req.StartDate); err == nil {
			reminder.StartDate = &t
		}
	}
	if req.TargetDate != nil {
		if t, err := time.Parse("2006-01-02", *req.TargetDate); err == nil {
			reminder.TargetDate = &t
		}
	}

	if err := s.repo.Create(reminder); err != nil {
		return nil, err
	}

	return s.repo.GetByID(reminder.ID)
}

func (s *ReminderService) GetByID(id string, userID uint) (*model.Reminder, error) {
	reminder, err := s.repo.GetByID(id)
	if err != nil {
		return nil, ErrReminderNotFound
	}
	if reminder.UserID != userID {
		return nil, ErrReminderNotFound
	}
	return reminder, nil
}

func (s *ReminderService) List(userID uint) ([]model.Reminder, error) {
	return s.repo.GetByUserID(userID)
}

func (s *ReminderService) ListByAccountID(userID uint, accountID string) ([]model.Reminder, error) {
	return s.repo.ListByAccountID(userID, accountID)
}

func (s *ReminderService) Update(id string, userID uint, req CreateReminderRequest) (*model.Reminder, error) {
	reminder, err := s.GetByID(id, userID)
	if err != nil {
		return nil, err
	}

	reminder.Name = req.Name
	reminder.AccountID = req.AccountID
	reminder.LoanType = req.LoanType
	reminder.PaymentDay = req.PaymentDay
	reminder.BillingDay = req.BillingDay
	reminder.AdvanceDays = req.AdvanceDays
	reminder.Amount = req.Amount
	reminder.Principal = req.Principal
	reminder.CurrentBalance = req.CurrentBalance
	reminder.InterestRate = req.InterestRate
	reminder.TotalInterest = req.TotalInterest
	reminder.Color = req.Color
	reminder.Remark = req.Remark
	reminder.Evidence = req.Evidence

	if req.StartDate != nil {
		if t, err := time.Parse("2006-01-02", *req.StartDate); err == nil {
			reminder.StartDate = &t
		}
	}
	if req.TargetDate != nil {
		if t, err := time.Parse("2006-01-02", *req.TargetDate); err == nil {
			reminder.TargetDate = &t
		}
	}

	if err := s.repo.Update(reminder); err != nil {
		return nil, err
	}

	return s.repo.GetByID(id)
}

func (s *ReminderService) Delete(id string, userID uint) error {
	_, err := s.GetByID(id, userID)
	if err != nil {
		return err
	}

	return s.txRepo.DB().Transaction(func(txdb *gorm.DB) error {
		if err := txdb.Model(&model.Transaction{}).
			Where("user_id = ? AND reminder_id = ?", userID, id).
			Update("reminder_id", nil).Error; err != nil {
			return err
		}
		if err := txdb.Model(&model.AccountLog{}).
			Where("user_id = ? AND reminder_id = ?", userID, id).
			Update("reminder_id", nil).Error; err != nil {
			return err
		}
		result := txdb.Where("id = ? AND user_id = ?", id, userID).Delete(&model.Reminder{})
		if result.Error != nil {
			return result.Error
		}
		if result.RowsAffected != 1 {
			return ErrReminderNotFound
		}
		return nil
	})
}

func (s *ReminderService) Toggle(id string, userID uint) (*model.Reminder, error) {
	reminder, err := s.GetByID(id, userID)
	if err != nil {
		return nil, err
	}

	reminder.IsEnabled = !reminder.IsEnabled
	if err := s.repo.Update(reminder); err != nil {
		return nil, err
	}

	return reminder, nil
}

type RecordPaymentRequest struct {
	Amount          float64 `json:"amount" binding:"required,gt=0"`
	PrincipalAmount float64 `json:"principal_amount"`
	InterestAmount  float64 `json:"interest_amount"`
	AccountID       *string `json:"account_id"`
}

func (s *ReminderService) RecordPayment(id string, userID uint, req RecordPaymentRequest) (*model.Reminder, error) {
	reminder, err := s.GetByID(id, userID)
	if err != nil {
		return nil, err
	}

	principalPaid, interestPaid, err := normalizeReminderPaymentSplit(req)
	if err != nil {
		return nil, err
	}

	// Validate repayment principal doesn't exceed remaining principal balance.
	if reminder.CurrentBalance != nil && *reminder.CurrentBalance > 0 {
		if principalPaid > *reminder.CurrentBalance {
			return nil, fmt.Errorf("还款金额不能超过待还金额 ¥%.2f", *reminder.CurrentBalance)
		}
	}

	if err := s.txRepo.DB().Transaction(func(txdb *gorm.DB) error {
		var sourceAccount *model.Account
		if req.AccountID != nil && *req.AccountID != "" {
			account, err := getAccountForUserTx(txdb, *req.AccountID, userID)
			if err != nil {
				return err
			}
			sourceAccount = account
		}

		var debtAccount *model.Account
		if reminder.AccountID != nil && *reminder.AccountID != "" {
			account, err := getAccountForUserTx(txdb, *reminder.AccountID, userID)
			if err != nil {
				return err
			}
			debtAccount = account
		}

		nextTotalPaid := reminder.TotalPaid + req.Amount
		nextInterestPaid := reminder.InterestPaid + interestPaid
		nextCurrentBalance := reminder.CurrentBalance
		var nextPaidOffAt *time.Time
		if reminder.PaidOffAt != nil {
			nextPaidOffAt = reminder.PaidOffAt
		}
		if reminder.CurrentBalance != nil {
			newBalance := *reminder.CurrentBalance - principalPaid
			if newBalance < 0 {
				newBalance = 0
			}
			nextCurrentBalance = &newBalance
			if newBalance == 0 {
				now := time.Now()
				nextPaidOffAt = &now
			}
		}

		result := txdb.Model(&model.Reminder{}).
			Where("id = ? AND user_id = ?", reminder.ID, userID).
			Updates(map[string]any{
				"total_paid":      nextTotalPaid,
				"interest_paid":   nextInterestPaid,
				"current_balance": nextCurrentBalance,
				"paid_off_at":     nextPaidOffAt,
			})
		if result.Error != nil {
			return result.Error
		}
		if result.RowsAffected != 1 {
			return ErrReminderNotFound
		}

		if debtAccount != nil {
			debtAccount.CurrentBalance -= principalPaid
			debtAccount.TotalPaid += principalPaid
			if debtAccount.CurrentBalance < 0 {
				debtAccount.CurrentBalance = 0
			}
			if debtAccount.CurrentBalance == 0 {
				now := time.Now()
				debtAccount.PaidOffAt = &now
			}
			if err := txdb.Model(&model.Account{}).
				Where("id = ? AND user_id = ?", debtAccount.ID, userID).
				Updates(map[string]any{
					"current_balance": debtAccount.CurrentBalance,
					"total_paid":      debtAccount.TotalPaid,
					"paid_off_at":     debtAccount.PaidOffAt,
				}).Error; err != nil {
				return err
			}
		}

		if sourceAccount != nil {
			return s.createPaymentTransactionTx(txdb, userID, reminder, req, principalPaid, interestPaid, sourceAccount)
		}
		return nil
	}); err != nil {
		return nil, err
	}
	return s.repo.GetByID(id)
}

func normalizeReminderPaymentSplit(req RecordPaymentRequest) (float64, float64, error) {
	if req.Amount <= 0 {
		return 0, 0, fmt.Errorf("还款金额必须大于 0")
	}
	if req.PrincipalAmount < 0 || req.InterestAmount < 0 {
		return 0, 0, fmt.Errorf("本金和利息不能为负数")
	}
	if req.PrincipalAmount == 0 && req.InterestAmount == 0 {
		return req.Amount, 0, nil
	}

	principalPaid := req.PrincipalAmount
	interestPaid := req.InterestAmount
	if principalPaid == 0 {
		principalPaid = req.Amount - interestPaid
	}
	if interestPaid == 0 {
		interestPaid = req.Amount - principalPaid
	}
	if principalPaid < 0 || interestPaid < 0 || math.Abs(principalPaid+interestPaid-req.Amount) > 0.01 {
		return 0, 0, fmt.Errorf("本金+利息必须等于还款金额")
	}
	return principalPaid, interestPaid, nil
}

func (s *ReminderService) createPaymentTransactionTx(txdb *gorm.DB, userID uint, reminder *model.Reminder, req RecordPaymentRequest, principalPaid float64, interestPaid float64, sourceAccount *model.Account) error {
	repaymentCategoryID, err := s.findOrCreateRepaymentCategoryTx(txdb, userID)
	if err != nil {
		return err
	}

	remark := "还款"
	if reminder.Name != "" {
		remark = reminder.Name + " 还款"
	}

	now := time.Now()
	tx := &model.Transaction{
		ID:              uuid.New().String(),
		UserID:          userID,
		Type:            "expense",
		Amount:          req.Amount,
		PrincipalAmount: principalPaid,
		InterestAmount:  interestPaid,
		AccountID:       sourceAccount.ID,
		CategoryID:      repaymentCategoryID,
		TransactionDate: now,
		Remark:          remark,
		Source:          "reminder",
		ReminderID:      &reminder.ID,
	}

	if err := txdb.Create(tx).Error; err != nil {
		return err
	}

	sourceAccount.CurrentBalance -= req.Amount
	return txdb.Model(&model.Account{}).
		Where("id = ? AND user_id = ?", sourceAccount.ID, userID).
		Update("current_balance", sourceAccount.CurrentBalance).Error
}

func (s *ReminderService) findOrCreateRepaymentCategoryTx(txdb *gorm.DB, userID uint) (*string, error) {
	var category model.Category
	err := txdb.Where("user_id = ? AND type = ? AND name = ?", userID, "expense", "还款").
		First(&category).Error
	if err == nil {
		return &category.ID, nil
	}
	if !errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, err
	}

	var sortOrder int64
	if err := txdb.Model(&model.Category{}).
		Where("user_id = ? AND type = ?", userID, "expense").
		Count(&sortOrder).Error; err != nil {
		return nil, err
	}

	category = model.Category{
		ID:        uuid.New().String(),
		UserID:    userID,
		Name:      "还款",
		Type:      "expense",
		Icon:      "💳",
		Color:     "#8B5CF6",
		IsSystem:  true,
		SortOrder: int(sortOrder),
	}
	if err := txdb.Create(&category).Error; err != nil {
		return nil, err
	}
	return &category.ID, nil
}

func getAccountForUserTx(txdb *gorm.DB, accountID string, userID uint) (*model.Account, error) {
	var account model.Account
	if err := txdb.First(&account, "id = ? AND user_id = ?", accountID, userID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrAccountNotFound
		}
		return nil, err
	}
	return &account, nil
}

type ReminderDebtSummary struct {
	TotalDebt       float64 `json:"total_debt"`      // 待还总额
	TotalPaid       float64 `json:"total_paid"`      // 已还金额 (本金 - 待还)
	TotalPrincipal  float64 `json:"total_principal"` // 共需还金额 (本金总额)
	Progress        float64 `json:"progress"`
	ActiveLoans     int     `json:"active_loans"`
	PaidOffLoans    int     `json:"paid_off_loans"`
	NextPaymentDay  int     `json:"next_payment_day"`
	NextPaymentName string  `json:"next_payment_name"`
	DaysUntilNext   int     `json:"days_until_next"`
}

func (s *ReminderService) GetDebtSummary(userID uint) (*ReminderDebtSummary, error) {
	reminders, err := s.repo.GetByUserID(userID)
	if err != nil {
		return nil, err
	}

	summary := &ReminderDebtSummary{
		DaysUntilNext: 999,
	}
	now := time.Now()
	today := now.Day()

	for _, r := range reminders {
		if r.Principal != nil {
			summary.TotalPrincipal += *r.Principal
		}
		if r.CurrentBalance != nil {
			summary.TotalDebt += *r.CurrentBalance
		}
		// 已还金额 = 本金 - 待还 (不使用 r.TotalPaid，因为它可能包含利息)
		if r.Principal != nil && r.CurrentBalance != nil {
			paid := *r.Principal - *r.CurrentBalance
			if paid > 0 {
				summary.TotalPaid += paid
			}
		}

		if r.PaidOffAt != nil {
			summary.PaidOffLoans++
		} else if r.IsEnabled {
			summary.ActiveLoans++

			// Calculate next payment date
			var daysUntil int
			if r.PaymentDay >= today {
				daysUntil = r.PaymentDay - today
			} else {
				// Next month
				daysInMonth := time.Date(now.Year(), now.Month()+1, 0, 0, 0, 0, 0, time.Local).Day()
				daysUntil = daysInMonth - today + r.PaymentDay
			}
			if daysUntil < summary.DaysUntilNext {
				summary.DaysUntilNext = daysUntil
				summary.NextPaymentDay = r.PaymentDay
				summary.NextPaymentName = r.Name
			}
		}
	}

	// Reset if no payment found
	if summary.DaysUntilNext == 999 {
		summary.DaysUntilNext = 0
	}

	// Calculate progress: paid / principal
	// 进度 = 已还金额 / 本金总额
	if summary.TotalPrincipal > 0 {
		summary.Progress = (summary.TotalPaid / summary.TotalPrincipal) * 100
	}

	return summary, nil
}
