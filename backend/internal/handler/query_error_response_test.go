package handler

import (
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/repository"
	"github.com/sky/personal-ledger/internal/service"
)

func TestSystemEntryPathDoesNotExposeDatabaseError(t *testing.T) {
	repos := newClosedRepositoriesForHandlerTest(t)
	handler := NewSystemHandler(service.NewSystemService(repos.System))

	router := gin.New()
	router.GET("/system/entry-path", handler.GetEntryPath)

	response := performQueryErrorRequest(router, "/system/entry-path")

	assertGenericInternalError(t, response, "failed to load entry path")
}

func TestAccountLogsDoNotExposeDatabaseError(t *testing.T) {
	repos := newClosedRepositoriesForHandlerTest(t)
	handler := NewAccountLogHandler(service.NewAccountLogService(repos.AccountLog, repos.Account))

	router := gin.New()
	router.GET("/account-logs", func(c *gin.Context) {
		c.Set("user_id", uint(1))
		handler.GetAll(c)
	})

	response := performQueryErrorRequest(router, "/account-logs")

	assertGenericInternalError(t, response, "failed to load account logs")
}

func TestExportYearlyReportDoesNotExposeDatabaseError(t *testing.T) {
	repos := newClosedRepositoriesForHandlerTest(t)
	handler := NewExportHandler(service.NewExportService(repos.Transaction, repos.Category, repos.Account))

	router := gin.New()
	router.GET("/export/yearly", func(c *gin.Context) {
		c.Set("userID", uint(1))
		handler.GetYearlyReport(c)
	})

	response := performQueryErrorRequest(router, "/export/yearly?year=2026")

	assertGenericInternalError(t, response, "failed to load yearly report")
}

func newClosedRepositoriesForHandlerTest(t *testing.T) *repository.Repositories {
	t.Helper()
	gin.SetMode(gin.TestMode)
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	sqlDB, err := db.DB()
	if err != nil {
		t.Fatalf("get sql db: %v", err)
	}
	if err := sqlDB.Close(); err != nil {
		t.Fatalf("close sql db: %v", err)
	}
	return repos
}

func performQueryErrorRequest(router *gin.Engine, target string) *httptest.ResponseRecorder {
	request := httptest.NewRequest(http.MethodGet, target, nil)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	return response
}

func assertGenericInternalError(t *testing.T, response *httptest.ResponseRecorder, message string) {
	t.Helper()
	body := response.Body.String()
	if response.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500; body=%s", response.Code, body)
	}
	if !strings.Contains(body, message) {
		t.Fatalf("body = %s, want generic message %q", body, message)
	}
	lowerBody := strings.ToLower(body)
	if strings.Contains(lowerBody, "database") || strings.Contains(lowerBody, "sql") {
		t.Fatalf("response exposed internal database error: %s", body)
	}
}
