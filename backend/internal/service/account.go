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
	ErrAccountNotFound     = errors.New("account not found")
	ErrAccountHasBalance   = errors.New("cannot delete account with non-zero balance")
	ErrInvalidAccountPatch = errors.New("invalid account patch")
)

type AccountService struct {
	repo *repository.AccountRepository
}

func NewAccountService(repo *repository.AccountRepository) *AccountService {
	return &AccountService{repo: repo}
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
		parsed, err := parseLocalDate(*req.StartDate)
		if err != nil {
			return nil, ErrInvalidLocalDate
		}
		account.StartDate = &parsed
	}
	if req.TargetDate != nil {
		parsed, err := parseLocalDate(*req.TargetDate)
		if err != nil {
			return nil, ErrInvalidLocalDate
		}
		account.TargetDate = &parsed
	}

	if err := s.repo.DB().Transaction(func(txdb *gorm.DB) error {
		if err := txdb.Create(account).Error; err != nil {
			return err
		}
		if req.InitialBalance != 0 {
			return s.createInitialBalanceTransactionTx(txdb, userID, account)
		}
		return nil
	}); err != nil {
		return nil, err
	}

	return account, nil
}

func (s *AccountService) createInitialBalanceTransactionTx(txdb *gorm.DB, userID uint, account *model.Account) error {
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
	categoryID, err := s.findOrCreateInitialBalanceCategoryTx(txdb, userID, txType)
	if err != nil {
		return err
	}

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

	return txdb.Create(tx).Error
}

func (s *AccountService) findOrCreateInitialBalanceCategoryTx(txdb *gorm.DB, userID uint, txType string) (*string, error) {
	var category model.Category
	if err := txdb.First(&category, "user_id = ? AND type = ? AND name = ?", userID, txType, "期初余额").Error; err == nil {
		return &category.ID, nil
	} else if !errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, err
	}

	var categoryCount int64
	if err := txdb.Model(&model.Category{}).Where("user_id = ? AND type = ?", userID, txType).Count(&categoryCount).Error; err != nil {
		return nil, err
	}
	newCat := &model.Category{
		ID:        uuid.New().String(),
		UserID:    userID,
		Name:      "期初余额",
		Icon:      "📋",
		Color:     "#6B7280",
		Type:      txType,
		IsSystem:  true,
		SortOrder: int(categoryCount),
	}
	if err := txdb.Create(newCat).Error; err != nil {
		return nil, err
	}
	return &newCat.ID, nil
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

type PatchAccountRequest struct {
	Name         Optional[string]  `json:"name"`
	Icon         Optional[string]  `json:"icon"`
	Color        Optional[string]  `json:"color"`
	PaymentDay   Optional[int]     `json:"payment_day"`
	BillingDay   Optional[int]     `json:"billing_day"`
	CreditLimit  Optional[float64] `json:"credit_limit"`
	InterestRate Optional[float64] `json:"interest_rate"`
	StartDate    Optional[string]  `json:"start_date"`
	TargetDate   Optional[string]  `json:"target_date"`
	Remark       Optional[string]  `json:"remark"`
}

func (s *AccountService) Patch(id string, userID uint, req PatchAccountRequest) (*model.Account, error) {
	if _, err := s.GetByID(id, userID); err != nil {
		return nil, err
	}
	updates := map[string]any{}
	if req.Name.Set {
		if req.Name.Null || req.Name.Value == "" {
			return nil, ErrInvalidAccountPatch
		}
		updates["name"] = req.Name.Value
	}
	for column, field := range map[string]Optional[string]{
		"icon": req.Icon, "color": req.Color, "remark": req.Remark,
	} {
		if field.Set {
			if field.Null {
				updates[column] = ""
			} else {
				updates[column] = field.Value
			}
		}
	}
	if err := addOptionalDayPatch(updates, "payment_day", req.PaymentDay); err != nil {
		return nil, err
	}
	if err := addOptionalDayPatch(updates, "billing_day", req.BillingDay); err != nil {
		return nil, err
	}
	if err := addOptionalNonNegativePatch(updates, "credit_limit", req.CreditLimit); err != nil {
		return nil, err
	}
	if req.InterestRate.Set {
		if req.InterestRate.Null {
			updates["interest_rate"] = nil
		} else if req.InterestRate.Value < 0 || req.InterestRate.Value > 100 {
			return nil, ErrInvalidAccountPatch
		} else {
			updates["interest_rate"] = req.InterestRate.Value
		}
	}
	if err := addOptionalDatePatch(updates, "start_date", req.StartDate); err != nil {
		return nil, err
	}
	if err := addOptionalDatePatch(updates, "target_date", req.TargetDate); err != nil {
		return nil, err
	}
	if len(updates) == 0 {
		return s.GetByID(id, userID)
	}
	if err := s.repo.UpdateMetadataForUser(id, userID, updates); err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrAccountNotFound
		}
		return nil, err
	}
	return s.GetByID(id, userID)
}

func addOptionalDayPatch(updates map[string]any, column string, field Optional[int]) error {
	if !field.Set {
		return nil
	}
	if field.Null {
		updates[column] = nil
		return nil
	}
	if field.Value < 1 || field.Value > 31 {
		return ErrInvalidAccountPatch
	}
	updates[column] = field.Value
	return nil
}

func addOptionalNonNegativePatch(updates map[string]any, column string, field Optional[float64]) error {
	if !field.Set {
		return nil
	}
	if field.Null {
		updates[column] = nil
		return nil
	}
	if field.Value < 0 {
		return ErrInvalidAccountPatch
	}
	updates[column] = roundMoney(field.Value)
	return nil
}

func addOptionalDatePatch(updates map[string]any, column string, field Optional[string]) error {
	if !field.Set {
		return nil
	}
	if field.Null || field.Value == "" {
		updates[column] = nil
		return nil
	}
	parsed, err := parseLocalDate(field.Value)
	if err != nil {
		return ErrInvalidLocalDate
	}
	updates[column] = &parsed
	return nil
}

func (s *AccountService) Update(id string, userID uint, req UpdateAccountRequest) (*model.Account, error) {
	if _, err := s.GetByID(id, userID); err != nil {
		return nil, err
	}

	updates := map[string]any{}
	if req.Name != "" {
		updates["name"] = req.Name
	}
	if req.Icon != "" {
		updates["icon"] = req.Icon
	}
	if req.Color != "" {
		updates["color"] = req.Color
	}
	if req.PaymentDay != nil {
		updates["payment_day"] = req.PaymentDay
	}
	if req.BillingDay != nil {
		updates["billing_day"] = req.BillingDay
	}
	if req.CreditLimit != nil {
		updates["credit_limit"] = req.CreditLimit
	}
	if req.InterestRate != nil {
		updates["interest_rate"] = req.InterestRate
	}
	if req.Remark != "" {
		updates["remark"] = req.Remark
	}

	if req.StartDate != nil {
		parsed, err := parseLocalDate(*req.StartDate)
		if err != nil {
			return nil, ErrInvalidLocalDate
		}
		updates["start_date"] = &parsed
	}
	if req.TargetDate != nil {
		parsed, err := parseLocalDate(*req.TargetDate)
		if err != nil {
			return nil, ErrInvalidLocalDate
		}
		updates["target_date"] = &parsed
	}

	if err := s.repo.UpdateMetadataForUser(id, userID, updates); err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrAccountNotFound
		}
		return nil, err
	}
	return s.GetByID(id, userID)
}

func (s *AccountService) Delete(id string, userID uint) error {
	if err := s.repo.DeleteForUserIfBalanceAllows(id, userID); err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrAccountNotFound
		}
		if errors.Is(err, repository.ErrAccountBalancePreventsDeletion) {
			return ErrAccountHasBalance
		}
		return err
	}
	return nil
}

func (s *AccountService) Archive(id string, userID uint, isArchived bool) error {
	if err := s.repo.UpdateMetadataForUser(id, userID, map[string]any{"is_archived": isArchived}); err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrAccountNotFound
		}
		return err
	}
	return nil
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

func IsDebtAccount(accountType string) bool {
	return model.IsDebtAccountType(accountType)
}

func classifyAccountBalance(accountType string, balance float64) (assets float64, liabilities float64) {
	if IsDebtAccount(accountType) {
		if balance >= 0 {
			return 0, balance
		}
		// A negative debt balance is an overpayment or account credit and is
		// therefore an asset rather than a negative liability.
		return -balance, 0
	}
	if balance >= 0 {
		return balance, 0
	}
	return 0, -balance
}

func (s *AccountService) GetSummary(userID uint) (*AccountSummary, error) {
	accounts, err := s.repo.GetByUserID(userID, true)
	if err != nil {
		return nil, err
	}

	var assets, liabilities float64
	for _, acc := range accounts {
		accountAssets, accountLiabilities := classifyAccountBalance(acc.Type, acc.CurrentBalance)
		assets += accountAssets
		liabilities += accountLiabilities
	}

	return &AccountSummary{
		TotalAssets:      assets,
		TotalLiabilities: liabilities,
		NetAssets:        assets - liabilities,
	}, nil
}
