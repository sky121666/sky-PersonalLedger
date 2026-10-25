package handler

import (
	"encoding/json"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestAccountLockIncludesMatchingRetryAfter(t *testing.T) {
	handler := newAuthHandlerForTest(t)
	for i := 0; i < 5; i++ {
		handler.rateLimiter.RecordAttempt("192.0.2.1", "admin")
	}
	router := gin.New()
	router.POST("/login", handler.Login)
	response := httptest.NewRecorder()
	req := httptest.NewRequest("POST", "/login", strings.NewReader(`{"password":"wrong-password"}`))
	req.Header.Set("Content-Type", "application/json")
	router.ServeHTTP(response, req)
	if response.Code != 429 {
		t.Fatalf("status = %d; body %s", response.Code, response.Body.String())
	}
	var payload struct {
		RetryAfter int `json:"retry_after"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	if payload.RetryAfter < 1 || response.Header().Get("Retry-After") != strconv.Itoa(payload.RetryAfter) {
		t.Fatalf("Retry-After header %q does not match body delay %d", response.Header().Get("Retry-After"), payload.RetryAfter)
	}
}
