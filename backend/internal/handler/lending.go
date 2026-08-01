package handler

import (
	"errors"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/middleware"
	"github.com/sky/personal-ledger/internal/service"
	"github.com/sky/personal-ledger/pkg/response"
)

type LendingHandler struct {
	service *service.LendingService
}

func NewLendingHandler(service *service.LendingService) *LendingHandler {
	return &LendingHandler{service: service}
}

func (h *LendingHandler) Create(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req service.CreateLendingRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	lending, err := h.service.Create(userID, req)
	if err != nil {
		if handleLendingRequestError(c, err) {
			return
		}
		internalServerError(c, err, "failed to create lending")
		return
	}

	response.Created(c, lending)
}

func (h *LendingHandler) List(c *gin.Context) {
	userID := middleware.GetUserID(c)
	includeSettled := c.Query("include_settled") == "true"

	lendings, err := h.service.List(userID, includeSettled)
	if err != nil {
		internalServerError(c, err, "failed to list lendings")
		return
	}

	response.Success(c, lendings)
}

func (h *LendingHandler) GetByID(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	lending, err := h.service.GetByID(id, userID)
	if err != nil {
		if errors.Is(err, service.ErrLendingNotFound) {
			response.NotFound(c, "lending not found")
			return
		}
		internalServerError(c, err, "failed to load lending")
		return
	}

	response.Success(c, lending)
}

func (h *LendingHandler) Update(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	var req service.PatchLendingRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	lending, err := h.service.Patch(id, userID, req)
	if err != nil {
		if handleLendingRequestError(c, err) {
			return
		}
		if errors.Is(err, service.ErrLendingNotFound) {
			response.NotFound(c, "lending not found")
			return
		}
		internalServerError(c, err, "failed to update lending")
		return
	}

	response.Success(c, lending)
}

func (h *LendingHandler) Delete(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	if err := h.service.Delete(id, userID); err != nil {
		if errors.Is(err, service.ErrLendingNotFound) {
			response.NotFound(c, "lending not found")
			return
		}
		internalServerError(c, err, "failed to delete lending")
		return
	}

	response.Success(c, nil)
}

func (h *LendingHandler) RecordRepayment(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	var req service.RecordRepaymentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	lending, err := h.service.RecordRepayment(id, userID, req)
	if err != nil {
		if errors.Is(err, service.ErrLendingNotFound) {
			response.NotFound(c, "lending not found")
			return
		}
		if handleLendingRequestError(c, err) {
			return
		}
		internalServerError(c, err, "failed to record lending repayment")
		return
	}

	response.Success(c, lending)
}

func (h *LendingHandler) GetRecords(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	records, err := h.service.GetRecords(id, userID)
	if err != nil {
		if errors.Is(err, service.ErrLendingNotFound) {
			response.NotFound(c, "lending not found")
			return
		}
		internalServerError(c, err, "failed to list lending records")
		return
	}

	response.Success(c, records)
}

func (h *LendingHandler) GetSummary(c *gin.Context) {
	userID := middleware.GetUserID(c)

	summary, err := h.service.GetSummary(userID)
	if err != nil {
		internalServerError(c, err, "failed to summarize lendings")
		return
	}

	response.Success(c, summary)
}

func handleLendingRequestError(c *gin.Context, err error) bool {
	switch {
	case errors.Is(err, service.ErrAccountNotFound):
		response.BadRequest(c, "account not found")
	case errors.Is(err, service.ErrInvalidDateTime):
		response.BadRequest(c, "invalid date time format")
	case errors.Is(err, service.ErrAlreadySettled):
		response.BadRequest(c, "lending already settled")
	case errors.Is(err, service.ErrInvalidAmount):
		response.BadRequest(c, "invalid amount")
	case errors.Is(err, service.ErrLendingOverpayment):
		response.Error(c, 422, 42201, "repayment exceeds remaining balance")
	case errors.Is(err, service.ErrInvalidLendingPatch):
		response.Error(c, 422, 42204, "invalid lending update")
	default:
		return false
	}
	return true
}
