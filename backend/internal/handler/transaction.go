package handler

import (
	"encoding/csv"
	"fmt"
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
		response.InternalError(c, err.Error())
		return
	}

	response.Success(c, result)
}

func (h *TransactionHandler) Create(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req service.CreateTransactionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, err.Error())
		return
	}

	tx, err := h.service.Create(userID, req)
	if err != nil {
		if err == service.ErrSameAccount {
			response.BadRequest(c, "source and target account must be different")
			return
		}
		response.InternalError(c, err.Error())
		return
	}

	response.Created(c, tx)
}

func (h *TransactionHandler) GetByID(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	tx, err := h.service.GetByID(id, userID)
	if err != nil {
		response.NotFound(c, "transaction not found")
		return
	}

	response.Success(c, tx)
}

func (h *TransactionHandler) Update(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	var req service.CreateTransactionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, err.Error())
		return
	}

	tx, err := h.service.Update(id, userID, req)
	if err != nil {
		response.NotFound(c, "transaction not found")
		return
	}

	response.Success(c, tx)
}

func (h *TransactionHandler) Delete(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	if err := h.service.Delete(id, userID); err != nil {
		response.NotFound(c, "transaction not found")
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
		response.BadRequest(c, err.Error())
		return
	}

	if err := h.service.DeleteBatch(req.IDs, userID); err != nil {
		response.InternalError(c, err.Error())
		return
	}

	response.Success(c, nil)
}

func (h *TransactionHandler) Export(c *gin.Context) {
	userID := middleware.GetUserID(c)
	format := c.DefaultQuery("format", "csv")
	startDate := c.Query("start_date")
	endDate := c.Query("end_date")

	var start, end *time.Time
	if startDate != "" {
		t, _ := time.Parse("2006-01-02", startDate)
		start = &t
	}
	if endDate != "" {
		t, _ := time.Parse("2006-01-02", endDate)
		end = &t
	}

	transactions, err := h.service.Export(userID, start, end)
	if err != nil {
		response.InternalError(c, err.Error())
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

func (h *TransactionHandler) Backup(c *gin.Context) {
	userID := middleware.GetUserID(c)

	backup, err := h.service.Backup(userID)
	if err != nil {
		response.InternalError(c, err.Error())
		return
	}

	filename := fmt.Sprintf("backup_%s.json", time.Now().Format("20060102_150405"))
	c.Header("Content-Type", "application/json; charset=utf-8")
	setAttachmentHeader(c, filename)
	c.JSON(200, backup)
}

func (h *TransactionHandler) Import(c *gin.Context) {
	userID := middleware.GetUserID(c)

	file, err := c.FormFile("file")
	if err != nil {
		response.BadRequest(c, "file is required")
		return
	}

	count, err := h.service.Import(userID, file)
	if err != nil {
		response.InternalError(c, err.Error())
		return
	}

	response.Success(c, gin.H{"count": count})
}
