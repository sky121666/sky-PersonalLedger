package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func performCORSRequest(allowedOrigins string, origin string) *httptest.ResponseRecorder {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.Use(CORS(allowedOrigins))
	r.GET("/ping", func(c *gin.Context) { c.String(http.StatusOK, "pong") })

	req := httptest.NewRequest(http.MethodGet, "/ping", nil)
	if origin != "" {
		req.Header.Set("Origin", origin)
	}
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

func TestCORSEmptyConfigAllowsOriginlessRequestOnly(t *testing.T) {
	if status := performCORSRequest("", "").Code; status != http.StatusOK {
		t.Fatalf("originless status = %d, want 200", status)
	}
	if status := performCORSRequest("", "http://localhost:5173").Code; status != http.StatusForbidden {
		t.Fatalf("browser origin status = %d, want 403", status)
	}
}

func TestCORSWildcardAllowsAnyOrigin(t *testing.T) {
	w := performCORSRequest("*", "http://localhost:5173")
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", w.Code)
	}
	if got := w.Header().Get("Access-Control-Allow-Origin"); got != "*" {
		t.Fatalf("allow origin = %q, want *", got)
	}
}

func TestCORSExactOriginList(t *testing.T) {
	allowed := "http://localhost:5173, https://ledger.example.com"
	w := performCORSRequest(allowed, "https://ledger.example.com")
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", w.Code)
	}
	if got := w.Header().Get("Access-Control-Allow-Origin"); got != "https://ledger.example.com" {
		t.Fatalf("allow origin = %q", got)
	}
	if status := performCORSRequest(allowed, "https://evil.example.com").Code; status != http.StatusForbidden {
		t.Fatalf("rejected origin status = %d, want 403", status)
	}
}
