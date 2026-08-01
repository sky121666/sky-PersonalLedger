package middleware

import (
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/pkg/logger"
)

// AuditLog logs sensitive operations and security events
func AuditLog() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		path := c.Request.URL.Path
		method := c.Request.Method
		ip := c.ClientIP()

		// Process request
		c.Next()

		// Log after request is processed
		latency := time.Since(start)
		status := c.Writer.Status()

		// Log all requests in debug mode
		logger.Infof("[%s] %s %s - %d (%v) - IP: %s",
			method, path, c.Request.Proto, status, latency, ip)

		// Log security-sensitive operations
		if shouldAudit(path, method, status) {
			userIDStr := "anonymous"
			if value, exists := c.Get("userID"); exists {
				if userID, ok := value.(uint); ok {
					userIDStr = strconv.FormatUint(uint64(userID), 10)
				}
			}

			logger.Warnf("[AUDIT] User:%s IP:%s %s %s - Status:%d",
				userIDStr, ip, method, path, status)
		}

		// Log failed authentication attempts
		if status == 401 || status == 403 {
			logger.Warnf("[SECURITY] Failed auth - IP:%s %s %s - Status:%d",
				ip, method, path, status)
		}

		// Log rate limit hits
		if status == 429 {
			logger.Warnf("[SECURITY] Rate limit hit - IP:%s %s %s",
				ip, method, path)
		}
	}
}

func shouldAudit(path, method string, status int) bool {
	// Audit login/logout
	if path == "/api/v1/auth/login" || path == "/api/v1/auth/logout" {
		return true
	}

	// Audit password changes
	if path == "/api/v1/auth/change-password" {
		return true
	}

	// Audit data deletion
	if method == "DELETE" && status >= 200 && status < 300 {
		return true
	}

	// Audit backup/restore operations
	if path == "/api/v1/backup" || path == "/api/v1/restore" {
		return true
	}

	return false
}
