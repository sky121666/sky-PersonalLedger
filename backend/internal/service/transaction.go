package service

import (
	"encoding/json"
	"errors"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/money"
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
	ErrInvalidTransactionImages    = errors.New("invalid transaction images")
	ErrTransactionAttachmentScope  = errors.New("transaction attachment does not belong to target transaction")
	ErrCreateTransactionImages     = errors.New("transaction attachments must be added after creation")
)

type TransactionService struct {
	txRepo           *repository.TransactionRepository
	accountRepo      *repository.AccountRepository
	reminderRepo     *repository.ReminderRepository
	lendingRepo      *repository.LendingRepository
	familyMemberRepo *repository.FamilyMemberRepository
	accountLogSvc    *AccountLogService
	uploadService    *UploadService
}

func (s *TransactionService) WithUploadService(uploadService *UploadService) *TransactionService {
	s.uploadService = uploadService
	return s
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
	Type              string       `json:"type" binding:"required,oneof=income expense transfer"`
	Amount            money.Amount `json:"amount" binding:"required,gt=0"`
	AccountID         string       `json:"account_id" binding:"required"`
	ToAccountID       *string      `json:"to_account_id"`
	CategoryID        *string      `json:"category_id"`
	TransactionDate   string       `json:"transaction_date" binding:"required"`
	Remark            string       `json:"remark"`
	Images            string       `json:"images"`
	Tags              string       `json:"tags"`
	MemberID          *string      `json:"member_id"`
	PaidByMemberID    *string      `json:"paid_by_member_id"`
	importFingerprint *string
}

type UpdateTransactionAttachmentsRequest struct {
	Images *string `json:"images"`
}

func (s *TransactionService) Create(userID uint, req CreateTransactionRequest) (*model.Transaction, error) {
	if strings.TrimSpace(req.Images) != "" {
		paths, _, err := parseStoredUploadReferenceList(req.Images)
		if err != nil {
			return nil, ErrInvalidTransactionImages
		}
		if len(paths) != 0 {
			return nil, ErrCreateTransactionImages
		}
		req.Images = ""
	}
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
		Tags:              req.Tags,
		ToAccountID:       req.ToAccountID,
		MemberID:          req.MemberID,
		PaidByMemberID:    req.PaidByMemberID,
		Source:            source,
		ImportFingerprint: req.importFingerprint,
	}
	normalizedImages, err := normalizeTransactionAttachmentImages(transaction.ID, userID, req.Images)
	if err != nil {
		return nil, err
	}
	if s.uploadService != nil {
		if err := s.uploadService.validateStoredAttachmentPaths(userID, normalizedImages); err != nil {
			return nil, err
		}
	}
	transaction.Images = normalizedImages

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
	if req.Amount <= 0 || !req.Amount.IsValid() {
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
	Page          int          `form:"page"`
	PageSize      int          `form:"page_size"`
	StartDate     string       `form:"start_date"`
	EndDate       string       `form:"end_date"`
	Type          string       `form:"type"`
	AccountID     string       `form:"account_id"`
	CategoryID    string       `form:"category_id"`
	MinAmount     money.Amount `form:"min_amount"`
	MaxAmount     money.Amount `form:"max_amount"`
	Keyword       string       `form:"keyword"`
	IncludeSystem bool         `form:"include_system"`
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
	if s.uploadService != nil {
		releaseStorage := acquireAttachmentStorageRead()
		defer releaseStorage()
		if !AttachmentStorageAvailable(userID) {
			return nil, ErrAttachmentRecoveryPending
		}
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
		normalizedImages, err := normalizeTransactionAttachmentImages(id, userID, req.Images)
		if err != nil {
			return err
		}
		if s.uploadService != nil {
			if err := s.uploadService.validateStoredAttachmentPaths(userID, normalizedImages); err != nil {
				return err
			}
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
			Images:          normalizedImages,
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
				"amount_cents":      req.Amount,
				"transaction_date":  txDate,
				"remark":            req.Remark,
				"images":            normalizedImages,
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

func (s *TransactionService) UpdateAttachments(id string, userID uint, req UpdateTransactionAttachmentsRequest) (*model.Transaction, error) {
	if req.Images == nil {
		return nil, ErrInvalidTransactionImages
	}
	if s.uploadService != nil {
		releaseStorage := acquireAttachmentStorageRead()
		defer releaseStorage()
		if !AttachmentStorageAvailable(userID) {
			return nil, ErrAttachmentRecoveryPending
		}
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

		images, err := normalizeTransactionAttachmentImages(id, userID, *req.Images)
		if err != nil {
			return err
		}
		if s.uploadService != nil {
			if err := s.uploadService.validateStoredAttachmentPaths(userID, images); err != nil {
				return err
			}
		}
		if err := s.txRepo.UpdateImagesForUserWithDB(txdb, id, userID, images); err != nil {
			return err
		}
		updated, err = s.txRepo.GetByIDForUserWithDB(txdb, id, userID)
		return err
	}); err != nil {
		return nil, err
	}

	return updated, nil
}

func normalizeTransactionAttachmentImages(transactionID string, userID uint, value string) (string, error) {
	if strings.TrimSpace(value) == "" {
		return "", nil
	}
	paths, jsonArray, err := parseStoredUploadReferenceList(value)
	if err != nil {
		return "", ErrInvalidTransactionImages
	}

	owner := strconv.FormatUint(uint64(userID), 10)
	normalizedPaths := make([]string, 0, len(paths))
	for _, storedPath := range paths {
		candidate := storedPath
		if !jsonArray {
			candidate = strings.TrimSpace(candidate)
		}
		normalized := normalizeStoredUploadReference(candidate)
		if normalized == "" || strings.Contains(normalized, `\`) {
			return "", ErrInvalidTransactionImages
		}

		parts := strings.Split(normalized, "/")
		if len(parts) == 0 || parts[0] != owner {
			return "", ErrTransactionAttachmentScope
		}
		if len(parts) != 4 || parts[1] != "transactions" || parts[2] != transactionID {
			return "", ErrTransactionAttachmentScope
		}
		if sanitizeUploadFilename(parts[3]) != parts[3] {
			return "", ErrInvalidTransactionImages
		}
		normalizedPaths = append(normalizedPaths, normalized)
	}

	encoded, err := json.Marshal(normalizedPaths)
	if err != nil {
		return "", ErrInvalidTransactionImages
	}
	return string(encoded), nil
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
