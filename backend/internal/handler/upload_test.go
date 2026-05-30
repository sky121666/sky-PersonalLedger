package handler

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
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

func TestUploadListRejectsTraversalScope(t *testing.T) {
	handler, uploadPath, _ := newUploadDownloadTestHandler(t)
	writeUploadFixture(t, uploadPath, "2/transactions/t/b.txt", "other user attachment")

	w := performUploadListRequest(handler, 1, "..", "2")

	if w.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400; body=%s", w.Code, w.Body.String())
	}
}

func TestUploadListDoesNotExposeStoragePathOnInternalError(t *testing.T) {
	uploadRootFile := filepath.Join(t.TempDir(), "uploads-file")
	if err := os.WriteFile(uploadRootFile, []byte("not a directory"), 0600); err != nil {
		t.Fatalf("write upload root file: %v", err)
	}
	uploadService := service.NewUploadService(&config.StorageConfig{
		UploadPath:   uploadRootFile,
		MaxFileSize:  10,
		AllowedTypes: "txt",
	})
	jwtManager := jwt.NewManager("test-secret", 15, 60)
	authService := service.NewAuthService(nil, nil, nil, nil, jwtManager)
	handler := NewUploadHandler(uploadService, nil, authService)

	w := performUploadListRequest(handler, 1, "transactions", "t")

	if w.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500; body=%s", w.Code, w.Body.String())
	}
	var body struct {
		Message string `json:"message"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatalf("unmarshal response: %v", err)
	}
	if body.Message != "failed to list uploaded files" {
		t.Fatalf("message = %q, want generic upload list error", body.Message)
	}
	if strings.Contains(w.Body.String(), uploadRootFile) {
		t.Fatalf("response exposed storage path: %s", w.Body.String())
	}
}

func TestUploadServiceRejectsTraversalRefID(t *testing.T) {
	_, uploadPath, _ := newUploadDownloadTestHandler(t)
	uploadService := service.NewUploadService(&config.StorageConfig{
		UploadPath:   uploadPath,
		MaxFileSize:  10,
		AllowedTypes: "txt",
	})

	_, err := uploadService.ListFiles(1, "transactions", "../../../2")

	if !errors.Is(err, service.ErrUploadScopeInvalid) {
		t.Fatalf("err = %v, want ErrUploadScopeInvalid", err)
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

func performUploadListRequest(handler *UploadHandler, userID uint, category string, refID string) *httptest.ResponseRecorder {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.GET("/upload/list", func(c *gin.Context) {
		c.Set("userID", userID)
		handler.List(c)
	})

	req := httptest.NewRequest(
		http.MethodGet,
		"/upload/list?category="+url.QueryEscape(category)+"&ref_id="+url.QueryEscape(refID),
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
