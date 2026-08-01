package service

import (
	"bytes"
	"crypto/sha256"
	"encoding/csv"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

var (
	ErrTransactionImportFormat      = errors.New("invalid transaction import format")
	ErrTransactionImportTooLarge    = errors.New("transaction import file is too large")
	ErrTransactionImportRowsLimit   = errors.New("transaction import row limit exceeded")
	ErrTransactionImportNotFound    = errors.New("transaction import session not found")
	ErrTransactionImportExpired     = errors.New("transaction import session expired")
	ErrTransactionImportInvalidRows = errors.New("transaction import contains invalid rows")
	ErrTransactionImportState       = errors.New("transaction import state conflict")
)

const (
	transactionImportMaxFileBytes = 5 << 20
	transactionImportMaxRows      = 10000
	transactionImportPreviewRows  = 200
	transactionImportMaxSessions  = 64
	transactionImportPreviewTTL   = 30 * time.Minute
	transactionImportRollbackTTL  = 24 * time.Hour
)

func MaxTransactionImportFileBytes() int64 {
	return transactionImportMaxFileBytes
}

type TransactionImportInput struct {
	Type            string  `json:"type"`
	Amount          float64 `json:"amount"`
	AccountID       string  `json:"account_id"`
	AccountName     string  `json:"account_name"`
	ToAccountID     string  `json:"to_account_id"`
	ToAccountName   string  `json:"to_account_name"`
	CategoryID      string  `json:"category_id"`
	CategoryName    string  `json:"category_name"`
	TransactionDate string  `json:"transaction_date"`
	Remark          string  `json:"remark"`
	Tags            string  `json:"tags"`
	MemberID        string  `json:"member_id"`
	PaidByMemberID  string  `json:"paid_by_member_id"`
}

type TransactionImportRow struct {
	Row             int      `json:"row"`
	Type            string   `json:"type"`
	Amount          float64  `json:"amount"`
	TransactionDate string   `json:"transaction_date"`
	Account         string   `json:"account"`
	Category        string   `json:"category,omitempty"`
	Valid           bool     `json:"valid"`
	Duplicate       bool     `json:"duplicate"`
	Errors          []string `json:"errors,omitempty"`
	Warnings        []string `json:"warnings,omitempty"`
}

type TransactionImportPreview struct {
	ID             string                 `json:"id"`
	Filename       string                 `json:"filename"`
	Format         string                 `json:"format"`
	Status         string                 `json:"status"`
	TotalRows      int                    `json:"total_rows"`
	ValidRows      int                    `json:"valid_rows"`
	InvalidRows    int                    `json:"invalid_rows"`
	DuplicateRows  int                    `json:"duplicate_rows"`
	CreatedRows    int                    `json:"created_rows"`
	RolledBackRows int                    `json:"rolled_back_rows"`
	Rows           []TransactionImportRow `json:"rows"`
	RowsTruncated  bool                   `json:"rows_truncated"`
	CreatedAt      time.Time              `json:"created_at"`
	ExpiresAt      time.Time              `json:"expires_at"`
	CommittedAt    *time.Time             `json:"committed_at,omitempty"`
	RolledBackAt   *time.Time             `json:"rolled_back_at,omitempty"`
}

type transactionImportCandidate struct {
	Row         int
	Input       TransactionImportInput
	ParseErrors []string
}

type validatedTransactionImportRow struct {
	Preview     TransactionImportRow
	Request     CreateTransactionRequest
	Fingerprint string
}

type transactionImportSession struct {
	ID             string
	UserID         uint
	Filename       string
	Format         string
	FileDigest     string
	Status         string
	Candidates     []transactionImportCandidate
	Rows           []validatedTransactionImportRow
	CreatedIDs     []string
	RolledBackRows int
	CreatedAt      time.Time
	ExpiresAt      time.Time
	CommittedAt    *time.Time
	RolledBackAt   *time.Time
}

type transactionImportPayload struct {
	Candidates     []transactionImportCandidate    `json:"candidates"`
	Rows           []validatedTransactionImportRow `json:"rows"`
	CreatedIDs     []string                        `json:"created_ids"`
	RolledBackRows int                             `json:"rolled_back_rows"`
}

type TransactionImportService struct {
	transactions *TransactionService
	mu           sync.Mutex
}

func NewTransactionImportService(transactions *TransactionService) *TransactionImportService {
	return &TransactionImportService{transactions: transactions}
}

func (s *TransactionImportService) Preview(userID uint, filename string, reader io.Reader) (*TransactionImportPreview, error) {
	if userID == 0 || reader == nil {
		return nil, ErrTransactionImportFormat
	}
	data, err := readTransactionImportFile(reader)
	if err != nil {
		return nil, err
	}
	format, candidates, err := parseTransactionImportFile(filename, data)
	if err != nil {
		return nil, err
	}
	digestBytes := sha256.Sum256(data)
	now := time.Now()
	session := &transactionImportSession{
		ID:         uuid.NewString(),
		UserID:     userID,
		Filename:   safeImportFilename(filename),
		Format:     format,
		FileDigest: hex.EncodeToString(digestBytes[:]),
		Status:     "previewed",
		Candidates: candidates,
		CreatedAt:  now,
		ExpiresAt:  now.Add(transactionImportPreviewTTL),
	}
	rows, err := s.validateCandidates(userID, session.FileDigest, candidates)
	if err != nil {
		return nil, err
	}
	session.Rows = rows
	if err := s.storeSession(session); err != nil {
		return nil, err
	}
	return buildTransactionImportPreview(session), nil
}

func (s *TransactionImportService) Validate(userID uint, sessionID string) (*TransactionImportPreview, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	session, err := s.sessionForUser(userID, sessionID)
	if err != nil {
		return nil, err
	}
	if session.Status == "committed" || session.Status == "rolled_back" {
		return nil, ErrTransactionImportState
	}
	rows, err := s.validateCandidates(userID, session.FileDigest, session.Candidates)
	if err != nil {
		return nil, err
	}
	session.Rows = rows
	session.Status = "validated"
	session.ExpiresAt = time.Now().Add(transactionImportPreviewTTL)
	if err := s.persistSessionState(session, []string{"previewed", "validated"}); err != nil {
		return nil, err
	}
	return buildTransactionImportPreview(session), nil
}

func (s *TransactionImportService) Commit(userID uint, sessionID string) (*TransactionImportPreview, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	session, err := s.sessionForUser(userID, sessionID)
	if err != nil {
		return nil, err
	}
	if session.Status == "committed" || session.Status == "rolled_back" {
		return nil, ErrTransactionImportState
	}
	rows, err := s.validateCandidates(userID, session.FileDigest, session.Candidates)
	if err != nil {
		return nil, err
	}
	session.Rows = rows
	if countInvalidImportRows(rows) > 0 {
		session.Status = "validated"
		session.ExpiresAt = time.Now().Add(transactionImportPreviewTTL)
		if err := s.persistSessionState(session, []string{"previewed", "validated"}); err != nil {
			return nil, err
		}
		return buildTransactionImportPreview(session), ErrTransactionImportInvalidRows
	}

	createdIDs := make([]string, 0, len(rows))
	now := time.Now()
	err = s.transactions.txRepo.DB().Transaction(func(txdb *gorm.DB) error {
		claimed := txdb.Model(&model.TransactionImportBatch{}).
			Where("id = ? AND user_id = ? AND status IN ? AND expires_at > ?", session.ID, userID, []string{"previewed", "validated"}, now).
			Updates(map[string]interface{}{"status": "committing", "updated_at": now})
		if claimed.Error != nil {
			return claimed.Error
		}
		if claimed.RowsAffected != 1 {
			return ErrTransactionImportState
		}
		for _, row := range rows {
			if row.Preview.Duplicate {
				continue
			}
			request := row.Request
			fingerprint := row.Fingerprint
			request.importFingerprint = &fingerprint
			transaction, err := s.transactions.createWithTx(txdb, userID, request, "import")
			if err != nil {
				return err
			}
			createdIDs = append(createdIDs, transaction.ID)
		}
		committedAt := time.Now()
		session.CreatedIDs = createdIDs
		session.Status = "committed"
		session.CommittedAt = &committedAt
		session.ExpiresAt = committedAt.Add(transactionImportRollbackTTL)
		return s.persistSessionStateWithDB(txdb, session, []string{"committing"})
	})
	if err != nil {
		session.Status = "validated"
		return nil, err
	}
	return buildTransactionImportPreview(session), nil
}

func (s *TransactionImportService) Rollback(userID uint, sessionID string) (*TransactionImportPreview, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	session, err := s.sessionForUser(userID, sessionID)
	if err != nil {
		return nil, err
	}
	if session.Status != "committed" {
		return nil, ErrTransactionImportState
	}

	now := time.Now()
	err = s.transactions.txRepo.DB().Transaction(func(txdb *gorm.DB) error {
		claimed := txdb.Model(&model.TransactionImportBatch{}).
			Where("id = ? AND user_id = ? AND status = ? AND expires_at > ?", session.ID, userID, "committed", now).
			Updates(map[string]interface{}{"status": "rolling_back", "updated_at": now})
		if claimed.Error != nil {
			return claimed.Error
		}
		if claimed.RowsAffected != 1 {
			return ErrTransactionImportState
		}
		for index := len(session.CreatedIDs) - 1; index >= 0; index-- {
			transaction, err := s.transactions.txRepo.GetByIDForUserWithDB(txdb, session.CreatedIDs[index], userID)
			if err != nil {
				return ErrTransactionImportState
			}
			if transaction.Source != "import" || transaction.ImportFingerprint == nil {
				return ErrTransactionImportState
			}
			if err := s.transactions.deleteWithTx(txdb, transaction.ID, userID); err != nil {
				return err
			}
		}
		rolledBackAt := time.Now()
		session.RolledBackRows = len(session.CreatedIDs)
		session.Status = "rolled_back"
		session.RolledBackAt = &rolledBackAt
		session.ExpiresAt = rolledBackAt.Add(transactionImportPreviewTTL)
		return s.persistSessionStateWithDB(txdb, session, []string{"rolling_back"})
	})
	if err != nil {
		return nil, err
	}
	return buildTransactionImportPreview(session), nil
}

func (s *TransactionImportService) Get(userID uint, sessionID string) (*TransactionImportPreview, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	session, err := s.sessionForUser(userID, sessionID)
	if err != nil {
		return nil, err
	}
	return buildTransactionImportPreview(session), nil
}

// Recent returns the newest unexpired workflow for a user. It lets clients
// recover the preview or rollback affordance after an app/browser restart.
func (s *TransactionImportService) Recent(userID uint) (*TransactionImportPreview, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if userID == 0 {
		return nil, nil
	}
	var batch model.TransactionImportBatch
	err := s.transactions.txRepo.DB().
		Where("user_id = ? AND expires_at > ?", userID, time.Now()).
		Order("updated_at DESC").
		First(&batch).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	session, err := transactionImportSessionFromBatch(&batch)
	if err != nil {
		return nil, err
	}
	return buildTransactionImportPreview(session), nil
}

// ListRecent returns lightweight summaries for every workflow that still has
// a user-visible preview or rollback window. The payload column is excluded so
// listing many large imports remains bounded.
func (s *TransactionImportService) ListRecent(userID uint, limit int) ([]TransactionImportPreview, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if userID == 0 {
		return []TransactionImportPreview{}, nil
	}
	if limit <= 0 {
		limit = 10
	}
	if limit > transactionImportMaxSessions {
		limit = transactionImportMaxSessions
	}
	var batches []model.TransactionImportBatch
	err := s.transactions.txRepo.DB().
		Select(
			"id", "user_id", "filename", "format", "status",
			"total_rows", "valid_rows", "invalid_rows", "duplicate_rows",
			"created_rows", "rolled_back_rows", "created_at", "updated_at",
			"expires_at", "committed_at", "rolled_back_at",
		).
		Where("user_id = ? AND expires_at > ?", userID, time.Now()).
		Order("updated_at DESC").
		Limit(limit).
		Find(&batches).Error
	if err != nil {
		return nil, err
	}
	result := make([]TransactionImportPreview, 0, len(batches))
	for index := range batches {
		result = append(result, transactionImportPreviewFromBatchSummary(&batches[index]))
	}
	return result, nil
}

func (s *TransactionImportService) validateCandidates(userID uint, fileDigest string, candidates []transactionImportCandidate) ([]validatedTransactionImportRow, error) {
	var rows []validatedTransactionImportRow
	err := s.transactions.txRepo.DB().Transaction(func(txdb *gorm.DB) error {
		accounts, accountNames, err := importAccountLookups(txdb, userID)
		if err != nil {
			return err
		}
		categories, categoryNames, err := importCategoryLookups(txdb, userID)
		if err != nil {
			return err
		}
		members, err := importMemberLookup(txdb, userID)
		if err != nil {
			return err
		}

		rows = make([]validatedTransactionImportRow, 0, len(candidates))
		fingerprints := make([]string, 0, len(candidates))
		for _, candidate := range candidates {
			row := validateTransactionImportCandidate(candidate, accounts, accountNames, categories, categoryNames, members)
			fingerprintBytes := sha256.Sum256([]byte(fileDigest + ":" + strconv.Itoa(candidate.Row)))
			row.Fingerprint = hex.EncodeToString(fingerprintBytes[:])
			fingerprints = append(fingerprints, row.Fingerprint)
			rows = append(rows, row)
		}

		existing, err := existingImportFingerprints(txdb, userID, fingerprints)
		if err != nil {
			return err
		}
		for index := range rows {
			if _, duplicate := existing[rows[index].Fingerprint]; duplicate {
				rows[index].Preview.Duplicate = true
				rows[index].Preview.Warnings = append(rows[index].Preview.Warnings, "该文件中的这一行已经导入，将自动跳过")
			}
		}
		return nil
	})
	return rows, err
}

func validateTransactionImportCandidate(
	candidate transactionImportCandidate,
	accounts map[string]model.Account,
	accountNames map[string][]string,
	categories map[string]model.Category,
	categoryNames map[string][]string,
	members map[string]struct{},
) validatedTransactionImportRow {
	input := candidate.Input
	input.Type = normalizeImportedTransactionType(input.Type)
	input.AccountID = strings.TrimSpace(input.AccountID)
	input.ToAccountID = strings.TrimSpace(input.ToAccountID)
	input.CategoryID = strings.TrimSpace(input.CategoryID)
	input.MemberID = strings.TrimSpace(input.MemberID)
	input.PaidByMemberID = strings.TrimSpace(input.PaidByMemberID)
	errorsList := append([]string(nil), candidate.ParseErrors...)

	if input.AccountID == "" {
		input.AccountID, errorsList = resolveImportName("账户", input.AccountName, accountNames, errorsList)
	}
	if input.Type == "transfer" && input.ToAccountID == "" {
		input.ToAccountID, errorsList = resolveImportName("转入账户", input.ToAccountName, accountNames, errorsList)
	}
	if input.Type != "transfer" {
		input.ToAccountID = ""
	}
	if input.CategoryID == "" && strings.TrimSpace(input.CategoryName) != "" {
		input.CategoryID, errorsList = resolveImportName("分类", input.CategoryName, categoryNames, errorsList)
	}
	if input.Type == "transfer" {
		input.CategoryID = ""
	}

	request := CreateTransactionRequest{
		Type: input.Type, Amount: roundMoney(input.Amount), AccountID: input.AccountID,
		TransactionDate: strings.TrimSpace(input.TransactionDate), Remark: input.Remark, Tags: input.Tags,
	}
	if input.ToAccountID != "" {
		request.ToAccountID = &input.ToAccountID
	}
	if input.CategoryID != "" {
		request.CategoryID = &input.CategoryID
	}
	if input.MemberID != "" {
		request.MemberID = &input.MemberID
	}
	if input.PaidByMemberID != "" {
		request.PaidByMemberID = &input.PaidByMemberID
	}

	if request.Type != "income" && request.Type != "expense" && request.Type != "transfer" {
		errorsList = append(errorsList, "类型必须是收入、支出或转账")
	}
	if request.Amount <= 0 || math.IsNaN(request.Amount) || math.IsInf(request.Amount, 0) {
		errorsList = append(errorsList, "金额必须大于 0")
	}
	account, accountExists := accounts[request.AccountID]
	if !accountExists {
		errorsList = append(errorsList, "账户不存在或不属于当前用户")
	}
	if request.Type == "transfer" {
		if request.ToAccountID == nil || *request.ToAccountID == "" || *request.ToAccountID == request.AccountID {
			errorsList = append(errorsList, "转账必须指定不同的转入账户")
		} else if _, exists := accounts[*request.ToAccountID]; !exists {
			errorsList = append(errorsList, "转入账户不存在或不属于当前用户")
		}
	}
	categoryName := strings.TrimSpace(input.CategoryName)
	if request.CategoryID != nil {
		category, exists := categories[*request.CategoryID]
		if !exists {
			errorsList = append(errorsList, "分类不存在或不属于当前用户")
		} else {
			categoryName = category.Name
			if request.Type != "transfer" && category.Type != request.Type {
				errorsList = append(errorsList, "分类与收支类型不匹配")
			}
		}
	}
	if request.MemberID != nil {
		if _, exists := members[*request.MemberID]; !exists {
			errorsList = append(errorsList, "家庭成员不存在或不属于当前用户")
		}
	}
	if request.PaidByMemberID != nil {
		if _, exists := members[*request.PaidByMemberID]; !exists {
			errorsList = append(errorsList, "付款成员不存在或不属于当前用户")
		}
	}
	if parsedDate, err := parseTransactionDate(request.TransactionDate); err != nil {
		errorsList = append(errorsList, "交易日期格式无效")
	} else {
		request.TransactionDate = parsedDate.Format(time.RFC3339Nano)
	}
	errorsList = uniqueStringsInOrder(errorsList)
	accountLabel := strings.TrimSpace(input.AccountName)
	if accountExists {
		accountLabel = account.Name
	}
	return validatedTransactionImportRow{
		Preview: TransactionImportRow{
			Row: candidate.Row, Type: request.Type, Amount: request.Amount,
			TransactionDate: request.TransactionDate, Account: accountLabel, Category: categoryName,
			Valid: len(errorsList) == 0, Errors: errorsList,
		},
		Request: request,
	}
}

func importAccountLookups(txdb *gorm.DB, userID uint) (map[string]model.Account, map[string][]string, error) {
	var values []model.Account
	if err := txdb.Where("user_id = ?", userID).Find(&values).Error; err != nil {
		return nil, nil, err
	}
	byID := make(map[string]model.Account, len(values))
	byName := make(map[string][]string)
	for _, value := range values {
		byID[value.ID] = value
		name := strings.TrimSpace(value.Name)
		if name != "" {
			byName[name] = append(byName[name], value.ID)
		}
	}
	return byID, byName, nil
}

func importCategoryLookups(txdb *gorm.DB, userID uint) (map[string]model.Category, map[string][]string, error) {
	var values []model.Category
	if err := txdb.Where("user_id = ?", userID).Find(&values).Error; err != nil {
		return nil, nil, err
	}
	byID := make(map[string]model.Category, len(values))
	byName := make(map[string][]string)
	for _, value := range values {
		byID[value.ID] = value
		name := strings.TrimSpace(value.Name)
		if name != "" {
			byName[name] = append(byName[name], value.ID)
		}
	}
	return byID, byName, nil
}

func importMemberLookup(txdb *gorm.DB, userID uint) (map[string]struct{}, error) {
	var ids []string
	if err := txdb.Model(&model.FamilyMember{}).Where("user_id = ?", userID).Pluck("id", &ids).Error; err != nil {
		return nil, err
	}
	result := make(map[string]struct{}, len(ids))
	for _, id := range ids {
		result[id] = struct{}{}
	}
	return result, nil
}

func existingImportFingerprints(txdb *gorm.DB, userID uint, fingerprints []string) (map[string]struct{}, error) {
	result := make(map[string]struct{})
	for start := 0; start < len(fingerprints); start += 500 {
		end := start + 500
		if end > len(fingerprints) {
			end = len(fingerprints)
		}
		var existing []string
		if err := txdb.Model(&model.Transaction{}).
			Where("user_id = ? AND import_fingerprint IN ?", userID, fingerprints[start:end]).
			Pluck("import_fingerprint", &existing).Error; err != nil {
			return nil, err
		}
		for _, fingerprint := range existing {
			result[fingerprint] = struct{}{}
		}
	}
	return result, nil
}

func resolveImportName(label, value string, lookup map[string][]string, errorsList []string) (string, []string) {
	name := strings.TrimSpace(value)
	if name == "" {
		return "", append(errorsList, label+"不能为空")
	}
	ids := lookup[name]
	switch len(ids) {
	case 0:
		return "", append(errorsList, label+"不存在")
	case 1:
		return ids[0], errorsList
	default:
		return "", append(errorsList, label+"名称不唯一，请改用 ID")
	}
}

func normalizeImportedTransactionType(value string) string {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "income", "收入":
		return "income"
	case "expense", "支出":
		return "expense"
	case "transfer", "转账":
		return "transfer"
	default:
		return strings.ToLower(strings.TrimSpace(value))
	}
}

func readTransactionImportFile(reader io.Reader) ([]byte, error) {
	data, err := io.ReadAll(io.LimitReader(reader, transactionImportMaxFileBytes+1))
	if err != nil {
		return nil, err
	}
	if len(data) > transactionImportMaxFileBytes {
		return nil, ErrTransactionImportTooLarge
	}
	if len(bytes.TrimSpace(data)) == 0 {
		return nil, ErrTransactionImportFormat
	}
	return data, nil
}

func parseTransactionImportFile(filename string, data []byte) (string, []transactionImportCandidate, error) {
	extension := strings.ToLower(filepath.Ext(filename))
	trimmed := bytes.TrimSpace(data)
	if extension == ".json" || (extension == "" && len(trimmed) > 0 && (trimmed[0] == '{' || trimmed[0] == '[')) {
		candidates, err := parseTransactionImportJSON(trimmed)
		return "json", candidates, err
	}
	if extension == ".csv" || extension == "" {
		candidates, err := parseTransactionImportCSV(data)
		return "csv", candidates, err
	}
	return "", nil, ErrTransactionImportFormat
}

func parseTransactionImportJSON(data []byte) ([]transactionImportCandidate, error) {
	var inputs []TransactionImportInput
	if len(data) > 0 && data[0] == '[' {
		if err := json.Unmarshal(data, &inputs); err != nil {
			return nil, ErrTransactionImportFormat
		}
	} else {
		var envelope struct {
			Transactions []TransactionImportInput `json:"transactions"`
		}
		if err := json.Unmarshal(data, &envelope); err != nil {
			return nil, ErrTransactionImportFormat
		}
		inputs = envelope.Transactions
	}
	if len(inputs) == 0 {
		return nil, ErrTransactionImportFormat
	}
	if len(inputs) > transactionImportMaxRows {
		return nil, ErrTransactionImportRowsLimit
	}
	candidates := make([]transactionImportCandidate, 0, len(inputs))
	for index, input := range inputs {
		candidates = append(candidates, transactionImportCandidate{Row: index + 1, Input: input})
	}
	return candidates, nil
}

func parseTransactionImportCSV(data []byte) ([]transactionImportCandidate, error) {
	reader := csv.NewReader(bytes.NewReader(data))
	reader.FieldsPerRecord = -1
	reader.TrimLeadingSpace = true
	header, err := reader.Read()
	if err != nil {
		return nil, ErrTransactionImportFormat
	}
	columns := make(map[string]int)
	for index, value := range header {
		if canonical := canonicalImportCSVColumn(value); canonical != "" {
			columns[canonical] = index
		}
	}
	for _, required := range []string{"type", "amount", "transaction_date"} {
		if _, exists := columns[required]; !exists {
			return nil, ErrTransactionImportFormat
		}
	}
	if _, hasID := columns["account_id"]; !hasID {
		if _, hasName := columns["account_name"]; !hasName {
			return nil, ErrTransactionImportFormat
		}
	}

	candidates := make([]transactionImportCandidate, 0)
	for rowNumber := 2; ; rowNumber++ {
		record, err := reader.Read()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return nil, ErrTransactionImportFormat
		}
		if csvRecordIsEmpty(record) {
			continue
		}
		if len(candidates) >= transactionImportMaxRows {
			return nil, ErrTransactionImportRowsLimit
		}
		amount, amountErr := strconv.ParseFloat(strings.TrimSpace(importCSVValue(record, columns, "amount")), 64)
		parseErrors := []string(nil)
		if amountErr != nil {
			parseErrors = append(parseErrors, "金额格式无效")
		}
		candidates = append(candidates, transactionImportCandidate{
			Row: rowNumber,
			Input: TransactionImportInput{
				Type: importCSVValue(record, columns, "type"), Amount: amount,
				AccountID: importCSVValue(record, columns, "account_id"), AccountName: importCSVValue(record, columns, "account_name"),
				ToAccountID: importCSVValue(record, columns, "to_account_id"), ToAccountName: importCSVValue(record, columns, "to_account_name"),
				CategoryID: importCSVValue(record, columns, "category_id"), CategoryName: importCSVValue(record, columns, "category_name"),
				TransactionDate: importCSVValue(record, columns, "transaction_date"), Remark: importCSVValue(record, columns, "remark"),
			},
			ParseErrors: parseErrors,
		})
	}
	if len(candidates) == 0 {
		return nil, ErrTransactionImportFormat
	}
	return candidates, nil
}

func canonicalImportCSVColumn(value string) string {
	normalized := strings.ToLower(strings.TrimSpace(strings.TrimPrefix(value, "\ufeff")))
	switch normalized {
	case "类型", "type":
		return "type"
	case "金额", "amount":
		return "amount"
	case "日期", "交易日期", "date", "transaction_date":
		return "transaction_date"
	case "账户", "account", "account_name":
		return "account_name"
	case "账户id", "account_id":
		return "account_id"
	case "转入账户", "to_account", "to_account_name":
		return "to_account_name"
	case "转入账户id", "to_account_id":
		return "to_account_id"
	case "分类", "category", "category_name":
		return "category_name"
	case "分类id", "category_id":
		return "category_id"
	case "备注", "remark":
		return "remark"
	default:
		return ""
	}
}

func importCSVValue(record []string, columns map[string]int, key string) string {
	index, exists := columns[key]
	if !exists || index < 0 || index >= len(record) {
		return ""
	}
	return strings.TrimSpace(record[index])
}

func csvRecordIsEmpty(record []string) bool {
	for _, value := range record {
		if strings.TrimSpace(value) != "" {
			return false
		}
	}
	return true
}

func countInvalidImportRows(rows []validatedTransactionImportRow) int {
	count := 0
	for _, row := range rows {
		if !row.Preview.Valid {
			count++
		}
	}
	return count
}

func buildTransactionImportPreview(session *transactionImportSession) *TransactionImportPreview {
	preview := &TransactionImportPreview{
		ID: session.ID, Filename: session.Filename, Format: session.Format, Status: session.Status,
		TotalRows: len(session.Rows), CreatedRows: len(session.CreatedIDs), RolledBackRows: session.RolledBackRows,
		CreatedAt: session.CreatedAt, ExpiresAt: session.ExpiresAt,
		CommittedAt: session.CommittedAt, RolledBackAt: session.RolledBackAt,
	}
	invalidRows := make([]TransactionImportRow, 0)
	validRows := make([]TransactionImportRow, 0)
	for _, row := range session.Rows {
		if row.Preview.Valid {
			preview.ValidRows++
			validRows = append(validRows, row.Preview)
		} else {
			preview.InvalidRows++
			invalidRows = append(invalidRows, row.Preview)
		}
		if row.Preview.Duplicate {
			preview.DuplicateRows++
		}
	}
	invalidLimit := len(invalidRows)
	if invalidLimit > transactionImportPreviewRows {
		invalidLimit = transactionImportPreviewRows
	}
	preview.Rows = append(preview.Rows, invalidRows[:invalidLimit]...)
	remaining := transactionImportPreviewRows - len(preview.Rows)
	if remaining > 0 {
		if remaining > len(validRows) {
			remaining = len(validRows)
		}
		preview.Rows = append(preview.Rows, validRows[:remaining]...)
	}
	sort.Slice(preview.Rows, func(i, j int) bool { return preview.Rows[i].Row < preview.Rows[j].Row })
	preview.RowsTruncated = len(preview.Rows) < len(session.Rows)
	return preview
}

func (s *TransactionImportService) storeSession(session *transactionImportSession) error {
	now := time.Now()
	return s.transactions.txRepo.DB().Transaction(func(txdb *gorm.DB) error {
		if err := txdb.Where("user_id = ? AND expires_at <= ?", session.UserID, now).
			Delete(&model.TransactionImportBatch{}).Error; err != nil {
			return err
		}

		var activeCount int64
		if err := txdb.Model(&model.TransactionImportBatch{}).
			Where("user_id = ? AND expires_at > ?", session.UserID, now).
			Count(&activeCount).Error; err != nil {
			return err
		}
		if activeCount >= transactionImportMaxSessions {
			var oldest model.TransactionImportBatch
			err := txdb.Where("user_id = ? AND expires_at > ? AND status <> ?", session.UserID, now, "committed").
				Order("created_at ASC").First(&oldest).Error
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return ErrTransactionImportState
			}
			if err != nil {
				return err
			}
			if err := txdb.Delete(&oldest).Error; err != nil {
				return err
			}
		}

		batch, err := transactionImportBatchFromSession(session)
		if err != nil {
			return err
		}
		return txdb.Create(batch).Error
	})
}

func (s *TransactionImportService) sessionForUser(userID uint, sessionID string) (*transactionImportSession, error) {
	id := strings.TrimSpace(sessionID)
	if userID == 0 || id == "" {
		return nil, ErrTransactionImportNotFound
	}
	var batch model.TransactionImportBatch
	err := s.transactions.txRepo.DB().Where("id = ? AND user_id = ?", id, userID).First(&batch).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, ErrTransactionImportNotFound
	}
	if err != nil {
		return nil, err
	}
	if !time.Now().Before(batch.ExpiresAt) {
		return nil, ErrTransactionImportExpired
	}
	return transactionImportSessionFromBatch(&batch)
}

func (s *TransactionImportService) persistSessionState(session *transactionImportSession, allowedStatuses []string) error {
	return s.persistSessionStateWithDB(s.transactions.txRepo.DB(), session, allowedStatuses)
}

func (s *TransactionImportService) persistSessionStateWithDB(
	txdb *gorm.DB,
	session *transactionImportSession,
	allowedStatuses []string,
) error {
	payload, err := encodeTransactionImportPayload(session)
	if err != nil {
		return err
	}
	preview := buildTransactionImportPreview(session)
	result := txdb.Model(&model.TransactionImportBatch{}).
		Where("id = ? AND user_id = ? AND status IN ?", session.ID, session.UserID, allowedStatuses).
		Updates(map[string]interface{}{
			"status":           session.Status,
			"total_rows":       preview.TotalRows,
			"valid_rows":       preview.ValidRows,
			"invalid_rows":     preview.InvalidRows,
			"duplicate_rows":   preview.DuplicateRows,
			"created_rows":     preview.CreatedRows,
			"rolled_back_rows": preview.RolledBackRows,
			"payload":          payload,
			"expires_at":       session.ExpiresAt,
			"committed_at":     session.CommittedAt,
			"rolled_back_at":   session.RolledBackAt,
			"updated_at":       time.Now(),
		})
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected != 1 {
		return ErrTransactionImportState
	}
	return nil
}

func transactionImportBatchFromSession(session *transactionImportSession) (*model.TransactionImportBatch, error) {
	payload, err := encodeTransactionImportPayload(session)
	if err != nil {
		return nil, err
	}
	preview := buildTransactionImportPreview(session)
	return &model.TransactionImportBatch{
		ID: session.ID, UserID: session.UserID, Filename: session.Filename,
		Format: session.Format, FileDigest: session.FileDigest, Status: session.Status,
		TotalRows: preview.TotalRows, ValidRows: preview.ValidRows,
		InvalidRows: preview.InvalidRows, DuplicateRows: preview.DuplicateRows,
		CreatedRows: preview.CreatedRows, RolledBackRows: preview.RolledBackRows,
		Payload: payload, CreatedAt: session.CreatedAt, UpdatedAt: session.CreatedAt,
		ExpiresAt: session.ExpiresAt, CommittedAt: session.CommittedAt, RolledBackAt: session.RolledBackAt,
	}, nil
}

func transactionImportPreviewFromBatchSummary(batch *model.TransactionImportBatch) TransactionImportPreview {
	return TransactionImportPreview{
		ID: batch.ID, Filename: batch.Filename, Format: batch.Format, Status: batch.Status,
		TotalRows: batch.TotalRows, ValidRows: batch.ValidRows, InvalidRows: batch.InvalidRows,
		DuplicateRows: batch.DuplicateRows, CreatedRows: batch.CreatedRows,
		RolledBackRows: batch.RolledBackRows, Rows: []TransactionImportRow{},
		RowsTruncated: batch.TotalRows > 0,
		CreatedAt:     batch.CreatedAt, ExpiresAt: batch.ExpiresAt,
		CommittedAt: batch.CommittedAt, RolledBackAt: batch.RolledBackAt,
	}
}

func transactionImportSessionFromBatch(batch *model.TransactionImportBatch) (*transactionImportSession, error) {
	var payload transactionImportPayload
	if err := json.Unmarshal(batch.Payload, &payload); err != nil {
		return nil, fmt.Errorf("decode transaction import batch %s: %w", batch.ID, err)
	}
	if len(payload.Candidates) > transactionImportMaxRows || len(payload.Rows) > transactionImportMaxRows || len(payload.CreatedIDs) > transactionImportMaxRows {
		return nil, fmt.Errorf("transaction import batch %s exceeds persisted row limits", batch.ID)
	}
	return &transactionImportSession{
		ID: batch.ID, UserID: batch.UserID, Filename: batch.Filename, Format: batch.Format,
		FileDigest: batch.FileDigest, Status: batch.Status, Candidates: payload.Candidates,
		Rows: payload.Rows, CreatedIDs: payload.CreatedIDs, RolledBackRows: payload.RolledBackRows,
		CreatedAt: batch.CreatedAt, ExpiresAt: batch.ExpiresAt,
		CommittedAt: batch.CommittedAt, RolledBackAt: batch.RolledBackAt,
	}, nil
}

func encodeTransactionImportPayload(session *transactionImportSession) ([]byte, error) {
	return json.Marshal(transactionImportPayload{
		Candidates: session.Candidates, Rows: session.Rows,
		CreatedIDs: session.CreatedIDs, RolledBackRows: session.RolledBackRows,
	})
}

func safeImportFilename(filename string) string {
	value := filepath.Base(strings.ReplaceAll(strings.TrimSpace(filename), "\\", "/"))
	if value == "" || value == "." || value == ".." {
		return "transactions"
	}
	runes := []rune(value)
	if len(runes) > 240 {
		value = string(runes[:240])
	}
	return value
}

func uniqueStringsInOrder(values []string) []string {
	seen := make(map[string]struct{}, len(values))
	result := make([]string, 0, len(values))
	for _, value := range values {
		if value == "" {
			continue
		}
		if _, exists := seen[value]; exists {
			continue
		}
		seen[value] = struct{}{}
		result = append(result, value)
	}
	return result
}
