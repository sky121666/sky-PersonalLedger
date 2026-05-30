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

func TestAccountListDoesNotExposeDatabaseError(t *testing.T) {
	handler, repos, userID := newAccountHandlerForTest(t)
	sqlDB, err := repos.Account.DB().DB()
	if err != nil {
		t.Fatalf("get sql db: %v", err)
	}
	if err := sqlDB.Close(); err != nil {
		t.Fatalf("close sql db: %v", err)
	}

	response := performAccountListRequest(handler, userID)

	if response.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500; body=%s", response.Code, response.Body.String())
	}
	if !strings.Contains(response.Body.String(), "failed to list accounts") {
		t.Fatalf("body = %s, want generic account list error", response.Body.String())
	}
	if strings.Contains(strings.ToLower(response.Body.String()), "database") ||
		strings.Contains(strings.ToLower(response.Body.String()), "sql") {
		t.Fatalf("response exposed database error: %s", response.Body.String())
	}
}

func TestAccountSortMissingAccountIsBadRequest(t *testing.T) {
	handler, _, userID := newAccountHandlerForTest(t)

	response := performAccountSortRequest(handler, userID, `{"ids":["missing-account"]}`)

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

func newAccountHandlerForTest(t *testing.T) (*AccountHandler, *repository.Repositories, uint) {
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
	return NewAccountHandler(service.NewAccountService(repos.Account, repos.Transaction, repos.Category)), repos, user.ID
}

func performAccountListRequest(handler *AccountHandler, userID uint) *httptest.ResponseRecorder {
	router := gin.New()
	router.GET("/accounts", func(c *gin.Context) {
		c.Set("userID", userID)
		handler.List(c)
	})
	request := httptest.NewRequest(http.MethodGet, "/accounts", nil)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	return response
}

func performAccountSortRequest(handler *AccountHandler, userID uint, body string) *httptest.ResponseRecorder {
	router := gin.New()
	router.PUT("/accounts/sort", func(c *gin.Context) {
		c.Set("userID", userID)
		handler.UpdateSortOrder(c)
	})
	request := httptest.NewRequest(http.MethodPut, "/accounts/sort", bytes.NewBufferString(body))
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	return response
}
