package handler

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/gin-gonic/gin/binding"
	"github.com/sky/personal-ledger/internal/middleware"
	"github.com/sky/personal-ledger/internal/service"
	"github.com/sky/personal-ledger/pkg/response"
)

type DebtHandler struct{ service *service.DebtService }

func NewDebtHandler(s *service.DebtService) *DebtHandler { return &DebtHandler{service: s} }

func (h *DebtHandler) RegisterRoutes(group *gin.RouterGroup) {
	group.GET("/capabilities", func(c *gin.Context) {
		response.Success(c, gin.H{"contract_version": 1, "multiple_plans": true, "explicit_allocation": true,
			"reversal": true, "backup_version": "2.5", "managed_accounts": "new_accounts_only",
			"external_cash_interest": false, "operation_history": true})
	})
	group.GET("/plans", func(c *gin.Context) {
		rows, err := h.service.ListPlans(middleware.GetUserID(c), c.Query("account_id"))
		if err != nil {
			debtResponseError(c, err)
			return
		}
		response.Success(c, rows)
	})
	group.GET("/plans/:id", func(c *gin.Context) {
		row, err := h.service.GetPlan(middleware.GetUserID(c), c.Param("id"))
		if err != nil {
			debtResponseError(c, err)
			return
		}
		response.Success(c, row)
	})
	group.POST("/plans", func(c *gin.Context) {
		var req service.CreateDebtPlanRequest
		if !bindDebtRequest(c, &req) {
			return
		}
		row, err := h.service.CreatePlan(middleware.GetUserID(c), req)
		if err != nil {
			debtResponseError(c, err)
			return
		}
		response.Created(c, row)
	})
	group.POST("/plans/:id/interest", func(c *gin.Context) {
		var req service.DebtInterestRequest
		if !bindDebtRequest(c, &req) {
			return
		}
		row, err := h.service.BookInterest(middleware.GetUserID(c), c.Param("id"), req)
		if err != nil {
			debtResponseError(c, err)
			return
		}
		response.Success(c, row)
	})
	group.POST("/payments", func(c *gin.Context) {
		var req service.DebtPaymentRequest
		if !bindDebtRequest(c, &req) {
			return
		}
		row, err := h.service.Pay(middleware.GetUserID(c), req)
		if err != nil {
			debtResponseError(c, err)
			return
		}
		response.Success(c, row)
	})
	group.GET("/operations", func(c *gin.Context) {
		var filter service.DebtOperationFilter
		if err := c.ShouldBindQuery(&filter); err != nil {
			response.BadRequest(c, "分期历史筛选条件无效")
			return
		}
		rows, err := h.service.ListOperationsFiltered(middleware.GetUserID(c), filter)
		if err != nil {
			debtResponseError(c, err)
			return
		}
		response.Success(c, rows)
	})
	group.GET("/operations/:id", func(c *gin.Context) {
		row, err := h.service.OperationDetails(middleware.GetUserID(c), c.Param("id"))
		if err != nil {
			debtResponseError(c, err)
			return
		}
		response.Success(c, row)
	})
	group.POST("/operations/:id/allocations", func(c *gin.Context) {
		var req service.DebtAllocateRequest
		if !bindDebtRequest(c, &req) {
			return
		}
		row, err := h.service.Allocate(middleware.GetUserID(c), c.Param("id"), req)
		if err != nil {
			debtResponseError(c, err)
			return
		}
		response.Success(c, row)
	})
	group.POST("/operations/:id/reverse", func(c *gin.Context) {
		var req service.DebtReverseRequest
		if !bindDebtRequest(c, &req) {
			return
		}
		row, err := h.service.Reverse(middleware.GetUserID(c), c.Param("id"), req)
		if err != nil {
			debtResponseError(c, err)
			return
		}
		response.Success(c, row)
	})
}

func bindDebtRequest(c *gin.Context, target any) bool {
	decoder := json.NewDecoder(c.Request.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		response.BadRequest(c, "invalid debt request")
		return false
	}
	if err := decoder.Decode(new(any)); !errors.Is(err, io.EOF) {
		response.BadRequest(c, "invalid debt request")
		return false
	}
	if err := binding.Validator.ValidateStruct(target); err != nil {
		response.BadRequest(c, "invalid debt request")
		return false
	}
	return true
}

func debtResponseError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, service.ErrDebtNotFound):
		response.NotFound(c, err.Error())
	case errors.Is(err, service.ErrManagedDebt):
		response.Error(c, http.StatusConflict, 40910, err.Error())
	case errors.Is(err, service.ErrDebtReconciliation):
		response.Error(c, http.StatusConflict, 40911, err.Error())
	case errors.Is(err, service.ErrDebtDependency):
		response.Error(c, http.StatusConflict, 40912, err.Error())
	case errors.Is(err, service.ErrConcurrentBalanceUpdate):
		response.Error(c, http.StatusConflict, 40904, err.Error())
	case errors.Is(err, service.ErrIdempotencyConflict):
		response.Error(c, http.StatusConflict, 40903, err.Error())
	case errors.Is(err, service.ErrInvalidDebtRequest), errors.Is(err, service.ErrInvalidIdempotencyKey),
		errors.Is(err, service.ErrSameAccount), errors.Is(err, service.ErrAccountNotFound):
		response.BadRequest(c, err.Error())
	default:
		internalServerError(c, err, "debt operation failed")
	}
}
