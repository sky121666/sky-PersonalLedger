package handler

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/service"
	"github.com/sky/personal-ledger/pkg/response"
)

type AIHandler struct {
	providerService *service.AIProviderService
	reportService   *service.AIReportService
	reportScheduler *service.AIReportScheduler
}

func NewAIHandler(providerService *service.AIProviderService, reportService *service.AIReportService, reportScheduler *service.AIReportScheduler) *AIHandler {
	return &AIHandler{providerService: providerService, reportService: reportService, reportScheduler: reportScheduler}
}

func (h *AIHandler) ListProviders(c *gin.Context) {
	userID := c.GetUint("userID")
	providers, err := h.providerService.List(userID)
	if err != nil {
		response.InternalError(c, err.Error())
		return
	}
	response.Success(c, providers)
}

func (h *AIHandler) ListProviderPresets(c *gin.Context) {
	response.Success(c, h.providerService.ListPresets())
}

func (h *AIHandler) CreateProvider(c *gin.Context) {
	userID := c.GetUint("userID")
	var req service.SaveAIProviderRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, err.Error())
		return
	}
	provider, err := h.providerService.Create(userID, req)
	if err != nil {
		writeAIProviderError(c, err)
		return
	}
	response.Created(c, provider)
}

func (h *AIHandler) UpdateProvider(c *gin.Context) {
	userID := c.GetUint("userID")
	var req service.SaveAIProviderRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, err.Error())
		return
	}
	provider, err := h.providerService.Update(c.Param("id"), userID, req)
	if err != nil {
		writeAIProviderError(c, err)
		return
	}
	response.Success(c, provider)
}

func (h *AIHandler) DeleteProvider(c *gin.Context) {
	userID := c.GetUint("userID")
	if err := h.providerService.Delete(c.Param("id"), userID); err != nil {
		writeAIProviderError(c, err)
		return
	}
	response.Success(c, nil)
}

func (h *AIHandler) TestProvider(c *gin.Context) {
	userID := c.GetUint("userID")
	if err := h.providerService.TestConnection(c.Param("id"), userID); err != nil {
		writeAIProviderError(c, err)
		return
	}
	response.Success(c, gin.H{"ok": true})
}

func (h *AIHandler) ListReports(c *gin.Context) {
	userID := c.GetUint("userID")
	reports, err := h.reportService.List(userID)
	if err != nil {
		response.InternalError(c, err.Error())
		return
	}
	response.Success(c, reports)
}

func (h *AIHandler) GenerateReport(c *gin.Context) {
	userID := c.GetUint("userID")
	var req service.GenerateAIReportRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, err.Error())
		return
	}
	report, err := h.reportService.Generate(userID, req)
	if err != nil {
		writeAIReportError(c, err)
		return
	}
	response.Created(c, report)
}

func (h *AIHandler) GetReport(c *gin.Context) {
	userID := c.GetUint("userID")
	report, err := h.reportService.Get(c.Param("id"), userID)
	if err != nil {
		writeAIReportError(c, err)
		return
	}
	response.Success(c, report)
}

func (h *AIHandler) DeleteReport(c *gin.Context) {
	userID := c.GetUint("userID")
	if err := h.reportService.Delete(c.Param("id"), userID); err != nil {
		writeAIReportError(c, err)
		return
	}
	response.Success(c, nil)
}

func (h *AIHandler) GetReportScheduleSettings(c *gin.Context) {
	settings, err := h.reportScheduler.GetSettings()
	if err != nil {
		response.InternalError(c, err.Error())
		return
	}
	response.Success(c, settings)
}

type UpdateAIReportScheduleRequest struct {
	Enabled        bool `json:"enabled"`
	WeeklyEnabled  bool `json:"weekly_enabled"`
	MonthlyEnabled bool `json:"monthly_enabled"`
	Hour           int  `json:"hour"`
}

func (h *AIHandler) UpdateReportScheduleSettings(c *gin.Context) {
	var req UpdateAIReportScheduleRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, err.Error())
		return
	}

	current, err := h.reportScheduler.GetSettings()
	if err != nil {
		response.InternalError(c, err.Error())
		return
	}
	current.Enabled = req.Enabled
	current.WeeklyEnabled = req.WeeklyEnabled
	current.MonthlyEnabled = req.MonthlyEnabled
	current.Hour = req.Hour

	if err := h.reportScheduler.SaveSettings(current); err != nil {
		response.InternalError(c, err.Error())
		return
	}
	response.Success(c, current)
}

func (h *AIHandler) TriggerReportSchedule(c *gin.Context) {
	results, err := h.reportScheduler.TriggerDueReports()
	if err != nil {
		response.InternalError(c, err.Error())
		return
	}
	response.Success(c, gin.H{"results": results})
}

func writeAIProviderError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, service.ErrAIProviderNotFound):
		response.NotFound(c, err.Error())
	case errors.Is(err, service.ErrAIProviderNameRequired),
		errors.Is(err, service.ErrAIProviderBaseURLRequired),
		errors.Is(err, service.ErrAIProviderBaseURLInvalid),
		errors.Is(err, service.ErrAIProviderModelRequired),
		errors.Is(err, service.ErrAIProviderTypeUnsupported):
		response.BadRequest(c, err.Error())
	default:
		response.Error(c, http.StatusInternalServerError, 50001, err.Error())
	}
}

func writeAIReportError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, service.ErrAIReportNotFound),
		errors.Is(err, service.ErrAIReportProviderNotFound):
		response.NotFound(c, err.Error())
	case errors.Is(err, service.ErrAIReportTypeRequired),
		errors.Is(err, service.ErrAIReportPeriodInvalid):
		response.BadRequest(c, err.Error())
	default:
		response.Error(c, http.StatusInternalServerError, 50001, err.Error())
	}
}
