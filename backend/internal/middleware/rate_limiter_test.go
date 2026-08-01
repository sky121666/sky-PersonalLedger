package middleware

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
)

func TestGlobalRateLimiterLimitsPrivateUploads(t *testing.T) {
	router := newGlobalRateLimiterTestRouter()

	first := performGlobalRateLimiterRequest(router, "/uploads/1/transactions/t/a.txt")
	if first.Code != http.StatusOK {
		t.Fatalf("first status = %d, want 200", first.Code)
	}

	second := performGlobalRateLimiterRequest(router, "/uploads/1/transactions/t/a.txt")
	if second.Code != http.StatusTooManyRequests {
		t.Fatalf("second status = %d, want 429", second.Code)
	}
}

func TestGlobalRateLimiterSkipsPublicAvatarUploads(t *testing.T) {
	router := newGlobalRateLimiterTestRouter()

	first := performGlobalRateLimiterRequest(router, "/uploads/1/avatars/profile/a.png")
	if first.Code != http.StatusOK {
		t.Fatalf("first status = %d, want 200", first.Code)
	}

	second := performGlobalRateLimiterRequest(router, "/uploads/1/avatars/profile/a.png")
	if second.Code != http.StatusOK {
		t.Fatalf("second status = %d, want 200", second.Code)
	}
}

func TestIsPublicUploadPathRequiresAvatarScope(t *testing.T) {
	cases := []struct {
		name string
		path string
		want bool
	}{
		{name: "avatar", path: "/uploads/1/avatars/profile/a.png", want: true},
		{name: "private transaction", path: "/uploads/1/transactions/t/a.txt", want: false},
		{name: "missing user", path: "/uploads/avatars/profile/a.png", want: false},
		{name: "invalid user", path: "/uploads/abc/avatars/profile/a.png", want: false},
		{name: "extra segment", path: "/uploads/1/avatars/profile/nested/a.png", want: false},
		{name: "unsupported avatar", path: "/uploads/1/avatars/profile/a.gif", want: false},
		{name: "non upload", path: "/assets/app.js", want: false},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := isPublicUploadPath(tc.path); got != tc.want {
				t.Fatalf("isPublicUploadPath(%q) = %v, want %v", tc.path, got, tc.want)
			}
		})
	}
}

func TestLoginRateLimiterChecksDoNotAllocateEmptyEntries(t *testing.T) {
	limiter := newLoginRateLimiterForTest(10)
	for index := 0; index < 1000; index++ {
		if allowed, _ := limiter.CheckIP(fmt.Sprintf("198.51.100.%d", index)); !allowed {
			t.Fatalf("new IP %d was unexpectedly denied", index)
		}
	}
	if len(limiter.ipAttempts) != 0 {
		t.Fatalf("empty check entries = %d, want 0", len(limiter.ipAttempts))
	}
}

func TestLoginRateLimiterPrunesExpiredAttemptsAndEmptyKeys(t *testing.T) {
	limiter := newLoginRateLimiterForTest(10)
	now := time.Now()
	limiter.ipAttempts["198.51.100.10"] = &LoginAttempt{
		attempts: []time.Time{now.Add(-2 * time.Hour)},
		lastSeen: now.Add(-2 * time.Hour),
	}
	limiter.accountAttempts["admin"] = &LoginAttempt{
		attempts:    []time.Time{now.Add(-2 * time.Hour)},
		lockedUntil: now.Add(time.Hour),
		lastSeen:    now.Add(-2 * time.Hour),
	}

	limiter.cleanupMapAt(limiter.ipAttempts, now)
	limiter.cleanupMapAt(limiter.accountAttempts, now)
	if len(limiter.ipAttempts) != 0 {
		t.Fatalf("expired IP entries = %d, want 0", len(limiter.ipAttempts))
	}
	if len(limiter.accountAttempts) != 1 || len(limiter.accountAttempts["admin"].attempts) != 0 {
		t.Fatalf("locked account should remain without expired attempts: %#v", limiter.accountAttempts)
	}
	limiter.cleanupMapAt(limiter.accountAttempts, now.Add(2*time.Hour))
	if len(limiter.accountAttempts) != 0 {
		t.Fatalf("expired locked account entries = %d, want 0", len(limiter.accountAttempts))
	}
}

func TestLoginRateLimiterMapsStayBounded(t *testing.T) {
	limiter := newLoginRateLimiterForTest(3)
	for index := 0; index < 100; index++ {
		limiter.RecordAttempt(
			fmt.Sprintf("198.51.100.%d", index),
			fmt.Sprintf("account-%d", index),
		)
	}
	if len(limiter.ipAttempts) > 3 || len(limiter.accountAttempts) > 3 {
		t.Fatalf("limiter maps grew beyond cap: IP=%d account=%d", len(limiter.ipAttempts), len(limiter.accountAttempts))
	}
}

func TestGlobalRateLimiterMapStaysBounded(t *testing.T) {
	limiter := &GlobalRateLimiter{
		requests: make(map[string][]time.Time), maxRequests: 10, window: time.Minute, maxEntries: 3,
	}
	for index := 0; index < 100; index++ {
		if !limiter.Allow(fmt.Sprintf("198.51.100.%d", index)) {
			t.Fatalf("first request for IP %d was denied", index)
		}
	}
	if len(limiter.requests) > 3 {
		t.Fatalf("global limiter entries = %d, want at most 3", len(limiter.requests))
	}
}

func newLoginRateLimiterForTest(maxEntries int) *RateLimiter {
	return &RateLimiter{
		ipAttempts: make(map[string]*LoginAttempt), accountAttempts: make(map[string]*LoginAttempt),
		maxAttempts: 5, timeWindow: 5 * time.Minute, lockDuration: 30 * time.Minute, maxEntries: maxEntries,
	}
}

func newGlobalRateLimiterTestRouter() *gin.Engine {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(NewGlobalRateLimiter(1, time.Minute).Middleware())
	router.GET("/*path", func(c *gin.Context) {
		c.Status(http.StatusOK)
	})
	return router
}

func performGlobalRateLimiterRequest(router *gin.Engine, path string) *httptest.ResponseRecorder {
	request := httptest.NewRequest(http.MethodGet, path, nil)
	request.RemoteAddr = "198.51.100.10:1234"
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	return response
}
