package handler

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"github.com/sky/personal-ledger/internal/service"
)

func TestAIProviderHandlerDoesNotReturnRawAPIKey(t *testing.T) {
	handler, userID := newAIProviderTestHandler(t)

	response := performAIProviderRequest(handler, userID, http.MethodPost, "/ai/providers", map[string]any{
		"name":     "DeepSeek",
		"base_url": "https://api.deepseek.com",
		"api_key":  "sk-secret",
		"model":    "deepseek-chat",
		"enabled":  true,
	})
	if response.Code != http.StatusCreated {
		t.Fatalf("create status = %d, body = %s", response.Code, response.Body.String())
	}
	if strings.Contains(response.Body.String(), "sk-secret") {
		t.Fatalf("create response leaked api key: %s", response.Body.String())
	}

	listResponse := performAIProviderRequest(handler, userID, http.MethodGet, "/ai/providers", nil)
	if listResponse.Code != http.StatusOK {
		t.Fatalf("list status = %d, body = %s", listResponse.Code, listResponse.Body.String())
	}
	if strings.Contains(listResponse.Body.String(), "sk-secret") {
		t.Fatalf("list response leaked api key: %s", listResponse.Body.String())
	}
}

func newAIProviderTestHandler(t *testing.T) (*AIHandler, uint) {
	t.Helper()
	gin.SetMode(gin.TestMode)

	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	user := &model.User{Username: "admin", PasswordHash: "hash"}
	if err := repos.User.Create(user); err != nil {
		t.Fatalf("create user: %v", err)
	}
	providerService := service.NewAIProviderService(repos.AIProvider, service.NewOpenAICompatibleClient(nil))
	return NewAIHandler(providerService, nil, nil), user.ID
}

func performAIProviderRequest(handler *AIHandler, userID uint, method string, path string, payload any) *httptest.ResponseRecorder {
	router := gin.New()
	router.Use(func(c *gin.Context) {
		c.Set("userID", userID)
		c.Next()
	})
	router.GET("/ai/providers", handler.ListProviders)
	router.POST("/ai/providers", handler.CreateProvider)
	router.PUT("/ai/providers/:id", handler.UpdateProvider)
	router.DELETE("/ai/providers/:id", handler.DeleteProvider)
	router.POST("/ai/providers/:id/test", handler.TestProvider)

	var body *bytes.Reader
	if payload == nil {
		body = bytes.NewReader(nil)
	} else {
		data, _ := json.Marshal(payload)
		body = bytes.NewReader(data)
	}
	request := httptest.NewRequest(method, path, body)
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	return response
}
