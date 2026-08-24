package handler

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

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

func TestTransactionGetDatabaseErrorIsInternalServerError(t *testing.T) {
	handler, repos, userID := newTransactionHandlerForTest(t)
	closeTransactionHandlerDatabase(t, repos)

	response := performTransactionGetRequest(handler, userID, "missing")

	if response.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500; body=%s", response.Code, response.Body.String())
	}
	if !strings.Contains(response.Body.String(), "failed to load transaction") {
		t.Fatalf("body = %s, want generic transaction load error", response.Body.String())
	}
}

func TestTransactionUpdateDatabaseErrorIsInternalServerError(t *testing.T) {
	handler, repos, userID := newTransactionHandlerForTest(t)
	accountID := createTransactionHandlerAccount(t, repos, userID)
	closeTransactionHandlerDatabase(t, repos)
	body := `{
		"type":"expense",
		"amount":12.5,
		"account_id":"` + accountID + `",
		"transaction_date":"2026-05-30"
	}`

	response := performTransactionUpdateRequest(handler, userID, "missing", body)

	if response.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500; body=%s", response.Code, response.Body.String())
	}
	if !strings.Contains(response.Body.String(), "failed to update transaction") {
		t.Fatalf("body = %s, want generic transaction update error", response.Body.String())
	}
}

func TestTransactionUpdateManagedTransactionIsStableBadRequest(t *testing.T) {
	handler, repos, userID := newTransactionHandlerForTest(t)
	accountID := createTransactionHandlerAccount(t, repos, userID)
	transaction := &model.Transaction{
		ID:              uuid.NewString(),
		UserID:          userID,
		AccountID:       accountID,
		Type:            "expense",
		Amount:          10,
		TransactionDate: time.Now(),
		Source:          "lending",
	}
	if err := repos.Transaction.Create(transaction); err != nil {
		t.Fatalf("create managed transaction: %v", err)
	}
	body := `{
		"type":"expense",
		"amount":12.5,
		"account_id":"` + accountID + `",
		"transaction_date":"2026-05-30"
	}`

	response := performTransactionUpdateRequest(handler, userID, transaction.ID, body)

	if response.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400; body=%s", response.Code, response.Body.String())
	}
	const wantBody = `{"code":40000,"message":"managed transaction cannot be updated directly"}`
	if got := strings.TrimSpace(response.Body.String()); got != wantBody {
		t.Fatalf("body = %s, want %s", got, wantBody)
	}
}

func TestTransactionSystemMutationsAreStableBadRequests(t *testing.T) {
	handler, repos, userID := newTransactionHandlerForTest(t)
	accountID := createTransactionHandlerAccount(t, repos, userID)
	transaction := &model.Transaction{
		ID:              uuid.NewString(),
		UserID:          userID,
		AccountID:       accountID,
		Type:            "income",
		Amount:          10,
		TransactionDate: time.Now(),
		Source:          "system",
	}
	if err := repos.Transaction.Create(transaction); err != nil {
		t.Fatalf("create system transaction: %v", err)
	}
	body := `{
		"type":"income",
		"amount":12.5,
		"account_id":"` + accountID + `",
		"transaction_date":"2026-05-30"
	}`
	const wantBody = `{"code":40000,"message":"system transaction cannot be changed directly"}`

	updateResponse := performTransactionUpdateRequest(handler, userID, transaction.ID, body)
	if updateResponse.Code != http.StatusBadRequest || strings.TrimSpace(updateResponse.Body.String()) != wantBody {
		t.Fatalf("update response = %d %s, want 400 %s", updateResponse.Code, updateResponse.Body.String(), wantBody)
	}

	deleteResponse := performTransactionDeleteRequest(handler, userID, transaction.ID)
	if deleteResponse.Code != http.StatusBadRequest || strings.TrimSpace(deleteResponse.Body.String()) != wantBody {
		t.Fatalf("delete response = %d %s, want 400 %s", deleteResponse.Code, deleteResponse.Body.String(), wantBody)
	}

	batchResponse := performTransactionBatchDeleteRequest(handler, userID, transaction.ID)
	if batchResponse.Code != http.StatusBadRequest || strings.TrimSpace(batchResponse.Body.String()) != wantBody {
		t.Fatalf("batch delete response = %d %s, want 400 %s", batchResponse.Code, batchResponse.Body.String(), wantBody)
	}
}

func TestTransactionDeleteDatabaseErrorIsInternalServerError(t *testing.T) {
	handler, repos, userID := newTransactionHandlerForTest(t)
	closeTransactionHandlerDatabase(t, repos)

	response := performTransactionDeleteRequest(handler, userID, "missing")

	if response.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500; body=%s", response.Code, response.Body.String())
	}
	if !strings.Contains(response.Body.String(), "failed to delete transaction") {
		t.Fatalf("body = %s, want generic transaction delete error", response.Body.String())
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

func TestTransactionCreateWithImagesRequiresCreateThenPatch(t *testing.T) {
	handler, repos, userID := newTransactionHandlerForTest(t)
	accountID := createTransactionHandlerAccount(t, repos, userID)
	body := `{
		"type":"expense",
		"amount":12.5,
		"account_id":"` + accountID + `",
		"transaction_date":"2026-05-30",
		"images":"[\"` + strconv.FormatUint(uint64(userID), 10) + `/transactions/client-id/receipt.png\"]"
	}`

	response := performTransactionCreateRequest(handler, userID, body)
	if response.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400; body=%s", response.Code, response.Body.String())
	}
	if !strings.Contains(response.Body.String(), "create the transaction before adding attachments") {
		t.Fatalf("body = %s, want create-then-patch guidance", response.Body.String())
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

func closeTransactionHandlerDatabase(t *testing.T, repos *repository.Repositories) {
	t.Helper()
	sqlDB, err := repos.Transaction.DB().DB()
	if err != nil {
		t.Fatalf("get sql db: %v", err)
	}
	if err := sqlDB.Close(); err != nil {
		t.Fatalf("close sql db: %v", err)
	}
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

func performTransactionGetRequest(handler *TransactionHandler, userID uint, id string) *httptest.ResponseRecorder {
	router := gin.New()
	router.GET("/transactions/:id", func(c *gin.Context) {
		c.Set("userID", userID)
		handler.GetByID(c)
	})
	request := httptest.NewRequest(http.MethodGet, "/transactions/"+id, nil)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	return response
}

func performTransactionUpdateRequest(handler *TransactionHandler, userID uint, id string, body string) *httptest.ResponseRecorder {
	router := gin.New()
	router.PUT("/transactions/:id", func(c *gin.Context) {
		c.Set("userID", userID)
		handler.Update(c)
	})
	request := httptest.NewRequest(http.MethodPut, "/transactions/"+id, bytes.NewBufferString(body))
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	return response
}

func performTransactionDeleteRequest(handler *TransactionHandler, userID uint, id string) *httptest.ResponseRecorder {
	router := gin.New()
	router.DELETE("/transactions/:id", func(c *gin.Context) {
		c.Set("userID", userID)
		handler.Delete(c)
	})
	request := httptest.NewRequest(http.MethodDelete, "/transactions/"+id, nil)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	return response
}

func performTransactionBatchDeleteRequest(handler *TransactionHandler, userID uint, id string) *httptest.ResponseRecorder {
	router := gin.New()
	router.POST("/transactions/batch-delete", func(c *gin.Context) {
		c.Set("userID", userID)
		handler.BatchDelete(c)
	})
	request := httptest.NewRequest(
		http.MethodPost,
		"/transactions/batch-delete",
		bytes.NewBufferString(`{"ids":["`+id+`"]}`),
	)
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
