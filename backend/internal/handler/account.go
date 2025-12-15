package handler

import (
	"github.com/sky/personal-ledger/internal/middleware"
	"github.com/sky/personal-ledger/internal/service"
	"github.com/sky/personal-ledger/pkg/response"

	"github.com/gin-gonic/gin"
)

type AccountHandler struct {
	service *service.AccountService
}

func NewAccountHandler(s *service.AccountService) *AccountHandler {
	return &AccountHandler{service: s}
}

func (h *AccountHandler) List(c *gin.Context) {
	userID := middleware.GetUserID(c)
	includeArchived := c.Query("include_archived") == "true"

	accounts, err := h.service.List(userID, includeArchived)
	if err != nil {
		response.InternalError(c, err.Error())
		return
	}

	summary, _ := h.service.GetSummary(userID)

	response.Success(c, gin.H{
		"list":              accounts,
		"total_assets":      summary.TotalAssets,
		"total_liabilities": summary.TotalLiabilities,
		"net_assets":        summary.NetAssets,
	})
}

func (h *AccountHandler) Create(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req service.CreateAccountRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, err.Error())
		return
	}

	account, err := h.service.Create(userID, req)
	if err != nil {
		response.InternalError(c, err.Error())
		return
	}

	response.Created(c, account)
}

func (h *AccountHandler) GetByID(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	account, err := h.service.GetByID(id, userID)
	if err != nil {
		response.NotFound(c, "account not found")
		return
	}

	response.Success(c, account)
}

func (h *AccountHandler) Update(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	var req service.UpdateAccountRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, err.Error())
		return
	}

	account, err := h.service.Update(id, userID, req)
	if err != nil {
		if err == service.ErrAccountNotFound {
			response.NotFound(c, "account not found")
			return
		}
		response.InternalError(c, err.Error())
		return
	}

	response.Success(c, account)
}

func (h *AccountHandler) Delete(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	if err := h.service.Delete(id, userID); err != nil {
		if err == service.ErrAccountNotFound {
			response.NotFound(c, "account not found")
			return
		}
		if err == service.ErrAccountHasBalance {
			response.BadRequest(c, "cannot delete account with non-zero balance")
			return
		}
		response.InternalError(c, err.Error())
		return
	}

	response.Success(c, nil)
}

type ArchiveRequest struct {
	IsArchived bool `json:"is_archived"`
}

func (h *AccountHandler) Archive(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	var req ArchiveRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, err.Error())
		return
	}

	if err := h.service.Archive(id, userID, req.IsArchived); err != nil {
		response.NotFound(c, "account not found")
		return
	}

	response.Success(c, nil)
}

type SortRequest struct {
	IDs []string `json:"ids" binding:"required"`
}

func (h *AccountHandler) UpdateSortOrder(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req SortRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, err.Error())
		return
	}

	if err := h.service.UpdateSortOrder(userID, req.IDs); err != nil {
		response.InternalError(c, err.Error())
		return
	}

	response.Success(c, nil)
}
