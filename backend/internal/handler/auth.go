package handler

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/sky/personal-ledger/internal/middleware"
	"github.com/sky/personal-ledger/internal/service"
	"github.com/sky/personal-ledger/pkg/response"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type AuthHandler struct {
	service             *service.AuthService
	apiToken            *service.APITokenService
	notification        *service.NotificationService
	rateLimiter         *middleware.RateLimiter
	browserCookieSecure bool
}

const (
	browserTokenModeHeader = "X-Refresh-Token-Mode"
	browserTokenModeCookie = "cookie"
	refreshTokenCookieName = "ledger_refresh_token"
	csrfTokenCookieName    = "ledger_csrf_token"
	csrfTokenHeader        = "X-CSRF-Token"
	refreshCookiePath      = "/api/v1/auth"
)

func NewAuthHandler(s *service.AuthService, apiToken *service.APITokenService, n *service.NotificationService, rl *middleware.RateLimiter, browserCookieSecure ...bool) *AuthHandler {
	secure := false
	if len(browserCookieSecure) > 0 {
		secure = browserCookieSecure[0]
	}
	return &AuthHandler{
		service:             s,
		apiToken:            apiToken,
		notification:        n,
		rateLimiter:         rl,
		browserCookieSecure: secure,
	}
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
		response.BadRequest(c, "invalid request")
		return
	}

	result, err := h.service.Init(req.Password)
	if err != nil {
		if err == service.ErrUserExists {
			response.BadRequest(c, "already initialized")
			return
		}
		if errors.Is(err, service.ErrPasswordTooShort) {
			response.BadRequest(c, err.Error())
			return
		}
		internalServerError(c, err, "failed to initialize authentication")
		return
	}

	if !h.prepareAuthResponse(c, result) {
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
		if errors.Is(err, service.ErrUserLocked) {
			response.Error(c, 403, 40301, "account locked, try again later")
			return
		}
		if errors.Is(err, service.ErrInvalidPassword) {
			// Record only verified credential failures. Persistence failures must
			// not be hidden as ordinary password attempts.
			h.rateLimiter.RecordAttempt(c.ClientIP(), "admin")
			response.Unauthorized(c, "invalid password")
			return
		}
		internalServerError(c, err, "failed to authenticate")
		return
	}

	// Reset account attempts on successful login
	h.rateLimiter.ResetAccount("admin")
	if !h.prepareAuthResponse(c, result) {
		return
	}
	response.Success(c, result)
}

type RefreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

func (h *AuthHandler) Refresh(c *gin.Context) {
	refreshToken := ""
	if h.usesBrowserCookie(c) {
		if !sameOriginBrowserRequest(c.Request) || !validCSRFToken(c) {
			response.Forbidden(c, "invalid csrf token")
			return
		}
		var err error
		refreshToken, err = c.Cookie(refreshTokenCookieName)
		if err != nil || strings.TrimSpace(refreshToken) == "" {
			h.clearBrowserSessionCookies(c)
			response.Unauthorized(c, "invalid refresh token")
			return
		}
	} else {
		var req RefreshRequest
		if err := c.ShouldBindJSON(&req); err != nil || strings.TrimSpace(req.RefreshToken) == "" {
			response.BadRequest(c, "invalid request")
			return
		}
		refreshToken = req.RefreshToken
	}

	result, err := h.service.RefreshToken(refreshToken)
	if err != nil {
		if h.usesBrowserCookie(c) {
			h.clearBrowserSessionCookies(c)
		}
		response.Unauthorized(c, "invalid refresh token")
		return
	}

	if !h.prepareAuthResponse(c, result) {
		return
	}
	response.Success(c, result)
}

func (h *AuthHandler) Logout(c *gin.Context) {
	userID := middleware.GetUserID(c)
	h.clearBrowserSessionCookies(c)
	if err := h.service.Logout(userID); err != nil {
		internalServerError(c, err, "failed to logout")
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
		if errors.Is(err, service.ErrPasswordTooShort) {
			response.BadRequest(c, err.Error())
			return
		}
		internalServerError(c, err, "failed to change password")
		return
	}

	h.clearBrowserSessionCookies(c)
	response.Success(c, gin.H{"message": "password changed, please login again"})
}

func (h *AuthHandler) usesBrowserCookie(c *gin.Context) bool {
	return strings.EqualFold(strings.TrimSpace(c.GetHeader(browserTokenModeHeader)), browserTokenModeCookie)
}

func (h *AuthHandler) prepareAuthResponse(c *gin.Context, result *service.AuthResponse) bool {
	c.Header("Cache-Control", "no-store")
	c.Header("Pragma", "no-cache")
	if !h.usesBrowserCookie(c) {
		return true
	}

	csrfBytes := make([]byte, 32)
	if _, err := rand.Read(csrfBytes); err != nil {
		internalServerError(c, err, "failed to establish browser session")
		return false
	}
	csrfToken := base64.RawURLEncoding.EncodeToString(csrfBytes)
	maxAge := h.service.GetJWTManager().GetRefreshExpireSeconds()
	expires := time.Now().Add(time.Duration(maxAge) * time.Second)
	h.setSessionCookie(c, &http.Cookie{
		Name:     refreshTokenCookieName,
		Value:    result.RefreshToken,
		Path:     refreshCookiePath,
		MaxAge:   maxAge,
		Expires:  expires,
		HttpOnly: true,
		Secure:   h.browserCookieSecure,
		SameSite: http.SameSiteStrictMode,
	})
	h.setSessionCookie(c, &http.Cookie{
		Name:     csrfTokenCookieName,
		Value:    csrfToken,
		Path:     "/",
		MaxAge:   maxAge,
		Expires:  expires,
		HttpOnly: false,
		Secure:   h.browserCookieSecure,
		SameSite: http.SameSiteStrictMode,
	})
	result.RefreshToken = ""
	return true
}

func (h *AuthHandler) clearBrowserSessionCookies(c *gin.Context) {
	expires := time.Unix(1, 0).UTC()
	for _, cookie := range []*http.Cookie{
		{
			Name:     refreshTokenCookieName,
			Path:     refreshCookiePath,
			HttpOnly: true,
		},
		{
			Name: csrfTokenCookieName,
			Path: "/",
		},
	} {
		cookie.Value = ""
		cookie.MaxAge = -1
		cookie.Expires = expires
		cookie.Secure = h.browserCookieSecure
		cookie.SameSite = http.SameSiteStrictMode
		h.setSessionCookie(c, cookie)
	}
}

func (h *AuthHandler) setSessionCookie(c *gin.Context, cookie *http.Cookie) {
	http.SetCookie(c.Writer, cookie)
}

func validCSRFToken(c *gin.Context) bool {
	cookieToken, err := c.Cookie(csrfTokenCookieName)
	if err != nil {
		return false
	}
	headerToken := strings.TrimSpace(c.GetHeader(csrfTokenHeader))
	if headerToken == "" || len(headerToken) != len(cookieToken) {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(headerToken), []byte(cookieToken)) == 1
}

func sameOriginBrowserRequest(request *http.Request) bool {
	origin := strings.TrimSpace(request.Header.Get("Origin"))
	if origin == "" {
		return false
	}
	parsed, err := url.Parse(origin)
	if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") {
		return false
	}
	return strings.EqualFold(parsed.Host, request.Host)
}

func (h *AuthHandler) GetProfile(c *gin.Context) {
	userID := middleware.GetUserID(c)
	profile, err := h.service.GetProfile(userID)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			response.NotFound(c, "profile not found")
			return
		}
		internalServerError(c, err, "failed to load profile")
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
		if errors.Is(err, gorm.ErrRecordNotFound) {
			response.NotFound(c, "profile not found")
			return
		}
		internalServerError(c, err, "failed to update profile")
		return
	}
	response.Success(c, profile)
}

// VerifyAPIToken 验证 API Token（供 App 端使用）
func (h *AuthHandler) VerifyAPIToken(c *gin.Context) {
	authHeader := c.GetHeader("Authorization")
	if authHeader == "" {
		response.Unauthorized(c, "missing authorization header")
		return
	}

	// 解析 Bearer token
	parts := strings.SplitN(authHeader, " ", 2)
	if len(parts) != 2 || parts[0] != "Bearer" {
		response.Unauthorized(c, "invalid authorization header format")
		return
	}

	userID, err := h.apiToken.ValidateToken(parts[1])
	if err != nil {
		response.Unauthorized(c, "invalid token")
		return
	}

	// 获取用户信息
	profile, err := h.service.GetProfile(userID)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			response.NotFound(c, "profile not found")
			return
		}
		internalServerError(c, err, "failed to load profile")
		return
	}

	response.Success(c, gin.H{
		"valid":   true,
		"user_id": userID,
		"profile": profile,
	})
}
