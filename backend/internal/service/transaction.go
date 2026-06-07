package service

import (
	"encoding/json"
	"errors"
	"io"
	"mime/multipart"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"gorm.io/gorm"
)

var (
	ErrTransactionNotFound = errors.New("transaction not found")
	ErrSameAccount         = errors.New("source and target account must be different")
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
	Type            string  `json:"type" binding:"required,oneof=income expense transfer"`
	Amount          float64 `json:"amount" binding:"required,gt=0"`
	AccountID       string  `json:"account_id" binding:"required"`
	ToAccountID     *string `json:"to_account_id"`
	CategoryID      *string `json:"category_id"`
	TransactionDate string  `json:"transaction_date" binding:"required"`
	Remark          string  `json:"remark"`
	Images          string  `json:"images"`
	Tags            string  `json:"tags"`
	MemberID        *string `json:"member_id"`
	PaidByMemberID  *string `json:"paid_by_member_id"`
}

func (s *TransactionService) Create(userID uint, req CreateTransactionRequest) (*model.Transaction, error) {
	if err := s.validateTransactionAccounts(userID, req); err != nil {
		return nil, err
	}

	txDate, err := parseTransactionDate(req.TransactionDate)
	if err != nil {
		return nil, err
	}

	transaction := &model.Transaction{
		ID:              uuid.New().String(),
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
		Source:          "manual",
	}

	if err := s.txRepo.DB().Transaction(func(txdb *gorm.DB) error {
		if err := txdb.Create(transaction).Error; err != nil {
			return err
		}
		return s.applyBalanceChangesTx(txdb, transaction, true)
	}); err != nil {
		return nil, err
	}

	return s.txRepo.GetByID(transaction.ID)
}

func (s *TransactionService) validateTransactionAccounts(userID uint, req CreateTransactionRequest) error {
	if req.Type == "transfer" {
		if req.ToAccountID == nil || *req.ToAccountID == "" || *req.ToAccountID == req.AccountID {
			return ErrSameAccount
		}
	}
	if err := s.ensureAccountBelongsToUser(req.AccountID, userID); err != nil {
		return err
	}
	if req.Type == "transfer" {
		return s.ensureAccountBelongsToUser(*req.ToAccountID, userID)
	}
	return s.validateTransactionMembers(userID, req)
}

func (s *TransactionService) validateTransactionMembers(userID uint, req CreateTransactionRequest) error {
	if req.MemberID != nil && *req.MemberID != "" {
		if err := s.ensureFamilyMemberBelongsToUser(*req.MemberID, userID); err != nil {
			return err
		}
	}
	if req.PaidByMemberID != nil && *req.PaidByMemberID != "" {
		return s.ensureFamilyMemberBelongsToUser(*req.PaidByMemberID, userID)
	}
	return nil
}

func (s *TransactionService) ensureFamilyMemberBelongsToUser(memberID string, userID uint) error {
	if s.familyMemberRepo == nil {
		return ErrFamilyMemberNotFound
	}
	member, err := s.familyMemberRepo.GetByID(memberID)
	if err != nil || member.UserID != userID {
		return ErrFamilyMemberNotFound
	}
	return nil
}

func (s *TransactionService) ensureAccountBelongsToUser(accountID string, userID uint) error {
	account, err := s.accountRepo.GetByID(accountID)
	if err != nil || account.UserID != userID {
		return ErrAccountNotFound
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
			return txDate, nil
		}
		lastErr = err
	}
	return time.Time{}, lastErr
}

func (s *TransactionService) GetByID(id string, userID uint) (*model.Transaction, error) {
	tx, err := s.txRepo.GetByID(id)
	if err != nil {
		return nil, ErrTransactionNotFound
	}
	if tx.UserID != userID {
		return nil, ErrTransactionNotFound
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
		t, err := time.Parse("2006-01-02", req.StartDate)
		if err != nil {
			return nil, err
		}
		filter.StartDate = &t
	}
	if req.EndDate != "" {
		t, err := time.Parse("2006-01-02", req.EndDate)
		if err != nil {
			return nil, err
		}
		// Set to end of day (23:59:59)
		endOfDay := t.Add(23*time.Hour + 59*time.Minute + 59*time.Second)
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
	current, err := s.GetByID(id, userID)
	if err != nil {
		return nil, err
	}
	if err := s.validateTransactionAccounts(userID, req); err != nil {
		return nil, err
	}

	txDate, err := parseTransactionDate(req.TransactionDate)
	if err != nil {
		return nil, err
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

	if err := s.txRepo.DB().Transaction(func(txdb *gorm.DB) error {
		if err := s.revertBalanceChangesTx(txdb, current, false); err != nil {
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
		return s.applyBalanceChangesTx(txdb, next, false)
	}); err != nil {
		return nil, err
	}

	return s.txRepo.GetByID(id)
}

func (s *TransactionService) Delete(id string, userID uint) error {
	transaction, err := s.GetByID(id, userID)
	if err != nil {
		return err
	}

	if err := s.txRepo.DB().Transaction(func(txdb *gorm.DB) error {
		if err := s.revertBalanceChangesTx(txdb, transaction, true); err != nil {
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
		return nil
	}); err != nil {
		return err
	}

	// Revert linked reminder data
	if transaction.ReminderID != nil && *transaction.ReminderID != "" {
		s.revertReminderPayment(transaction)
	}

	return nil
}

// revertReminderPayment reverts the reminder's paid totals and principal balance.
func (s *TransactionService) revertReminderPayment(tx *model.Transaction) {
	if tx.ReminderID == nil || *tx.ReminderID == "" {
		return
	}
	reminder, err := s.reminderRepo.GetByID(*tx.ReminderID)
	if err != nil || reminder == nil {
		return
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

	// Revert total_paid
	reminder.TotalPaid -= amount
	if reminder.TotalPaid < 0 {
		reminder.TotalPaid = 0
	}
	reminder.InterestPaid -= interestAmount
	if reminder.InterestPaid < 0 {
		reminder.InterestPaid = 0
	}

	// Revert current_balance (add back the principal paid)
	if reminder.CurrentBalance != nil {
		newBalance := *reminder.CurrentBalance + principalAmount
		reminder.CurrentBalance = &newBalance
	}

	// Clear paid_off status if balance is restored
	if reminder.PaidOffAt != nil && reminder.CurrentBalance != nil && *reminder.CurrentBalance > 0 {
		reminder.PaidOffAt = nil
	}

	s.reminderRepo.Update(reminder)

	// Also revert linked account if exists
	if reminder.AccountID != nil && *reminder.AccountID != "" {
		if account, err := s.accountRepo.GetByID(*reminder.AccountID); err == nil && account != nil {
			account.CurrentBalance += principalAmount
			account.TotalPaid -= principalAmount
			if account.TotalPaid < 0 {
				account.TotalPaid = 0
			}
			if account.PaidOffAt != nil && account.CurrentBalance > 0 {
				account.PaidOffAt = nil
			}
			s.accountRepo.Update(account)
		}
	}
}

// revertLendingTransactionTx reverts lending totals when a linked transaction is deleted.
func (s *TransactionService) revertLendingTransactionTx(txdb *gorm.DB, tx *model.Transaction) error {
	if tx.LendingID == nil || *tx.LendingID == "" {
		return nil
	}

	var lending model.Lending
	if err := txdb.First(&lending, "id = ? AND user_id = ?", *tx.LendingID, tx.UserID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil
		}
		return err
	}

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

	return txdb.Save(&lending).Error
}

func (s *TransactionService) applyBalanceChangesTx(txdb *gorm.DB, tx *model.Transaction, logChange bool) error {
	switch tx.Type {
	case "expense":
		if err := s.logBalanceChangeTx(txdb, tx.UserID, tx.AccountID, "expense", tx.Amount, -tx.Amount, &tx.ID, nil, nil, "支出", logChange); err != nil {
			return err
		}
		return s.updateAccountBalanceTx(txdb, tx.UserID, tx.AccountID, -tx.Amount)
	case "income":
		if err := s.logBalanceChangeTx(txdb, tx.UserID, tx.AccountID, "income", tx.Amount, tx.Amount, &tx.ID, nil, nil, "收入", logChange); err != nil {
			return err
		}
		return s.updateAccountBalanceTx(txdb, tx.UserID, tx.AccountID, tx.Amount)
	case "transfer":
		if tx.ToAccountID == nil || *tx.ToAccountID == "" {
			return ErrSameAccount
		}
		if err := s.logBalanceChangeTx(txdb, tx.UserID, tx.AccountID, "transfer_out", tx.Amount, -tx.Amount, &tx.ID, nil, nil, "转出", logChange); err != nil {
			return err
		}
		if err := s.updateAccountBalanceTx(txdb, tx.UserID, tx.AccountID, -tx.Amount); err != nil {
			return err
		}
		if err := s.logBalanceChangeTx(txdb, tx.UserID, *tx.ToAccountID, "transfer_in", tx.Amount, tx.Amount, &tx.ID, nil, nil, "转入", logChange); err != nil {
			return err
		}
		return s.updateAccountBalanceTx(txdb, tx.UserID, *tx.ToAccountID, tx.Amount)
	default:
		return nil
	}
}

func (s *TransactionService) revertBalanceChangesTx(txdb *gorm.DB, tx *model.Transaction, logChange bool) error {
	switch tx.Type {
	case "expense":
		if err := s.logBalanceChangeTx(txdb, tx.UserID, tx.AccountID, "rollback", tx.Amount, tx.Amount, &tx.ID, tx.ReminderID, tx.LendingID, "撤回支出", logChange); err != nil {
			return err
		}
		return s.updateAccountBalanceTx(txdb, tx.UserID, tx.AccountID, tx.Amount)
	case "income":
		if err := s.logBalanceChangeTx(txdb, tx.UserID, tx.AccountID, "rollback", tx.Amount, -tx.Amount, &tx.ID, tx.ReminderID, tx.LendingID, "撤回收入", logChange); err != nil {
			return err
		}
		return s.updateAccountBalanceTx(txdb, tx.UserID, tx.AccountID, -tx.Amount)
	case "transfer":
		if err := s.logBalanceChangeTx(txdb, tx.UserID, tx.AccountID, "rollback", tx.Amount, tx.Amount, &tx.ID, nil, nil, "撤回转出", logChange); err != nil {
			return err
		}
		if err := s.updateAccountBalanceTx(txdb, tx.UserID, tx.AccountID, tx.Amount); err != nil {
			return err
		}
		if tx.ToAccountID != nil && *tx.ToAccountID != "" {
			if err := s.logBalanceChangeTx(txdb, tx.UserID, *tx.ToAccountID, "rollback", tx.Amount, -tx.Amount, &tx.ID, nil, nil, "撤回转入", logChange); err != nil {
				return err
			}
			return s.updateAccountBalanceTx(txdb, tx.UserID, *tx.ToAccountID, -tx.Amount)
		}
		return nil
	default:
		return nil
	}
}

func (s *TransactionService) updateAccountBalanceTx(txdb *gorm.DB, userID uint, accountID string, delta float64) error {
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

func (s *TransactionService) logBalanceChangeTx(txdb *gorm.DB, userID uint, accountID string, logType string, amount float64, balanceDelta float64, transactionID *string, reminderID *string, lendingID *string, remark string, enabled bool) error {
	if !enabled || s.accountLogSvc == nil {
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
	return s.accountLogSvc.logRepo.CreateWithDB(txdb, &repository.CreateAccountLogRequest{
		UserID:        userID,
		AccountID:     accountID,
		Type:          logType,
		Amount:        amount,
		BalanceBefore: balanceBefore,
		BalanceAfter:  balanceBefore + balanceDelta,
		TransactionID: transactionID,
		ReminderID:    reminderID,
		LendingID:     lendingID,
		Remark:        remark,
	})
}

func (s *TransactionService) DeleteBatch(ids []string, userID uint) error {
	for _, id := range ids {
		if err := s.Delete(id, userID); err != nil {
			return err
		}
	}
	return nil
}

func (s *TransactionService) Export(userID uint, startDate, endDate *time.Time) ([]model.Transaction, error) {
	return s.txRepo.GetAllForExport(userID, startDate, endDate)
}

type BackupData struct {
	Transactions []model.Transaction `json:"transactions"`
	ExportedAt   time.Time           `json:"exported_at"`
	Version      string              `json:"version"`
}

func (s *TransactionService) Backup(userID uint) (*BackupData, error) {
	transactions, err := s.txRepo.GetAllForExport(userID, nil, nil)
	if err != nil {
		return nil, err
	}

	return &BackupData{
		Transactions: transactions,
		ExportedAt:   time.Now(),
		Version:      "1.0",
	}, nil
}

func (s *TransactionService) Import(userID uint, file *multipart.FileHeader) (int, error) {
	f, err := file.Open()
	if err != nil {
		return 0, err
	}
	defer f.Close()

	data, err := io.ReadAll(f)
	if err != nil {
		return 0, err
	}

	var importData struct {
		Transactions []struct {
			Type            string  `json:"type"`
			Amount          float64 `json:"amount"`
			AccountID       string  `json:"account_id"`
			CategoryID      *string `json:"category_id"`
			TransactionDate string  `json:"transaction_date"`
			Remark          string  `json:"remark"`
		} `json:"transactions"`
	}

	if err := json.Unmarshal(data, &importData); err != nil {
		return 0, err
	}

	count := 0
	for _, tx := range importData.Transactions {
		req := CreateTransactionRequest{
			Type:            tx.Type,
			Amount:          tx.Amount,
			AccountID:       tx.AccountID,
			CategoryID:      tx.CategoryID,
			TransactionDate: tx.TransactionDate,
			Remark:          tx.Remark,
		}
		if _, err := s.Create(userID, req); err == nil {
			count++
		}
	}

	return count, nil
}
