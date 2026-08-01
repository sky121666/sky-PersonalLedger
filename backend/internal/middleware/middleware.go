package middleware

import (
	"errors"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/sky/personal-ledger/internal/authz"
	"github.com/sky/personal-ledger/pkg/jwt"
	"github.com/sky/personal-ledger/pkg/logger"
	"github.com/sky/personal-ledger/pkg/response"

	"github.com/gin-gonic/gin"
)

const principalContextKey = "authPrincipal"

// Note: sync was removed as rate limiter was removed

// CORS handles Cross-Origin Resource Sharing with configurable origins.
func CORS(allowedOrigins string) gin.HandlerFunc {
	origins := parseAllowedOrigins(allowedOrigins)
	allowAll := len(origins) == 1 && origins[0] == "*"

	return func(c *gin.Context) {
		origin := c.GetHeader("Origin")

		// Non-browser requests may not send Origin and should pass through.
		if origin == "" {
			setCORSCommonHeaders(c)
			c.Next()
			return
		}

		if allowAll {
			// Credentialed browser requests cannot use a wildcard origin.
			c.Header("Access-Control-Allow-Origin", origin)
			c.Header("Vary", "Origin")
			setCORSCommonHeaders(c)
			if c.Request.Method == http.MethodOptions {
				c.AbortWithStatus(http.StatusNoContent)
				return
			}
			c.Next()
			return
		}

		for _, allowed := range origins {
			if allowed == origin {
				c.Header("Access-Control-Allow-Origin", origin)
				c.Header("Vary", "Origin")
				setCORSCommonHeaders(c)
				if c.Request.Method == http.MethodOptions {
					c.AbortWithStatus(http.StatusNoContent)
					return
				}
				c.Next()
				return
			}
		}

		if len(origins) == 0 && isSameHostOrigin(c.Request, origin) {
			c.Header("Access-Control-Allow-Origin", origin)
			c.Header("Vary", "Origin")
			setCORSCommonHeaders(c)
			if c.Request.Method == http.MethodOptions {
				c.AbortWithStatus(http.StatusNoContent)
				return
			}
			c.Next()
			return
		}

		c.AbortWithStatus(http.StatusForbidden)
	}
}

func parseAllowedOrigins(value string) []string {
	parts := strings.Split(value, ",")
	origins := make([]string, 0, len(parts))
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part != "" {
			origins = append(origins, part)
		}
	}
	return origins
}

func setCORSCommonHeaders(c *gin.Context) {
	c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
	c.Header("Access-Control-Allow-Headers", "Origin, Content-Type, Accept, Authorization, X-CSRF-Token, X-Refresh-Token-Mode, X-Session-Bootstrap, X-Setup-Token")
	c.Header("Access-Control-Allow-Credentials", "true")
	c.Header("Access-Control-Expose-Headers", "Content-Disposition")
	c.Header("Access-Control-Max-Age", "86400")
}

func isSameHostOrigin(r *http.Request, origin string) bool {
	parsed, err := url.Parse(origin)
	if err != nil || parsed == nil || parsed.Host == "" {
		return false
	}
	return strings.EqualFold(parsed.Host, r.Host)
}

// SecurityHeaders adds security-related HTTP headers
func SecurityHeaders() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Header("X-Content-Type-Options", "nosniff")
		c.Header("X-Frame-Options", "DENY")
		c.Header("X-XSS-Protection", "1; mode=block")
		c.Header("Referrer-Policy", "strict-origin-when-cross-origin")
		c.Header("Permissions-Policy", "geolocation=(), microphone=(), camera=()")
		c.Next()
	}
}

func Logger() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		path := c.Request.URL.Path
		method := c.Request.Method

		c.Next()

		latency := time.Since(start)
		status := c.Writer.Status()

		logger.Infof("%s %s %d %v", method, path, status, latency)
	}
}

func Auth(jwtManager *jwt.Manager) gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			response.Unauthorized(c, "missing authorization header")
			c.Abort()
			return
		}

		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || parts[0] != "Bearer" {
			response.Unauthorized(c, "invalid authorization header format")
			c.Abort()
			return
		}

		claims, err := jwtManager.ValidateAccessToken(parts[1])
		if err != nil {
			if errors.Is(err, jwt.ErrExpiredToken) {
				response.Error(c, 401, 40102, "token expired")
			} else {
				response.Unauthorized(c, "invalid token")
			}
			c.Abort()
			return
		}

		c.Set("userID", claims.UserID)
		c.Set(principalContextKey, authz.Principal{UserID: claims.UserID, CredentialType: authz.CredentialJWT})
		c.Next()
	}
}

// AuthWithAPIToken 同时支持 JWT 和 API Token 的认证中间件
func AuthWithAPIToken(jwtManager *jwt.Manager, apiTokenValidator APITokenValidator) gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			response.Unauthorized(c, "missing authorization header")
			c.Abort()
			return
		}

		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || parts[0] != "Bearer" {
			response.Unauthorized(c, "invalid authorization header format")
			c.Abort()
			return
		}

		token := parts[1]

		// 先尝试 JWT 验证
		claims, err := jwtManager.ValidateAccessToken(token)
		if err == nil {
			c.Set("userID", claims.UserID)
			c.Set(principalContextKey, authz.Principal{UserID: claims.UserID, CredentialType: authz.CredentialJWT})
			c.Next()
			return
		}
		if errors.Is(err, jwt.ErrExpiredToken) {
			response.Error(c, http.StatusUnauthorized, 40102, "token expired")
			c.Abort()
			return
		}
		if errors.Is(err, jwt.ErrInvalidTokenType) {
			response.Unauthorized(c, "invalid token")
			c.Abort()
			return
		}

		// JWT 验证失败，尝试 API Token 验证
		principal, err := validateAPITokenPrincipal(apiTokenValidator, token)
		if err == nil {
			c.Set("userID", principal.UserID)
			c.Set(principalContextKey, principal)
			c.Next()
			return
		}

		// 两种验证都失败
		response.Unauthorized(c, "invalid token")
		c.Abort()
	}
}

func GetUserID(c *gin.Context) uint {
	userID, exists := c.Get("userID")
	if !exists {
		return 0
	}
	return userID.(uint)
}

// APITokenValidator API Token 验证器接口
type APITokenValidator interface {
	ValidateToken(token string) (uint, error)
}

type apiTokenPrincipalValidator interface {
	ValidatePrincipal(token string) (authz.Principal, error)
}

func validateAPITokenPrincipal(validator APITokenValidator, token string) (authz.Principal, error) {
	if extended, ok := validator.(apiTokenPrincipalValidator); ok {
		return extended.ValidatePrincipal(token)
	}
	userID, err := validator.ValidateToken(token)
	if err != nil {
		return authz.Principal{}, err
	}
	return authz.Principal{
		UserID: userID, CredentialType: authz.CredentialAPIToken,
		Scopes: append([]string(nil), authz.AllowedAPITokenScopes...),
	}, nil
}

func GetPrincipal(c *gin.Context) (authz.Principal, bool) {
	value, exists := c.Get(principalContextKey)
	if !exists {
		return authz.Principal{}, false
	}
	principal, ok := value.(authz.Principal)
	return principal, ok
}

// EnforceAPITokenScopes applies a deny-by-default route policy to API tokens.
// User JWTs retain the existing single-user application permissions.
func EnforceAPITokenScopes() gin.HandlerFunc {
	return func(c *gin.Context) {
		principal, exists := GetPrincipal(c)
		if !exists || principal.CredentialType == authz.CredentialJWT {
			c.Next()
			return
		}
		required, allowed := requiredAPITokenScope(c.Request.Method, c.Request.URL.Path)
		if !allowed || !principal.HasScope(required) {
			response.Forbidden(c, "api token is not permitted for this operation")
			c.Abort()
			return
		}
		c.Next()
	}
}

func requiredAPITokenScope(method string, path string) (string, bool) {
	apiPath := path
	if index := strings.Index(apiPath, "/api/v1/"); index >= 0 {
		apiPath = apiPath[index+len("/api/v1"):]
	}
	for _, prefix := range []string{"/statistics", "/export"} {
		if apiPath == prefix || strings.HasPrefix(apiPath, prefix+"/") {
			if method == http.MethodGet || method == http.MethodHead {
				return authz.ScopeReportRead, true
			}
			return "", false
		}
	}
	if apiPath == "/upload" || strings.HasPrefix(apiPath, "/upload/") {
		if method == http.MethodGet || method == http.MethodHead {
			return authz.ScopeUploadRead, true
		}
		return authz.ScopeUploadWrite, true
	}
	for _, prefix := range []string{
		"/accounts", "/categories", "/transactions", "/budgets", "/reminders",
		"/debt", "/templates", "/lendings", "/account-logs", "/tags", "/family",
	} {
		if apiPath == prefix || strings.HasPrefix(apiPath, prefix+"/") {
			if method == http.MethodGet || method == http.MethodHead {
				return authz.ScopeLedgerRead, true
			}
			return authz.ScopeLedgerWrite, true
		}
	}
	return "", false
}

// APITokenAuth API Token 认证中间件
func APITokenAuth(validator APITokenValidator) gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			response.Unauthorized(c, "missing authorization header")
			c.Abort()
			return
		}

		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || parts[0] != "Bearer" {
			response.Unauthorized(c, "invalid authorization header format")
			c.Abort()
			return
		}

		principal, err := validateAPITokenPrincipal(validator, parts[1])
		if err != nil {
			response.Unauthorized(c, "invalid token")
			c.Abort()
			return
		}

		c.Set("userID", principal.UserID)
		c.Set(principalContextKey, principal)
		c.Next()
	}
}
