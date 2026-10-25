package middleware

import (
	"encoding/json"
	"net/http/httptest"
	"strconv"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
)

func TestRateLimitResponsesIncludeMatchingRetryAfter(t *testing.T) {
	for _, kind := range []string{"login", "global"} {
		t.Run(kind, func(t *testing.T) {
			router := gin.New()
			if kind == "login" {
				limiter := NewRateLimiter()
				for i := 0; i < 5; i++ {
					limiter.RecordAttempt("192.0.2.1", "admin")
				}
				router.Use(limiter.Middleware())
			} else {
				router.Use(NewGlobalRateLimiter(1, 2*time.Minute).Middleware())
			}
			router.POST("/api/v1/auth/login", func(c *gin.Context) { c.Status(200) })
			var response *httptest.ResponseRecorder
			for i := 0; i < 2; i++ {
				response = httptest.NewRecorder()
				req := httptest.NewRequest("POST", "/api/v1/auth/login", nil)
				req.RemoteAddr = "192.0.2.1:12345"
				router.ServeHTTP(response, req)
			}
			if response.Code != 429 {
				t.Fatalf("status = %d", response.Code)
			}
			var payload struct {
				RetryAfter int `json:"retry_after"`
			}
			if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
				t.Fatal(err)
			}
			if payload.RetryAfter < 1 || response.Header().Get("Retry-After") != strconv.Itoa(payload.RetryAfter) {
				t.Fatalf("Retry-After header %q does not match positive body delay %d", response.Header().Get("Retry-After"), payload.RetryAfter)
			}
		})
	}
}
