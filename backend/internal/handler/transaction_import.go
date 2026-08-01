package handler

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/middleware"
	"github.com/sky/personal-ledger/internal/service"
	"github.com/sky/personal-ledger/pkg/response"
)

type TransactionImportHandler struct {
	service *service.TransactionImportService
}

func NewTransactionImportHandler(service *service.TransactionImportService) *TransactionImportHandler {
	return &TransactionImportHandler{service: service}
}

func (h *TransactionImportHandler) Preview(c *gin.Context) {
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, service.MaxTransactionImportFileBytes()+(1<<20))
	fileHeader, err := c.FormFile("file")
	if err != nil {
		if isMultipartBodyTooLarge(err) {
			response.Error(c, http.StatusRequestEntityTooLarge, 41301, "transaction import file is too large")
			return
		}
		response.BadRequest(c, "file is required")
		return
	}
	if fileHeader.Size > service.MaxTransactionImportFileBytes() {
		response.Error(c, http.StatusRequestEntityTooLarge, 41301, "transaction import file is too large")
		return
	}
	file, err := fileHeader.Open()
	if err != nil {
		internalServerError(c, err, "failed to read transaction import file")
		return
	}
	defer file.Close()

	preview, err := h.service.Preview(middleware.GetUserID(c), fileHeader.Filename, file)
	if err != nil {
		h.respondError(c, nil, err)
		return
	}
	response.Success(c, preview)
}

func (h *TransactionImportHandler) Get(c *gin.Context) {
	preview, err := h.service.Get(middleware.GetUserID(c), c.Param("id"))
	if err != nil {
		h.respondError(c, nil, err)
		return
	}
	response.Success(c, preview)
}

func (h *TransactionImportHandler) Recent(c *gin.Context) {
	preview, err := h.service.Recent(middleware.GetUserID(c))
	if err != nil {
		h.respondError(c, nil, err)
		return
	}
	response.Success(c, preview)
}

func (h *TransactionImportHandler) List(c *gin.Context) {
	limit := 10
	if value := c.Query("limit"); value != "" {
		parsed, err := strconv.Atoi(value)
		if err != nil || parsed < 1 || parsed > 64 {
			response.BadRequest(c, "limit must be between 1 and 64")
			return
		}
		limit = parsed
	}
	previews, err := h.service.ListRecent(middleware.GetUserID(c), limit)
	if err != nil {
		h.respondError(c, nil, err)
		return
	}
	response.Success(c, gin.H{"list": previews})
}

func (h *TransactionImportHandler) Validate(c *gin.Context) {
	preview, err := h.service.Validate(middleware.GetUserID(c), c.Param("id"))
	if err != nil {
		h.respondError(c, preview, err)
		return
	}
	response.Success(c, preview)
}

func (h *TransactionImportHandler) Commit(c *gin.Context) {
	preview, err := h.service.Commit(middleware.GetUserID(c), c.Param("id"))
	if err != nil {
		h.respondError(c, preview, err)
		return
	}
	response.Success(c, preview)
}

func (h *TransactionImportHandler) Rollback(c *gin.Context) {
	preview, err := h.service.Rollback(middleware.GetUserID(c), c.Param("id"))
	if err != nil {
		h.respondError(c, preview, err)
		return
	}
	response.Success(c, preview)
}

func (h *TransactionImportHandler) respondError(c *gin.Context, preview *service.TransactionImportPreview, err error) {
	switch {
	case errors.Is(err, service.ErrTransactionImportTooLarge):
		response.Error(c, http.StatusRequestEntityTooLarge, 41301, "transaction import file is too large")
	case errors.Is(err, service.ErrTransactionImportFormat):
		response.Error(c, http.StatusUnprocessableEntity, 42210, "invalid transaction import format")
	case errors.Is(err, service.ErrTransactionImportRowsLimit):
		response.Error(c, http.StatusUnprocessableEntity, 42211, "transaction import exceeds 10000 rows")
	case errors.Is(err, service.ErrTransactionImportInvalidRows):
		c.JSON(http.StatusUnprocessableEntity, response.Response{
			Code: 42212, Message: "transaction import contains invalid rows", Data: preview,
		})
	case errors.Is(err, service.ErrTransactionImportExpired):
		response.Error(c, http.StatusGone, 41001, "transaction import session expired")
	case errors.Is(err, service.ErrTransactionImportNotFound):
		response.NotFound(c, "transaction import session not found")
	case errors.Is(err, service.ErrTransactionImportState):
		response.Error(c, http.StatusConflict, 40902, "transaction import state conflict")
	default:
		internalServerError(c, err, "transaction import operation failed")
	}
}
