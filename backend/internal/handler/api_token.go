package handler

import (
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/service"
	"github.com/sky/personal-ledger/pkg/response"
)

// APITokenHandler API令牌处理器
type APITokenHandler struct {
	service *service.APITokenService
}

func NewAPITokenHandler(service *service.APITokenService) *APITokenHandler {
	return &APITokenHandler{service: service}
}

// CreateTokenRequest 创建令牌请求
type CreateTokenRequest struct {
	Name          string `json:"name" binding:"required,max=100"`
	ExpiresInDays int    `json:"expires_in_days"` // 0 = 永不过期
}

// Create 生成新的API令牌
func (h *APITokenHandler) Create(c *gin.Context) {
	userID := c.GetUint("userID")
	if userID == 0 {
		response.Unauthorized(c, "unauthorized")
		return
	}

	var req CreateTokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, err.Error())
		return
	}

	token, err := h.service.GenerateToken(userID, req.Name, req.ExpiresInDays)
	if err != nil {
		internalServerError(c, err, "failed to generate token")
		return
	}

	response.Success(c, token)
}

// List 返回当前用户的所有令牌
func (h *APITokenHandler) List(c *gin.Context) {
	userID := c.GetUint("userID")
	if userID == 0 {
		response.Unauthorized(c, "unauthorized")
		return
	}

	tokens, err := h.service.ListTokens(userID)
	if err != nil {
		internalServerError(c, err, "failed to list tokens")
		return
	}

	response.Success(c, gin.H{"list": tokens})
}

// Delete 删除API令牌
func (h *APITokenHandler) Delete(c *gin.Context) {
	userID := c.GetUint("userID")
	if userID == 0 {
		response.Unauthorized(c, "unauthorized")
		return
	}

	idStr := c.Param("id")
	id, err := strconv.ParseUint(idStr, 10, 32)
	if err != nil {
		response.BadRequest(c, "invalid id")
		return
	}

	if err := h.service.DeleteToken(uint(id), userID); err != nil {
		internalServerError(c, err, "failed to delete token")
		return
	}

	response.Success(c, nil)
}
