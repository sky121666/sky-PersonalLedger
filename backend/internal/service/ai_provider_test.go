package service

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

func newAIProviderTestService(t *testing.T) (*AIProviderService, *repository.Repositories, uint) {
	t.Helper()
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	user := &model.User{Username: "admin", PasswordHash: "hash"}
	if err := repos.User.Create(user); err != nil {
		t.Fatalf("create user: %v", err)
	}
	return NewAIProviderService(repos.AIProvider, NewOpenAICompatibleClient(nil)), repos, user.ID
}

func TestAIProviderCreateListUpdateDeleteDoesNotExposeAPIKey(t *testing.T) {
	svc, _, userID := newAIProviderTestService(t)

	provider, err := svc.Create(userID, SaveAIProviderRequest{
		Name:    "DeepSeek",
		BaseURL: "https://api.deepseek.com",
		APIKey:  "sk-secret",
		Model:   "deepseek-chat",
		Enabled: true,
	})
	if err != nil {
		t.Fatalf("create provider: %v", err)
	}
	if provider.ID == "" {
		t.Fatal("provider ID should be generated")
	}
	if provider.APIKey != "" {
		t.Fatalf("provider response api key = %q, want empty", provider.APIKey)
	}

	list, err := svc.List(userID)
	if err != nil {
		t.Fatalf("list providers: %v", err)
	}
	if len(list) != 1 {
		t.Fatalf("list len = %d, want 1", len(list))
	}
	if list[0].APIKey != "" {
		t.Fatalf("listed provider api key = %q, want empty", list[0].APIKey)
	}

	updated, err := svc.Update(provider.ID, userID, SaveAIProviderRequest{
		Name:    "DeepSeek Main",
		BaseURL: "https://api.deepseek.com/v1",
		APIKey:  "",
		Model:   "deepseek-reasoner",
		Enabled: false,
	})
	if err != nil {
		t.Fatalf("update provider: %v", err)
	}
	if updated.Name != "DeepSeek Main" || updated.Model != "deepseek-reasoner" || updated.Enabled {
		t.Fatalf("updated provider = %#v", updated)
	}

	if err := svc.Delete(provider.ID, userID); err != nil {
		t.Fatalf("delete provider: %v", err)
	}
	list, err = svc.List(userID)
	if err != nil {
		t.Fatalf("list after delete: %v", err)
	}
	if len(list) != 0 {
		t.Fatalf("list len after delete = %d, want 0", len(list))
	}
}

func TestAIProviderRejectsUnsupportedType(t *testing.T) {
	svc, _, userID := newAIProviderTestService(t)

	_, err := svc.Create(userID, SaveAIProviderRequest{
		Name:         "DeepSeek",
		ProviderType: "unsupported_provider",
		BaseURL:      "https://api.deepseek.com",
		APIKey:       "sk-secret",
		Model:        "deepseek-chat",
		Enabled:      true,
	})
	if !errors.Is(err, ErrAIProviderTypeUnsupported) {
		t.Fatalf("err = %v, want ErrAIProviderTypeUnsupported", err)
	}
}

func TestAIProviderRejectsInvalidBaseURL(t *testing.T) {
	svc, _, userID := newAIProviderTestService(t)

	_, err := svc.Create(userID, SaveAIProviderRequest{
		Name:    "DeepSeek",
		BaseURL: "ftp://api.deepseek.com",
		APIKey:  "sk-secret",
		Model:   "deepseek-chat",
		Enabled: true,
	})
	if !errors.Is(err, ErrAIProviderBaseURLInvalid) {
		t.Fatalf("err = %v, want ErrAIProviderBaseURLInvalid", err)
	}
}

func TestAIProviderAllowsOnlyHTTPSOrLoopbackHTTPBaseURL(t *testing.T) {
	svc, _, userID := newAIProviderTestService(t)

	for _, baseURL := range []string{
		"http://api.deepseek.com",
		"https://token@api.deepseek.com",
		"https://api.deepseek.com?api_key=sk-test",
		"https://api.deepseek.com#sk-test",
	} {
		_, err := svc.Create(userID, SaveAIProviderRequest{
			Name:    "Invalid",
			BaseURL: baseURL,
			APIKey:  "sk-test",
			Model:   "deepseek-v4-flash",
		})
		if !errors.Is(err, ErrAIProviderBaseURLInvalid) {
			t.Fatalf("base url %q err = %v, want ErrAIProviderBaseURLInvalid", baseURL, err)
		}
	}

	for _, baseURL := range []string{"https://api.deepseek.com", "http://localhost:11434", "http://127.0.0.1:8080", "http://[::1]:8080"} {
		if _, err := svc.Create(userID, SaveAIProviderRequest{
			Name:    "Allowed",
			BaseURL: baseURL,
			APIKey:  "sk-test",
			Model:   "deepseek-v4-flash",
		}); err != nil {
			t.Fatalf("base url %q err = %v, want nil", baseURL, err)
		}
	}
}

func TestAIProviderPresetsIncludeDeepSeekDefaults(t *testing.T) {
	svc, _, _ := newAIProviderTestService(t)

	presets := svc.ListPresets()
	if len(presets) == 0 {
		t.Fatal("presets should not be empty")
	}
	var deepSeek *AIProviderPresetResponse
	for i := range presets {
		if presets[i].ID == "deepseek" {
			deepSeek = &presets[i]
			break
		}
	}
	if deepSeek == nil {
		t.Fatal("deepseek preset missing")
	}
	if deepSeek.ProviderType != aiProviderTypeOpenAICompatible ||
		deepSeek.BaseURL != "https://api.deepseek.com" ||
		deepSeek.Model != "deepseek-v4-flash" {
		t.Fatalf("deepseek preset = %#v", deepSeek)
	}
	if !containsString(deepSeek.Models, "deepseek-v4-flash") ||
		!containsString(deepSeek.Models, "deepseek-v4-pro") ||
		!containsString(deepSeek.Models, "deepseek-chat") ||
		!containsString(deepSeek.Models, "deepseek-reasoner") {
		t.Fatalf("deepseek models = %#v, want current v4 models and legacy compatibility options", deepSeek.Models)
	}
}

func containsString(values []string, want string) bool {
	for _, value := range values {
		if value == want {
			return true
		}
	}
	return false
}

func TestAIProviderProtectsStoredAPIKeyWhenEncryptionSecretConfigured(t *testing.T) {
	_, repos, userID := newAIProviderTestService(t)
	svc := NewAIProviderService(
		repos.AIProvider,
		NewOpenAICompatibleClient(nil),
		"test-secret-with-at-least-32-characters",
	)

	provider, err := svc.Create(userID, SaveAIProviderRequest{
		Name:    "DeepSeek",
		BaseURL: "https://api.deepseek.com",
		APIKey:  "sk-secret",
		Model:   "deepseek-chat",
		Enabled: true,
	})
	if err != nil {
		t.Fatalf("create provider: %v", err)
	}

	stored, err := repos.AIProvider.GetByID(provider.ID)
	if err != nil {
		t.Fatalf("get stored provider: %v", err)
	}
	if stored.APIKeyCiphertext == "sk-secret" {
		t.Fatal("stored api key was not encrypted")
	}
	if !strings.HasPrefix(stored.APIKeyCiphertext, aiSecretPrefix) {
		t.Fatalf("stored api key prefix = %q, want encrypted prefix", stored.APIKeyCiphertext)
	}
	revealed, err := revealAISecret(stored.APIKeyCiphertext, "test-secret-with-at-least-32-characters")
	if err != nil {
		t.Fatalf("reveal stored api key: %v", err)
	}
	if revealed != "sk-secret" {
		t.Fatalf("revealed api key = %q, want original key", revealed)
	}
}

func TestOpenAICompatibleChatCompletionsURL(t *testing.T) {
	cases := map[string]string{
		"https://api.deepseek.com":     "https://api.deepseek.com/chat/completions",
		"https://api.deepseek.com/":    "https://api.deepseek.com/chat/completions",
		"https://api.example.com":      "https://api.example.com/v1/chat/completions",
		"https://api.example.com/":     "https://api.example.com/v1/chat/completions",
		"https://api.example.com/v1":   "https://api.example.com/v1/chat/completions",
		"https://api.example.com/v1/":  "https://api.example.com/v1/chat/completions",
		"https://gateway.local/custom": "https://gateway.local/custom/v1/chat/completions",
	}
	for input, want := range cases {
		got := NormalizeOpenAIChatCompletionsURL(input)
		if got != want {
			t.Fatalf("NormalizeOpenAIChatCompletionsURL(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestAIProviderTestConnectionUsesOpenAICompatibleRequest(t *testing.T) {
	var gotAuth string
	var gotPath string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAuth = r.Header.Get("Authorization")
		gotPath = r.URL.Path
		var payload map[string]any
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			t.Fatalf("decode request: %v", err)
		}
		if payload["model"] != "deepseek-chat" {
			t.Fatalf("model = %v, want deepseek-chat", payload["model"])
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"ok"}}]}`))
	}))
	defer server.Close()

	svc, _, userID := newAIProviderTestService(t)
	provider, err := svc.Create(userID, SaveAIProviderRequest{
		Name:    "Fake",
		BaseURL: server.URL,
		APIKey:  "sk-test",
		Model:   "deepseek-chat",
		Enabled: true,
	})
	if err != nil {
		t.Fatalf("create provider: %v", err)
	}

	if err := svc.TestConnection(provider.ID, userID); err != nil {
		t.Fatalf("test connection: %v", err)
	}
	if gotPath != "/v1/chat/completions" {
		t.Fatalf("request path = %q, want /v1/chat/completions", gotPath)
	}
	if gotAuth != "Bearer sk-test" {
		t.Fatalf("authorization = %q, want bearer key", gotAuth)
	}
}
