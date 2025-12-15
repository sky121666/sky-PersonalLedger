package service

import (
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
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
	return s.repo.Delete(id)
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

	// Validate repayment doesn't exceed remaining balance
	if reminder.CurrentBalance != nil && *reminder.CurrentBalance > 0 {
		if req.Amount > *reminder.CurrentBalance {
			return nil, fmt.Errorf("还款金额不能超过待还金额 ¥%.2f", *reminder.CurrentBalance)
		}
	}

	// Update total paid and interest paid
	reminder.TotalPaid += req.Amount
	if req.InterestAmount > 0 {
		reminder.InterestPaid += req.InterestAmount
	}

	// Update current balance (reduce by principal amount)
	principalPaid := req.PrincipalAmount
	if principalPaid == 0 {
		// If not specified, assume all payment goes to principal
		principalPaid = req.Amount
	}

	if reminder.CurrentBalance != nil {
		newBalance := *reminder.CurrentBalance - principalPaid
		if newBalance < 0 {
			newBalance = 0
		}
		reminder.CurrentBalance = &newBalance
		if newBalance == 0 {
			now := time.Now()
			reminder.PaidOffAt = &now
		}
	}

	if err := s.repo.Update(reminder); err != nil {
		return nil, err
	}

	// Sync with linked account (debt account) if exists
	if reminder.AccountID != nil && *reminder.AccountID != "" {
		account, err := s.accountRepo.GetByID(*reminder.AccountID)
		if err == nil && account != nil {
			account.CurrentBalance -= req.Amount
			account.TotalPaid += req.Amount
			if account.CurrentBalance < 0 {
				account.CurrentBalance = 0
			}
			if account.CurrentBalance == 0 {
				now := time.Now()
				account.PaidOffAt = &now
			}
			s.accountRepo.Update(account)
		}
	}

	// Create transaction record for this payment
	s.createPaymentTransaction(userID, reminder, req)

	return s.repo.GetByID(id)
}

func (s *ReminderService) createPaymentTransaction(userID uint, reminder *model.Reminder, req RecordPaymentRequest) {
	// Must have source account to create transaction
	if req.AccountID == nil || *req.AccountID == "" {
		return
	}
	sourceAccountID := *req.AccountID

	// Find or create repayment category
	categories, err := s.categoryRepo.GetByUserID(userID, "expense")
	if err != nil {
		return
	}

	var repaymentCategoryID string
	for _, cat := range categories {
		if cat.Name == "还款" {
			repaymentCategoryID = cat.ID
			break
		}
	}

	// Create repayment category if not exists
	if repaymentCategoryID == "" {
		newCat := &model.Category{
			ID:        uuid.New().String(),
			UserID:    userID,
			Name:      "还款",
			Type:      "expense",
			Icon:      "💳",
			Color:     "#8B5CF6",
			IsSystem:  true,
			SortOrder: len(categories),
		}
		if err := s.categoryRepo.Create(newCat); err != nil {
			return
		}
		repaymentCategoryID = newCat.ID
	}

	// Build remark with loan name
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
		AccountID:       sourceAccountID,
		CategoryID:      &repaymentCategoryID,
		TransactionDate: now,
		Remark:          remark,
		Source:          "reminder",
		ReminderID:      &reminder.ID,
	}

	// Create transaction record
	if err := s.txRepo.Create(tx); err != nil {
		return
	}

	// Deduct from source account
	if account, err := s.accountRepo.GetByID(sourceAccountID); err == nil {
		account.CurrentBalance -= req.Amount
		s.accountRepo.Update(account)
	}
}

type ReminderDebtSummary struct {
	TotalDebt       float64 `json:"total_debt"`
	TotalPaid       float64 `json:"total_paid"`
	TotalPrincipal  float64 `json:"total_principal"`
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
		summary.TotalPaid += r.TotalPaid

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

	// Calculate progress: total_paid / total_principal
	if summary.TotalPrincipal > 0 {
		summary.Progress = (summary.TotalPaid / summary.TotalPrincipal) * 100
		if summary.Progress > 100 {
			summary.Progress = 100
		}
	}

	return summary, nil
}
