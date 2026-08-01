package middleware

import (
	"crypto/subtle"
	"net"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/pkg/response"
)

const setupTokenHeader = "X-Setup-Token"

type initializationChecker interface {
	IsInitialized() (bool, error)
}

// RequireSetupAccess prevents an uninitialized server from being claimed over
// the network. A configured setup token is always required. Without one, only
// a direct loopback connection is allowed; proxy headers are intentionally not
// consulted when deciding whether the caller is local.
func RequireSetupAccess(checker initializationChecker, configuredToken string) gin.HandlerFunc {
	expectedToken := strings.TrimSpace(configuredToken)

	return func(c *gin.Context) {
		initialized, err := checker.IsInitialized()
		if err != nil {
			response.InternalError(c, "failed to check setup status")
			c.Abort()
			return
		}
		if initialized {
			c.Next()
			return
		}

		if expectedToken == "" {
			if isDirectLoopbackRequest(c.Request.RemoteAddr) {
				c.Next()
				return
			}
			response.Error(c, http.StatusForbidden, 40310, "remote setup is disabled; configure LEDGER_SETUP_TOKEN")
			c.Abort()
			return
		}

		providedToken := strings.TrimSpace(c.GetHeader(setupTokenHeader))
		if providedToken == "" || subtle.ConstantTimeCompare([]byte(providedToken), []byte(expectedToken)) != 1 {
			response.Error(c, http.StatusUnauthorized, 40110, "valid setup token required")
			c.Abort()
			return
		}

		c.Next()
	}
}

func isDirectLoopbackRequest(remoteAddr string) bool {
	host, _, err := net.SplitHostPort(strings.TrimSpace(remoteAddr))
	if err != nil {
		host = strings.Trim(strings.TrimSpace(remoteAddr), "[]")
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}
