package service

import (
	"encoding/json"
	"errors"
	"math"
	"sort"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

var (
	ErrTransactionNotFound         = errors.New("transaction not found")
	ErrSameAccount                 = errors.New("source and target account must be different")
	ErrInvalidTransactionAmount    = errors.New("transaction amount must be greater than zero")
	ErrInvalidTransactionType      = errors.New("invalid transaction type")
	ErrCategoryTypeMismatch        = errors.New("category type does not match transaction type")
	ErrManagedTransactionImmutable = errors.New("managed transaction cannot be updated directly")
	ErrSystemTransactionImmutable  = errors.New("system transaction cannot be changed directly")
)

type TransactionService struct {
	txRepo           *repository.TransactionRepository
	accountRepo      *repository.AccountRepository
	reminderRepo     *repository.ReminderRepository
	lendingRepo      *repository.LendingRepository
	familyMemberRepo *repository.FamilyMemberRepository
	accountLogSvc    *AccountLogService
}

func NewTransactionService(
	txRepo *repository.TransactionRepository,
	accountRepo *repository.AccountRepository,
	reminderRepo *repository.ReminderRepository,
	lendingRepo *repository.LendingRepository,
	familyMemberRepo *repository.FamilyMemberRepository,
	accountLogSvc *AccountLogService,
) *TransactionService {
	return &TransactionService{
		txRepo:           txRepo,
		accountRepo:      accountRepo,
		reminderRepo:     reminderRepo,
		lendingRepo:      lendingRepo,
		familyMemberRepo: familyMemberRepo,
		accountLogSvc:    accountLogSvc,
	}
}

type CreateTransactionRequest struct {
	Type              string  `json:"type" binding:"required,oneof=income expense transfer"`
	Amount            float64 `json:"amount" binding:"required,gt=0"`
	AccountID         string  `json:"account_id" binding:"required"`
	ToAccountID       *string `json:"to_account_id"`
	CategoryID        *string `json:"category_id"`
	TransactionDate   string  `json:"transaction_date" binding:"required"`
	Remark            string  `json:"remark"`
	Images            string  `json:"images"`
	Tags              string  `json:"tags"`
	MemberID          *string `json:"member_id"`
	PaidByMemberID    *string `json:"paid_by_member_id"`
	importFingerprint *string
}

func (s *TransactionService) Create(userID uint, req CreateTransactionRequest) (*model.Transaction, error) {
	var transaction *model.Transaction
	if err := s.txRepo.DB().Transaction(func(txdb *gorm.DB) error {
		var err error
		transaction, err = s.createWithTx(txdb, userID, req, "manual")
		return err
	}); err != nil {
		return nil, err
	}

	return transaction, nil
}

func (s *TransactionService) createWithTx(txdb *gorm.DB, userID uint, req CreateTransactionRequest, source string) (*model.Transaction, error) {
	if err := validateTransactionRequest(req); err != nil {
		return nil, err
	}
	if err := s.validateTransactionReferencesTx(txdb, userID, req); err != nil {
		return nil, err
	}

	txDate, err := parseTransactionDate(req.TransactionDate)
	if err != nil {
		return nil, err
	}

	transaction := &model.Transaction{
		ID:                uuid.New().String(),
		UserID:            userID,
		AccountID:         req.AccountID,
		CategoryID:        req.CategoryID,
		Type:              req.Type,
		Amount:            req.Amount,
		TransactionDate:   txDate,
		Remark:            req.Remark,
		Images:            req.Images,
		Tags:              req.Tags,
		ToAccountID:       req.ToAccountID,
		MemberID:          req.MemberID,
		PaidByMemberID:    req.PaidByMemberID,
		Source:            source,
		ImportFingerprint: req.importFingerprint,
	}

	// Lock every balance-bearing account in stable ID order before inserting
	// the transaction row. On databases with foreign keys, inserting first can
	// acquire weaker reference locks in an inconsistent order and make reverse
	// transfers more prone to deadlocks.
	if err := lockBalanceAccountsTx(txdb, transaction); err != nil {
		return nil, err
	}
	if err := txdb.Create(transaction).Error; err != nil {
		return nil, err
	}
	if err := s.applyBalanceChangesTx(txdb, transaction, true); err != nil {
		return nil, err
	}
	if err := repository.NewTagRepository(txdb).IncrementUsedCountsByNames(userID, transactionTagNames(transaction.Tags)); err != nil {
		return nil, err
	}
	return s.txRepo.GetByIDForUserWithDB(txdb, transaction.ID, userID)
}

func validateTransactionRequest(req CreateTransactionRequest) error {
	if req.Type != "income" && req.Type != "expense" && req.Type != "transfer" {
		return ErrInvalidTransactionType
	}
	if req.Amount <= 0 || math.IsNaN(req.Amount) || math.IsInf(req.Amount, 0) {
		return ErrInvalidTransactionAmount
	}
	if req.AccountID == "" {
		return ErrAccountNotFound
	}
	return nil
}

func (s *TransactionService) validateTransactionReferencesTx(txdb *gorm.DB, userID uint, req CreateTransactionRequest) error {
	if req.Type == "transfer" {
		if req.ToAccountID == nil || *req.ToAccountID == "" || *req.ToAccountID == req.AccountID {
			return ErrSameAccount
		}
	}
	if err := ensureAccountBelongsToUserTx(txdb, req.AccountID, userID); err != nil {
		return err
	}
	if req.Type == "transfer" {
		if err := ensureAccountBelongsToUserTx(txdb, *req.ToAccountID, userID); err != nil {
			return err
		}
	}
	if req.CategoryID != nil && *req.CategoryID != "" {
		var category model.Category
		if err := txdb.First(&category, "id = ? AND user_id = ?", *req.CategoryID, userID).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return ErrCategoryNotFound
			}
			return err
		}
		if req.Type != "transfer" && category.Type != req.Type {
			return ErrCategoryTypeMismatch
		}
	}
	if req.MemberID != nil && *req.MemberID != "" {
		if err := ensureFamilyMemberBelongsToUserTx(txdb, *req.MemberID, userID); err != nil {
			return err
		}
	}
	if req.PaidByMemberID != nil && *req.PaidByMemberID != "" {
		return ensureFamilyMemberBelongsToUserTx(txdb, *req.PaidByMemberID, userID)
	}
	return nil
}

func ensureAccountBelongsToUserTx(txdb *gorm.DB, accountID string, userID uint) error {
	var account model.Account
	if err := txdb.Select("id").First(&account, "id = ? AND user_id = ?", accountID, userID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrAccountNotFound
		}
		return err
	}
	return nil
}

func ensureFamilyMemberBelongsToUserTx(txdb *gorm.DB, memberID string, userID uint) error {
	var member model.FamilyMember
	if err := txdb.Select("id").First(&member, "id = ? AND user_id = ?", memberID, userID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrFamilyMemberNotFound
		}
		return err
	}
	return nil
}

func parseTransactionDate(value string) (time.Time, error) {
	location := time.Local
	layouts := []string{
		time.RFC3339Nano,
		time.RFC3339,
		"2006-01-02T15:04:05.999999",
		"2006-01-02T15:04:05",
		"2006-01-02 15:04:05",
		"2006-01-02",
	}
	var lastErr error
	for _, layout := range layouts {
		txDate, err := time.ParseInLocation(layout, value, location)
		if err == nil {
			// Current clients submit explicit RFC3339 instants. Legacy native
			// clients may still send local timestamps without an offset. Persist
			// both forms in the ledger's local location so calendar-day filters
			// have one consistent interpretation.
			return txDate.In(location), nil
		}
		lastErr = err
	}
	return time.Time{}, lastErr
}

func transactionTagNames(raw string) []string {
	if strings.TrimSpace(raw) == "" {
		return nil
	}

	var decoded any
	var names []string
	if err := json.Unmarshal([]byte(raw), &decoded); err == nil {
		switch value := decoded.(type) {
		case []any:
			for _, item := range value {
				if name, ok := item.(string); ok {
					names = append(names, name)
				}
			}
		case string:
			names = append(names, value)
		}
	} else {
		names = strings.Split(raw, ",")
	}

	for i := range names {
		names[i] = strings.TrimSpace(names[i])
	}
	return uniqueSortedStrings(names)
}

func transactionTagNameDiff(currentRaw string, nextRaw string) (removed []string, added []string) {
	current := transactionTagNames(currentRaw)
	next := transactionTagNames(nextRaw)
	currentSet := make(map[string]struct{}, len(current))
	nextSet := make(map[string]struct{}, len(next))
	for _, name := range current {
		currentSet[name] = struct{}{}
	}
	for _, name := range next {
		nextSet[name] = struct{}{}
	}
	for _, name := range current {
		if _, exists := nextSet[name]; !exists {
			removed = append(removed, name)
		}
	}
	for _, name := range next {
		if _, exists := currentSet[name]; !exists {
			added = append(added, name)
		}
	}
	return removed, added
}

func uniqueSortedStrings(values []string) []string {
	seen := make(map[string]struct{}, len(values))
	unique := make([]string, 0, len(values))
	for _, value := range values {
		if value == "" {
			continue
		}
		if _, exists := seen[value]; exists {
			continue
		}
		seen[value] = struct{}{}
		unique = append(unique, value)
	}
	sort.Strings(unique)
	return unique
}

func (s *TransactionService) GetByID(id string, userID uint) (*model.Transaction, error) {
	tx, err := s.txRepo.GetByIDForUser(id, userID)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrTransactionNotFound
		}
		return nil, err
	}
	return tx, nil
}

type ListTransactionRequest struct {
	Page          int     `form:"page"`
	PageSize      int     `form:"page_size"`
	StartDate     string  `form:"start_date"`
	EndDate       string  `form:"end_date"`
	Type          string  `form:"type"`
	AccountID     string  `form:"account_id"`
	CategoryID    string  `form:"category_id"`
	MinAmount     float64 `form:"min_amount"`
	MaxAmount     float64 `form:"max_amount"`
	Keyword       string  `form:"keyword"`
	IncludeSystem bool    `form:"include_system"`
}

type ListTransactionResponse struct {
	List     []model.Transaction `json:"list"`
	Total    int64               `json:"total"`
	Page     int                 `json:"page"`
	PageSize int                 `json:"page_size"`
}

func (s *TransactionService) List(userID uint, req ListTransactionRequest) (*ListTransactionResponse, error) {
	if req.Page <= 0 {
		req.Page = 1
	}
	if req.PageSize <= 0 || req.PageSize > 100 {
		req.PageSize = 20
	}

	filter := repository.TransactionFilter{
		UserID:        userID,
		Type:          req.Type,
		AccountID:     req.AccountID,
		CategoryID:    req.CategoryID,
		Keyword:       req.Keyword,
		IncludeSystem: req.IncludeSystem,
		Page:          req.Page,
		PageSize:      req.PageSize,
	}

	if req.StartDate != "" {
		t, err := time.ParseInLocation("2006-01-02", req.StartDate, time.Local)
		if err != nil {
			return nil, err
		}
		filter.StartDate = &t
	}
	if req.EndDate != "" {
		t, err := time.ParseInLocation("2006-01-02", req.EndDate, time.Local)
		if err != nil {
			return nil, err
		}
		endOfDay := t.AddDate(0, 0, 1).Add(-time.Nanosecond)
		filter.EndDate = &endOfDay
	}
	if req.MinAmount > 0 {
		filter.MinAmount = &req.MinAmount
	}
	if req.MaxAmount > 0 {
		filter.MaxAmount = &req.MaxAmount
	}

	list, total, err := s.txRepo.List(filter)
	if err != nil {
		return nil, err
	}

	return &ListTransactionResponse{
		List:     list,
		Total:    total,
		Page:     req.Page,
		PageSize: req.PageSize,
	}, nil
}

func (s *TransactionService) Update(id string, userID uint, req CreateTransactionRequest) (*model.Transaction, error) {
	if err := validateTransactionRequest(req); err != nil {
		return nil, err
	}

	txDate, err := parseTransactionDate(req.TransactionDate)
	if err != nil {
		return nil, err
	}

	var updated *model.Transaction
	if err := s.txRepo.DB().Transaction(func(txdb *gorm.DB) error {
		current, err := s.txRepo.GetByIDForUserWithDB(
			txdb.Clauses(clause.Locking{Strength: "UPDATE"}),
			id,
			userID,
		)
		if err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return ErrTransactionNotFound
			}
			return err
		}
		if isSystemTransaction(current) {
			return ErrSystemTransactionImmutable
		}
		if isBusinessManagedTransaction(current) {
			return ErrManagedTransactionImmutable
		}
		if err := s.validateTransactionReferencesTx(txdb, userID, req); err != nil {
			return err
		}

		next := &model.Transaction{
			ID:              current.ID,
			UserID:          userID,
			AccountID:       req.AccountID,
			CategoryID:      req.CategoryID,
			Type:            req.Type,
			Amount:          req.Amount,
			TransactionDate: txDate,
			Remark:          req.Remark,
			Images:          req.Images,
			Tags:            req.Tags,
			ToAccountID:     req.ToAccountID,
			MemberID:        req.MemberID,
			PaidByMemberID:  req.PaidByMemberID,
			Source:          current.Source,
		}
		if err := lockBalanceAccountsTx(txdb, current, next); err != nil {
			return err
		}
		if err := s.revertBalanceChangesTx(txdb, current, true); err != nil {
			return err
		}
		result := txdb.Model(&model.Transaction{}).
			Where("id = ? AND user_id = ?", id, userID).
			Updates(map[string]any{
				"account_id":        req.AccountID,
				"category_id":       req.CategoryID,
				"type":              req.Type,
				"amount":            req.Amount,
				"transaction_date":  txDate,
				"remark":            req.Remark,
				"images":            req.Images,
				"tags":              req.Tags,
				"to_account_id":     req.ToAccountID,
				"member_id":         req.MemberID,
				"paid_by_member_id": req.PaidByMemberID,
			})
		if result.Error != nil {
			return result.Error
		}
		if result.RowsAffected != 1 {
			return ErrTransactionNotFound
		}
		if err := s.applyBalanceChangesTx(txdb, next, true); err != nil {
			return err
		}
		removedTags, addedTags := transactionTagNameDiff(current.Tags, next.Tags)
		tagRepo := repository.NewTagRepository(txdb)
		if err := tagRepo.DecrementUsedCountsByNames(userID, removedTags); err != nil {
			return err
		}
		if err := tagRepo.IncrementUsedCountsByNames(userID, addedTags); err != nil {
			return err
		}
		updated, err = s.txRepo.GetByIDForUserWithDB(txdb, id, userID)
		return err
	}); err != nil {
		return nil, err
	}

	return updated, nil
}

func (s *TransactionService) Delete(id string, userID uint) error {
	return s.txRepo.DB().Transaction(func(txdb *gorm.DB) error {
		return s.deleteWithTx(txdb, id, userID)
	})
}

func (s *TransactionService) deleteWithTx(txdb *gorm.DB, id string, userID uint) error {
	transaction, err := s.txRepo.GetByIDForUserWithDB(
		txdb.Clauses(clause.Locking{Strength: "UPDATE"}),
		id,
		userID,
	)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrTransactionNotFound
		}
		return err
	}
	if isSystemTransaction(transaction) {
		return ErrSystemTransactionImmutable
	}

	reminder, err := loadLinkedReminderForRollbackTx(txdb, transaction)
	if err != nil {
		return err
	}
	accountsToLock := []*model.Transaction{transaction}
	if reminder != nil && reminder.AccountID != nil && *reminder.AccountID != "" {
		accountsToLock = append(accountsToLock, &model.Transaction{
			UserID:    userID,
			AccountID: *reminder.AccountID,
		})
	}
	if err := lockBalanceAccountsTx(txdb, accountsToLock...); err != nil {
		return err
	}
	if err := s.revertBalanceChangesTx(txdb, transaction, true); err != nil {
		return err
	}
	if err := s.revertReminderPaymentTx(txdb, transaction, reminder); err != nil {
		return err
	}
	if err := s.revertLendingTransactionTx(txdb, transaction); err != nil {
		return err
	}

	result := txdb.Where("id = ? AND user_id = ?", id, userID).Delete(&model.Transaction{})
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected != 1 {
		return ErrTransactionNotFound
	}
	if err := repository.NewTagRepository(txdb).DecrementUsedCountsByNames(userID, transactionTagNames(transaction.Tags)); err != nil {
		return err
	}
	return nil
}

func normalizedTransactionSource(transaction *model.Transaction) string {
	if transaction == nil {
		return ""
	}
	return strings.ToLower(strings.TrimSpace(transaction.Source))
}

func isSystemTransaction(transaction *model.Transaction) bool {
	return normalizedTransactionSource(transaction) == "system"
}

func isBusinessManagedTransaction(transaction *model.Transaction) bool {
	if transaction == nil {
		return false
	}
	source := normalizedTransactionSource(transaction)
	return source == "lending" || source == "reminder" ||
		transaction.LendingID != nil || transaction.ReminderID != nil
}

func loadLinkedReminderForRollbackTx(txdb *gorm.DB, tx *model.Transaction) (*model.Reminder, error) {
	if tx.ReminderID == nil || *tx.ReminderID == "" {
		return nil, nil
	}

	var reminder model.Reminder
	if err := txdb.Unscoped().Clauses(clause.Locking{Strength: "UPDATE"}).
		First(&reminder, "id = ? AND user_id = ?", *tx.ReminderID, tx.UserID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, err
	}
	return &reminder, nil
}

// revertReminderPaymentTx reverts reminder and debt-account state atomically
// with the linked transaction deletion.
func (s *TransactionService) revertReminderPaymentTx(txdb *gorm.DB, tx *model.Transaction, reminder *model.Reminder) error {
	if reminder == nil {
		return nil
	}

	amount := tx.Amount
	principalAmount := tx.PrincipalAmount
	if principalAmount == 0 {
		principalAmount = amount
	}
	interestAmount := tx.InterestAmount
	if interestAmount == 0 && amount > principalAmount {
		interestAmount = amount - principalAmount
	}

	reminder.TotalPaid -= amount
	if reminder.TotalPaid < 0 {
		reminder.TotalPaid = 0
	}
	reminder.InterestPaid -= interestAmount
	if reminder.InterestPaid < 0 {
		reminder.InterestPaid = 0
	}

	if reminder.CurrentBalance != nil {
		newBalance := *reminder.CurrentBalance + principalAmount
		reminder.CurrentBalance = &newBalance
	}

	if reminder.PaidOffAt != nil && reminder.CurrentBalance != nil && *reminder.CurrentBalance > 0 {
		reminder.PaidOffAt = nil
	}

	result := txdb.Unscoped().Model(&model.Reminder{}).
		Where("id = ? AND user_id = ?", reminder.ID, tx.UserID).
		Updates(map[string]any{
			"total_paid":      reminder.TotalPaid,
			"interest_paid":   reminder.InterestPaid,
			"current_balance": reminder.CurrentBalance,
			"paid_off_at":     reminder.PaidOffAt,
		})
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected != 1 {
		return ErrReminderNotFound
	}

	if reminder.AccountID != nil && *reminder.AccountID != "" {
		var account model.Account
		if err := txdb.Clauses(clause.Locking{Strength: "UPDATE"}).
			First(&account, "id = ? AND user_id = ?", *reminder.AccountID, tx.UserID).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return ErrAccountNotFound
			}
			return err
		}
		account.CurrentBalance += principalAmount
		account.TotalPaid -= principalAmount
		if account.TotalPaid < 0 {
			account.TotalPaid = 0
		}
		if account.PaidOffAt != nil && account.CurrentBalance > 0 {
			account.PaidOffAt = nil
		}
		if err := logAccountBalanceChangeTx(
			txdb,
			s.accountLogSvc,
			tx.UserID,
			account.ID,
			"rollback",
			principalAmount,
			principalAmount,
			&tx.ID,
			&reminder.ID,
			nil,
			"撤回还款负债调整",
			true,
		); err != nil {
			return err
		}
		result := txdb.Model(&model.Account{}).
			Where("id = ? AND user_id = ?", account.ID, tx.UserID).
			Updates(map[string]any{
				"current_balance": account.CurrentBalance,
				"total_paid":      account.TotalPaid,
				"paid_off_at":     account.PaidOffAt,
			})
		if result.Error != nil {
			return result.Error
		}
		if result.RowsAffected != 1 {
			return ErrAccountNotFound
		}
	}
	return nil
}

// revertLendingTransactionTx reverts lending totals when a linked transaction is deleted.
func (s *TransactionService) revertLendingTransactionTx(txdb *gorm.DB, tx *model.Transaction) error {
	if tx.LendingID == nil || *tx.LendingID == "" {
		return nil
	}

	var lending model.Lending
	if err := txdb.Unscoped().Clauses(clause.Locking{Strength: "UPDATE"}).
		First(&lending, "id = ? AND user_id = ?", *tx.LendingID, tx.UserID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil
		}
		return err
	}
	originalBalance := lending.CurrentBalance
	originalTotalRepaid := lending.TotalRepaid
	originalIsSettled := lending.IsSettled

	isRepayment := (lending.Type == "lend_out" && tx.Type == "income") ||
		(lending.Type == "borrow_in" && tx.Type == "expense")

	if isRepayment {
		lending.TotalRepaid -= tx.Amount
		if lending.TotalRepaid < 0 {
			lending.TotalRepaid = 0
		}
		lending.CurrentBalance += tx.Amount

		if lending.IsSettled && lending.CurrentBalance > 0 {
			lending.IsSettled = false
			lending.SettledAt = nil
		}

		if err := txdb.Where("user_id = ? AND transaction_id = ?", tx.UserID, tx.ID).
			Delete(&model.LendingRecord{}).Error; err != nil {
			return err
		}
	} else {
		lending.CurrentBalance -= tx.Amount
		if lending.CurrentBalance < 0 {
			lending.CurrentBalance = 0
		}
	}

	result := txdb.Unscoped().Model(&model.Lending{}).
		Where(
			"id = ? AND user_id = ? AND current_balance = ? AND total_repaid = ? AND is_settled = ?",
			lending.ID,
			tx.UserID,
			originalBalance,
			originalTotalRepaid,
			originalIsSettled,
		).
		Updates(map[string]any{
			"current_balance": lending.CurrentBalance,
			"total_repaid":    lending.TotalRepaid,
			"is_settled":      lending.IsSettled,
			"settled_at":      lending.SettledAt,
		})
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected != 1 {
		return ErrConcurrentBalanceUpdate
	}
	return nil
}

func (s *TransactionService) applyBalanceChangesTx(txdb *gorm.DB, tx *model.Transaction, logChange bool) error {
	if err := lockBalanceAccountsTx(txdb, tx); err != nil {
		return err
	}

	switch tx.Type {
	case "expense":
		return s.applyTransactionAccountDeltaTx(txdb, tx, tx.AccountID, "expense", -tx.Amount, nil, nil, "支出", logChange)
	case "income":
		return s.applyTransactionAccountDeltaTx(txdb, tx, tx.AccountID, "income", tx.Amount, nil, nil, "收入", logChange)
	case "transfer":
		if tx.ToAccountID == nil || *tx.ToAccountID == "" {
			return ErrSameAccount
		}
		if err := s.applyTransactionAccountDeltaTx(txdb, tx, tx.AccountID, "transfer_out", -tx.Amount, nil, nil, "转出", logChange); err != nil {
			return err
		}
		return s.applyTransactionAccountDeltaTx(txdb, tx, *tx.ToAccountID, "transfer_in", tx.Amount, nil, nil, "转入", logChange)
	default:
		return nil
	}
}

func lockBalanceAccountsTx(txdb *gorm.DB, transactions ...*model.Transaction) error {
	accountOwners := make(map[string]uint)
	for _, transaction := range transactions {
		for _, accountID := range balanceAccountIDs(transaction) {
			accountOwners[accountID] = transaction.UserID
		}
	}

	accountIDs := make([]string, 0, len(accountOwners))
	for accountID := range accountOwners {
		accountIDs = append(accountIDs, accountID)
	}
	sort.Strings(accountIDs)
	for _, accountID := range accountIDs {
		var account model.Account
		if err := txdb.Clauses(clause.Locking{Strength: "UPDATE"}).
			Select("id").
			First(&account, "id = ? AND user_id = ?", accountID, accountOwners[accountID]).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return ErrAccountNotFound
			}
			return err
		}
	}
	return nil
}

func balanceAccountIDs(tx *model.Transaction) []string {
	if tx == nil || tx.AccountID == "" {
		return nil
	}

	accountIDs := []string{tx.AccountID}
	if tx.Type == "transfer" && tx.ToAccountID != nil && *tx.ToAccountID != "" && *tx.ToAccountID != tx.AccountID {
		accountIDs = append(accountIDs, *tx.ToAccountID)
	}
	sort.Strings(accountIDs)
	return accountIDs
}

// accountBalanceDeltaTx converts the ordinary asset-account cash-flow sign
// into the stored balance convention. Asset balances represent money held;
// debt balances represent money owed, so the same cash flow has the opposite
// effect for debt accounts.
func accountBalanceDeltaTx(txdb *gorm.DB, userID uint, accountID string, cashFlowDelta float64) (float64, error) {
	var account model.Account
	if err := txdb.Select("type").First(&account, "id = ? AND user_id = ?", accountID, userID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return 0, ErrAccountNotFound
		}
		return 0, err
	}
	if IsDebtAccount(account.Type) {
		return -cashFlowDelta, nil
	}
	return cashFlowDelta, nil
}

func (s *TransactionService) applyTransactionAccountDeltaTx(
	txdb *gorm.DB,
	tx *model.Transaction,
	accountID string,
	logType string,
	cashFlowDelta float64,
	reminderID *string,
	lendingID *string,
	remark string,
	logChange bool,
) error {
	balanceDelta, err := accountBalanceDeltaTx(txdb, tx.UserID, accountID, cashFlowDelta)
	if err != nil {
		return err
	}
	return applyAccountBalanceMutationTx(
		txdb,
		s.accountLogSvc,
		tx.UserID,
		accountID,
		logType,
		tx.Amount,
		balanceDelta,
		&tx.ID,
		reminderID,
		lendingID,
		remark,
		logChange,
	)
}

func (s *TransactionService) revertBalanceChangesTx(txdb *gorm.DB, tx *model.Transaction, logChange bool) error {
	if err := lockBalanceAccountsTx(txdb, tx); err != nil {
		return err
	}

	switch tx.Type {
	case "expense":
		return s.applyTransactionAccountDeltaTx(txdb, tx, tx.AccountID, "rollback", tx.Amount, tx.ReminderID, tx.LendingID, "撤回支出", logChange)
	case "income":
		return s.applyTransactionAccountDeltaTx(txdb, tx, tx.AccountID, "rollback", -tx.Amount, tx.ReminderID, tx.LendingID, "撤回收入", logChange)
	case "transfer":
		if err := s.applyTransactionAccountDeltaTx(txdb, tx, tx.AccountID, "rollback", tx.Amount, nil, nil, "撤回转出", logChange); err != nil {
			return err
		}
		if tx.ToAccountID != nil && *tx.ToAccountID != "" {
			return s.applyTransactionAccountDeltaTx(txdb, tx, *tx.ToAccountID, "rollback", -tx.Amount, nil, nil, "撤回转入", logChange)
		}
		return nil
	default:
		return nil
	}
}

func (s *TransactionService) updateAccountBalanceTx(txdb *gorm.DB, userID uint, accountID string, delta float64) error {
	return updateAccountBalanceForUserTx(txdb, accountID, userID, delta)
}

func applyAccountBalanceMutationTx(
	txdb *gorm.DB,
	accountLogSvc *AccountLogService,
	userID uint,
	accountID string,
	logType string,
	amount float64,
	balanceDelta float64,
	transactionID *string,
	reminderID *string,
	lendingID *string,
	remark string,
	logChange bool,
) error {
	if err := logAccountBalanceChangeTx(
		txdb,
		accountLogSvc,
		userID,
		accountID,
		logType,
		amount,
		balanceDelta,
		transactionID,
		reminderID,
		lendingID,
		remark,
		logChange,
	); err != nil {
		return err
	}
	return updateAccountBalanceForUserTx(txdb, accountID, userID, balanceDelta)
}

func logAccountBalanceChangeTx(
	txdb *gorm.DB,
	accountLogSvc *AccountLogService,
	userID uint,
	accountID string,
	logType string,
	amount float64,
	balanceDelta float64,
	transactionID *string,
	reminderID *string,
	lendingID *string,
	remark string,
	enabled bool,
) error {
	if !enabled || accountLogSvc == nil {
		return nil
	}

	var account model.Account
	if err := txdb.First(&account, "id = ? AND user_id = ?", accountID, userID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrAccountNotFound
		}
		return err
	}

	balanceBefore := account.CurrentBalance
	return accountLogSvc.logRepo.CreateWithDB(txdb, &repository.CreateAccountLogRequest{
		UserID:        userID,
		AccountID:     accountID,
		Type:          logType,
		Amount:        amount,
		BalanceBefore: balanceBefore,
		BalanceAfter:  roundMoney(balanceBefore + balanceDelta),
		TransactionID: transactionID,
		ReminderID:    reminderID,
		LendingID:     lendingID,
		Remark:        remark,
	})
}

func (s *TransactionService) DeleteBatch(ids []string, userID uint) error {
	orderedIDs := append([]string(nil), ids...)
	sort.Strings(orderedIDs)
	return s.txRepo.DB().Transaction(func(txdb *gorm.DB) error {
		for _, id := range orderedIDs {
			if err := s.deleteWithTx(txdb, id, userID); err != nil {
				return err
			}
		}
		return nil
	})
}

func (s *TransactionService) Export(userID uint, startDate, endDate *time.Time) ([]model.Transaction, error) {
	return s.txRepo.GetAllForExport(userID, startDate, endDate)
}
