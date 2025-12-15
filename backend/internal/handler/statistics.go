package handler

import (
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/middleware"
	"github.com/sky/personal-ledger/internal/service"
	"github.com/sky/personal-ledger/pkg/response"
)

type StatisticsHandler struct {
	service *service.StatisticsService
}

func NewStatisticsHandler(s *service.StatisticsService) *StatisticsHandler {
	return &StatisticsHandler{service: s}
}

func (h *StatisticsHandler) Overview(c *gin.Context) {
	userID := middleware.GetUserID(c)
	month := c.Query("month")

	result, err := h.service.GetOverview(userID, month)
	if err != nil {
		response.InternalError(c, err.Error())
		return
	}

	response.Success(c, result)
}

func (h *StatisticsHandler) Categories(c *gin.Context) {
	userID := middleware.GetUserID(c)
	month := c.Query("month")
	txType := c.Query("type")

	result, err := h.service.GetCategoryStats(userID, month, txType)
	if err != nil {
		response.InternalError(c, err.Error())
		return
	}

	response.Success(c, result)
}

func (h *StatisticsHandler) Trend(c *gin.Context) {
	userID := middleware.GetUserID(c)
	month := c.Query("month")

	result, err := h.service.GetTrend(userID, month)
	if err != nil {
		response.InternalError(c, err.Error())
		return
	}

	response.Success(c, result)
}

func (h *StatisticsHandler) AssetTrend(c *gin.Context) {
	userID := middleware.GetUserID(c)
	months := 12
	if m := c.Query("months"); m != "" {
		if v, err := strconv.Atoi(m); err == nil && v > 0 {
			months = v
		}
	}

	result, err := h.service.GetAssetTrend(userID, months)
	if err != nil {
		response.InternalError(c, err.Error())
		return
	}

	response.Success(c, result)
}
