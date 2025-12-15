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
)

var (
	ErrTransactionNotFound = errors.New("transaction not found")
	ErrSameAccount         = errors.New("source and target account must be different")
)

type TransactionService struct {
	txRepo       *repository.TransactionRepository
	accountRepo  *repository.AccountRepository
	reminderRepo *repository.ReminderRepository
	lendingRepo  *repository.LendingRepository
}

func NewTransactionService(
	txRepo *repository.TransactionRepository,
	accountRepo *repository.AccountRepository,
	reminderRepo *repository.ReminderRepository,
	lendingRepo *repository.LendingRepository,
) *TransactionService {
	return &TransactionService{
		txRepo:       txRepo,
		accountRepo:  accountRepo,
		reminderRepo: reminderRepo,
		lendingRepo:  lendingRepo,
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
}

func (s *TransactionService) Create(userID uint, req CreateTransactionRequest) (*model.Transaction, error) {
	if req.Type == "transfer" && (req.ToAccountID == nil || *req.ToAccountID == req.AccountID) {
		return nil, ErrSameAccount
	}

	// Try parsing with datetime first, fallback to date only
	txDate, err := time.Parse(time.RFC3339, req.TransactionDate)
	if err != nil {
		txDate, err = time.Parse("2006-01-02", req.TransactionDate)
		if err != nil {
			return nil, err
		}
	}

	tx := &model.Transaction{
		ID:              uuid.New().String(),
		UserID:          userID,
		AccountID:       req.AccountID,
		CategoryID:      req.CategoryID,
		Type:            req.Type,
		Amount:          req.Amount,
		TransactionDate: txDate,
		Remark:          req.Remark,
		Images:          req.Images,
		ToAccountID:     req.ToAccountID,
		Source:          "manual",
	}

	if err := s.txRepo.Create(tx); err != nil {
		return nil, err
	}

	// Update account balances
	switch req.Type {
	case "expense":
		s.accountRepo.UpdateBalance(req.AccountID, -req.Amount)
	case "income":
		s.accountRepo.UpdateBalance(req.AccountID, req.Amount)
	case "transfer":
		s.accountRepo.UpdateBalance(req.AccountID, -req.Amount)
		s.accountRepo.UpdateBalance(*req.ToAccountID, req.Amount)
	}

	return s.txRepo.GetByID(tx.ID)
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
	Page       int     `form:"page"`
	PageSize   int     `form:"page_size"`
	StartDate  string  `form:"start_date"`
	EndDate    string  `form:"end_date"`
	Type       string  `form:"type"`
	AccountID  string  `form:"account_id"`
	CategoryID string  `form:"category_id"`
	MinAmount  float64 `form:"min_amount"`
	MaxAmount  float64 `form:"max_amount"`
	Keyword    string  `form:"keyword"`
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
		UserID:     userID,
		Type:       req.Type,
		AccountID:  req.AccountID,
		CategoryID: req.CategoryID,
		Keyword:    req.Keyword,
		Page:       req.Page,
		PageSize:   req.PageSize,
	}

	if req.StartDate != "" {
		t, _ := time.Parse("2006-01-02", req.StartDate)
		filter.StartDate = &t
	}
	if req.EndDate != "" {
		t, _ := time.Parse("2006-01-02", req.EndDate)
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
	tx, err := s.GetByID(id, userID)
	if err != nil {
		return nil, err
	}

	// Revert old balance changes
	switch tx.Type {
	case "expense":
		s.accountRepo.UpdateBalance(tx.AccountID, tx.Amount)
	case "income":
		s.accountRepo.UpdateBalance(tx.AccountID, -tx.Amount)
	case "transfer":
		s.accountRepo.UpdateBalance(tx.AccountID, tx.Amount)
		if tx.ToAccountID != nil {
			s.accountRepo.UpdateBalance(*tx.ToAccountID, -tx.Amount)
		}
	}

	// Update transaction
	// Try parsing with datetime first, fallback to date only
	txDate, err := time.Parse(time.RFC3339, req.TransactionDate)
	if err != nil {
		txDate, _ = time.Parse("2006-01-02", req.TransactionDate)
	}
	tx.AccountID = req.AccountID
	tx.CategoryID = req.CategoryID
	tx.Type = req.Type
	tx.Amount = req.Amount
	tx.TransactionDate = txDate
	tx.Remark = req.Remark
	tx.Images = req.Images
	tx.ToAccountID = req.ToAccountID

	if err := s.txRepo.Update(tx); err != nil {
		return nil, err
	}

	// Apply new balance changes
	switch req.Type {
	case "expense":
		s.accountRepo.UpdateBalance(req.AccountID, -req.Amount)
	case "income":
		s.accountRepo.UpdateBalance(req.AccountID, req.Amount)
	case "transfer":
		s.accountRepo.UpdateBalance(req.AccountID, -req.Amount)
		s.accountRepo.UpdateBalance(*req.ToAccountID, req.Amount)
	}

	return s.txRepo.GetByID(id)
}

func (s *TransactionService) Delete(id string, userID uint) error {
	tx, err := s.GetByID(id, userID)
	if err != nil {
		return err
	}

	// Revert balance changes
	switch tx.Type {
	case "expense":
		s.accountRepo.UpdateBalance(tx.AccountID, tx.Amount)
	case "income":
		s.accountRepo.UpdateBalance(tx.AccountID, -tx.Amount)
	case "transfer":
		s.accountRepo.UpdateBalance(tx.AccountID, tx.Amount)
		if tx.ToAccountID != nil {
			s.accountRepo.UpdateBalance(*tx.ToAccountID, -tx.Amount)
		}
	}

	// Revert linked reminder data
	if tx.ReminderID != nil && *tx.ReminderID != "" {
		s.revertReminderPayment(*tx.ReminderID, tx.Amount)
	}

	// Revert linked lending data
	if tx.LendingID != nil && *tx.LendingID != "" {
		s.revertLendingTransaction(*tx.LendingID, tx.Type, tx.Amount)
	}

	return s.txRepo.Delete(id)
}

// revertReminderPayment reverts the reminder's total_paid and current_balance
func (s *TransactionService) revertReminderPayment(reminderID string, amount float64) {
	reminder, err := s.reminderRepo.GetByID(reminderID)
	if err != nil || reminder == nil {
		return
	}

	// Revert total_paid
	reminder.TotalPaid -= amount
	if reminder.TotalPaid < 0 {
		reminder.TotalPaid = 0
	}

	// Revert current_balance (add back the principal paid)
	if reminder.CurrentBalance != nil {
		newBalance := *reminder.CurrentBalance + amount
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
			account.CurrentBalance += amount
			account.TotalPaid -= amount
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

// revertLendingTransaction reverts the lending's total_repaid and current_balance
func (s *TransactionService) revertLendingTransaction(lendingID string, txType string, amount float64) {
	lending, err := s.lendingRepo.GetByID(lendingID)
	if err != nil || lending == nil {
		return
	}

	// For repayment transactions (income for lend_out, expense for borrow)
	isRepayment := (lending.Type == "lend_out" && txType == "income") ||
		(lending.Type == "borrow" && txType == "expense")

	if isRepayment {
		// Revert repayment
		lending.TotalRepaid -= amount
		if lending.TotalRepaid < 0 {
			lending.TotalRepaid = 0
		}
		lending.CurrentBalance += amount

		// Clear settled status if balance is restored
		if lending.IsSettled && lending.CurrentBalance > 0 {
			lending.IsSettled = false
			lending.SettledAt = nil
		}
	} else {
		// Revert initial lending transaction
		lending.CurrentBalance -= amount
		if lending.CurrentBalance < 0 {
			lending.CurrentBalance = 0
		}
	}

	s.lendingRepo.Update(lending)
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
