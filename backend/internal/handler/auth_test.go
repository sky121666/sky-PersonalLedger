package handler

import (
	"errors"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/middleware"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"github.com/sky/personal-ledger/internal/service"
	"github.com/sky/personal-ledger/pkg/jwt"
	"gorm.io/gorm"
)

func TestAuthInitMalformedJSONDoesNotExposeParserDetails(t *testing.T) {
	handler := newAuthHandlerForTest(t)
	response := httptest.NewRecorder()
	router := gin.New()
	router.POST("/init", handler.Init)

	request := httptest.NewRequest(http.MethodPost, "/init", strings.NewReader(`{"password":`))
	request.Header.Set("Content-Type", "application/json")
	router.ServeHTTP(response, request)

	if response.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400; body=%s", response.Code, response.Body.String())
	}
	body := strings.ToLower(response.Body.String())
	if !strings.Contains(body, "invalid request") {
		t.Fatalf("body = %s, want invalid request", response.Body.String())
	}
	for _, forbidden := range []string{"unexpected", "eof", "json", "password"} {
		if strings.Contains(body, forbidden) {
			t.Fatalf("response exposed parser detail %q: %s", forbidden, response.Body.String())
		}
	}
}

func TestAuthLoginReturnsInternalErrorWhenLoginStateCannotPersist(t *testing.T) {
	handler, repos := newAuthHandlerAndReposForTest(t)
	if _, err := handler.service.Init("strong-password"); err != nil {
		t.Fatalf("init auth: %v", err)
	}
	forcedErr := errors.New("forced login state update failure")
	callbackName := "test:fail-handler-login-user-update"
	db := repos.User.DB()
	if err := db.Callback().Update().Before("gorm:update").Register(callbackName, func(tx *gorm.DB) {
		if tx.Statement.Table == "users" {
			tx.AddError(forcedErr)
		}
	}); err != nil {
		t.Fatalf("register update callback: %v", err)
	}
	t.Cleanup(func() { _ = db.Callback().Update().Remove(callbackName) })

	response := httptest.NewRecorder()
	router := gin.New()
	router.POST("/login", handler.Login)
	request := httptest.NewRequest(http.MethodPost, "/login", strings.NewReader(`{"password":"strong-password"}`))
	request.Header.Set("Content-Type", "application/json")
	router.ServeHTTP(response, request)

	if response.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500; body=%s", response.Code, response.Body.String())
	}
	if !strings.Contains(response.Body.String(), "failed to authenticate") {
		t.Fatalf("body = %s, want generic authentication failure", response.Body.String())
	}
	if strings.Contains(response.Body.String(), forcedErr.Error()) {
		t.Fatalf("response exposed persistence error: %s", response.Body.String())
	}
}

func TestAuthLoginReturnsInternalErrorWhenUserQueryFails(t *testing.T) {
	handler, repos := newAuthHandlerAndReposForTest(t)
	if _, err := handler.service.Init("strong-password"); err != nil {
		t.Fatalf("init auth: %v", err)
	}
	sqlDB, err := repos.User.DB().DB()
	if err != nil {
		t.Fatalf("get database handle: %v", err)
	}
	if err := sqlDB.Close(); err != nil {
		t.Fatalf("close database: %v", err)
	}

	response := httptest.NewRecorder()
	router := gin.New()
	router.POST("/login", handler.Login)
	request := httptest.NewRequest(http.MethodPost, "/login", strings.NewReader(`{"password":"wrong-password"}`))
	request.Header.Set("Content-Type", "application/json")
	router.ServeHTTP(response, request)

	if response.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500; body=%s", response.Code, response.Body.String())
	}
	if !strings.Contains(response.Body.String(), "failed to authenticate") {
		t.Fatalf("body = %s, want generic authentication failure", response.Body.String())
	}
}

func TestBrowserAuthUsesSecureHttpOnlyRefreshCookieAndOmitsTokenBody(t *testing.T) {
	handler := newAuthHandlerForTest(t)
	handler.browserCookieSecure = true
	router := gin.New()
	router.POST("/api/v1/auth/init", handler.Init)

	request := httptest.NewRequest(http.MethodPost, "/api/v1/auth/init", strings.NewReader(`{"password":"strong-password"}`))
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set(browserTokenModeHeader, browserTokenModeCookie)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

	if response.Code != http.StatusCreated {
		t.Fatalf("status = %d, want 201; body=%s", response.Code, response.Body.String())
	}
	if strings.Contains(response.Body.String(), "refresh_token") {
		t.Fatalf("browser auth response exposed refresh token: %s", response.Body.String())
	}
	if !strings.Contains(response.Body.String(), "access_token") {
		t.Fatalf("browser auth response omitted access token: %s", response.Body.String())
	}

	refreshCookie := responseCookieByName(t, response.Result(), refreshTokenCookieName)
	if !refreshCookie.HttpOnly || !refreshCookie.Secure || refreshCookie.SameSite != http.SameSiteStrictMode {
		t.Fatalf("refresh cookie flags = HttpOnly:%v Secure:%v SameSite:%v", refreshCookie.HttpOnly, refreshCookie.Secure, refreshCookie.SameSite)
	}
	if refreshCookie.Path != refreshCookiePath || refreshCookie.Value == "" {
		t.Fatalf("refresh cookie path/value = %q/%q", refreshCookie.Path, refreshCookie.Value)
	}
	csrfCookie := responseCookieByName(t, response.Result(), csrfTokenCookieName)
	if csrfCookie.HttpOnly || !csrfCookie.Secure || csrfCookie.SameSite != http.SameSiteStrictMode || csrfCookie.Value == "" {
		t.Fatalf("csrf cookie flags/value = HttpOnly:%v Secure:%v SameSite:%v value:%q", csrfCookie.HttpOnly, csrfCookie.Secure, csrfCookie.SameSite, csrfCookie.Value)
	}
}

func TestBrowserRefreshRequiresSameOriginAndCSRFThenRotatesToken(t *testing.T) {
	handler := newAuthHandlerForTest(t)
	router := gin.New()
	router.POST("/api/v1/auth/init", handler.Init)
	router.POST("/api/v1/auth/refresh", handler.Refresh)

	initRequest := httptest.NewRequest(http.MethodPost, "/api/v1/auth/init", strings.NewReader(`{"password":"strong-password"}`))
	initRequest.Header.Set("Content-Type", "application/json")
	initRequest.Header.Set(browserTokenModeHeader, browserTokenModeCookie)
	initResponse := httptest.NewRecorder()
	router.ServeHTTP(initResponse, initRequest)
	if initResponse.Code != http.StatusCreated {
		t.Fatalf("init status = %d; body=%s", initResponse.Code, initResponse.Body.String())
	}
	refreshCookie := responseCookieByName(t, initResponse.Result(), refreshTokenCookieName)
	csrfCookie := responseCookieByName(t, initResponse.Result(), csrfTokenCookieName)

	for _, test := range []struct {
		name   string
		origin string
		csrf   string
	}{
		{name: "missing origin", csrf: csrfCookie.Value},
		{name: "cross origin", origin: "https://evil.test", csrf: csrfCookie.Value},
		{name: "missing csrf", origin: "https://ledger.test"},
		{name: "mismatched csrf", origin: "https://ledger.test", csrf: "wrong"},
	} {
		t.Run(test.name, func(t *testing.T) {
			request := browserRefreshRequest(refreshCookie, csrfCookie, test.origin, test.csrf)
			response := httptest.NewRecorder()
			router.ServeHTTP(response, request)
			if response.Code != http.StatusForbidden {
				t.Fatalf("status = %d, want 403; body=%s", response.Code, response.Body.String())
			}
		})
	}

	validRequest := browserRefreshRequest(refreshCookie, csrfCookie, "https://ledger.test", csrfCookie.Value)
	validResponse := httptest.NewRecorder()
	router.ServeHTTP(validResponse, validRequest)
	if validResponse.Code != http.StatusOK {
		t.Fatalf("valid refresh status = %d, want 200; body=%s", validResponse.Code, validResponse.Body.String())
	}
	if strings.Contains(validResponse.Body.String(), "refresh_token") {
		t.Fatalf("browser refresh response exposed token: %s", validResponse.Body.String())
	}
	rotatedRefresh := responseCookieByName(t, validResponse.Result(), refreshTokenCookieName)
	rotatedCSRF := responseCookieByName(t, validResponse.Result(), csrfTokenCookieName)
	if rotatedRefresh.Value == refreshCookie.Value || rotatedCSRF.Value == csrfCookie.Value {
		t.Fatal("refresh or CSRF cookie was not rotated")
	}

	reusedRequest := browserRefreshRequest(refreshCookie, csrfCookie, "https://ledger.test", csrfCookie.Value)
	reusedResponse := httptest.NewRecorder()
	router.ServeHTTP(reusedResponse, reusedRequest)
	if reusedResponse.Code != http.StatusUnauthorized {
		t.Fatalf("reused refresh status = %d, want 401; body=%s", reusedResponse.Code, reusedResponse.Body.String())
	}
}

func TestNativeAuthKeepsRefreshTokenInResponseBody(t *testing.T) {
	handler := newAuthHandlerForTest(t)
	router := gin.New()
	router.POST("/api/v1/auth/init", handler.Init)

	request := httptest.NewRequest(http.MethodPost, "/api/v1/auth/init", strings.NewReader(`{"password":"strong-password"}`))
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

	if response.Code != http.StatusCreated {
		t.Fatalf("status = %d, want 201; body=%s", response.Code, response.Body.String())
	}
	if !strings.Contains(response.Body.String(), "refresh_token") {
		t.Fatalf("native auth response omitted refresh token: %s", response.Body.String())
	}
	if len(response.Result().Cookies()) != 0 {
		t.Fatalf("native auth unexpectedly set cookies: %#v", response.Result().Cookies())
	}
}

func TestAuthGetProfileMissingUserDoesNotExposeORMError(t *testing.T) {
	handler := newAuthHandlerForTest(t)
	response := httptest.NewRecorder()
	router := gin.New()
	router.GET("/profile", func(c *gin.Context) {
		c.Set("userID", uint(404))
		handler.GetProfile(c)
	})

	request := httptest.NewRequest(http.MethodGet, "/profile", nil)
	router.ServeHTTP(response, request)

	if response.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404; body=%s", response.Code, response.Body.String())
	}
	if !strings.Contains(response.Body.String(), "profile not found") {
		t.Fatalf("body = %s, want generic profile not found message", response.Body.String())
	}
	if strings.Contains(strings.ToLower(response.Body.String()), "record not found") {
		t.Fatalf("response exposed ORM error: %s", response.Body.String())
	}
}

func TestAuthVerifyAPITokenDoesNotExposeExpiredTokenReason(t *testing.T) {
	handler, repos := newAuthHandlerAndReposForTest(t)
	expiresAt := time.Now().Add(-time.Hour)
	if err := repos.APIToken.Create(&model.APIToken{
		UserID:    1,
		Name:      "expired",
		Token:     "expired-token",
		ExpiresAt: &expiresAt,
	}); err != nil {
		t.Fatalf("create expired token: %v", err)
	}

	response := httptest.NewRecorder()
	router := gin.New()
	router.GET("/verify", handler.VerifyAPIToken)

	request := httptest.NewRequest(http.MethodGet, "/verify", nil)
	request.Header.Set("Authorization", "Bearer expired-token")
	router.ServeHTTP(response, request)

	if response.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401; body=%s", response.Code, response.Body.String())
	}
	if !strings.Contains(response.Body.String(), "invalid token") {
		t.Fatalf("body = %s, want generic invalid token message", response.Body.String())
	}
	if strings.Contains(strings.ToLower(response.Body.String()), "expired") {
		t.Fatalf("response exposed token state: %s", response.Body.String())
	}
}

func newAuthHandlerForTest(t *testing.T) *AuthHandler {
	t.Helper()
	handler, _ := newAuthHandlerAndReposForTest(t)
	return handler
}

func newAuthHandlerAndReposForTest(t *testing.T) (*AuthHandler, *repository.Repositories) {
	t.Helper()
	gin.SetMode(gin.TestMode)
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	jwtManager := jwt.NewManager("test-auth-secret-with-at-least-32-chars", 15, 60)
	authService := service.NewAuthService(
		repos.User,
		repos.RefreshToken,
		repos.Category,
		repos.Account,
		jwtManager,
	)
	handler := NewAuthHandler(
		authService,
		service.NewAPITokenService(repos.APIToken),
		nil,
		middleware.NewRateLimiter(),
	)
	return handler, repos
}

func responseCookieByName(t *testing.T, response *http.Response, name string) *http.Cookie {
	t.Helper()
	for _, cookie := range response.Cookies() {
		if cookie.Name == name {
			return cookie
		}
	}
	t.Fatalf("response cookie %q not found", name)
	return nil
}

func browserRefreshRequest(refreshCookie, csrfCookie *http.Cookie, origin, csrfHeader string) *http.Request {
	request := httptest.NewRequest(http.MethodPost, "/api/v1/auth/refresh", nil)
	request.Host = "ledger.test"
	request.Header.Set(browserTokenModeHeader, browserTokenModeCookie)
	if origin != "" {
		request.Header.Set("Origin", origin)
	}
	if csrfHeader != "" {
		request.Header.Set(csrfTokenHeader, csrfHeader)
	}
	request.AddCookie(refreshCookie)
	request.AddCookie(csrfCookie)
	return request
}
