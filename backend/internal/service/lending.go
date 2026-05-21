package service

import (
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"gorm.io/gorm"
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
	accountID := normalizeOptionalString(req.AccountID)

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
		AccountID:      accountID,
		Remark:         req.Remark,
		Evidence:       req.Evidence,
		IsSettled:      false,
	}

	if req.DueDate != nil {
		if dueDate, err := parseDateTime(*req.DueDate); err == nil {
			lending.DueDate = &dueDate
		}
	}

	if err := s.txRepo.DB().Transaction(func(txdb *gorm.DB) error {
		var account *model.Account
		if accountID != nil {
			foundAccount, err := getAccountForUserTx(txdb, *accountID, userID)
			if err != nil {
				return err
			}
			account = foundAccount
		}

		if err := txdb.Create(lending).Error; err != nil {
			return err
		}

		if req.CreateTransaction && account != nil {
			var txType string
			var balanceDelta float64
			if req.Type == "lend_out" {
				txType = "expense"
				balanceDelta = -req.Principal
			} else {
				txType = "income"
				balanceDelta = req.Principal
			}
			if _, err := s.createLendingTransactionTx(txdb, userID, lending.ID, account.ID, txType, req.Principal, lendDate, "借贷: "+req.ContactName); err != nil {
				return err
			}
			if err := updateAccountBalanceForUserTx(txdb, account.ID, userID, balanceDelta); err != nil {
				return err
			}
		}
		return nil
	}); err != nil {
		return nil, err
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

	return s.txRepo.DB().Transaction(func(txdb *gorm.DB) error {
		if err := txdb.Model(&model.Transaction{}).
			Where("user_id = ? AND lending_id = ?", userID, lending.ID).
			Update("lending_id", nil).Error; err != nil {
			return err
		}
		if err := txdb.Model(&model.AccountLog{}).
			Where("user_id = ? AND lending_id = ?", userID, lending.ID).
			Update("lending_id", nil).Error; err != nil {
			return err
		}
		if err := txdb.Where("user_id = ? AND lending_id = ?", userID, lending.ID).
			Delete(&model.LendingRecord{}).Error; err != nil {
			return err
		}
		result := txdb.Where("id = ? AND user_id = ?", lending.ID, userID).Delete(&model.Lending{})
		if result.Error != nil {
			return result.Error
		}
		if result.RowsAffected != 1 {
			return ErrLendingNotFound
		}
		return nil
	})
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
	accountID := normalizeOptionalString(req.AccountID)

	if err := s.txRepo.DB().Transaction(func(txdb *gorm.DB) error {
		var account *model.Account
		if accountID != nil {
			foundAccount, err := getAccountForUserTx(txdb, *accountID, userID)
			if err != nil {
				return err
			}
			account = foundAccount
		}

		var transactionID *string
		if req.CreateTransaction && account != nil {
			var txType string
			var balanceDelta float64
			if lending.Type == "lend_out" {
				txType = "income"
				balanceDelta = req.Amount
			} else {
				txType = "expense"
				balanceDelta = -req.Amount
			}
			txID, err := s.createLendingTransactionTx(txdb, userID, lendingID, account.ID, txType, req.Amount, recordDate, "还款: "+lending.ContactName)
			if err != nil {
				return err
			}
			transactionID = &txID
			if err := updateAccountBalanceForUserTx(txdb, account.ID, userID, balanceDelta); err != nil {
				return err
			}
		}

		record := &model.LendingRecord{
			ID:            uuid.New().String(),
			LendingID:     lendingID,
			UserID:        userID,
			Type:          "repay",
			Amount:        req.Amount,
			RecordDate:    recordDate,
			AccountID:     accountID,
			TransactionID: transactionID,
			Remark:        req.Remark,
			Evidence:      req.Evidence,
		}

		if err := txdb.Create(record).Error; err != nil {
			return err
		}

		nextBalance := lending.CurrentBalance - req.Amount
		nextTotalRepaid := lending.TotalRepaid + req.Amount
		isSettled := lending.IsSettled
		settledAt := lending.SettledAt
		if nextBalance <= 0.01 {
			nextBalance = 0
			isSettled = true
			now := time.Now()
			settledAt = &now
		}

		result := txdb.Model(&model.Lending{}).
			Where("id = ? AND user_id = ?", lending.ID, userID).
			Updates(map[string]any{
				"current_balance": nextBalance,
				"total_repaid":    nextTotalRepaid,
				"is_settled":      isSettled,
				"settled_at":      settledAt,
			})
		if result.Error != nil {
			return result.Error
		}
		if result.RowsAffected != 1 {
			return ErrLendingNotFound
		}
		return nil
	}); err != nil {
		return nil, err
	}

	return s.repo.GetByID(lendingID)
}

func normalizeOptionalString(value *string) *string {
	if value == nil || *value == "" {
		return nil
	}
	return value
}

func (s *LendingService) createLendingTransactionTx(txdb *gorm.DB, userID uint, lendingID string, accountID string, txType string, amount float64, txDate time.Time, remark string) (string, error) {
	categoryID, err := s.findOrCreateLendingCategoryTx(txdb, userID, txType)
	if err != nil {
		return "", err
	}

	tx := &model.Transaction{
		ID:              uuid.New().String(),
		UserID:          userID,
		AccountID:       accountID,
		CategoryID:      categoryID,
		Type:            txType,
		Amount:          amount,
		TransactionDate: txDate,
		Remark:          remark,
		Source:          "lending",
		LendingID:       &lendingID,
	}
	if err := txdb.Create(tx).Error; err != nil {
		return "", err
	}
	return tx.ID, nil
}

func (s *LendingService) findOrCreateLendingCategoryTx(txdb *gorm.DB, userID uint, txType string) (*string, error) {
	var category model.Category
	err := txdb.Where("user_id = ? AND type = ? AND name = ?", userID, txType, "借贷").
		First(&category).Error
	if err == nil {
		return &category.ID, nil
	}
	if !errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, err
	}

	var sortOrder int64
	if err := txdb.Model(&model.Category{}).
		Where("user_id = ? AND type = ?", userID, txType).
		Count(&sortOrder).Error; err != nil {
		return nil, err
	}

	category = model.Category{
		ID:        uuid.New().String(),
		UserID:    userID,
		Name:      "借贷",
		Icon:      "💰",
		Color:     "#8B5CF6",
		Type:      txType,
		IsSystem:  true,
		SortOrder: int(sortOrder),
	}
	if err := txdb.Create(&category).Error; err != nil {
		return nil, err
	}
	return &category.ID, nil
}

func updateAccountBalanceForUserTx(txdb *gorm.DB, accountID string, userID uint, delta float64) error {
	result := txdb.Model(&model.Account{}).
		Where("id = ? AND user_id = ?", accountID, userID).
		Update("current_balance", gorm.Expr("current_balance + ?", delta))
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected != 1 {
		return ErrAccountNotFound
	}
	return nil
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
