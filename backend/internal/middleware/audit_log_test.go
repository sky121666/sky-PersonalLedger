package middleware

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/pkg/logger"
	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
	"go.uber.org/zap/zaptest/observer"
)

func TestAuditLogSerializesUserIDAsDecimal(t *testing.T) {
	message := performAuditLogRequest(t, uint(12345), true)
	if !strings.Contains(message, "User:12345 ") {
		t.Fatalf("audit message = %q, want decimal user ID", message)
	}
}

func TestAuditLogUsesAnonymousForMissingOrUnsupportedUserID(t *testing.T) {
	tests := []struct {
		name      string
		userID    any
		setUserID bool
	}{
		{name: "missing", setUserID: false},
		{name: "string", userID: "12345", setUserID: true},
		{name: "int", userID: 12345, setUserID: true},
		{name: "uint64", userID: uint64(12345), setUserID: true},
		{name: "nil", userID: nil, setUserID: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			message := performAuditLogRequest(t, tt.userID, tt.setUserID)
			if !strings.Contains(message, "User:anonymous ") {
				t.Fatalf("audit message = %q, want anonymous user", message)
			}
		})
	}
}

func TestAuditLogKeepsSingleDigitUserIDBehavior(t *testing.T) {
	message := performAuditLogRequest(t, uint(7), true)
	if !strings.Contains(message, "User:7 ") {
		t.Fatalf("audit message = %q, want user ID 7", message)
	}
}

func performAuditLogRequest(t *testing.T, userID any, setUserID bool) string {
	t.Helper()

	core, observed := observer.New(zapcore.DebugLevel)
	previousLogger := logger.Log
	logger.Log = zap.New(core).Sugar()
	t.Cleanup(func() {
		logger.Log = previousLogger
	})

	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(AuditLog())
	if setUserID {
		router.Use(func(c *gin.Context) {
			c.Set("userID", userID)
			c.Next()
		})
	}
	router.DELETE("/api/v1/items/:id", func(c *gin.Context) {
		c.Status(http.StatusNoContent)
	})

	request := httptest.NewRequest(http.MethodDelete, "/api/v1/items/1", nil)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	if response.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusNoContent)
	}

	entries := observed.FilterMessageSnippet("[AUDIT]").All()
	if len(entries) != 1 {
		t.Fatalf("audit entry count = %d, want 1", len(entries))
	}
	return entries[0].Message
}
