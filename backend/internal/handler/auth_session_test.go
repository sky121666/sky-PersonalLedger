package handler

import (
	"errors"
	"net/http"
	"net/http/cookiejar"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/service"
	"github.com/sky/personal-ledger/pkg/jwt"
)

func authSessionRouter(t *testing.T) (*AuthHandler, *gin.Engine) {
	t.Helper()
	h := newAuthHandlerForTest(t)
	handlers := emptyRouteContractHandlers()
	handlers.Auth = h
	router := gin.New()
	SetupRoutes(router, handlers, h.service, h.apiToken)
	return h, router
}

func browserSessionRequest(path, token string) *http.Request {
	req := browserRefreshRequest(
		&http.Cookie{Name: refreshTokenCookieName, Value: token},
		&http.Cookie{Name: csrfTokenCookieName, Value: "csrf-test"},
		"https://ledger.test", "csrf-test",
	)
	req.URL.Path = path
	return req
}

func TestLateChangePasswordResponseCannotClearNewLoginCookie(t *testing.T) {
	h, router := authSessionRouter(t)
	old, err := h.service.Init("strong-password")
	if err != nil {
		t.Fatal(err)
	}
	change := httptest.NewRequest(http.MethodPost, "/api/v1/auth/change-password", strings.NewReader(`{"old_password":"strong-password","new_password":"new-strong-password"}`))
	change.Header.Set("Content-Type", "application/json")
	change.Header.Set("Authorization", "Bearer "+old.AccessToken)
	change.Header.Set(browserTokenModeHeader, browserTokenModeCookie)
	late := httptest.NewRecorder()
	router.ServeHTTP(late, change)
	if late.Code != http.StatusOK {
		t.Fatalf("password change status=%d", late.Code)
	}
	if _, err := h.service.RefreshToken(old.RefreshToken); !errors.Is(err, service.ErrInvalidToken) {
		t.Fatal("password change left the previous refresh session usable")
	}
	login := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", strings.NewReader(`{"password":"new-strong-password"}`))
	login.Header.Set("Content-Type", "application/json")
	login.Header.Set(browserTokenModeHeader, browserTokenModeCookie)
	fresh := httptest.NewRecorder()
	router.ServeHTTP(fresh, login)
	if fresh.Code != http.StatusOK {
		t.Fatalf("new login status=%d", fresh.Code)
	}
	newCookie := responseCookieByName(t, fresh.Result(), refreshTokenCookieName)
	if len(late.Result().Cookies()) != 0 {
		t.Fatal("late password response overwrites a newer browser login")
	}
	jar, _ := cookiejar.New(nil)
	base, _ := url.Parse("http://ledger.test/api/v1/auth")
	jar.SetCookies(base, fresh.Result().Cookies())
	jar.SetCookies(base, late.Result().Cookies())
	preserved := false
	for _, cookie := range jar.Cookies(base) {
		if cookie.Name == refreshTokenCookieName && cookie.Value == newCookie.Value {
			preserved = true
		}
	}
	if !preserved {
		t.Fatal("late password response removed the new login cookie from the jar")
	}
	if _, err := h.service.RefreshToken(newCookie.Value); err != nil {
		t.Fatalf("new password login lost its server session: %v", err)
	}
}

func TestBrowserLogoutWithExpiredAccessRevokesRefreshSession(t *testing.T) {
	h, router := authSessionRouter(t)
	tokens, err := h.service.Init("strong-password")
	if err != nil {
		t.Fatal(err)
	}
	claims, err := h.service.GetJWTManager().ValidateRefreshToken(tokens.RefreshToken)
	if err != nil {
		t.Fatal(err)
	}
	expired, err := jwt.NewManager("test-auth-secret-with-at-least-32-chars", -1, 60).GenerateAccessToken(claims.UserID)
	if err != nil {
		t.Fatal(err)
	}
	req := browserSessionRequest("/api/v1/auth/logout", tokens.RefreshToken)
	req.Header.Set("Authorization", "Bearer "+expired)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, req)
	if response.Code != http.StatusOK {
		t.Fatalf("logout status=%d body=%s", response.Code, response.Body.String())
	}
	if _, err := h.service.RefreshToken(tokens.RefreshToken); !errors.Is(err, service.ErrInvalidToken) {
		t.Fatalf("logout left bootstrap possible: %v", err)
	}
	if cookie := responseCookieByName(t, response.Result(), refreshTokenCookieName); cookie.MaxAge != -1 {
		t.Fatalf("logout did not expire browser cookie")
	}
}

func TestFailedOldBrowserRefreshCannotEraseNewLoginCookie(t *testing.T) {
	h, router := authSessionRouter(t)
	old, err := h.service.Init("strong-password")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := h.service.RefreshToken(old.RefreshToken); err != nil {
		t.Fatal(err)
	}
	login := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", strings.NewReader(`{"password":"strong-password"}`))
	login.Header.Set("Content-Type", "application/json")
	login.Header.Set(browserTokenModeHeader, browserTokenModeCookie)
	newResponse := httptest.NewRecorder()
	router.ServeHTTP(newResponse, login)
	if newResponse.Code != http.StatusOK {
		t.Fatalf("login status=%d", newResponse.Code)
	}
	newCookie := responseCookieByName(t, newResponse.Result(), refreshTokenCookieName)
	late := httptest.NewRecorder()
	router.ServeHTTP(late, browserSessionRequest("/api/v1/auth/refresh", old.RefreshToken))
	if late.Code != http.StatusUnauthorized {
		t.Fatalf("old refresh status=%d", late.Code)
	}
	if len(late.Result().Cookies()) != 0 {
		t.Fatal("late failed refresh overwrites the newer login's cookies")
	}
	if _, err := h.service.RefreshToken(newCookie.Value); err != nil {
		t.Fatalf("new login lost refresh: %v", err)
	}
}

func TestBrowserLogoutRevokesRotatedFamilyButPreservesNewLogin(t *testing.T) {
	h, router := authSessionRouter(t)
	old, err := h.service.Init("strong-password")
	if err != nil {
		t.Fatal(err)
	}
	rotated, err := h.service.RefreshToken(old.RefreshToken)
	if err != nil {
		t.Fatal(err)
	}
	newLogin, err := h.service.Login("strong-password")
	if err != nil {
		t.Fatal(err)
	}
	req := browserSessionRequest("/api/v1/auth/logout", old.RefreshToken)
	req.Header.Set("Authorization", "Bearer "+old.AccessToken)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, req)
	if response.Code != http.StatusOK {
		t.Fatalf("logout status=%d", response.Code)
	}
	if _, err := h.service.RefreshToken(rotated.RefreshToken); !errors.Is(err, service.ErrInvalidToken) {
		t.Fatalf("rotated old family remains usable: %v", err)
	}
	if _, err := h.service.RefreshToken(newLogin.RefreshToken); err != nil {
		t.Fatalf("old logout revoked newer independent login: %v", err)
	}
}

func TestBrowserLogoutRequiresOriginAndCSRF(t *testing.T) {
	for _, field := range []string{"Origin", csrfTokenHeader} {
		t.Run(field, func(t *testing.T) {
			h, router := authSessionRouter(t)
			tokens, err := h.service.Init("strong-password")
			if err != nil {
				t.Fatal(err)
			}
			req := browserSessionRequest("/api/v1/auth/logout", tokens.RefreshToken)
			req.Header.Set("Authorization", "Bearer "+tokens.AccessToken)
			req.Header.Del(field)
			response := httptest.NewRecorder()
			router.ServeHTTP(response, req)
			if response.Code != http.StatusForbidden {
				t.Fatalf("status=%d, want csrf rejection", response.Code)
			}
			if len(response.Result().Cookies()) != 0 {
				t.Fatal("csrf rejection changed cookies")
			}
			if _, err := h.service.RefreshToken(tokens.RefreshToken); err != nil {
				t.Fatalf("csrf request revoked session: %v", err)
			}
		})
	}
}

func TestBrowserLogoutWithoutValidCookieDoesNotRevokeNewLogin(t *testing.T) {
	for _, token := range []string{"", "not-a-signed-refresh-token"} {
		t.Run(token, func(t *testing.T) {
			h, router := authSessionRouter(t)
			newLogin, err := h.service.Init("strong-password")
			if err != nil {
				t.Fatal(err)
			}
			req := browserSessionRequest("/api/v1/auth/logout", token)
			// An access token must not turn a malformed cookie into global logout.
			req.Header.Set("Authorization", "Bearer "+newLogin.AccessToken)
			response := httptest.NewRecorder()
			router.ServeHTTP(response, req)
			if response.Code != http.StatusOK {
				t.Fatalf("status=%d", response.Code)
			}
			if len(response.Result().Cookies()) != 0 {
				t.Fatal("invalid cookie logout changed browser cookies")
			}
			if _, err := h.service.RefreshToken(newLogin.RefreshToken); err != nil {
				t.Fatalf("new login revoked: %v", err)
			}
		})
	}
}

func TestRepeatedOldBrowserLogoutDoesNotClearNewLoginCookie(t *testing.T) {
	h, router := authSessionRouter(t)
	old, err := h.service.Init("strong-password")
	if err != nil {
		t.Fatal(err)
	}
	first := httptest.NewRecorder()
	router.ServeHTTP(first, browserSessionRequest("/api/v1/auth/logout", old.RefreshToken))
	if first.Code != http.StatusOK {
		t.Fatalf("first logout status=%d", first.Code)
	}
	newLogin, err := h.service.Login("strong-password")
	if err != nil {
		t.Fatal(err)
	}
	late := httptest.NewRecorder()
	router.ServeHTTP(late, browserSessionRequest("/api/v1/auth/logout", old.RefreshToken))
	if len(late.Result().Cookies()) != 0 {
		t.Fatal("already-revoked session writes cookies over new login")
	}
	if _, err := h.service.RefreshToken(newLogin.RefreshToken); err != nil {
		t.Fatalf("new login revoked: %v", err)
	}
}

func TestNativeLogoutKeepsAuthenticationAndRevocationContract(t *testing.T) {
	h, router := authSessionRouter(t)
	tokens, err := h.service.Init("strong-password")
	if err != nil {
		t.Fatal(err)
	}
	unauthenticated := httptest.NewRecorder()
	router.ServeHTTP(unauthenticated, httptest.NewRequest(http.MethodPost, "/api/v1/auth/logout", nil))
	if unauthenticated.Code != http.StatusUnauthorized {
		t.Fatalf("native logout without JWT status=%d", unauthenticated.Code)
	}
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/logout", nil)
	req.Header.Set("Authorization", "Bearer "+tokens.AccessToken)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, req)
	if response.Code != http.StatusOK {
		t.Fatalf("native logout status=%d", response.Code)
	}
	if _, err := h.service.RefreshToken(tokens.RefreshToken); !errors.Is(err, service.ErrInvalidToken) {
		t.Fatalf("native refresh survived logout: %v", err)
	}
}

func TestBrowserLogoutHTTPPreventsCookieBootstrap(t *testing.T) {
	h, router := authSessionRouter(t)
	tokens, err := h.service.Init("strong-password")
	if err != nil {
		t.Fatal(err)
	}
	claims, err := h.service.GetJWTManager().ValidateRefreshToken(tokens.RefreshToken)
	if err != nil {
		t.Fatal(err)
	}
	expired, err := jwt.NewManager("test-auth-secret-with-at-least-32-chars", -1, 60).GenerateAccessToken(claims.UserID)
	if err != nil {
		t.Fatal(err)
	}
	server := httptest.NewServer(router)
	defer server.Close()
	jar, err := cookiejar.New(nil)
	if err != nil {
		t.Fatal(err)
	}
	origin, err := url.Parse(server.URL)
	if err != nil {
		t.Fatal(err)
	}
	jar.SetCookies(origin, []*http.Cookie{
		{Name: refreshTokenCookieName, Value: tokens.RefreshToken, Path: refreshCookiePath, HttpOnly: true},
		{Name: csrfTokenCookieName, Value: "csrf-test", Path: "/"},
	})
	client := &http.Client{Jar: jar}
	req, err := http.NewRequest(http.MethodPost, server.URL+"/api/v1/auth/logout", nil)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set(browserTokenModeHeader, browserTokenModeCookie)
	req.Header.Set("Origin", server.URL)
	req.Header.Set(csrfTokenHeader, "csrf-test")
	req.Header.Set("Authorization", "Bearer "+expired)
	response, err := client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()
	if response.StatusCode != http.StatusOK {
		t.Fatalf("HTTP logout status=%d", response.StatusCode)
	}
	bootstrap, err := http.NewRequest(http.MethodPost, server.URL+"/api/v1/auth/refresh", nil)
	if err != nil {
		t.Fatal(err)
	}
	bootstrap.Header.Set(browserTokenModeHeader, browserTokenModeCookie)
	bootstrap.Header.Set("Origin", server.URL)
	bootstrap.Header.Set(csrfTokenHeader, "csrf-test")
	response, err = client.Do(bootstrap)
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()
	if response.StatusCode == http.StatusOK {
		t.Fatal("reload restored an explicitly logged-out browser")
	}
	if _, err := h.service.RefreshToken(tokens.RefreshToken); !errors.Is(err, service.ErrInvalidToken) {
		t.Fatalf("cookie removal concealed a still-valid server session: %v", err)
	}
}
