package middleware

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	ledgerjwt "github.com/sky/personal-ledger/pkg/jwt"
)

func performCORSRequest(allowedOrigins string, origin string) *httptest.ResponseRecorder {
	return performCORSRequestWithHost(allowedOrigins, origin, "example.com")
}

func performCORSRequestWithHost(allowedOrigins string, origin string, host string) *httptest.ResponseRecorder {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.Use(CORS(allowedOrigins))
	r.GET("/ping", func(c *gin.Context) { c.String(http.StatusOK, "pong") })
	r.OPTIONS("/ping", func(c *gin.Context) { c.String(http.StatusOK, "pong") })

	req := httptest.NewRequest(http.MethodGet, "/ping", nil)
	req.Host = host
	if origin != "" {
		req.Header.Set("Origin", origin)
	}
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

func TestCORSEmptyConfigAllowsOriginlessAndRejectsDifferentHost(t *testing.T) {
	if status := performCORSRequest("", "").Code; status != http.StatusOK {
		t.Fatalf("originless status = %d, want 200", status)
	}
	if status := performCORSRequest("", "http://localhost:5173").Code; status != http.StatusForbidden {
		t.Fatalf("browser origin status = %d, want 403", status)
	}
}

func TestCORSEmptyConfigAllowsSameHostOrigin(t *testing.T) {
	w := performCORSRequestWithHost("", "https://ledger.example.com", "ledger.example.com")
	if w.Code != http.StatusOK {
		t.Fatalf("same-host origin status = %d, want 200", w.Code)
	}
	if got := w.Header().Get("Access-Control-Allow-Origin"); got != "https://ledger.example.com" {
		t.Fatalf("allow origin = %q, want same origin", got)
	}
}

func TestCORSEmptyConfigRejectsDifferentHostOrigin(t *testing.T) {
	if status := performCORSRequestWithHost("", "https://evil.example.com", "ledger.example.com").Code; status != http.StatusForbidden {
		t.Fatalf("different-host origin status = %d, want 403", status)
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

func TestAuthWithAPITokenReturnsExpiredCodeForExpiredJWT(t *testing.T) {
	gin.SetMode(gin.TestMode)
	manager := ledgerjwt.NewManager("test-secret-with-enough-length", -1, 30)
	token, err := manager.GenerateAccessToken(1)
	if err != nil {
		t.Fatalf("generate token: %v", err)
	}

	r := gin.New()
	r.Use(AuthWithAPIToken(manager, fakeAPITokenValidator{}))
	r.GET("/protected", func(c *gin.Context) { c.String(http.StatusOK, "ok") })

	req := httptest.NewRequest(http.MethodGet, "/protected", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", w.Code)
	}
	if body := w.Body.String(); !strings.Contains(body, `"code":40102`) {
		t.Fatalf("body = %s, want code 40102", body)
	}
}

type fakeAPITokenValidator struct{}

func (fakeAPITokenValidator) ValidateToken(string) (uint, error) {
	return 0, ledgerjwt.ErrInvalidToken
}
