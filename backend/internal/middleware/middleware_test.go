package middleware

import (
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/authz"
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
	if got := w.Header().Get("Access-Control-Allow-Origin"); got != "http://localhost:5173" {
		t.Fatalf("allow origin = %q, want requesting origin for credentialed CORS", got)
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

func TestAuthWithAPITokenRejectsRefreshBearerWithoutAPITokenFallback(t *testing.T) {
	gin.SetMode(gin.TestMode)
	manager := ledgerjwt.NewManager("test-secret-with-enough-length", 15, 30)
	refreshToken, _, err := manager.GenerateRefreshToken(1)
	if err != nil {
		t.Fatalf("generate refresh token: %v", err)
	}
	validator := &acceptingAPITokenValidator{}

	r := gin.New()
	r.Use(AuthWithAPIToken(manager, validator))
	r.GET("/protected", func(c *gin.Context) { c.String(http.StatusOK, "ok") })

	req := httptest.NewRequest(http.MethodGet, "/protected", nil)
	req.Header.Set("Authorization", "Bearer "+refreshToken)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", w.Code)
	}
	if validator.calls != 0 {
		t.Fatalf("API token validator calls = %d, want 0 for refresh JWT", validator.calls)
	}
}

func TestAPITokenAuthDoesNotExposeValidatorError(t *testing.T) {
	gin.SetMode(gin.TestMode)

	r := gin.New()
	r.Use(APITokenAuth(erroringAPITokenValidator{}))
	r.GET("/protected", func(c *gin.Context) { c.String(http.StatusOK, "ok") })

	req := httptest.NewRequest(http.MethodGet, "/protected", nil)
	req.Header.Set("Authorization", "Bearer raw-token")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", w.Code)
	}
	body := w.Body.String()
	if !strings.Contains(body, "invalid token") {
		t.Fatalf("body = %s, want generic invalid token", body)
	}
	if strings.Contains(strings.ToLower(body), "database") || strings.Contains(strings.ToLower(body), "sql") {
		t.Fatalf("body exposed validator error: %s", body)
	}
}

func TestAPITokenScopePolicyAllowsOnlyExplicitCapabilities(t *testing.T) {
	tests := []struct {
		name       string
		method     string
		path       string
		scopes     []string
		wantStatus int
	}{
		{
			name:       "read ledger",
			method:     http.MethodGet,
			path:       "/api/v1/accounts",
			scopes:     []string{authz.ScopeLedgerRead},
			wantStatus: http.StatusOK,
		},
		{
			name:       "write ledger without write scope",
			method:     http.MethodPost,
			path:       "/api/v1/accounts",
			scopes:     []string{authz.ScopeLedgerRead},
			wantStatus: http.StatusForbidden,
		},
		{
			name:       "write ledger",
			method:     http.MethodPost,
			path:       "/api/v1/accounts",
			scopes:     []string{authz.ScopeLedgerWrite},
			wantStatus: http.StatusOK,
		},
		{
			name:       "read report",
			method:     http.MethodGet,
			path:       "/api/v1/statistics/overview",
			scopes:     []string{authz.ScopeReportRead},
			wantStatus: http.StatusOK,
		},
		{
			name:       "manage api tokens denied",
			method:     http.MethodGet,
			path:       "/api/v1/api-tokens",
			scopes:     append([]string(nil), authz.AllowedAPITokenScopes...),
			wantStatus: http.StatusForbidden,
		},
		{
			name:       "auth route denied",
			method:     http.MethodPost,
			path:       "/api/v1/auth/change-password",
			scopes:     append([]string(nil), authz.AllowedAPITokenScopes...),
			wantStatus: http.StatusForbidden,
		},
		{
			name:       "restore denied",
			method:     http.MethodPost,
			path:       "/api/v1/restore",
			scopes:     append([]string(nil), authz.AllowedAPITokenScopes...),
			wantStatus: http.StatusForbidden,
		},
		{
			name:       "transaction import denied",
			method:     http.MethodPost,
			path:       "/api/v1/imports/transactions/preview",
			scopes:     append([]string(nil), authz.AllowedAPITokenScopes...),
			wantStatus: http.StatusForbidden,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			gin.SetMode(gin.TestMode)
			manager := ledgerjwt.NewManager("scope-policy-test-secret-with-32-chars", 15, 30)
			validator := scopedAPITokenValidator{principal: authz.Principal{
				UserID:         1,
				CredentialType: authz.CredentialAPIToken,
				Scopes:         tt.scopes,
			}}
			router := gin.New()
			router.Use(AuthWithAPIToken(manager, validator), EnforceAPITokenScopes())
			router.Handle(tt.method, tt.path, func(c *gin.Context) {
				c.Status(http.StatusOK)
			})

			req := httptest.NewRequest(tt.method, tt.path, nil)
			req.Header.Set("Authorization", "Bearer plk_scope_test")
			w := httptest.NewRecorder()
			router.ServeHTTP(w, req)

			if w.Code != tt.wantStatus {
				t.Fatalf("status = %d, want %d; body = %s", w.Code, tt.wantStatus, w.Body.String())
			}
		})
	}
}

func TestAPITokenScopePolicyDoesNotRestrictJWT(t *testing.T) {
	gin.SetMode(gin.TestMode)
	manager := ledgerjwt.NewManager("scope-policy-jwt-secret-with-32-chars", 15, 30)
	token, err := manager.GenerateAccessToken(1)
	if err != nil {
		t.Fatalf("generate access token: %v", err)
	}
	router := gin.New()
	router.Use(AuthWithAPIToken(manager, fakeAPITokenValidator{}), EnforceAPITokenScopes())
	router.POST("/api/v1/restore", func(c *gin.Context) {
		c.Status(http.StatusOK)
	})

	req := httptest.NewRequest(http.MethodPost, "/api/v1/restore", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200; body = %s", w.Code, w.Body.String())
	}
}

type fakeAPITokenValidator struct{}

func (fakeAPITokenValidator) ValidateToken(string) (uint, error) {
	return 0, ledgerjwt.ErrInvalidToken
}

type acceptingAPITokenValidator struct {
	calls int
}

func (v *acceptingAPITokenValidator) ValidateToken(string) (uint, error) {
	v.calls++
	return 1, nil
}

type erroringAPITokenValidator struct{}

func (erroringAPITokenValidator) ValidateToken(string) (uint, error) {
	return 0, errors.New("sql: database is closed")
}

type scopedAPITokenValidator struct {
	principal authz.Principal
}

func (v scopedAPITokenValidator) ValidateToken(string) (uint, error) {
	return v.principal.UserID, nil
}

func (v scopedAPITokenValidator) ValidatePrincipal(string) (authz.Principal, error) {
	return v.principal, nil
}
