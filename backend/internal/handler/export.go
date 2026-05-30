package handler

import (
	"fmt"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/service"
	"github.com/sky/personal-ledger/pkg/response"
)

type ExportHandler struct {
	service *service.ExportService
}

func NewExportHandler(service *service.ExportService) *ExportHandler {
	return &ExportHandler{service: service}
}

// ExportCSV exports transactions to CSV
func (h *ExportHandler) ExportCSV(c *gin.Context) {
	userID := c.GetUint("userID")

	filter := service.ExportFilter{
		StartDate: c.Query("start_date"),
		EndDate:   c.Query("end_date"),
		Type:      c.Query("type"),
		AccountID: c.Query("account_id"),
	}

	data, err := h.service.ExportTransactionsCSV(userID, filter)
	if err != nil {
		internalServerError(c, err, "failed to export transactions")
		return
	}

	filename := fmt.Sprintf("transactions_%s.csv", time.Now().Format("20060102"))
	c.Header("Content-Type", "text/csv; charset=utf-8")
	setAttachmentHeader(c, filename)
	c.Data(http.StatusOK, "text/csv; charset=utf-8", data)
}

// GetYearlyReport returns annual statistics
func (h *ExportHandler) GetYearlyReport(c *gin.Context) {
	userID := c.GetUint("userID")

	yearStr := c.Query("year")
	year := time.Now().Year()
	if yearStr != "" {
		if y, err := strconv.Atoi(yearStr); err == nil {
			year = y
		}
	}

	report, err := h.service.GetYearlyReport(userID, year)
	if err != nil {
		internalServerError(c, err, "failed to load yearly report")
		return
	}

	response.Success(c, report)
}

// GetAvailableYears returns years that have transactions
func (h *ExportHandler) GetAvailableYears(c *gin.Context) {
	userID := c.GetUint("userID")

	years, err := h.service.GetAvailableYears(userID)
	if err != nil {
		internalServerError(c, err, "failed to load available years")
		return
	}

	response.Success(c, gin.H{"years": years})
}
