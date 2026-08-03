package handler

import (
	"bytes"
	"encoding/json"
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

func TestAccountHandlerCRUDArchiveAndOwnership(t *testing.T) {
	handler, repos, userID := newAccountHandlerForTest(t)
	other := &model.User{Username: "account-handler-other", PasswordHash: "hash"}
	if err := repos.User.Create(other); err != nil {
		t.Fatalf("create other user: %v", err)
	}

	invalid := performAccountCRUDRequest(handler, userID, http.MethodPost, "/accounts", `{}`)
	if invalid.Code != http.StatusBadRequest {
		t.Fatalf("invalid create status = %d, body=%s", invalid.Code, invalid.Body.String())
	}
	invalidDate := performAccountCRUDRequest(handler, userID, http.MethodPost, "/accounts", `{"name":"Bad","type":"cash","start_date":"not-a-date"}`)
	if invalidDate.Code != http.StatusUnprocessableEntity {
		t.Fatalf("invalid date status = %d, body=%s", invalidDate.Code, invalidDate.Body.String())
	}

	created := performAccountCRUDRequest(handler, userID, http.MethodPost, "/accounts", `{"name":"Wallet","type":"cash"}`)
	if created.Code != http.StatusCreated {
		t.Fatalf("create status = %d, body=%s", created.Code, created.Body.String())
	}
	var envelope struct {
		Data model.Account `json:"data"`
	}
	if err := json.Unmarshal(created.Body.Bytes(), &envelope); err != nil || envelope.Data.ID == "" {
		t.Fatalf("decode created account: data=%#v err=%v", envelope.Data, err)
	}
	accountID := envelope.Data.ID

	got := performAccountCRUDRequest(handler, userID, http.MethodGet, "/accounts/"+accountID, "")
	if got.Code != http.StatusOK {
		t.Fatalf("get status = %d, body=%s", got.Code, got.Body.String())
	}
	foreign := performAccountCRUDRequest(handler, other.ID, http.MethodGet, "/accounts/"+accountID, "")
	if foreign.Code != http.StatusNotFound {
		t.Fatalf("cross-user get status = %d, body=%s", foreign.Code, foreign.Body.String())
	}

	invalidPatch := performAccountCRUDRequest(handler, userID, http.MethodPut, "/accounts/"+accountID, `{"payment_day":32}`)
	if invalidPatch.Code != http.StatusUnprocessableEntity {
		t.Fatalf("invalid patch status = %d, body=%s", invalidPatch.Code, invalidPatch.Body.String())
	}
	updated := performAccountCRUDRequest(handler, userID, http.MethodPut, "/accounts/"+accountID, `{"name":"Renamed","remark":"note"}`)
	if updated.Code != http.StatusOK || !strings.Contains(updated.Body.String(), "Renamed") {
		t.Fatalf("update status = %d, body=%s", updated.Code, updated.Body.String())
	}
	missingUpdate := performAccountCRUDRequest(handler, userID, http.MethodPut, "/accounts/missing", `{"name":"Missing"}`)
	if missingUpdate.Code != http.StatusNotFound {
		t.Fatalf("missing update status = %d, body=%s", missingUpdate.Code, missingUpdate.Body.String())
	}

	archived := performAccountCRUDRequest(handler, userID, http.MethodPatch, "/accounts/"+accountID+"/archive", `{"is_archived":true}`)
	if archived.Code != http.StatusOK {
		t.Fatalf("archive status = %d, body=%s", archived.Code, archived.Body.String())
	}
	badArchive := performAccountCRUDRequest(handler, userID, http.MethodPatch, "/accounts/"+accountID+"/archive", `{`)
	if badArchive.Code != http.StatusBadRequest {
		t.Fatalf("bad archive status = %d, body=%s", badArchive.Code, badArchive.Body.String())
	}
	missingArchive := performAccountCRUDRequest(handler, userID, http.MethodPatch, "/accounts/missing/archive", `{"is_archived":true}`)
	if missingArchive.Code != http.StatusNotFound {
		t.Fatalf("missing archive status = %d, body=%s", missingArchive.Code, missingArchive.Body.String())
	}

	deleted := performAccountCRUDRequest(handler, userID, http.MethodDelete, "/accounts/"+accountID, "")
	if deleted.Code != http.StatusOK {
		t.Fatalf("delete status = %d, body=%s", deleted.Code, deleted.Body.String())
	}
	missingDelete := performAccountCRUDRequest(handler, userID, http.MethodDelete, "/accounts/"+accountID, "")
	if missingDelete.Code != http.StatusNotFound {
		t.Fatalf("missing delete status = %d, body=%s", missingDelete.Code, missingDelete.Body.String())
	}
}

func TestAccountHandlerRejectsDeletingActiveNonZeroBalance(t *testing.T) {
	handler, repos, userID := newAccountHandlerForTest(t)
	account := &model.Account{ID: "non-zero", UserID: userID, Name: "Cash", Type: "cash", CurrentBalance: 100}
	if err := repos.Account.Create(account); err != nil {
		t.Fatalf("create account: %v", err)
	}
	response := performAccountCRUDRequest(handler, userID, http.MethodDelete, "/accounts/"+account.ID, "")
	if response.Code != http.StatusBadRequest || !strings.Contains(response.Body.String(), "non-zero balance") {
		t.Fatalf("delete non-zero status = %d, body=%s", response.Code, response.Body.String())
	}
}

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
	return NewAccountHandler(service.NewAccountService(repos.Account)), repos, user.ID
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

func performAccountCRUDRequest(handler *AccountHandler, userID uint, method, target, body string) *httptest.ResponseRecorder {
	router := gin.New()
	withUser := func(action gin.HandlerFunc) gin.HandlerFunc {
		return func(c *gin.Context) {
			c.Set("userID", userID)
			action(c)
		}
	}
	router.POST("/accounts", withUser(handler.Create))
	router.GET("/accounts/:id", withUser(handler.GetByID))
	router.PUT("/accounts/:id", withUser(handler.Update))
	router.DELETE("/accounts/:id", withUser(handler.Delete))
	router.PATCH("/accounts/:id/archive", withUser(handler.Archive))
	request := httptest.NewRequest(method, target, bytes.NewBufferString(body))
	if body != "" {
		request.Header.Set("Content-Type", "application/json")
	}
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	return response
}
