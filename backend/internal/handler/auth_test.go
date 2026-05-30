package handler

import (
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
)

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
