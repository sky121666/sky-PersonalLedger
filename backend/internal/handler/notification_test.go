package handler

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/repository"
	"github.com/sky/personal-ledger/internal/service"
)

func TestNotificationTestEndpointsAcceptEmptyEndpointPayload(t *testing.T) {
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init database: %v", err)
	}
	repos := repository.NewRepositories(db)
	handler := NewNotificationHandler(service.NewNotificationService(
		repos.Notification,
		repos.User,
		"handler-notification-encryption-key-at-least-32-chars",
	))
	tests := []struct {
		name   string
		path   string
		handle gin.HandlerFunc
	}{
		{name: "wecom", path: "/test-wecom", handle: handler.TestWecom},
		{name: "dingtalk", path: "/test-dingtalk", handle: handler.TestDingtalk},
		{name: "custom webhook", path: "/test-webhook", handle: handler.TestWebhook},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			router := gin.New()
			router.POST(tt.path, func(c *gin.Context) {
				c.Set("userID", uint(77))
				tt.handle(c)
			})
			request := httptest.NewRequest(http.MethodPost, tt.path, bytes.NewBufferString(`{}`))
			request.Header.Set("Content-Type", "application/json")
			response := httptest.NewRecorder()
			router.ServeHTTP(response, request)
			if response.Code != http.StatusOK {
				t.Fatalf("status = %d, want 200; body=%s", response.Code, response.Body.String())
			}
			body := strings.ToLower(response.Body.String())
			for _, forbidden := range []string{"wecom_webhook", "dingtalk_webhook", "webhook_url", "secret"} {
				if strings.Contains(body, forbidden) {
					t.Fatalf("test response exposed credential field %q: %s", forbidden, response.Body.String())
				}
			}
		})
	}
}
