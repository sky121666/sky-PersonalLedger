package service

import (
	"context"
	"errors"
	"fmt"
	"net/url"
	"strings"
	"time"

	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

var (
	ErrAIProviderNotFound        = errors.New("ai provider not found")
	ErrAIProviderNameRequired    = errors.New("ai provider name is required")
	ErrAIProviderBaseURLRequired = errors.New("ai provider base url is required")
	ErrAIProviderBaseURLInvalid  = errors.New("ai provider base url is invalid")
	ErrAIProviderModelRequired   = errors.New("ai provider model is required")
	ErrAIProviderTypeUnsupported = errors.New("ai provider type is unsupported")
)

const aiProviderTypeOpenAICompatible = "openai_compatible"

type AIProviderService struct {
	repo                 *repository.AIProviderRepository
	client               *OpenAICompatibleClient
	credentialKeys       credentialKeyring
	allowPrivateNetworks bool
}

func NewAIProviderService(repo *repository.AIProviderRepository, client *OpenAICompatibleClient, encryptionSecrets ...string) *AIProviderService {
	if client == nil {
		client = NewOpenAICompatibleClient(nil)
	}
	return &AIProviderService{
		repo:           repo,
		client:         client,
		credentialKeys: newCredentialKeyring(encryptionSecrets...),
	}
}

// WithPrivateOutboundNetworks enables local/private AI gateways only when the
// server operator has explicitly opted in through trusted configuration.
func (s *AIProviderService) WithPrivateOutboundNetworks(allow bool) *AIProviderService {
	s.allowPrivateNetworks = allow
	if s.client == nil || s.client.allowPrivateNetworks != allow {
		s.client = NewOpenAICompatibleClient(nil, allow)
	}
	return s
}

type SaveAIProviderRequest struct {
	Name         string `json:"name" binding:"required"`
	ProviderType string `json:"provider_type"`
	BaseURL      string `json:"base_url" binding:"required"`
	APIKey       string `json:"api_key"`
	Model        string `json:"model" binding:"required"`
	Enabled      bool   `json:"enabled"`
}

type AIProviderResponse struct {
	ID           string    `json:"id"`
	UserID       uint      `json:"user_id"`
	Name         string    `json:"name"`
	ProviderType string    `json:"provider_type"`
	BaseURL      string    `json:"base_url"`
	APIKey       string    `json:"api_key,omitempty"`
	Model        string    `json:"model"`
	Enabled      bool      `json:"enabled"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

type AIProviderPresetResponse struct {
	ID           string   `json:"id"`
	Name         string   `json:"name"`
	ProviderType string   `json:"provider_type"`
	BaseURL      string   `json:"base_url"`
	Model        string   `json:"model"`
	Models       []string `json:"models"`
}

func (s *AIProviderService) ListPresets() []AIProviderPresetResponse {
	return []AIProviderPresetResponse{
		{
			ID:           "deepseek",
			Name:         "DeepSeek",
			ProviderType: aiProviderTypeOpenAICompatible,
			BaseURL:      "https://api.deepseek.com",
			Model:        "deepseek-v4-flash",
			Models:       []string{"deepseek-v4-flash", "deepseek-v4-pro", "deepseek-chat", "deepseek-reasoner"},
		},
		{
			ID:           "openai",
			Name:         "OpenAI",
			ProviderType: aiProviderTypeOpenAICompatible,
			BaseURL:      "https://api.openai.com",
			Model:        "gpt-4.1-mini",
			Models:       []string{"gpt-4.1-mini", "gpt-4.1", "gpt-4o-mini"},
		},
		{
			ID:           "siliconflow",
			Name:         "SiliconFlow",
			ProviderType: aiProviderTypeOpenAICompatible,
			BaseURL:      "https://api.siliconflow.cn",
			Model:        "deepseek-ai/DeepSeek-V3",
			Models:       []string{"deepseek-ai/DeepSeek-V3", "deepseek-ai/DeepSeek-R1"},
		},
		{
			ID:           "openai-compatible",
			Name:         "OpenAI-compatible",
			ProviderType: aiProviderTypeOpenAICompatible,
			BaseURL:      "https://your-gateway.example.com",
			Model:        "model-name",
			Models:       []string{"model-name"},
		},
	}
}

func (s *AIProviderService) Create(userID uint, req SaveAIProviderRequest) (*AIProviderResponse, error) {
	normalized, err := normalizeSaveAIProviderRequest(req, s.allowPrivateNetworks)
	if err != nil {
		return nil, err
	}
	protectedKey, err := protectAISecret(req.APIKey, s.credentialKeys.primary())
	if err != nil {
		return nil, err
	}
	provider := &model.AIProvider{
		UserID:           userID,
		Name:             normalized.Name,
		ProviderType:     normalized.ProviderType,
		BaseURL:          normalized.BaseURL,
		APIKeyCiphertext: protectedKey,
		Model:            normalized.Model,
		Enabled:          req.Enabled,
	}
	if err := s.repo.Create(provider); err != nil {
		return nil, err
	}
	return aiProviderResponse(provider), nil
}

func (s *AIProviderService) List(userID uint) ([]AIProviderResponse, error) {
	providers, err := s.repo.GetByUserID(userID)
	if err != nil {
		return nil, err
	}
	responses := make([]AIProviderResponse, 0, len(providers))
	for i := range providers {
		responses = append(responses, *aiProviderResponse(&providers[i]))
	}
	return responses, nil
}

func (s *AIProviderService) Update(id string, userID uint, req SaveAIProviderRequest) (*AIProviderResponse, error) {
	provider, err := s.getOwnedProvider(id, userID)
	if err != nil {
		return nil, err
	}
	normalized, err := normalizeSaveAIProviderRequest(req, s.allowPrivateNetworks)
	if err != nil {
		return nil, err
	}

	provider.Name = normalized.Name
	provider.ProviderType = normalized.ProviderType
	provider.BaseURL = normalized.BaseURL
	if strings.TrimSpace(req.APIKey) != "" {
		protectedKey, err := protectAISecret(req.APIKey, s.credentialKeys.primary())
		if err != nil {
			return nil, err
		}
		provider.APIKeyCiphertext = protectedKey
	}
	provider.Model = normalized.Model
	provider.Enabled = req.Enabled

	if err := s.repo.Update(provider); err != nil {
		return nil, err
	}
	return aiProviderResponse(provider), nil
}

func (s *AIProviderService) Delete(id string, userID uint) error {
	provider, err := s.getOwnedProvider(id, userID)
	if err != nil {
		return err
	}
	return s.repo.Delete(provider)
}

func (s *AIProviderService) TestConnection(id string, userID uint) error {
	provider, err := s.getOwnedProvider(id, userID)
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	apiKey, err := revealAISecretWithKeyring(provider.APIKeyCiphertext, s.credentialKeys)
	if err != nil {
		return err
	}
	return s.client.TestConnection(ctx, provider.BaseURL, apiKey, provider.Model)
}

// MigrateStoredSecrets validates every provider credential before updating any
// row. Fallback-key ciphertext and legacy plaintext are re-encrypted with the
// active key in a single transaction.
func (s *AIProviderService) MigrateStoredSecrets() error {
	changedProviders, err := s.prepareStoredSecretMigration()
	if err != nil {
		return err
	}
	if err := s.repo.UpdateSecretsBatch(changedProviders); err != nil {
		return fmt.Errorf("persist migrated AI provider credentials: %w", err)
	}
	return nil
}

func (s *AIProviderService) prepareStoredSecretMigration() ([]model.AIProvider, error) {
	providers, err := s.repo.GetAll()
	if err != nil {
		return nil, fmt.Errorf("load AI providers for credential migration: %w", err)
	}
	changedProviders := make([]model.AIProvider, 0, len(providers))
	for index := range providers {
		migrated, changed, err := migrateAISecret(providers[index].APIKeyCiphertext, s.credentialKeys)
		if err != nil {
			return nil, fmt.Errorf("migrate AI provider credential %s: %w", providers[index].ID, err)
		}
		if changed {
			providers[index].APIKeyCiphertext = migrated
			changedProviders = append(changedProviders, providers[index])
		}
	}
	return changedProviders, nil
}

func (s *AIProviderService) getOwnedProvider(id string, userID uint) (*model.AIProvider, error) {
	provider, err := s.repo.GetByID(id)
	if err != nil || provider.UserID != userID {
		return nil, ErrAIProviderNotFound
	}
	return provider, nil
}

func normalizeSaveAIProviderRequest(req SaveAIProviderRequest, allowPrivateNetworks bool) (SaveAIProviderRequest, error) {
	req.Name = strings.TrimSpace(req.Name)
	req.ProviderType = strings.TrimSpace(req.ProviderType)
	req.BaseURL = strings.TrimRight(strings.TrimSpace(req.BaseURL), "/")
	req.Model = strings.TrimSpace(req.Model)
	if req.Name == "" {
		return req, ErrAIProviderNameRequired
	}
	if req.ProviderType == "" {
		req.ProviderType = aiProviderTypeOpenAICompatible
	}
	if req.ProviderType != aiProviderTypeOpenAICompatible {
		return req, ErrAIProviderTypeUnsupported
	}
	if req.BaseURL == "" {
		return req, ErrAIProviderBaseURLRequired
	}
	if !isValidAIProviderBaseURL(req.BaseURL, allowPrivateNetworks) {
		return req, ErrAIProviderBaseURLInvalid
	}
	if req.Model == "" {
		return req, ErrAIProviderModelRequired
	}
	return req, nil
}

func isValidAIProviderBaseURL(baseURL string, allowPrivateNetworks bool) bool {
	parsed, err := url.ParseRequestURI(baseURL)
	if err != nil || parsed == nil {
		return false
	}
	if parsed.Host == "" {
		return false
	}
	if parsed.User != nil || parsed.RawQuery != "" || parsed.Fragment != "" {
		return false
	}
	return validateOutboundURL(baseURL, allowPrivateNetworks) == nil
}

func aiProviderResponse(provider *model.AIProvider) *AIProviderResponse {
	return &AIProviderResponse{
		ID:           provider.ID,
		UserID:       provider.UserID,
		Name:         provider.Name,
		ProviderType: provider.ProviderType,
		BaseURL:      provider.BaseURL,
		Model:        provider.Model,
		Enabled:      provider.Enabled,
		CreatedAt:    provider.CreatedAt,
		UpdatedAt:    provider.UpdatedAt,
	}
}
