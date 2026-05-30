package middleware

import (
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
