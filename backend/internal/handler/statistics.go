package handler

import (
	"errors"
	"strconv"
	"time"

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
	period := c.Query("period")

	result, err := h.service.GetOverviewByPeriod(userID, month, period)
	if err != nil {
		if handleStatisticsRequestError(c, err) {
			return
		}
		internalServerError(c, err, "failed to load statistics overview")
		return
	}

	response.Success(c, result)
}

func (h *StatisticsHandler) Categories(c *gin.Context) {
	userID := middleware.GetUserID(c)
	month := c.Query("month")
	period := c.Query("period")
	txType := c.Query("type")

	result, err := h.service.GetCategoryStatsByPeriod(userID, month, period, txType)
	if err != nil {
		if handleStatisticsRequestError(c, err) {
			return
		}
		internalServerError(c, err, "failed to load category statistics")
		return
	}

	response.Success(c, result)
}

func (h *StatisticsHandler) Trend(c *gin.Context) {
	userID := middleware.GetUserID(c)
	month := c.Query("month")
	period := c.Query("period")

	result, err := h.service.GetTrendByPeriod(userID, month, period)
	if err != nil {
		if handleStatisticsRequestError(c, err) {
			return
		}
		internalServerError(c, err, "failed to load trend statistics")
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
		internalServerError(c, err, "failed to load asset trend statistics")
		return
	}

	response.Success(c, result)
}

func handleStatisticsRequestError(c *gin.Context, err error) bool {
	var parseErr *time.ParseError
	if errors.As(err, &parseErr) {
		response.BadRequest(c, "invalid month")
		return true
	}
	return false
}
