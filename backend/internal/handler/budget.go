package handler

import (
	"errors"

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
		if errors.Is(err, service.ErrInvalidBudgetMonth) {
			response.BadRequest(c, "invalid budget month")
			return
		}
		internalServerError(c, err, "failed to list budgets")
		return
	}

	response.Success(c, result)
}

func (h *BudgetHandler) GetSummary(c *gin.Context) {
	userID := middleware.GetUserID(c)

	summary, err := h.service.GetSummary(userID)
	if err != nil {
		internalServerError(c, err, "failed to summarize budgets")
		return
	}

	response.Success(c, summary)
}

func (h *BudgetHandler) SetTotal(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req service.SetBudgetRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	budget, err := h.service.SetTotalBudget(userID, req)
	if err != nil {
		internalServerError(c, err, "failed to update total budget")
		return
	}

	response.Success(c, budget)
}

func (h *BudgetHandler) SetCategory(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req service.SetBudgetRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	budget, err := h.service.SetCategoryBudget(userID, req)
	if err != nil {
		if errors.Is(err, service.ErrCategoryNotFound) || errors.Is(err, service.ErrFamilyMemberNotFound) {
			response.NotFound(c, "budget scope not found")
			return
		}
		internalServerError(c, err, "failed to update category budget")
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
