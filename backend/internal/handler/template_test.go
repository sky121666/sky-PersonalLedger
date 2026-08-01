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

func TestTemplateCreateMissingAccountIsBadRequest(t *testing.T) {
	handler, _, _, userID := newTemplateHandlerForTest(t)
	response := performTemplateRequest(handler, userID, http.MethodPost, "/templates", `{
		"name":"Lunch",
		"type":"expense",
		"amount":25,
		"account_id":"missing-account"
	}`)

	if response.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400; body=%s", response.Code, response.Body.String())
	}
	if !strings.Contains(response.Body.String(), "account not found") {
		t.Fatalf("body = %s, want account not found", response.Body.String())
	}
}

func TestTemplateApplyInvalidDateIsBadRequest(t *testing.T) {
	handler, templateService, repos, userID := newTemplateHandlerForTest(t)
	templateID := createHandlerTemplate(t, templateService, repos, userID)
	response := performTemplateRequest(handler, userID, http.MethodPost, "/templates/"+templateID+"/apply", `{"transaction_date":"not-a-date"}`)

	if response.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400; body=%s", response.Code, response.Body.String())
	}
	if !strings.Contains(response.Body.String(), "invalid transaction date") {
		t.Fatalf("body = %s, want invalid transaction date", response.Body.String())
	}
}

func TestTemplateApplyDoesNotExposeDatabaseError(t *testing.T) {
	handler, templateService, repos, userID := newTemplateHandlerForTest(t)
	templateID := createHandlerTemplate(t, templateService, repos, userID)
	sqlDB, err := repos.Account.DB().DB()
	if err != nil {
		t.Fatalf("get sql db: %v", err)
	}
	if err := sqlDB.Close(); err != nil {
		t.Fatalf("close sql db: %v", err)
	}

	response := performTemplateRequest(handler, userID, http.MethodPost, "/templates/"+templateID+"/apply", `{"transaction_date":"2026-07-13"}`)

	assertGenericInternalError(t, response, "failed to apply template")
}

func newTemplateHandlerForTest(t *testing.T) (*TemplateHandler, *service.TemplateService, *repository.Repositories, uint) {
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
	accountLogService := service.NewAccountLogService(repos.AccountLog, repos.Account)
	transactionService := service.NewTransactionService(repos.Transaction, repos.Account, repos.Reminder, repos.Lending, repos.FamilyMember, accountLogService)
	templateService := service.NewTemplateService(repos.Template, transactionService)
	return NewTemplateHandler(templateService), templateService, repos, user.ID
}

func createHandlerTemplate(t *testing.T, templateService *service.TemplateService, repos *repository.Repositories, userID uint) string {
	t.Helper()
	accountID := uuid.NewString()
	if err := repos.Account.Create(&model.Account{ID: accountID, UserID: userID, Name: "Wallet", Type: "cash", CurrentBalance: 100}); err != nil {
		t.Fatalf("create account: %v", err)
	}
	categoryID := uuid.NewString()
	if err := repos.Category.Create(&model.Category{ID: categoryID, UserID: userID, Name: "Food", Type: "expense"}); err != nil {
		t.Fatalf("create category: %v", err)
	}
	template, err := templateService.Create(userID, service.CreateTemplateRequest{
		Name:       "Lunch",
		Type:       "expense",
		Amount:     25,
		AccountID:  accountID,
		CategoryID: &categoryID,
	})
	if err != nil {
		t.Fatalf("create template: %v", err)
	}
	return template.ID
}

func performTemplateRequest(handler *TemplateHandler, userID uint, method, target, body string) *httptest.ResponseRecorder {
	router := gin.New()
	router.POST("/templates", func(c *gin.Context) {
		c.Set("userID", userID)
		handler.Create(c)
	})
	router.POST("/templates/:id/apply", func(c *gin.Context) {
		c.Set("userID", userID)
		handler.Apply(c)
	})
	request := httptest.NewRequest(method, target, bytes.NewBufferString(body))
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	return response
}
