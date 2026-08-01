package handler

import (
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

func TestStatisticsOverviewDoesNotExposeDatabaseError(t *testing.T) {
	handler, repos, userID := newStatisticsHandlerForTest(t)
	sqlDB, err := repos.Transaction.DB().DB()
	if err != nil {
		t.Fatalf("get sql db: %v", err)
	}
	if err := sqlDB.Close(); err != nil {
		t.Fatalf("close sql db: %v", err)
	}

	response := performStatisticsRequest(handler, userID, "/statistics/overview?month=2026-05")

	if response.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500; body=%s", response.Code, response.Body.String())
	}
	if !strings.Contains(response.Body.String(), "failed to load statistics overview") {
		t.Fatalf("body = %s, want generic statistics overview error", response.Body.String())
	}
	if strings.Contains(strings.ToLower(response.Body.String()), "database") ||
		strings.Contains(strings.ToLower(response.Body.String()), "sql") {
		t.Fatalf("response exposed database error: %s", response.Body.String())
	}
}

func TestStatisticsCategoryInvalidMonthIsBadRequest(t *testing.T) {
	handler, _, userID := newStatisticsHandlerForTest(t)

	response := performStatisticsRequest(handler, userID, "/statistics/categories?month=bad-month")

	if response.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400; body=%s", response.Code, response.Body.String())
	}
	if !strings.Contains(response.Body.String(), "invalid month") {
		t.Fatalf("body = %s, want invalid month", response.Body.String())
	}
	if strings.Contains(strings.ToLower(response.Body.String()), "parsing time") {
		t.Fatalf("response exposed parse error: %s", response.Body.String())
	}
}

func TestStatisticsAssetTrendRejectsUnboundedMonthRange(t *testing.T) {
	handler, _, userID := newStatisticsHandlerForTest(t)

	response := performStatisticsRequest(handler, userID, "/statistics/asset-trend?months=121")

	if response.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400; body=%s", response.Code, response.Body.String())
	}
	if !strings.Contains(response.Body.String(), "between 1 and 120") {
		t.Fatalf("body = %s, want bounded range guidance", response.Body.String())
	}
}

func newStatisticsHandlerForTest(t *testing.T) (*StatisticsHandler, *repository.Repositories, uint) {
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
	return NewStatisticsHandler(service.NewStatisticsService(repos.Transaction, repos.Category, repos.Account, repos.AccountLog)), repos, user.ID
}

func performStatisticsRequest(handler *StatisticsHandler, userID uint, target string) *httptest.ResponseRecorder {
	router := gin.New()
	router.GET("/statistics/overview", func(c *gin.Context) {
		c.Set("userID", userID)
		handler.Overview(c)
	})
	router.GET("/statistics/categories", func(c *gin.Context) {
		c.Set("userID", userID)
		handler.Categories(c)
	})
	router.GET("/statistics/asset-trend", func(c *gin.Context) {
		c.Set("userID", userID)
		handler.AssetTrend(c)
	})
	request := httptest.NewRequest(http.MethodGet, target, nil)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	return response
}
