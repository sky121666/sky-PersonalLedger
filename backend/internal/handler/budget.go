package handler

import (
	"github.com/sky/personal-ledger/internal/middleware"
	"github.com/sky/personal-ledger/internal/service"
	"github.com/sky/personal-ledger/pkg/response"

	"github.com/gin-gonic/gin"
)

type BudgetHandler struct {
	service *service.BudgetService
}

func NewBudgetHandler(s *service.BudgetService) *BudgetHandler {
	return &BudgetHandler{service: s}
}

func (h *BudgetHandler) List(c *gin.Context) {
	userID := middleware.GetUserID(c)
	month := c.Query("month")

	result, err := h.service.List(userID, month)
	if err != nil {
		response.InternalError(c, err.Error())
		return
	}

	response.Success(c, result)
}

func (h *BudgetHandler) GetSummary(c *gin.Context) {
	userID := middleware.GetUserID(c)

	summary, err := h.service.GetSummary(userID)
	if err != nil {
		response.InternalError(c, err.Error())
		return
	}

	response.Success(c, summary)
}

func (h *BudgetHandler) SetTotal(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req service.SetBudgetRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, err.Error())
		return
	}

	budget, err := h.service.SetTotalBudget(userID, req)
	if err != nil {
		response.InternalError(c, err.Error())
		return
	}

	response.Success(c, budget)
}

func (h *BudgetHandler) SetCategory(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req service.SetBudgetRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, err.Error())
		return
	}

	budget, err := h.service.SetCategoryBudget(userID, req)
	if err != nil {
		response.InternalError(c, err.Error())
		return
	}

	response.Created(c, budget)
}

func (h *BudgetHandler) Delete(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	if err := h.service.Delete(id, userID); err != nil {
		response.NotFound(c, "budget not found")
		return
	}

	response.Success(c, nil)
}
