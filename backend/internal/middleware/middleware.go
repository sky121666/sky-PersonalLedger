package middleware

import (
	"net/http"
	"strings"
	"time"

	"github.com/sky/personal-ledger/pkg/jwt"
	"github.com/sky/personal-ledger/pkg/logger"
	"github.com/sky/personal-ledger/pkg/response"

	"github.com/gin-gonic/gin"
)

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
			c.Header("Access-Control-Allow-Origin", "*")
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
				setCORSCommonHeaders(c)
				if c.Request.Method == http.MethodOptions {
					c.AbortWithStatus(http.StatusNoContent)
					return
				}
				c.Next()
				return
			}
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
	c.Header("Access-Control-Allow-Headers", "Origin, Content-Type, Accept, Authorization")
	c.Header("Access-Control-Allow-Credentials", "true")
	c.Header("Access-Control-Max-Age", "86400")
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

		claims, err := jwtManager.ValidateToken(parts[1])
		if err != nil {
			if err == jwt.ErrExpiredToken {
				response.Error(c, 401, 40102, "token expired")
			} else {
				response.Unauthorized(c, "invalid token")
			}
			c.Abort()
			return
		}

		c.Set("userID", claims.UserID)
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
		claims, err := jwtManager.ValidateToken(token)
		if err == nil {
			c.Set("userID", claims.UserID)
			c.Next()
			return
		}

		// JWT 验证失败，尝试 API Token 验证
		userID, err := apiTokenValidator.ValidateToken(token)
		if err == nil {
			c.Set("userID", userID)
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

		userID, err := validator.ValidateToken(parts[1])
		if err != nil {
			response.Unauthorized(c, err.Error())
			c.Abort()
			return
		}

		c.Set("userID", userID)
		c.Next()
	}
}
