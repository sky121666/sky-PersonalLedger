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

func TestCategoryListDoesNotExposeDatabaseError(t *testing.T) {
	repos := newClosedRepositoriesForHandlerTest(t)
	handler := NewCategoryHandler(service.NewCategoryService(repos.Category))

	router := gin.New()
	router.GET("/categories", func(c *gin.Context) {
		c.Set("userID", uint(1))
		handler.List(c)
	})

	response := performQueryErrorRequest(router, "/categories")

	assertGenericInternalError(t, response, "failed to list categories")
}

func TestTemplateListDoesNotExposeDatabaseError(t *testing.T) {
	repos := newClosedRepositoriesForHandlerTest(t)
	handler := NewTemplateHandler(service.NewTemplateService(repos.Template, repos.Transaction, repos.Account))

	router := gin.New()
	router.GET("/templates", func(c *gin.Context) {
		c.Set("userID", uint(1))
		handler.List(c)
	})

	response := performQueryErrorRequest(router, "/templates")

	assertGenericInternalError(t, response, "failed to list templates")
}

func TestBudgetListDoesNotExposeDatabaseError(t *testing.T) {
	repos := newClosedRepositoriesForHandlerTest(t)
	handler := NewBudgetHandler(service.NewBudgetService(repos.Budget, repos.Transaction, repos.FamilyMember))

	router := gin.New()
	router.GET("/budgets", func(c *gin.Context) {
		c.Set("userID", uint(1))
		handler.List(c)
	})

	response := performQueryErrorRequest(router, "/budgets")

	assertGenericInternalError(t, response, "failed to list budgets")
}

func TestReminderListDoesNotExposeDatabaseError(t *testing.T) {
	repos := newClosedRepositoriesForHandlerTest(t)
	accountLogService := service.NewAccountLogService(repos.AccountLog, repos.Account)
	handler := NewReminderHandler(service.NewReminderService(
		repos.Reminder,
		repos.Account,
		repos.Transaction,
		repos.Category,
		accountLogService,
	))

	router := gin.New()
	router.GET("/reminders", func(c *gin.Context) {
		c.Set("userID", uint(1))
		handler.List(c)
	})

	response := performQueryErrorRequest(router, "/reminders")

	assertGenericInternalError(t, response, "failed to list reminders")
}

func TestNotificationGetDoesNotExposeDatabaseError(t *testing.T) {
	repos := newClosedRepositoriesForHandlerTest(t)
	handler := NewNotificationHandler(service.NewNotificationService(repos.Notification, repos.User))

	router := gin.New()
	router.GET("/notifications", func(c *gin.Context) {
		c.Set("userID", uint(1))
		handler.Get(c)
	})

	response := performQueryErrorRequest(router, "/notifications")

	assertGenericInternalError(t, response, "failed to load notification settings")
}

func TestNotificationEmailTestDoesNotIgnoreSettingsError(t *testing.T) {
	repos := newClosedRepositoriesForHandlerTest(t)
	handler := NewNotificationHandler(service.NewNotificationService(repos.Notification, repos.User))

	router := gin.New()
	router.POST("/notifications/test-email", func(c *gin.Context) {
		c.Set("userID", uint(1))
		handler.TestEmail(c)
	})

	request := httptest.NewRequest(http.MethodPost, "/notifications/test-email", bytes.NewBufferString(`{
		"smtp_host":"smtp.example.test",
		"smtp_user":"user@example.test",
		"email_to":"to@example.test"
	}`))
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

	assertGenericInternalError(t, response, "failed to load notification settings")
}

func TestFamilyListDoesNotExposeDatabaseError(t *testing.T) {
	repos := newClosedRepositoriesForHandlerTest(t)
	handler := NewFamilyHandler(service.NewFamilyMemberService(repos.FamilyMember, repos.Transaction))

	router := gin.New()
	router.GET("/family/members", func(c *gin.Context) {
		c.Set("userID", uint(1))
		handler.ListMembers(c)
	})

	response := performQueryErrorRequest(router, "/family/members")

	assertGenericInternalError(t, response, "failed to list family members")
}

func TestTagListDoesNotExposeDatabaseError(t *testing.T) {
	repos := newClosedRepositoriesForHandlerTest(t)
	handler := NewTagHandler(service.NewTagService(repos.Tag))

	router := gin.New()
	router.GET("/tags", func(c *gin.Context) {
		c.Set("userID", uint(1))
		handler.List(c)
	})

	response := performQueryErrorRequest(router, "/tags")

	assertGenericInternalError(t, response, "failed to list tags")
}

func TestTagCreateDoesNotExposeDatabaseError(t *testing.T) {
	repos := newClosedRepositoriesForHandlerTest(t)
	handler := NewTagHandler(service.NewTagService(repos.Tag))

	router := gin.New()
	router.POST("/tags", func(c *gin.Context) {
		c.Set("userID", uint(1))
		handler.Create(c)
	})

	request := httptest.NewRequest(http.MethodPost, "/tags", bytes.NewBufferString(`{"name":"travel"}`))
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

	assertGenericInternalError(t, response, "failed to create tag")
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
