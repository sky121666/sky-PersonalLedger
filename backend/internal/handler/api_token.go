package handler

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/service"
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
		c.JSON(http.StatusUnauthorized, gin.H{"code": 40101, "message": "unauthorized"})
		return
	}

	var req CreateTokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"code": 40001, "message": err.Error()})
		return
	}

	token, err := h.service.GenerateToken(userID, req.Name, req.ExpiresInDays)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"code": 50001, "message": "failed to generate token"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"code":    0,
		"message": "ok",
		"data":    token,
	})
}

// List 返回当前用户的所有令牌
func (h *APITokenHandler) List(c *gin.Context) {
	userID := c.GetUint("userID")
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"code": 40101, "message": "unauthorized"})
		return
	}

	tokens, err := h.service.ListTokens(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"code": 50001, "message": "failed to list tokens"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"code":    0,
		"message": "ok",
		"data":    gin.H{"list": tokens},
	})
}

// Delete 删除API令牌
func (h *APITokenHandler) Delete(c *gin.Context) {
	userID := c.GetUint("userID")
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"code": 40101, "message": "unauthorized"})
		return
	}

	idStr := c.Param("id")
	id, err := strconv.ParseUint(idStr, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"code": 40001, "message": "invalid id"})
		return
	}

	if err := h.service.DeleteToken(uint(id), userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"code": 50001, "message": "failed to delete token"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"code":    0,
		"message": "ok",
	})
}
