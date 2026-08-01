package handler

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"github.com/sky/personal-ledger/internal/service"
)

func TestExportCSVRejectsInvalidDateOnProductionPath(t *testing.T) {
	handler, _, userID := newExportHandlerForTest(t)

	for _, target := range []string{
		"/export/transactions/csv?start_date=bad-date",
		"/export/transactions/csv?end_date=2026-02-30",
	} {
		response := performExportCSVRequest(handler, userID, target)
		if response.Code != http.StatusBadRequest {
			t.Fatalf("%s status = %d, want 400; body=%s", target, response.Code, response.Body.String())
		}
		if !strings.Contains(response.Body.String(), "invalid export date") {
			t.Fatalf("%s body = %s, want invalid export date", target, response.Body.String())
		}
	}
}

func TestExportCSVIncludesEntireLocalEndDateOnProductionPath(t *testing.T) {
	previousLocal := time.Local
	local := time.FixedZone("UTC+08", 8*60*60)
	time.Local = local
	t.Cleanup(func() { time.Local = previousLocal })

	handler, repos, userID := newExportHandlerForTest(t)
	accountID := createTransactionHandlerAccount(t, repos, userID)
	transactions := []model.Transaction{
		{
			ID:              "csv-local-day-start",
			UserID:          userID,
			AccountID:       accountID,
			Type:            "expense",
			Amount:          10,
			Remark:          "csv-local-day-start",
			TransactionDate: time.Date(2026, time.May, 31, 0, 0, 0, 0, local),
		},
		{
			ID:              "csv-local-day-end",
			UserID:          userID,
			AccountID:       accountID,
			Type:            "expense",
			Amount:          20,
			Remark:          "csv-local-day-end",
			TransactionDate: time.Date(2026, time.May, 31, 23, 59, 59, 500_000_000, local),
		},
		{
			ID:              "csv-next-local-day",
			UserID:          userID,
			AccountID:       accountID,
			Type:            "expense",
			Amount:          30,
			Remark:          "csv-next-local-day",
			TransactionDate: time.Date(2026, time.June, 1, 0, 0, 0, 0, local),
		},
	}
	for index := range transactions {
		if err := repos.Transaction.Create(&transactions[index]); err != nil {
			t.Fatalf("create transaction %s: %v", transactions[index].ID, err)
		}
	}

	response := performExportCSVRequest(
		handler,
		userID,
		"/export/transactions/csv?start_date=2026-05-31&end_date=2026-05-31",
	)
	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", response.Code, response.Body.String())
	}
	body := response.Body.String()
	if !strings.Contains(body, "csv-local-day-start") || !strings.Contains(body, "csv-local-day-end") {
		t.Fatalf("CSV body should contain both transactions on local end date: %s", body)
	}
	if strings.Contains(body, "csv-next-local-day") {
		t.Fatalf("CSV body should exclude next local day: %s", body)
	}
}

func newExportHandlerForTest(t *testing.T) (*ExportHandler, *repository.Repositories, uint) {
	t.Helper()
	_, repos, userID := newTransactionHandlerForTest(t)
	return NewExportHandler(service.NewExportService(repos.Transaction, repos.Category, repos.Account)), repos, userID
}

func performExportCSVRequest(handler *ExportHandler, userID uint, target string) *httptest.ResponseRecorder {
	router := gin.New()
	router.GET("/export/transactions/csv", func(c *gin.Context) {
		c.Set("userID", userID)
		handler.ExportCSV(c)
	})
	request := httptest.NewRequest(http.MethodGet, target, nil)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	return response
}
