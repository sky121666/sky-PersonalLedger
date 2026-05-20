package main

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/service"
	"github.com/sky/personal-ledger/pkg/jwt"
)

func TestSetupUploadFilesRejectsOtherUserPrivateFile(t *testing.T) {
	gin.SetMode(gin.TestMode)
	uploadPath := t.TempDir()
	writeServerUploadFixture(t, uploadPath, "2/transactions/t/b.txt", "other user attachment")

	jwtManager := jwt.NewManager("test-secret", 15, 60)
	authService := service.NewAuthService(nil, nil, nil, nil, jwtManager)
	token, err := jwtManager.GenerateAccessToken(1)
	if err != nil {
		t.Fatalf("generate access token: %v", err)
	}

	router := gin.New()
	setupUploadFiles(router, uploadPath, authService, nil)

	request := httptest.NewRequest(http.MethodGet, "/uploads/2/transactions/t/b.txt", nil)
	request.Header.Set("Authorization", "Bearer "+token)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

	if response.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403; body=%s", response.Code, response.Body.String())
	}
}

func writeServerUploadFixture(t *testing.T, uploadPath string, relativePath string, content string) {
	t.Helper()

	fullPath := filepath.Join(uploadPath, relativePath)
	if err := os.MkdirAll(filepath.Dir(fullPath), 0755); err != nil {
		t.Fatalf("create fixture directory: %v", err)
	}
	if err := os.WriteFile(fullPath, []byte(content), 0600); err != nil {
		t.Fatalf("write fixture: %v", err)
	}
}
