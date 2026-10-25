package handler

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/middleware"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/service"
	"github.com/sky/personal-ledger/pkg/response"
)

type ReminderHandler struct {
	service *service.ReminderService
}

func NewReminderHandler(s *service.ReminderService) *ReminderHandler {
	return &ReminderHandler{service: s}
}

func (h *ReminderHandler) List(c *gin.Context) {
	userID := middleware.GetUserID(c)

	// Check if filtering by account_id
	accountID := c.Query("account_id")
	var reminders []model.Reminder
	var err error

	if accountID != "" {
		reminders, err = h.service.ListByAccountID(userID, accountID)
	} else {
		reminders, err = h.service.List(userID)
	}

	if err != nil {
		internalServerError(c, err, "failed to list reminders")
		return
	}

	response.Success(c, reminders)
}

func (h *ReminderHandler) Create(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req service.CreateReminderRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	reminder, err := h.service.Create(userID, req)
	if err != nil {
		if errors.Is(err, service.ErrManagedDebt) {
			debtResponseError(c, err)
			return
		}
		if errors.Is(err, service.ErrAccountNotFound) {
			response.NotFound(c, "account not found")
			return
		}
		if errors.Is(err, service.ErrLinkedDebtBalanceImmutable) {
			response.Error(c, 409, 40902, "linked reminder balance is managed by its debt account")
			return
		}
		if errors.Is(err, service.ErrInvalidLocalDate) {
			response.Error(c, 422, 42203, "invalid reminder date")
			return
		}
		if errors.Is(err, service.ErrCreateAttachmentEvidence) || errors.Is(err, service.ErrInvalidAttachmentEvidence) {
			response.BadRequest(c, "create the reminder before adding attachments")
			return
		}
		internalServerError(c, err, "failed to create reminder")
		return
	}

	response.Created(c, reminder)
}

func (h *ReminderHandler) GetByID(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	reminder, err := h.service.GetByID(id, userID)
	if err != nil {
		response.NotFound(c, "reminder not found")
		return
	}

	response.Success(c, reminder)
}

func (h *ReminderHandler) Update(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	var req service.PatchReminderRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	reminder, err := h.service.Patch(id, userID, req)
	if err != nil {
		if errors.Is(err, service.ErrReminderPaymentHistory) {
			response.Error(c, http.StatusConflict, 40907, "该提醒仍有还款记录，不能改绑或解除账户；请先核对并撤销相关还款")
			return
		}
		if errors.Is(err, service.ErrAttachmentRecoveryPending) {
			response.Error(c, http.StatusServiceUnavailable, 50302, "attachment recovery is pending")
			return
		}
		if errors.Is(err, service.ErrAccountNotFound) {
			response.NotFound(c, "account not found")
			return
		}
		if errors.Is(err, service.ErrLinkedDebtBalanceImmutable) {
			response.Error(c, 409, 40902, "linked reminder balance is managed by its debt account")
			return
		}
		if errors.Is(err, service.ErrInvalidReminderPatch) || errors.Is(err, service.ErrInvalidLocalDate) || errors.Is(err, service.ErrInvalidAttachmentEvidence) || errors.Is(err, service.ErrAttachmentFileUnavailable) {
			response.Error(c, 422, 42203, "invalid reminder update")
			return
		}
		response.NotFound(c, "reminder not found")
		return
	}

	response.Success(c, reminder)
}

func (h *ReminderHandler) Delete(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	if err := h.service.Delete(id, userID); err != nil {
		response.NotFound(c, "reminder not found")
		return
	}

	response.Success(c, nil)
}

func (h *ReminderHandler) Toggle(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	reminder, err := h.service.Toggle(id, userID)
	if err != nil {
		response.NotFound(c, "reminder not found")
		return
	}

	response.Success(c, reminder)
}

func (h *ReminderHandler) RecordPayment(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	var req service.RecordPaymentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	reminder, err := h.service.RecordPayment(id, userID, req)
	if err != nil {
		if errors.Is(err, service.ErrManagedDebt) {
			debtResponseError(c, err)
			return
		}
		if errors.Is(err, service.ErrReminderBalanceConflict) {
			response.Error(c, http.StatusConflict, 40908, "提醒余额与账户负债不一致，请先核对；本次未扣款")
			return
		}
		if errors.Is(err, service.ErrIdempotencyConflict) {
			response.Error(c, http.StatusConflict, 40903, err.Error())
			return
		}
		if errors.Is(err, service.ErrReminderNotFound) {
			response.NotFound(c, "reminder not found")
			return
		}
		if errors.Is(err, service.ErrInvalidReminderPayment) || errors.Is(err, service.ErrInvalidIdempotencyKey) || errors.Is(err, service.ErrSameAccount) || errors.Is(err, service.ErrAccountNotFound) {
			response.BadRequest(c, err.Error())
			return
		}
		internalServerError(c, err, "failed to record reminder payment")
		return
	}

	response.Success(c, reminder)
}

func (h *ReminderHandler) GetDebtSummary(c *gin.Context) {
	userID := middleware.GetUserID(c)

	summary, err := h.service.GetDebtSummary(userID)
	if err != nil {
		internalServerError(c, err, "failed to summarize reminder debt")
		return
	}

	response.Success(c, summary)
}
