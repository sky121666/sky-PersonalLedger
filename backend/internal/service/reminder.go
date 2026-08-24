package service

import (
	"errors"
	"fmt"
	"math"
	"sort"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/money"
	"github.com/sky/personal-ledger/internal/repository"
	"gorm.io/gorm"
)

var (
	ErrReminderNotFound           = errors.New("reminder not found")
	ErrLinkedDebtBalanceImmutable = errors.New("linked reminder balance is managed by its debt account")
	ErrInvalidReminderPatch       = errors.New("invalid reminder patch")
)

type ReminderService struct {
	repo          *repository.ReminderRepository
	accountRepo   *repository.AccountRepository
	txRepo        *repository.TransactionRepository
	categoryRepo  *repository.CategoryRepository
	accountLogSvc *AccountLogService
	uploadService *UploadService
}

func (s *ReminderService) WithUploadService(uploadService *UploadService) *ReminderService {
	s.uploadService = uploadService
	return s
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
	Name           string        `json:"name"`
	AccountID      *string       `json:"account_id"`
	LoanType       string        `json:"loan_type"`
	PaymentDay     int           `json:"payment_day" binding:"required,min=1,max=31"`
	BillingDay     *int          `json:"billing_day"`
	AdvanceDays    int           `json:"advance_days"`
	Amount         *money.Amount `json:"amount"`
	Principal      *money.Amount `json:"principal"`
	CurrentBalance *money.Amount `json:"current_balance"`
	InterestRate   *float64      `json:"interest_rate"`
	TotalInterest  *money.Amount `json:"total_interest"`
	StartDate      *string       `json:"start_date"`
	TargetDate     *string       `json:"target_date"`
	Color          string        `json:"color"`
	Remark         string        `json:"remark"`
	Evidence       string        `json:"evidence"`
}

func (s *ReminderService) Create(userID uint, req CreateReminderRequest) (*model.Reminder, error) {
	evidence, err := normalizeCreateAttachmentEvidence(req.Evidence)
	if err != nil {
		return nil, err
	}
	accountID := normalizeOptionalString(req.AccountID)
	if err := s.ensureAccountBelongsToUser(accountID, userID); err != nil {
		return nil, err
	}
	if accountID != nil {
		account, err := s.accountRepo.GetByID(*accountID)
		if err != nil || account.UserID != userID {
			return nil, ErrAccountNotFound
		}
		if IsDebtAccount(account.Type) {
			if req.CurrentBalance != nil && roundMoney(*req.CurrentBalance) != roundMoney(account.CurrentBalance) {
				return nil, ErrLinkedDebtBalanceImmutable
			}
			balance := account.CurrentBalance
			req.CurrentBalance = &balance
		}
	}
	reminder := &model.Reminder{
		ID:             uuid.New().String(),
		UserID:         userID,
		Name:           req.Name,
		AccountID:      accountID,
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
		Evidence:       evidence,
		IsEnabled:      true,
	}

	if reminder.LoanType == "" {
		reminder.LoanType = "other"
	}
	if reminder.AdvanceDays == 0 {
		reminder.AdvanceDays = 3
	}
	if req.StartDate != nil {
		parsed, err := parseLocalDate(*req.StartDate)
		if err != nil {
			return nil, ErrInvalidLocalDate
		}
		reminder.StartDate = &parsed
	}
	if req.TargetDate != nil {
		parsed, err := parseLocalDate(*req.TargetDate)
		if err != nil {
			return nil, ErrInvalidLocalDate
		}
		reminder.TargetDate = &parsed
	}

	if err := s.repo.Create(reminder); err != nil {
		return nil, err
	}

	return s.repo.GetByID(reminder.ID)
}

func (s *ReminderService) GetByID(id string, userID uint) (*model.Reminder, error) {
	reminder, err := s.repo.GetByIDForUser(id, userID)
	if err != nil {
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
	if s.uploadService != nil {
		releaseStorage := acquireAttachmentStorageRead()
		defer releaseStorage()
		if !AttachmentStorageAvailable(userID) {
			return nil, ErrAttachmentRecoveryPending
		}
	}
	reminder, err := s.GetByID(id, userID)
	if err != nil {
		return nil, err
	}
	originalUpdatedAt := reminder.UpdatedAt
	accountID := normalizeOptionalString(req.AccountID)
	if err := s.ensureAccountBelongsToUser(accountID, userID); err != nil {
		return nil, err
	}
	if accountID != nil {
		account, err := s.accountRepo.GetByID(*accountID)
		if err != nil || account.UserID != userID {
			return nil, ErrAccountNotFound
		}
		if IsDebtAccount(account.Type) {
			if req.CurrentBalance != nil && roundMoney(*req.CurrentBalance) != roundMoney(account.CurrentBalance) {
				return nil, ErrLinkedDebtBalanceImmutable
			}
			balance := account.CurrentBalance
			req.CurrentBalance = &balance
		}
	}

	reminder.Name = req.Name
	reminder.AccountID = accountID
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
	reminder.Evidence, err = normalizeAttachmentEvidence(req.Evidence, userID, "reminders", exactAttachmentRef(id))
	if err != nil {
		return nil, err
	}
	if s.uploadService != nil {
		if err := s.uploadService.validateStoredAttachmentPaths(userID, reminder.Evidence); err != nil {
			return nil, err
		}
	}

	if req.StartDate != nil {
		parsed, err := parseLocalDate(*req.StartDate)
		if err != nil {
			return nil, ErrInvalidLocalDate
		}
		reminder.StartDate = &parsed
	}
	if req.TargetDate != nil {
		parsed, err := parseLocalDate(*req.TargetDate)
		if err != nil {
			return nil, ErrInvalidLocalDate
		}
		reminder.TargetDate = &parsed
	}

	result := s.txRepo.DB().Model(&model.Reminder{}).
		Where("id = ? AND user_id = ? AND updated_at = ?", id, userID, originalUpdatedAt).
		Updates(map[string]any{
			"name":                  reminder.Name,
			"account_id":            reminder.AccountID,
			"loan_type":             reminder.LoanType,
			"payment_day":           reminder.PaymentDay,
			"billing_day":           reminder.BillingDay,
			"advance_days":          reminder.AdvanceDays,
			"amount_cents":          reminder.Amount,
			"principal_cents":       reminder.Principal,
			"current_balance_cents": reminder.CurrentBalance,
			"interest_rate":         reminder.InterestRate,
			"total_interest_cents":  reminder.TotalInterest,
			"start_date":            reminder.StartDate,
			"target_date":           reminder.TargetDate,
			"color":                 reminder.Color,
			"remark":                reminder.Remark,
			"evidence":              reminder.Evidence,
		})
	if result.Error != nil {
		return nil, result.Error
	}
	if result.RowsAffected != 1 {
		return nil, ErrConcurrentBalanceUpdate
	}

	return s.repo.GetByID(id)
}

type PatchReminderRequest struct {
	Name           Optional[string]       `json:"name"`
	AccountID      Optional[string]       `json:"account_id"`
	LoanType       Optional[string]       `json:"loan_type"`
	PaymentDay     Optional[int]          `json:"payment_day"`
	BillingDay     Optional[int]          `json:"billing_day"`
	AdvanceDays    Optional[int]          `json:"advance_days"`
	Amount         Optional[money.Amount] `json:"amount"`
	Principal      Optional[money.Amount] `json:"principal"`
	CurrentBalance Optional[money.Amount] `json:"current_balance"`
	InterestRate   Optional[float64]      `json:"interest_rate"`
	TotalInterest  Optional[money.Amount] `json:"total_interest"`
	StartDate      Optional[string]       `json:"start_date"`
	TargetDate     Optional[string]       `json:"target_date"`
	Color          Optional[string]       `json:"color"`
	Remark         Optional[string]       `json:"remark"`
	Evidence       Optional[string]       `json:"evidence"`
}

func (s *ReminderService) Patch(id string, userID uint, req PatchReminderRequest) (*model.Reminder, error) {
	if s.uploadService != nil {
		releaseStorage := acquireAttachmentStorageRead()
		defer releaseStorage()
		if !AttachmentStorageAvailable(userID) {
			return nil, ErrAttachmentRecoveryPending
		}
	}
	reminder, err := s.GetByID(id, userID)
	if err != nil {
		return nil, err
	}
	updates := map[string]any{}
	if req.Name.Set {
		if req.Name.Null || req.Name.Value == "" {
			return nil, ErrInvalidReminderPatch
		}
		updates["name"] = req.Name.Value
	}
	if req.LoanType.Set {
		if req.LoanType.Null || req.LoanType.Value == "" {
			return nil, ErrInvalidReminderPatch
		}
		updates["loan_type"] = req.LoanType.Value
	}
	if req.PaymentDay.Set {
		if req.PaymentDay.Null || req.PaymentDay.Value < 1 || req.PaymentDay.Value > 31 {
			return nil, ErrInvalidReminderPatch
		}
		updates["payment_day"] = req.PaymentDay.Value
	}
	if err := addReminderOptionalDayPatch(updates, "billing_day", req.BillingDay); err != nil {
		return nil, err
	}
	if req.AdvanceDays.Set {
		if req.AdvanceDays.Null || req.AdvanceDays.Value < 0 || req.AdvanceDays.Value > 365 {
			return nil, ErrInvalidReminderPatch
		}
		updates["advance_days"] = req.AdvanceDays.Value
	}
	for column, field := range map[string]Optional[string]{
		"color": req.Color, "remark": req.Remark,
	} {
		if field.Set {
			if field.Null {
				updates[column] = ""
			} else {
				updates[column] = field.Value
			}
		}
	}
	if req.Evidence.Set {
		if req.Evidence.Null {
			updates["evidence"] = ""
		} else {
			evidence, err := normalizeAttachmentEvidence(req.Evidence.Value, userID, "reminders", exactAttachmentRef(id))
			if err != nil {
				return nil, err
			}
			if s.uploadService != nil {
				if err := s.uploadService.validateStoredAttachmentPaths(userID, evidence); err != nil {
					return nil, err
				}
			}
			updates["evidence"] = evidence
		}
	}
	for column, field := range map[string]Optional[money.Amount]{
		"amount_cents": req.Amount, "principal_cents": req.Principal, "total_interest_cents": req.TotalInterest,
	} {
		if err := addReminderOptionalMoneyPatch(updates, column, field); err != nil {
			return nil, err
		}
	}
	if req.InterestRate.Set {
		if req.InterestRate.Null {
			updates["interest_rate"] = nil
		} else if math.IsNaN(req.InterestRate.Value) || math.IsInf(req.InterestRate.Value, 0) || req.InterestRate.Value < 0 || req.InterestRate.Value > 100 {
			return nil, ErrInvalidReminderPatch
		} else {
			updates["interest_rate"] = req.InterestRate.Value
		}
	}
	if err := addReminderOptionalDatePatch(updates, "start_date", req.StartDate); err != nil {
		return nil, err
	}
	if err := addReminderOptionalDatePatch(updates, "target_date", req.TargetDate); err != nil {
		return nil, err
	}

	targetAccountID := reminder.AccountID
	if req.AccountID.Set {
		if req.AccountID.Null || req.AccountID.Value == "" {
			targetAccountID = nil
			updates["account_id"] = nil
		} else {
			value := req.AccountID.Value
			targetAccountID = &value
			updates["account_id"] = value
		}
	}
	var linkedDebtAccount *model.Account
	if targetAccountID != nil {
		account, err := s.accountRepo.GetByID(*targetAccountID)
		if err != nil || account.UserID != userID {
			return nil, ErrAccountNotFound
		}
		if IsDebtAccount(account.Type) {
			linkedDebtAccount = account
		}
	}
	if linkedDebtAccount != nil {
		if req.CurrentBalance.Set && (req.CurrentBalance.Null || roundMoney(req.CurrentBalance.Value) != roundMoney(linkedDebtAccount.CurrentBalance)) {
			return nil, ErrLinkedDebtBalanceImmutable
		}
		updates["current_balance_cents"] = linkedDebtAccount.CurrentBalance
	} else if err := addReminderOptionalMoneyPatch(updates, "current_balance_cents", req.CurrentBalance); err != nil {
		return nil, err
	}

	if len(updates) == 0 {
		return reminder, nil
	}
	result := s.txRepo.DB().Model(&model.Reminder{}).
		Where("id = ? AND user_id = ? AND updated_at = ?", id, userID, reminder.UpdatedAt).
		Updates(updates)
	if result.Error != nil {
		return nil, result.Error
	}
	if result.RowsAffected != 1 {
		return nil, ErrConcurrentBalanceUpdate
	}
	return s.repo.GetByID(id)
}

func addReminderOptionalDayPatch(updates map[string]any, column string, field Optional[int]) error {
	if !field.Set {
		return nil
	}
	if field.Null {
		updates[column] = nil
		return nil
	}
	if field.Value < 1 || field.Value > 31 {
		return ErrInvalidReminderPatch
	}
	updates[column] = field.Value
	return nil
}

func addReminderOptionalMoneyPatch(updates map[string]any, column string, field Optional[money.Amount]) error {
	if !field.Set {
		return nil
	}
	if field.Null {
		updates[column] = nil
		return nil
	}
	if !field.Value.IsValid() || field.Value < 0 {
		return ErrInvalidReminderPatch
	}
	updates[column] = field.Value
	return nil
}

func addReminderOptionalDatePatch(updates map[string]any, column string, field Optional[string]) error {
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

func (s *ReminderService) ensureAccountBelongsToUser(accountID *string, userID uint) error {
	if accountID == nil {
		return nil
	}
	account, err := s.accountRepo.GetByID(*accountID)
	if err != nil || account.UserID != userID {
		return ErrAccountNotFound
	}
	return nil
}

func (s *ReminderService) Delete(id string, userID uint) error {
	_, err := s.GetByID(id, userID)
	if err != nil {
		return err
	}

	return s.txRepo.DB().Transaction(func(txdb *gorm.DB) error {
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
	if err := s.txRepo.DB().Model(&model.Reminder{}).
		Where("id = ? AND user_id = ?", id, userID).
		Update("is_enabled", reminder.IsEnabled).Error; err != nil {
		return nil, err
	}

	return reminder, nil
}

type RecordPaymentRequest struct {
	Amount          money.Amount `json:"amount" binding:"required,gt=0"`
	PrincipalAmount money.Amount `json:"principal_amount"`
	InterestAmount  money.Amount `json:"interest_amount"`
	AccountID       *string      `json:"account_id"`
}

func (s *ReminderService) RecordPayment(id string, userID uint, req RecordPaymentRequest) (*model.Reminder, error) {
	principalPaid, interestPaid, err := normalizeReminderPaymentSplit(req)
	if err != nil {
		return nil, err
	}
	sourceAccountID := normalizeOptionalString(req.AccountID)

	if err := financeWriteTransaction(s.txRepo.DB(), func(txdb *gorm.DB) error {
		var reminder model.Reminder
		if err := financeQueryForUpdate(txdb).
			First(&reminder, "id = ? AND user_id = ?", id, userID).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return ErrReminderNotFound
			}
			return err
		}
		if sourceAccountID != nil && reminder.AccountID != nil && *reminder.AccountID != "" && *sourceAccountID == *reminder.AccountID {
			return ErrSameAccount
		}

		// Validate against the balance read in this transaction. PostgreSQL and
		// MySQL hold a row lock; SQLite serializes this service path and still
		// verifies the previous values in the conditional update below.
		if reminder.CurrentBalance != nil && principalPaid > *reminder.CurrentBalance {
			return fmt.Errorf("还款金额不能超过待还金额 ¥%.2f", reminder.CurrentBalance.Float64())
		}

		nextTotalPaid := reminder.TotalPaid.Add(req.Amount)
		nextInterestPaid := reminder.InterestPaid.Add(interestPaid)
		nextCurrentBalance := reminder.CurrentBalance
		var nextPaidOffAt *time.Time
		if reminder.PaidOffAt != nil {
			nextPaidOffAt = reminder.PaidOffAt
		}
		if reminder.CurrentBalance != nil {
			newBalance := reminder.CurrentBalance.Sub(principalPaid)
			if newBalance < 0 {
				newBalance = 0
			}
			nextCurrentBalance = &newBalance
			if newBalance == 0 {
				now := time.Now()
				nextPaidOffAt = &now
			}
		}

		updateQuery := txdb.Model(&model.Reminder{}).
			Where(
				"id = ? AND user_id = ? AND total_paid_cents = ? AND interest_paid_cents = ?",
				reminder.ID,
				userID,
				reminder.TotalPaid.Cents(),
				reminder.InterestPaid.Cents(),
			)
		if reminder.CurrentBalance == nil {
			updateQuery = updateQuery.Where("current_balance_cents IS NULL")
		} else {
			updateQuery = updateQuery.Where("current_balance_cents = ?", reminder.CurrentBalance.Cents())
		}
		result := updateQuery.
			Updates(map[string]any{
				"total_paid_cents":      nextTotalPaid,
				"interest_paid_cents":   nextInterestPaid,
				"current_balance_cents": nextCurrentBalance,
				"paid_off_at":           nextPaidOffAt,
			})
		if result.Error != nil {
			return result.Error
		}
		if result.RowsAffected != 1 {
			return ErrConcurrentBalanceUpdate
		}

		accounts, err := getAccountsForUserTx(txdb, userID, sourceAccountID, reminder.AccountID)
		if err != nil {
			return err
		}
		var sourceAccount *model.Account
		if sourceAccountID != nil {
			sourceAccount = accounts[*sourceAccountID]
		}
		var debtAccount *model.Account
		if reminder.AccountID != nil && *reminder.AccountID != "" {
			debtAccount = accounts[*reminder.AccountID]
		}

		var paymentTransaction *model.Transaction
		if sourceAccount != nil {
			paymentTransaction, err = s.createPaymentTransactionTx(txdb, userID, &reminder, req, principalPaid, interestPaid, sourceAccount)
			if err != nil {
				return err
			}
		}

		if debtAccount != nil {
			var transactionID *string
			if paymentTransaction != nil {
				transactionID = &paymentTransaction.ID
			}
			if err := applyDebtAccountPaymentTx(
				txdb,
				debtAccount,
				userID,
				principalPaid,
				s.accountLogSvc,
				transactionID,
				&reminder.ID,
			); err != nil {
				return err
			}
		}
		return nil
	}); err != nil {
		return nil, err
	}
	return s.repo.GetByID(id)
}

func normalizeReminderPaymentSplit(req RecordPaymentRequest) (money.Amount, money.Amount, error) {
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
		principalPaid = req.Amount.Sub(interestPaid)
	}
	if interestPaid == 0 {
		interestPaid = req.Amount.Sub(principalPaid)
	}
	if principalPaid < 0 || interestPaid < 0 || principalPaid.Add(interestPaid).Cents() != req.Amount.Cents() {
		return 0, 0, fmt.Errorf("本金+利息必须等于还款金额")
	}
	return principalPaid, interestPaid, nil
}

func (s *ReminderService) createPaymentTransactionTx(txdb *gorm.DB, userID uint, reminder *model.Reminder, req RecordPaymentRequest, principalPaid money.Amount, interestPaid money.Amount, sourceAccount *model.Account) (*model.Transaction, error) {
	repaymentCategoryID, err := s.findOrCreateRepaymentCategoryTx(txdb, userID)
	if err != nil {
		return nil, err
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
		return nil, err
	}

	balanceDelta, err := accountBalanceDeltaTx(txdb, userID, sourceAccount.ID, req.Amount.Negate())
	if err != nil {
		return nil, err
	}
	if err := applyAccountBalanceMutationTx(
		txdb,
		s.accountLogSvc,
		userID,
		sourceAccount.ID,
		"expense",
		req.Amount,
		balanceDelta,
		&tx.ID,
		&reminder.ID,
		nil,
		remark,
		true,
	); err != nil {
		return nil, err
	}
	return tx, nil
}

func applyDebtAccountPaymentTx(
	txdb *gorm.DB,
	account *model.Account,
	userID uint,
	principalPaid money.Amount,
	accountLogSvc *AccountLogService,
	transactionID *string,
	reminderID *string,
) error {
	if principalPaid == 0 {
		return nil
	}
	if account == nil {
		return ErrAccountNotFound
	}

	nextBalance := account.CurrentBalance.Sub(principalPaid)
	if nextBalance < 0 {
		nextBalance = 0
	}
	if err := logAccountBalanceChangeTx(
		txdb,
		accountLogSvc,
		userID,
		account.ID,
		"adjustment",
		principalPaid,
		nextBalance.Sub(account.CurrentBalance),
		transactionID,
		reminderID,
		nil,
		"还款减少负债",
		true,
	); err != nil {
		return err
	}

	result := txdb.Model(&model.Account{}).
		Where("id = ? AND user_id = ?", account.ID, userID).
		Updates(map[string]any{
			"current_balance_cents": nextBalance,
			"total_paid_cents":      roundedTotalPaidDelta(txdb, principalPaid),
		})
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected != 1 {
		return ErrAccountNotFound
	}

	return txdb.Model(&model.Account{}).
		Where("id = ? AND user_id = ? AND current_balance_cents <= 0", account.ID, userID).
		Update("paid_off_at", time.Now()).Error
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
	if err := financeQueryForUpdate(txdb).
		First(&account, "id = ? AND user_id = ?", accountID, userID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrAccountNotFound
		}
		return nil, err
	}
	return &account, nil
}

func getAccountsForUserTx(txdb *gorm.DB, userID uint, accountIDs ...*string) (map[string]*model.Account, error) {
	uniqueIDs := make(map[string]struct{})
	for _, accountID := range accountIDs {
		if accountID != nil && *accountID != "" {
			uniqueIDs[*accountID] = struct{}{}
		}
	}

	orderedIDs := make([]string, 0, len(uniqueIDs))
	for accountID := range uniqueIDs {
		orderedIDs = append(orderedIDs, accountID)
	}
	sort.Strings(orderedIDs)

	accounts := make(map[string]*model.Account, len(orderedIDs))
	for _, accountID := range orderedIDs {
		account, err := getAccountForUserTx(txdb, accountID, userID)
		if err != nil {
			return nil, err
		}
		accounts[accountID] = account
	}
	return accounts, nil
}

type ReminderDebtSummary struct {
	TotalDebt       money.Amount `json:"total_debt"`      // 待还总额
	TotalPaid       money.Amount `json:"total_paid"`      // 已还金额 (本金 - 待还)
	TotalPrincipal  money.Amount `json:"total_principal"` // 共需还金额 (本金总额)
	Progress        float64      `json:"progress"`
	ActiveLoans     int          `json:"active_loans"`
	PaidOffLoans    int          `json:"paid_off_loans"`
	NextPaymentDay  int          `json:"next_payment_day"`
	NextPaymentName string       `json:"next_payment_name"`
	DaysUntilNext   int          `json:"days_until_next"`
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
			summary.TotalPrincipal = summary.TotalPrincipal.Add(*r.Principal)
		}
		if r.CurrentBalance != nil {
			summary.TotalDebt = summary.TotalDebt.Add(*r.CurrentBalance)
		}
		// 已还金额 = 本金 - 待还 (不使用 r.TotalPaid，因为它可能包含利息)
		if r.Principal != nil && r.CurrentBalance != nil {
			paid := r.Principal.Sub(*r.CurrentBalance)
			if paid > 0 {
				summary.TotalPaid = summary.TotalPaid.Add(paid)
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
		summary.Progress = float64(summary.TotalPaid.Cents()) / float64(summary.TotalPrincipal.Cents()) * 100
	}

	return summary, nil
}
