package handler

import (
	"encoding/csv"
	"errors"
	"fmt"
	"net/http"
	"time"

	"github.com/sky/personal-ledger/internal/middleware"
	"github.com/sky/personal-ledger/internal/service"
	"github.com/sky/personal-ledger/pkg/response"

	"github.com/gin-gonic/gin"
)

type TransactionHandler struct {
	service *service.TransactionService
}

func NewTransactionHandler(s *service.TransactionService) *TransactionHandler {
	return &TransactionHandler{service: s}
}

func (h *TransactionHandler) List(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req service.ListTransactionRequest
	if err := c.ShouldBindQuery(&req); err != nil {
		response.BadRequest(c, err.Error())
		return
	}

	result, err := h.service.List(userID, req)
	if err != nil {
		if handleTransactionRequestError(c, err) {
			return
		}
		internalServerError(c, err, "failed to list transactions")
		return
	}

	response.Success(c, result)
}

func (h *TransactionHandler) Create(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req service.CreateTransactionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	tx, err := h.service.Create(userID, req)
	if err != nil {
		if handleTransactionRequestError(c, err) {
			return
		}
		internalServerError(c, err, "failed to create transaction")
		return
	}

	response.Created(c, tx)
}

func (h *TransactionHandler) GetByID(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	tx, err := h.service.GetByID(id, userID)
	if err != nil {
		if errors.Is(err, service.ErrTransactionNotFound) {
			response.NotFound(c, "transaction not found")
			return
		}
		internalServerError(c, err, "failed to load transaction")
		return
	}

	response.Success(c, tx)
}

func (h *TransactionHandler) Update(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	var req service.CreateTransactionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	tx, err := h.service.Update(id, userID, req)
	if err != nil {
		if handleTransactionRequestError(c, err) {
			return
		}
		if errors.Is(err, service.ErrTransactionNotFound) {
			response.NotFound(c, "transaction not found")
			return
		}
		internalServerError(c, err, "failed to update transaction")
		return
	}

	response.Success(c, tx)
}

func (h *TransactionHandler) UpdateAttachments(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	var req service.UpdateTransactionAttachmentsRequest
	if err := c.ShouldBindJSON(&req); err != nil || req.Images == nil {
		response.BadRequest(c, "invalid request")
		return
	}

	tx, err := h.service.UpdateAttachments(id, userID, req)
	if err != nil {
		if handleTransactionRequestError(c, err) {
			return
		}
		if errors.Is(err, service.ErrTransactionNotFound) {
			response.NotFound(c, "transaction not found")
			return
		}
		internalServerError(c, err, "failed to update transaction attachments")
		return
	}

	response.Success(c, tx)
}

func (h *TransactionHandler) Delete(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	if err := h.service.Delete(id, userID); err != nil {
		if errors.Is(err, service.ErrTransactionNotFound) {
			response.NotFound(c, "transaction not found")
			return
		}
		if errors.Is(err, service.ErrSystemTransactionImmutable) {
			response.BadRequest(c, "system transaction cannot be changed directly")
			return
		}
		internalServerError(c, err, "failed to delete transaction")
		return
	}

	response.Success(c, nil)
}

type BatchDeleteRequest struct {
	IDs []string `json:"ids" binding:"required"`
}

func (h *TransactionHandler) BatchDelete(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req BatchDeleteRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	if err := h.service.DeleteBatch(req.IDs, userID); err != nil {
		if errors.Is(err, service.ErrTransactionNotFound) {
			response.NotFound(c, "transaction not found")
			return
		}
		if errors.Is(err, service.ErrSystemTransactionImmutable) {
			response.BadRequest(c, "system transaction cannot be changed directly")
			return
		}
		internalServerError(c, err, "failed to delete transactions")
		return
	}

	response.Success(c, nil)
}

func (h *TransactionHandler) Export(c *gin.Context) {
	userID := middleware.GetUserID(c)
	format := c.DefaultQuery("format", "csv")
	startDate := c.Query("start_date")
	endDate := c.Query("end_date")

	start, err := parseTransactionExportDate(startDate)
	if err != nil {
		response.BadRequest(c, "invalid start date")
		return
	}
	end, err := parseTransactionExportDate(endDate)
	if err != nil {
		response.BadRequest(c, "invalid end date")
		return
	}
	if end != nil {
		endOfDay := end.AddDate(0, 0, 1).Add(-time.Nanosecond)
		end = &endOfDay
	}

	transactions, err := h.service.Export(userID, start, end)
	if err != nil {
		internalServerError(c, err, "failed to export transactions")
		return
	}

	if format == "json" {
		response.Success(c, transactions)
		return
	}

	// CSV export
	filename := fmt.Sprintf("transactions_%s.csv", time.Now().Format("20060102"))
	c.Header("Content-Type", "text/csv; charset=utf-8")
	setAttachmentHeader(c, filename)
	c.Writer.Write([]byte{0xEF, 0xBB, 0xBF}) // UTF-8 BOM for Excel

	writer := csv.NewWriter(c.Writer)
	defer writer.Flush()

	// Header
	writer.Write([]string{"日期", "类型", "分类", "账户", "金额", "备注"})

	// Data
	for _, tx := range transactions {
		txType := "支出"
		if tx.Type == "income" {
			txType = "收入"
		} else if tx.Type == "transfer" {
			txType = "转账"
		}

		categoryName := ""
		if tx.Category != nil {
			categoryName = tx.Category.Name
		}

		accountName := ""
		if tx.Account != nil {
			accountName = tx.Account.Name
		}

		writer.Write([]string{
			tx.TransactionDate.Format("2006-01-02"),
			txType,
			categoryName,
			accountName,
			fmt.Sprintf("%.2f", tx.Amount),
			tx.Remark,
		})
	}
}

func handleTransactionRequestError(c *gin.Context, err error) bool {
	switch {
	case errors.Is(err, service.ErrSameAccount):
		response.BadRequest(c, "source and target account must be different")
	case errors.Is(err, service.ErrAccountNotFound):
		response.BadRequest(c, "account not found")
	case errors.Is(err, service.ErrCategoryNotFound):
		response.BadRequest(c, "category not found")
	case errors.Is(err, service.ErrCategoryTypeMismatch):
		response.BadRequest(c, "category type does not match transaction type")
	case errors.Is(err, service.ErrInvalidTransactionAmount):
		response.BadRequest(c, "amount must be greater than zero")
	case errors.Is(err, service.ErrInvalidTransactionType):
		response.BadRequest(c, "invalid transaction type")
	case errors.Is(err, service.ErrFamilyMemberNotFound):
		response.BadRequest(c, "family member not found")
	case errors.Is(err, service.ErrManagedTransactionImmutable):
		response.BadRequest(c, "managed transaction cannot be updated directly")
	case errors.Is(err, service.ErrSystemTransactionImmutable):
		response.BadRequest(c, "system transaction cannot be changed directly")
	case errors.Is(err, service.ErrInvalidTransactionImages):
		response.BadRequest(c, "invalid transaction images")
	case errors.Is(err, service.ErrCreateTransactionImages):
		response.BadRequest(c, "create the transaction before adding attachments")
	case errors.Is(err, service.ErrTransactionAttachmentScope):
		response.Forbidden(c, "attachment path does not belong to transaction")
	case errors.Is(err, service.ErrAttachmentFileUnavailable):
		response.Error(c, http.StatusUnprocessableEntity, 42205, "attachment file is unavailable")
	case errors.Is(err, service.ErrAttachmentRecoveryPending):
		response.Error(c, http.StatusServiceUnavailable, 50302, "attachment recovery is pending")
	case isTransactionDateParseError(err):
		response.BadRequest(c, "invalid transaction date")
	default:
		return false
	}
	return true
}

func isTransactionDateParseError(err error) bool {
	var parseErr *time.ParseError
	return errors.As(err, &parseErr)
}

func parseTransactionExportDate(value string) (*time.Time, error) {
	if value == "" {
		return nil, nil
	}
	t, err := time.ParseInLocation("2006-01-02", value, time.Local)
	if err != nil {
		return nil, err
	}
	return &t, nil
}
