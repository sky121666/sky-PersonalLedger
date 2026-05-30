package handler

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"github.com/sky/personal-ledger/internal/service"
)

func TestLendingListDoesNotExposeDatabaseError(t *testing.T) {
	handler, repos, userID := newLendingHandlerForTest(t)
	sqlDB, err := repos.Account.DB().DB()
	if err != nil {
		t.Fatalf("get sql db: %v", err)
	}
	if err := sqlDB.Close(); err != nil {
		t.Fatalf("close sql db: %v", err)
	}

	response := performLendingListRequest(handler, userID)

	if response.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500; body=%s", response.Code, response.Body.String())
	}
	if !strings.Contains(response.Body.String(), "failed to list lendings") {
		t.Fatalf("body = %s, want generic lending list error", response.Body.String())
	}
	if strings.Contains(strings.ToLower(response.Body.String()), "database") ||
		strings.Contains(strings.ToLower(response.Body.String()), "sql") {
		t.Fatalf("response exposed database error: %s", response.Body.String())
	}
}

func TestLendingCreateInvalidDateIsBadRequest(t *testing.T) {
	handler, _, userID := newLendingHandlerForTest(t)
	body := `{
		"type":"lend_out",
		"contact_name":"Alice",
		"principal":100,
		"lend_date":"not-a-date"
	}`

	response := performLendingCreateRequest(handler, userID, body)

	if response.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400; body=%s", response.Code, response.Body.String())
	}
	if !strings.Contains(response.Body.String(), "invalid date time format") {
		t.Fatalf("body = %s, want invalid date time format", response.Body.String())
	}
}

func TestLendingCreateMissingAccountIsBadRequest(t *testing.T) {
	handler, _, userID := newLendingHandlerForTest(t)
	body := `{
		"type":"lend_out",
		"contact_name":"Alice",
		"principal":100,
		"lend_date":"2026-05-30",
		"account_id":"missing-account",
		"create_transaction":true
	}`

	response := performLendingCreateRequest(handler, userID, body)

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

func newLendingHandlerForTest(t *testing.T) (*LendingHandler, *repository.Repositories, uint) {
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
	lendingService := service.NewLendingService(
		repos.Lending,
		repos.Account,
		repos.Transaction,
		repos.Category,
		accountLogSvc,
	)
	return NewLendingHandler(lendingService), repos, user.ID
}

func performLendingListRequest(handler *LendingHandler, userID uint) *httptest.ResponseRecorder {
	router := gin.New()
	router.GET("/lendings", func(c *gin.Context) {
		c.Set("userID", userID)
		handler.List(c)
	})
	request := httptest.NewRequest(http.MethodGet, "/lendings", nil)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	return response
}

func performLendingCreateRequest(handler *LendingHandler, userID uint, body string) *httptest.ResponseRecorder {
	router := gin.New()
	router.POST("/lendings", func(c *gin.Context) {
		c.Set("userID", userID)
		handler.Create(c)
	})
	request := httptest.NewRequest(http.MethodPost, "/lendings", bytes.NewBufferString(body))
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	return response
}
