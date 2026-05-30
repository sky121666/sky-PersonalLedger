package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/service"
	"github.com/sky/personal-ledger/pkg/response"
)

func TestHealthHandlerReturnsOK(t *testing.T) {
	gin.SetMode(gin.TestMode)
	root := t.TempDir()
	db, err := database.Init(filepath.Join(root, "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	handler := NewHealthHandler(service.NewHealthService(db, "", ""))
	router := gin.New()
	router.GET("/api/v1/health", handler.Check)

	request := httptest.NewRequest(http.MethodGet, "/api/v1/health", nil)
	recorder := httptest.NewRecorder()
	router.ServeHTTP(recorder, request)

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", recorder.Code, recorder.Body.String())
	}
	var payload response.Response
	if err := json.Unmarshal(recorder.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if payload.Code != 0 {
		t.Fatalf("payload code = %d, want 0", payload.Code)
	}
}

func TestHealthHandlerReturnsServiceUnavailable(t *testing.T) {
	gin.SetMode(gin.TestMode)
	root := t.TempDir()
	db, err := database.Init(filepath.Join(root, "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	handler := NewHealthHandler(service.NewHealthService(db, filepath.Join(root, "missing"), ""))
	router := gin.New()
	router.GET("/api/v1/health", handler.Check)

	request := httptest.NewRequest(http.MethodGet, "/api/v1/health", nil)
	recorder := httptest.NewRecorder()
	router.ServeHTTP(recorder, request)

	if recorder.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want 503; body = %s", recorder.Code, recorder.Body.String())
	}
}
