package service

import (
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

var (
	ErrLendingNotFound       = errors.New("lending not found")
	ErrLendingRecordNotFound = errors.New("lending record not found")
	ErrInvalidAmount         = errors.New("invalid amount")
	ErrAlreadySettled        = errors.New("lending already settled")
)

func parseDateTime(s string) (time.Time, error) {
	// Get local timezone
	loc := time.Local

	formats := []string{
		"2006-01-02T15:04",
		"2006-01-02 15:04",
		"2006-01-02T15:04:05",
		"2006-01-02 15:04:05",
		"2006-01-02",
	}
	for _, f := range formats {
		if t, err := time.ParseInLocation(f, s, loc); err == nil {
			return t, nil
		}
	}
	// Try RFC3339 which includes timezone
	if t, err := time.Parse(time.RFC3339, s); err == nil {
		return t, nil
	}
	return time.Time{}, errors.New("invalid date time format")
}

type LendingService struct {
	repo          *repository.LendingRepository
	accountRepo   *repository.AccountRepository
	txRepo        *repository.TransactionRepository
	categoryRepo  *repository.CategoryRepository
	accountLogSvc *AccountLogService
}

func NewLendingService(
	repo *repository.LendingRepository,
	accountRepo *repository.AccountRepository,
	txRepo *repository.TransactionRepository,
	categoryRepo *repository.CategoryRepository,
	accountLogSvc *AccountLogService,
) *LendingService {
	return &LendingService{
		repo:          repo,
		accountRepo:   accountRepo,
		txRepo:        txRepo,
		categoryRepo:  categoryRepo,
		accountLogSvc: accountLogSvc,
	}
}

func (s *LendingService) findOrCreateLendingCategory(userID uint, txType string) *string {
	categories, err := s.categoryRepo.GetByUserID(userID, txType)
	if err != nil {
		return nil
	}

	// Look for existing lending category
	for _, cat := range categories {
		if cat.Name == "借贷" {
			return &cat.ID
		}
	}

	// Create a new lending category
	newCat := &model.Category{
		ID:        uuid.New().String(),
		UserID:    userID,
		Name:      "借贷",
		Icon:      "💰",
		Color:     "#8B5CF6",
		Type:      txType,
		IsSystem:  true,
		SortOrder: len(categories),
	}
	if err := s.categoryRepo.Create(newCat); err != nil {
		return nil
	}
	return &newCat.ID
}

type CreateLendingRequest struct {
	Type              string   `json:"type" binding:"required,oneof=lend_out borrow_in"`
	ContactName       string   `json:"contact_name" binding:"required"`
	ContactPhone      string   `json:"contact_phone"`
	ContactRemark     string   `json:"contact_remark"`
	Principal         float64  `json:"principal" binding:"required,gt=0"`
	InterestRate      *float64 `json:"interest_rate"`
	LendDate          string   `json:"lend_date" binding:"required"`
	DueDate           *string  `json:"due_date"`
	AccountID         *string  `json:"account_id"`
	Remark            string   `json:"remark"`
	Evidence          string   `json:"evidence"`
	CreateTransaction bool     `json:"create_transaction"`
}

func (s *LendingService) Create(userID uint, req CreateLendingRequest) (*model.Lending, error) {
	lendDate, err := parseDateTime(req.LendDate)
	if err != nil {
		return nil, err
	}

	lending := &model.Lending{
		ID:             uuid.New().String(),
		UserID:         userID,
		Type:           req.Type,
		ContactName:    req.ContactName,
		ContactPhone:   req.ContactPhone,
		ContactRemark:  req.ContactRemark,
		Principal:      req.Principal,
		InterestRate:   req.InterestRate,
		CurrentBalance: req.Principal,
		TotalRepaid:    0,
		LendDate:       lendDate,
		AccountID:      req.AccountID,
		Remark:         req.Remark,
		Evidence:       req.Evidence,
		IsSettled:      false,
	}

	if req.DueDate != nil {
		if dueDate, err := parseDateTime(*req.DueDate); err == nil {
			lending.DueDate = &dueDate
		}
	}

	if err := s.repo.Create(lending); err != nil {
		return nil, err
	}

	if req.CreateTransaction && req.AccountID != nil {
		var txType string
		var amount float64
		if req.Type == "lend_out" {
			txType = "expense"
			amount = req.Principal
		} else {
			txType = "income"
			amount = req.Principal
		}

		categoryID := s.findOrCreateLendingCategory(userID, txType)
		tx := &model.Transaction{
			ID:              uuid.New().String(),
			UserID:          userID,
			AccountID:       *req.AccountID,
			CategoryID:      categoryID,
			Type:            txType,
			Amount:          amount,
			TransactionDate: lendDate,
			Remark:          "借贷: " + req.ContactName,
			Source:          "lending",
			LendingID:       &lending.ID,
		}

		if err := s.txRepo.Create(tx); err == nil {
			if txType == "expense" {
				s.accountRepo.UpdateBalance(*req.AccountID, -amount)
			} else {
				s.accountRepo.UpdateBalance(*req.AccountID, amount)
			}
		}
	}

	return s.repo.GetByID(lending.ID)
}

func (s *LendingService) GetByID(id string, userID uint) (*model.Lending, error) {
	lending, err := s.repo.GetByID(id)
	if err != nil {
		return nil, ErrLendingNotFound
	}
	if lending.UserID != userID {
		return nil, ErrLendingNotFound
	}
	return lending, nil
}

func (s *LendingService) List(userID uint, includeSettled bool) ([]*model.Lending, error) {
	return s.repo.GetByUserID(userID, includeSettled)
}

type UpdateLendingRequest struct {
	ContactName   string   `json:"contact_name"`
	ContactPhone  string   `json:"contact_phone"`
	ContactRemark string   `json:"contact_remark"`
	InterestRate  *float64 `json:"interest_rate"`
	DueDate       *string  `json:"due_date"`
	Remark        string   `json:"remark"`
	Evidence      string   `json:"evidence"`
}

func (s *LendingService) Update(id string, userID uint, req UpdateLendingRequest) (*model.Lending, error) {
	lending, err := s.GetByID(id, userID)
	if err != nil {
		return nil, err
	}

	lending.ContactName = req.ContactName
	lending.ContactPhone = req.ContactPhone
	lending.ContactRemark = req.ContactRemark
	lending.InterestRate = req.InterestRate
	lending.Remark = req.Remark
	lending.Evidence = req.Evidence

	if req.DueDate != nil {
		if dueDate, err := parseDateTime(*req.DueDate); err == nil {
			lending.DueDate = &dueDate
		}
	} else {
		lending.DueDate = nil
	}

	if err := s.repo.Update(lending); err != nil {
		return nil, err
	}

	return s.repo.GetByID(id)
}

func (s *LendingService) Delete(id string, userID uint) error {
	lending, err := s.GetByID(id, userID)
	if err != nil {
		return err
	}
	return s.repo.Delete(lending.ID)
}

type RecordRepaymentRequest struct {
	Amount            float64 `json:"amount" binding:"required,gt=0"`
	RecordDate        string  `json:"record_date" binding:"required"`
	AccountID         *string `json:"account_id"`
	Remark            string  `json:"remark"`
	Evidence          string  `json:"evidence"`
	CreateTransaction bool    `json:"create_transaction"`
}

func (s *LendingService) RecordRepayment(lendingID string, userID uint, req RecordRepaymentRequest) (*model.Lending, error) {
	lending, err := s.GetByID(lendingID, userID)
	if err != nil {
		return nil, err
	}

	if lending.IsSettled {
		return nil, ErrAlreadySettled
	}

	if req.Amount <= 0 {
		return nil, ErrInvalidAmount
	}

	if req.Amount > lending.CurrentBalance {
		req.Amount = lending.CurrentBalance
	}

	recordDate, err := parseDateTime(req.RecordDate)
	if err != nil {
		return nil, err
	}

	var transactionID *string
	if req.CreateTransaction && req.AccountID != nil {
		var txType string
		if lending.Type == "lend_out" {
			txType = "income"
		} else {
			txType = "expense"
		}

		categoryID := s.findOrCreateLendingCategory(userID, txType)
		tx := &model.Transaction{
			ID:              uuid.New().String(),
			UserID:          userID,
			AccountID:       *req.AccountID,
			CategoryID:      categoryID,
			Type:            txType,
			Amount:          req.Amount,
			TransactionDate: recordDate,
			Remark:          "还款: " + lending.ContactName,
			Source:          "lending",
			LendingID:       &lendingID,
		}

		if err := s.txRepo.Create(tx); err == nil {
			transactionID = &tx.ID
			if txType == "income" {
				s.accountRepo.UpdateBalance(*req.AccountID, req.Amount)
			} else {
				s.accountRepo.UpdateBalance(*req.AccountID, -req.Amount)
			}
		}
	}

	record := &model.LendingRecord{
		ID:            uuid.New().String(),
		LendingID:     lendingID,
		UserID:        userID,
		Type:          "repay",
		Amount:        req.Amount,
		RecordDate:    recordDate,
		AccountID:     req.AccountID,
		TransactionID: transactionID,
		Remark:        req.Remark,
		Evidence:      req.Evidence,
	}

	if err := s.repo.CreateRecord(record); err != nil {
		return nil, err
	}

	lending.CurrentBalance -= req.Amount
	lending.TotalRepaid += req.Amount

	if lending.CurrentBalance <= 0.01 {
		lending.CurrentBalance = 0
		lending.IsSettled = true
		now := time.Now()
		lending.SettledAt = &now
	}

	if err := s.repo.Update(lending); err != nil {
		return nil, err
	}

	return s.repo.GetByID(lendingID)
}

func (s *LendingService) GetRecords(lendingID string, userID uint) ([]*model.LendingRecord, error) {
	lending, err := s.GetByID(lendingID, userID)
	if err != nil {
		return nil, err
	}
	return s.repo.GetRecordsByLendingID(lending.ID)
}

type LendingSummary struct {
	TotalLendOut    float64 `json:"total_lend_out"`
	TotalBorrowIn   float64 `json:"total_borrow_in"`
	ActiveLendOut   int     `json:"active_lend_out"`
	ActiveBorrowIn  int     `json:"active_borrow_in"`
	SettledLendOut  int     `json:"settled_lend_out"`
	SettledBorrowIn int     `json:"settled_borrow_in"`
	TotalReceivable float64 `json:"total_receivable"`
	TotalPayable    float64 `json:"total_payable"`
	NetLending      float64 `json:"net_lending"`
}

func (s *LendingService) GetSummary(userID uint) (*LendingSummary, error) {
	lendings, err := s.repo.GetByUserID(userID, true)
	if err != nil {
		return nil, err
	}

	summary := &LendingSummary{}

	for _, lending := range lendings {
		if lending.Type == "lend_out" {
			summary.TotalLendOut += lending.Principal
			if lending.IsSettled {
				summary.SettledLendOut++
			} else {
				summary.ActiveLendOut++
				summary.TotalReceivable += lending.CurrentBalance
			}
		} else {
			summary.TotalBorrowIn += lending.Principal
			if lending.IsSettled {
				summary.SettledBorrowIn++
			} else {
				summary.ActiveBorrowIn++
				summary.TotalPayable += lending.CurrentBalance
			}
		}
	}

	summary.NetLending = summary.TotalReceivable - summary.TotalPayable

	return summary, nil
}
