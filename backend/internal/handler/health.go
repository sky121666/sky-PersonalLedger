package handler

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/service"
	"github.com/sky/personal-ledger/pkg/response"
)

type HealthHandler struct {
	service *service.HealthService
}

func NewHealthHandler(s *service.HealthService) *HealthHandler {
	return &HealthHandler{service: s}
}

func (h *HealthHandler) Check(c *gin.Context) {
	status := h.service.Check()
	if status.Status != "ok" {
		c.JSON(http.StatusServiceUnavailable, response.Response{
			Code:    50301,
			Message: "health check failed",
			Data:    status,
		})
		return
	}
	response.Success(c, status)
}
