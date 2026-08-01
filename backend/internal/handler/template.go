package handler

import (
	"errors"

	"github.com/sky/personal-ledger/internal/middleware"
	"github.com/sky/personal-ledger/internal/service"
	"github.com/sky/personal-ledger/pkg/response"

	"github.com/gin-gonic/gin"
)

type TemplateHandler struct {
	service *service.TemplateService
}

func NewTemplateHandler(s *service.TemplateService) *TemplateHandler {
	return &TemplateHandler{service: s}
}

func (h *TemplateHandler) List(c *gin.Context) {
	userID := middleware.GetUserID(c)

	templates, err := h.service.List(userID)
	if err != nil {
		internalServerError(c, err, "failed to list templates")
		return
	}

	response.Success(c, gin.H{"list": templates})
}

func (h *TemplateHandler) Create(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req service.CreateTemplateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	template, err := h.service.Create(userID, req)
	if err != nil {
		if handleTemplateRequestError(c, err) {
			return
		}
		internalServerError(c, err, "failed to create template")
		return
	}

	response.Created(c, template)
}

func (h *TemplateHandler) Delete(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	if err := h.service.Delete(id, userID); err != nil {
		if handleTemplateRequestError(c, err) {
			return
		}
		internalServerError(c, err, "failed to delete template")
		return
	}

	response.Success(c, nil)
}

func (h *TemplateHandler) Apply(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	var req service.ApplyTemplateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	tx, err := h.service.Apply(id, userID, req)
	if err != nil {
		if handleTemplateRequestError(c, err) {
			return
		}
		internalServerError(c, err, "failed to apply template")
		return
	}

	response.Created(c, tx)
}

func handleTemplateRequestError(c *gin.Context, err error) bool {
	switch {
	case errors.Is(err, service.ErrTemplateNotFound):
		response.NotFound(c, "template not found")
	case errors.Is(err, service.ErrInvalidTemplateType):
		response.BadRequest(c, "invalid transaction type")
	case errors.Is(err, service.ErrInvalidTemplateAmount):
		response.BadRequest(c, "template amount must not be negative")
	default:
		return handleTransactionRequestError(c, err)
	}
	return true
}
