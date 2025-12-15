package handler

import (
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
		response.BadRequest(c, err.Error())
		return
	}

	lending, err := h.service.Create(userID, req)
	if err != nil {
		response.InternalError(c, err.Error())
		return
	}

	response.Created(c, lending)
}

func (h *LendingHandler) List(c *gin.Context) {
	userID := middleware.GetUserID(c)
	includeSettled := c.Query("include_settled") == "true"

	lendings, err := h.service.List(userID, includeSettled)
	if err != nil {
		response.InternalError(c, err.Error())
		return
	}

	response.Success(c, lendings)
}

func (h *LendingHandler) GetByID(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	lending, err := h.service.GetByID(id, userID)
	if err != nil {
		if err == service.ErrLendingNotFound {
			response.NotFound(c, "lending not found")
			return
		}
		response.InternalError(c, err.Error())
		return
	}

	response.Success(c, lending)
}

func (h *LendingHandler) Update(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	var req service.UpdateLendingRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, err.Error())
		return
	}

	lending, err := h.service.Update(id, userID, req)
	if err != nil {
		if err == service.ErrLendingNotFound {
			response.NotFound(c, "lending not found")
			return
		}
		response.InternalError(c, err.Error())
		return
	}

	response.Success(c, lending)
}

func (h *LendingHandler) Delete(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	if err := h.service.Delete(id, userID); err != nil {
		if err == service.ErrLendingNotFound {
			response.NotFound(c, "lending not found")
			return
		}
		response.InternalError(c, err.Error())
		return
	}

	response.Success(c, nil)
}

func (h *LendingHandler) RecordRepayment(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	var req service.RecordRepaymentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, err.Error())
		return
	}

	lending, err := h.service.RecordRepayment(id, userID, req)
	if err != nil {
		if err == service.ErrLendingNotFound {
			response.NotFound(c, "lending not found")
			return
		}
		if err == service.ErrAlreadySettled {
			response.BadRequest(c, "lending already settled")
			return
		}
		if err == service.ErrInvalidAmount {
			response.BadRequest(c, "invalid amount")
			return
		}
		response.InternalError(c, err.Error())
		return
	}

	response.Success(c, lending)
}

func (h *LendingHandler) GetRecords(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	records, err := h.service.GetRecords(id, userID)
	if err != nil {
		if err == service.ErrLendingNotFound {
			response.NotFound(c, "lending not found")
			return
		}
		response.InternalError(c, err.Error())
		return
	}

	response.Success(c, records)
}

func (h *LendingHandler) GetSummary(c *gin.Context) {
	userID := middleware.GetUserID(c)

	summary, err := h.service.GetSummary(userID)
	if err != nil {
		response.InternalError(c, err.Error())
		return
	}

	response.Success(c, summary)
}
