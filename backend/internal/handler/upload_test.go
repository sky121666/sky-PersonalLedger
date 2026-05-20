package handler

import (
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/config"
	"github.com/sky/personal-ledger/internal/service"
	"github.com/sky/personal-ledger/pkg/jwt"
)

func TestUploadDownloadRequiresToken(t *testing.T) {
	handler, _, _ := newUploadDownloadTestHandler(t)
	w := performUploadDownloadRequest(handler, "1/transactions/t/a.txt", "")

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", w.Code)
	}
}

func TestUploadDownloadAcceptsBearerToken(t *testing.T) {
	handler, uploadPath, jwtManager := newUploadDownloadTestHandler(t)
	writeUploadFixture(t, uploadPath, "1/transactions/t/a.txt", "ledger attachment")

	token, err := jwtManager.GenerateAccessToken(1)
	if err != nil {
		t.Fatalf("generate access token: %v", err)
	}

	w := performUploadDownloadRequest(handler, "1/transactions/t/a.txt", token)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	if got := w.Body.String(); got != "ledger attachment" {
		t.Fatalf("body = %q, want fixture content", got)
	}
}

func TestUploadDownloadRejectsOtherUserFile(t *testing.T) {
	handler, uploadPath, jwtManager := newUploadDownloadTestHandler(t)
	writeUploadFixture(t, uploadPath, "2/transactions/t/b.txt", "other user attachment")

	token, err := jwtManager.GenerateAccessToken(1)
	if err != nil {
		t.Fatalf("generate access token: %v", err)
	}

	w := performUploadDownloadRequest(handler, "2/transactions/t/b.txt", token)

	if w.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403; body=%s", w.Code, w.Body.String())
	}
}

func TestUploadDeleteRemovesOnlyCurrentUserFile(t *testing.T) {
	handler, uploadPath, _ := newUploadDownloadTestHandler(t)
	writeUploadFixture(t, uploadPath, "1/transactions/t/a.txt", "ledger attachment")
	writeUploadFixture(t, uploadPath, "2/transactions/t/b.txt", "other user attachment")

	w := performUploadDeleteRequest(handler, 1, "1/transactions/t/a.txt")

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	if _, err := os.Stat(filepath.Join(uploadPath, "1/transactions/t/a.txt")); !os.IsNotExist(err) {
		t.Fatalf("current user file still exists or stat failed: %v", err)
	}
	if _, err := os.Stat(filepath.Join(uploadPath, "2/transactions/t/b.txt")); err != nil {
		t.Fatalf("other user file should remain: %v", err)
	}
}

func TestUploadDeleteRejectsOtherUserFile(t *testing.T) {
	handler, uploadPath, _ := newUploadDownloadTestHandler(t)
	writeUploadFixture(t, uploadPath, "2/transactions/t/b.txt", "other user attachment")

	w := performUploadDeleteRequest(handler, 1, "2/transactions/t/b.txt")

	if w.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403; body=%s", w.Code, w.Body.String())
	}
	if _, err := os.Stat(filepath.Join(uploadPath, "2/transactions/t/b.txt")); err != nil {
		t.Fatalf("other user file should remain: %v", err)
	}
}

func TestUploadDeleteRejectsUserRootPath(t *testing.T) {
	handler, uploadPath, _ := newUploadDownloadTestHandler(t)
	if err := os.MkdirAll(filepath.Join(uploadPath, "1"), 0755); err != nil {
		t.Fatalf("create user upload directory: %v", err)
	}

	w := performUploadDeleteRequest(handler, 1, "1")

	if w.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400; body=%s", w.Code, w.Body.String())
	}
	if _, err := os.Stat(filepath.Join(uploadPath, "1")); err != nil {
		t.Fatalf("user upload directory should remain: %v", err)
	}
}

func newUploadDownloadTestHandler(t *testing.T) (*UploadHandler, string, *jwt.Manager) {
	t.Helper()

	uploadPath := t.TempDir()
	uploadService := service.NewUploadService(&config.StorageConfig{
		UploadPath:   uploadPath,
		MaxFileSize:  10,
		AllowedTypes: "txt",
	})
	jwtManager := jwt.NewManager("test-secret", 15, 60)
	authService := service.NewAuthService(nil, nil, nil, nil, jwtManager)

	return NewUploadHandler(uploadService, nil, authService), uploadPath, jwtManager
}

func performUploadDownloadRequest(handler *UploadHandler, path string, token string) *httptest.ResponseRecorder {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.GET("/download", handler.Download)

	req := httptest.NewRequest(
		http.MethodGet,
		"/download?path="+url.QueryEscape(path),
		nil,
	)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}

	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	return w
}

func performUploadDeleteRequest(handler *UploadHandler, userID uint, path string) *httptest.ResponseRecorder {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.DELETE("/upload", func(c *gin.Context) {
		c.Set("userID", userID)
		handler.Delete(c)
	})

	req := httptest.NewRequest(
		http.MethodDelete,
		"/upload?path="+url.QueryEscape(path),
		nil,
	)

	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	return w
}

func writeUploadFixture(t *testing.T, uploadPath string, relativePath string, content string) {
	t.Helper()

	fullPath := filepath.Join(uploadPath, relativePath)
	if err := os.MkdirAll(filepath.Dir(fullPath), 0755); err != nil {
		t.Fatalf("create fixture directory: %v", err)
	}
	if err := os.WriteFile(fullPath, []byte(content), 0600); err != nil {
		t.Fatalf("write fixture: %v", err)
	}
}
