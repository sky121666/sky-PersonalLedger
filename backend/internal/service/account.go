package service

import (
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

var (
	ErrAccountNotFound   = errors.New("account not found")
	ErrAccountHasBalance = errors.New("cannot delete account with non-zero balance")
)

type AccountService struct {
	repo         *repository.AccountRepository
	txRepo       *repository.TransactionRepository
	categoryRepo *repository.CategoryRepository
}

func NewAccountService(
	repo *repository.AccountRepository,
	txRepo *repository.TransactionRepository,
	categoryRepo *repository.CategoryRepository,
) *AccountService {
	return &AccountService{
		repo:         repo,
		txRepo:       txRepo,
		categoryRepo: categoryRepo,
	}
}

type CreateAccountRequest struct {
	Name           string   `json:"name" binding:"required"`
	Type           string   `json:"type" binding:"required,oneof=cash bank_card alipay wechat credit loan mortgage car_loan consumer_loan receivable payable savings investment fund stock crypto prepaid qq_pay jd_pay apple_pay huabei baitiao other"`
	Icon           string   `json:"icon"`
	Color          string   `json:"color"`
	InitialBalance float64  `json:"initial_balance"`
	PaymentDay     *int     `json:"payment_day"`
	BillingDay     *int     `json:"billing_day"`
	CreditLimit    *float64 `json:"credit_limit"`
	InterestRate   *float64 `json:"interest_rate"`
	StartDate      *string  `json:"start_date"`
	TargetDate     *string  `json:"target_date"`
	Remark         string   `json:"remark"`
}

func (s *AccountService) Create(userID uint, req CreateAccountRequest) (*model.Account, error) {
	account := &model.Account{
		ID:             uuid.New().String(),
		UserID:         userID,
		Name:           req.Name,
		Type:           req.Type,
		Icon:           req.Icon,
		Color:          req.Color,
		InitialBalance: req.InitialBalance,
		CurrentBalance: req.InitialBalance,
		PaymentDay:     req.PaymentDay,
		BillingDay:     req.BillingDay,
		CreditLimit:    req.CreditLimit,
		InterestRate:   req.InterestRate,
		Remark:         req.Remark,
	}

	if req.StartDate != nil {
		if t, err := time.Parse("2006-01-02", *req.StartDate); err == nil {
			account.StartDate = &t
		}
	}
	if req.TargetDate != nil {
		if t, err := time.Parse("2006-01-02", *req.TargetDate); err == nil {
			account.TargetDate = &t
		}
	}

	if err := s.repo.Create(account); err != nil {
		return nil, err
	}

	// Create initial balance transaction if initial balance is non-zero
	if req.InitialBalance != 0 {
		s.createInitialBalanceTransaction(userID, account)
	}

	return account, nil
}

func (s *AccountService) createInitialBalanceTransaction(userID uint, account *model.Account) {
	var txType string
	var amount float64

	if IsDebtAccount(account.Type) {
		// For debt accounts, positive balance means owing money (expense-like)
		if account.InitialBalance > 0 {
			txType = "expense"
			amount = account.InitialBalance
		} else {
			txType = "income"
			amount = -account.InitialBalance
		}
	} else {
		// For asset accounts, positive balance is income-like
		if account.InitialBalance > 0 {
			txType = "income"
			amount = account.InitialBalance
		} else {
			txType = "expense"
			amount = -account.InitialBalance
		}
	}

	// Find or create "期初余额" category
	categoryID := s.findOrCreateInitialBalanceCategory(userID, txType)

	tx := &model.Transaction{
		ID:              uuid.New().String(),
		UserID:          userID,
		AccountID:       account.ID,
		CategoryID:      categoryID,
		Type:            txType,
		Amount:          amount,
		TransactionDate: time.Now(),
		Remark:          "期初余额: " + account.Name,
		Source:          "system",
	}

	s.txRepo.Create(tx)
}

func (s *AccountService) findOrCreateInitialBalanceCategory(userID uint, txType string) *string {
	categories, err := s.categoryRepo.GetByUserID(userID, txType)
	if err != nil {
		return nil
	}

	for _, cat := range categories {
		if cat.Name == "期初余额" {
			return &cat.ID
		}
	}

	// Create new category
	newCat := &model.Category{
		ID:        uuid.New().String(),
		UserID:    userID,
		Name:      "期初余额",
		Icon:      "📋",
		Color:     "#6B7280",
		Type:      txType,
		IsSystem:  true,
		SortOrder: len(categories),
	}
	if err := s.categoryRepo.Create(newCat); err != nil {
		return nil
	}
	return &newCat.ID
}

func (s *AccountService) GetByID(id string, userID uint) (*model.Account, error) {
	account, err := s.repo.GetByID(id)
	if err != nil {
		return nil, ErrAccountNotFound
	}
	if account.UserID != userID {
		return nil, ErrAccountNotFound
	}
	return account, nil
}

func (s *AccountService) List(userID uint, includeArchived bool) ([]model.Account, error) {
	return s.repo.GetByUserID(userID, includeArchived)
}

type UpdateAccountRequest struct {
	Name         string   `json:"name"`
	Icon         string   `json:"icon"`
	Color        string   `json:"color"`
	PaymentDay   *int     `json:"payment_day"`
	BillingDay   *int     `json:"billing_day"`
	CreditLimit  *float64 `json:"credit_limit"`
	InterestRate *float64 `json:"interest_rate"`
	StartDate    *string  `json:"start_date"`
	TargetDate   *string  `json:"target_date"`
	Remark       string   `json:"remark"`
}

func (s *AccountService) Update(id string, userID uint, req UpdateAccountRequest) (*model.Account, error) {
	account, err := s.GetByID(id, userID)
	if err != nil {
		return nil, err
	}

	if req.Name != "" {
		account.Name = req.Name
	}
	if req.Icon != "" {
		account.Icon = req.Icon
	}
	if req.Color != "" {
		account.Color = req.Color
	}
	account.PaymentDay = req.PaymentDay
	account.BillingDay = req.BillingDay
	account.CreditLimit = req.CreditLimit
	account.InterestRate = req.InterestRate
	account.Remark = req.Remark

	if req.StartDate != nil {
		if t, err := time.Parse("2006-01-02", *req.StartDate); err == nil {
			account.StartDate = &t
		}
	}
	if req.TargetDate != nil {
		if t, err := time.Parse("2006-01-02", *req.TargetDate); err == nil {
			account.TargetDate = &t
		}
	}

	if err := s.repo.Update(account); err != nil {
		return nil, err
	}

	return account, nil
}

func (s *AccountService) Delete(id string, userID uint) error {
	account, err := s.GetByID(id, userID)
	if err != nil {
		return err
	}

	// Allow deletion of archived accounts regardless of balance
	// For non-archived accounts, require zero balance
	if !account.IsArchived && account.CurrentBalance != 0 {
		return ErrAccountHasBalance
	}

	return s.repo.Delete(id)
}

func (s *AccountService) Archive(id string, userID uint, isArchived bool) error {
	account, err := s.GetByID(id, userID)
	if err != nil {
		return err
	}

	account.IsArchived = isArchived
	return s.repo.Update(account)
}

func (s *AccountService) UpdateSortOrder(userID uint, ids []string) error {
	// Verify all accounts belong to user
	for _, id := range ids {
		if _, err := s.GetByID(id, userID); err != nil {
			return err
		}
	}
	return s.repo.UpdateSortOrder(ids)
}

type AccountSummary struct {
	TotalAssets      float64 `json:"total_assets"`
	TotalLiabilities float64 `json:"total_liabilities"`
	NetAssets        float64 `json:"net_assets"`
}

var debtAccountTypes = map[string]bool{
	"credit":        true,
	"loan":          true,
	"mortgage":      true,
	"car_loan":      true,
	"consumer_loan": true,
	"huabei":        true,
	"baitiao":       true,
}

func IsDebtAccount(accountType string) bool {
	return debtAccountTypes[accountType]
}

func (s *AccountService) GetSummary(userID uint) (*AccountSummary, error) {
	accounts, err := s.repo.GetByUserID(userID, false)
	if err != nil {
		return nil, err
	}

	var assets, liabilities float64
	for _, acc := range accounts {
		balance := acc.CurrentBalance

		if IsDebtAccount(acc.Type) {
			// Debt accounts: positive balance = owe money (liability)
			if balance > 0 {
				liabilities += balance
			}
		} else {
			// Regular asset accounts: can be positive or negative
			if balance > 0 {
				assets += balance
			} else {
				// Negative balance in asset account means debt
				liabilities += -balance
			}
		}
	}

	return &AccountSummary{
		TotalAssets:      assets,
		TotalLiabilities: liabilities,
		NetAssets:        assets - liabilities,
	}, nil
}
