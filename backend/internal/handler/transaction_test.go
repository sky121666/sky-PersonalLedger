package handler

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"github.com/sky/personal-ledger/internal/service"
)

func TestTransactionListDoesNotExposeDatabaseError(t *testing.T) {
	handler, repos, userID := newTransactionHandlerForTest(t)
	sqlDB, err := repos.Transaction.DB().DB()
	if err != nil {
		t.Fatalf("get sql db: %v", err)
	}
	if err := sqlDB.Close(); err != nil {
		t.Fatalf("close sql db: %v", err)
	}

	response := performTransactionListRequest(handler, userID)

	if response.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500; body=%s", response.Code, response.Body.String())
	}
	if !strings.Contains(response.Body.String(), "failed to list transactions") {
		t.Fatalf("body = %s, want generic transaction list error", response.Body.String())
	}
	if strings.Contains(strings.ToLower(response.Body.String()), "database") ||
		strings.Contains(strings.ToLower(response.Body.String()), "sql") {
		t.Fatalf("response exposed database error: %s", response.Body.String())
	}
}

func TestTransactionCreateMissingAccountIsBadRequest(t *testing.T) {
	handler, _, userID := newTransactionHandlerForTest(t)
	body := `{
		"type":"expense",
		"amount":12.5,
		"account_id":"missing-account",
		"transaction_date":"2026-05-30"
	}`

	response := performTransactionCreateRequest(handler, userID, body)

	if response.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400; body=%s", response.Code, response.Body.String())
	}
	if !strings.Contains(response.Body.String(), "account not found") {
		t.Fatalf("body = %s, want account not found", response.Body.String())
	}
	if strings.Contains(strings.ToLower(response.Body.String()), "record not found") {
		t.Fatalf("response exposed ORM error: %s", response.Body.String())
	}
}

func TestTransactionCreateInvalidDateIsBadRequest(t *testing.T) {
	handler, repos, userID := newTransactionHandlerForTest(t)
	accountID := createTransactionHandlerAccount(t, repos, userID)
	body := `{
		"type":"expense",
		"amount":12.5,
		"account_id":"` + accountID + `",
		"transaction_date":"not-a-date"
	}`

	response := performTransactionCreateRequest(handler, userID, body)

	if response.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400; body=%s", response.Code, response.Body.String())
	}
	if !strings.Contains(response.Body.String(), "invalid transaction date") {
		t.Fatalf("body = %s, want invalid transaction date", response.Body.String())
	}
}

func TestTransactionListInvalidDateIsBadRequest(t *testing.T) {
	handler, _, userID := newTransactionHandlerForTest(t)

	response := performTransactionListRequestTarget(handler, userID, "/transactions?start_date=bad-date")

	if response.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400; body=%s", response.Code, response.Body.String())
	}
	if !strings.Contains(response.Body.String(), "invalid transaction date") {
		t.Fatalf("body = %s, want invalid transaction date", response.Body.String())
	}
}

func TestTransactionExportInvalidStartDateIsBadRequest(t *testing.T) {
	handler, _, userID := newTransactionHandlerForTest(t)

	response := performTransactionExportRequest(handler, userID, "/transactions/export?start_date=bad-date")

	if response.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400; body=%s", response.Code, response.Body.String())
	}
	if !strings.Contains(response.Body.String(), "invalid start date") {
		t.Fatalf("body = %s, want invalid start date", response.Body.String())
	}
}

func TestTransactionExportInvalidEndDateIsBadRequest(t *testing.T) {
	handler, _, userID := newTransactionHandlerForTest(t)

	response := performTransactionExportRequest(handler, userID, "/transactions/export?end_date=bad-date")

	if response.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400; body=%s", response.Code, response.Body.String())
	}
	if !strings.Contains(response.Body.String(), "invalid end date") {
		t.Fatalf("body = %s, want invalid end date", response.Body.String())
	}
}

func newTransactionHandlerForTest(t *testing.T) (*TransactionHandler, *repository.Repositories, uint) {
	t.Helper()
	gin.SetMode(gin.TestMode)
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	user := &model.User{Username: "admin", PasswordHash: "hash"}
	if err := repos.User.Create(user); err != nil {
		t.Fatalf("create user: %v", err)
	}
	accountLogSvc := service.NewAccountLogService(repos.AccountLog, repos.Account)
	txService := service.NewTransactionService(
		repos.Transaction,
		repos.Account,
		repos.Reminder,
		repos.Lending,
		repos.FamilyMember,
		accountLogSvc,
	)
	return NewTransactionHandler(txService), repos, user.ID
}

func createTransactionHandlerAccount(t *testing.T, repos *repository.Repositories, userID uint) string {
	t.Helper()
	accountID := uuid.NewString()
	if err := repos.Account.Create(&model.Account{
		ID:             accountID,
		UserID:         userID,
		Name:           "Wallet",
		Type:           "cash",
		CurrentBalance: 100,
	}); err != nil {
		t.Fatalf("create account: %v", err)
	}
	return accountID
}

func performTransactionListRequest(handler *TransactionHandler, userID uint) *httptest.ResponseRecorder {
	return performTransactionListRequestTarget(handler, userID, "/transactions")
}

func performTransactionListRequestTarget(handler *TransactionHandler, userID uint, target string) *httptest.ResponseRecorder {
	router := gin.New()
	router.GET("/transactions", func(c *gin.Context) {
		c.Set("userID", userID)
		handler.List(c)
	})
	request := httptest.NewRequest(http.MethodGet, target, nil)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	return response
}

func performTransactionCreateRequest(handler *TransactionHandler, userID uint, body string) *httptest.ResponseRecorder {
	router := gin.New()
	router.POST("/transactions", func(c *gin.Context) {
		c.Set("userID", userID)
		handler.Create(c)
	})
	request := httptest.NewRequest(http.MethodPost, "/transactions", bytes.NewBufferString(body))
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	return response
}

func performTransactionExportRequest(handler *TransactionHandler, userID uint, target string) *httptest.ResponseRecorder {
	router := gin.New()
	router.GET("/transactions/export", func(c *gin.Context) {
		c.Set("userID", userID)
		handler.Export(c)
	})
	request := httptest.NewRequest(http.MethodGet, target, nil)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	return response
}
