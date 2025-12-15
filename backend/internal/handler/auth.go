package handler

import (
	"time"

	"github.com/sky/personal-ledger/internal/middleware"
	"github.com/sky/personal-ledger/internal/service"
	"github.com/sky/personal-ledger/pkg/response"

	"github.com/gin-gonic/gin"
)

type AuthHandler struct {
	service      *service.AuthService
	notification *service.NotificationService
	rateLimiter  *middleware.RateLimiter
}

func NewAuthHandler(s *service.AuthService, n *service.NotificationService, rl *middleware.RateLimiter) *AuthHandler {
	return &AuthHandler{service: s, notification: n, rateLimiter: rl}
}

func (h *AuthHandler) Status(c *gin.Context) {
	initialized, err := h.service.IsInitialized()
	if err != nil {
		response.InternalError(c, "failed to check status")
		return
	}
	response.Success(c, gin.H{"initialized": initialized})
}

type InitRequest struct {
	Password string `json:"password" binding:"required,min=8"`
}

func (h *AuthHandler) Init(c *gin.Context) {
	var req InitRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request: "+err.Error())
		return
	}

	result, err := h.service.Init(req.Password)
	if err != nil {
		if err == service.ErrUserExists {
			response.BadRequest(c, "already initialized")
			return
		}
		response.InternalError(c, err.Error())
		return
	}

	response.Created(c, result)
}

type LoginRequest struct {
	Password string `json:"password" binding:"required"`
}

func (h *AuthHandler) Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	// Check account rate limit
	allowed, lockedUntil := h.rateLimiter.CheckAccount("admin")
	if !allowed {
		remainingSeconds := int(time.Until(lockedUntil).Seconds())
		c.JSON(429, gin.H{
			"code":         42902,
			"message":      "Account temporarily locked due to too many failed attempts.",
			"locked_until": lockedUntil.Format(time.RFC3339),
			"retry_after":  remainingSeconds,
		})
		return
	}

	result, err := h.service.Login(req.Password)
	if err != nil {
		if err == service.ErrUserLocked {
			response.Error(c, 403, 40301, "account locked, try again later")
			return
		}
		// Record failed attempt
		h.rateLimiter.RecordAttempt(c.ClientIP(), "admin")
		response.Unauthorized(c, "invalid password")
		return
	}

	// Reset account attempts on successful login
	h.rateLimiter.ResetAccount("admin")
	response.Success(c, result)
}

type RefreshRequest struct {
	RefreshToken string `json:"refresh_token" binding:"required"`
}

func (h *AuthHandler) Refresh(c *gin.Context) {
	var req RefreshRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	result, err := h.service.RefreshToken(req.RefreshToken)
	if err != nil {
		response.Unauthorized(c, "invalid refresh token")
		return
	}

	response.Success(c, result)
}

func (h *AuthHandler) Logout(c *gin.Context) {
	userID := middleware.GetUserID(c)
	if err := h.service.Logout(userID); err != nil {
		response.InternalError(c, err.Error())
		return
	}
	response.Success(c, nil)
}

type ChangePasswordRequest struct {
	OldPassword string `json:"old_password" binding:"required"`
	NewPassword string `json:"new_password" binding:"required,min=8"`
}

func (h *AuthHandler) ChangePassword(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req ChangePasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	if err := h.service.ChangePassword(userID, req.OldPassword, req.NewPassword); err != nil {
		if err == service.ErrInvalidPassword {
			response.BadRequest(c, "wrong old password")
			return
		}
		response.InternalError(c, err.Error())
		return
	}

	response.Success(c, gin.H{"message": "password changed, please login again"})
}

func (h *AuthHandler) GetProfile(c *gin.Context) {
	userID := middleware.GetUserID(c)
	profile, err := h.service.GetProfile(userID)
	if err != nil {
		response.InternalError(c, err.Error())
		return
	}
	response.Success(c, profile)
}

type UpdateProfileRequest struct {
	Nickname string `json:"nickname"`
	Email    string `json:"email"`
	Avatar   string `json:"avatar"`
	Bio      string `json:"bio"`
}

func (h *AuthHandler) UpdateProfile(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req UpdateProfileRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	profile, err := h.service.UpdateProfile(userID, req.Nickname, req.Email, req.Avatar, req.Bio)
	if err != nil {
		response.InternalError(c, err.Error())
		return
	}
	response.Success(c, profile)
}
