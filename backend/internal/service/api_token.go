package service

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"strings"
	"time"

	"github.com/sky/personal-ledger/internal/authz"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"gorm.io/gorm"
)

var ErrInvalidAPITokenScopes = errors.New("invalid api token scopes")
var ErrInvalidAPITokenName = errors.New("invalid api token name")
var ErrInvalidAPITokenExpiry = errors.New("invalid api token expiry")
var ErrAPITokenNotFound = errors.New("api token not found")

const maxAPITokenExpiryDays = 3650

type APITokenSummary struct {
	ID          uint       `json:"id"`
	Name        string     `json:"name"`
	TokenPrefix string     `json:"token_prefix"`
	Scopes      []string   `json:"scopes"`
	LastUsedAt  *time.Time `json:"last_used_at"`
	ExpiresAt   *time.Time `json:"expires_at"`
	CreatedAt   time.Time  `json:"created_at"`
}

// APITokenService API令牌服务
type APITokenService struct {
	repo *repository.APITokenRepository
}

func NewAPITokenService(repo *repository.APITokenRepository) *APITokenService {
	return &APITokenService{repo: repo}
}

// GenerateToken 生成新的API令牌
func (s *APITokenService) GenerateToken(userID uint, name string, expiresInDays int, requestedScopes ...[]string) (*model.APITokenResponse, error) {
	name = strings.TrimSpace(name)
	if name == "" || len([]rune(name)) > 100 {
		return nil, ErrInvalidAPITokenName
	}
	if expiresInDays < 0 || expiresInDays > maxAPITokenExpiryDays {
		return nil, ErrInvalidAPITokenExpiry
	}
	scopes := append([]string(nil), authz.AllowedAPITokenScopes...)
	if len(requestedScopes) > 0 && len(requestedScopes[0]) > 0 {
		normalized, ok := authz.NormalizeScopes(requestedScopes[0])
		if !ok || len(normalized) == 0 {
			return nil, ErrInvalidAPITokenScopes
		}
		scopes = normalized
	}
	encodedScopes, err := json.Marshal(scopes)
	if err != nil {
		return nil, err
	}

	// 生成随机令牌。固定产品前缀用于在日志和密钥扫描中快速识别，
	// 数据库中只保存 SHA-256 摘要。
	tokenBytes := make([]byte, 32)
	if _, err := rand.Read(tokenBytes); err != nil {
		return nil, err
	}
	token := "plk_" + hex.EncodeToString(tokenBytes)

	var expiresAt *time.Time
	if expiresInDays > 0 {
		t := time.Now().AddDate(0, 0, expiresInDays)
		expiresAt = &t
	}

	apiToken := &model.APIToken{
		UserID:      userID,
		Name:        name,
		Token:       hashAPIToken(token),
		TokenPrefix: token[:12],
		Scopes:      string(encodedScopes),
		ExpiresAt:   expiresAt,
	}

	if err := s.repo.Create(apiToken); err != nil {
		return nil, err
	}

	return &model.APITokenResponse{
		ID:          apiToken.ID,
		Name:        apiToken.Name,
		Token:       token, // 完整令牌仅显示一次
		TokenPrefix: apiToken.TokenPrefix,
		Scopes:      scopes,
		ExpiresAt:   apiToken.ExpiresAt,
		CreatedAt:   apiToken.CreatedAt,
	}, nil
}

// ValidateToken 验证API令牌并返回用户ID
func (s *APITokenService) ValidatePrincipal(token string) (authz.Principal, error) {
	normalizedToken := strings.TrimSpace(token)
	if normalizedToken == "" {
		return authz.Principal{}, errors.New("invalid token")
	}

	tokenHash := hashAPIToken(normalizedToken)
	apiToken, err := s.repo.FindByToken(tokenHash)
	if err != nil {
		apiToken, err = s.repo.FindByToken(normalizedToken)
		if err != nil {
			return authz.Principal{}, errors.New("invalid token")
		}
		if err := s.repo.UpdateToken(apiToken.ID, tokenHash); err != nil {
			// Fail closed: a legacy plaintext token must not remain usable when
			// its one-way migration cannot be persisted.
			return authz.Principal{}, errors.New("invalid token")
		}
	}

	// 检查过期
	if apiToken.ExpiresAt != nil && time.Now().After(*apiToken.ExpiresAt) {
		return authz.Principal{}, errors.New("token expired")
	}

	scopes, err := decodeAPITokenScopes(apiToken.Scopes)
	if err != nil {
		return authz.Principal{}, err
	}

	if err := s.repo.UpdateLastUsed(apiToken.ID); err != nil {
		return authz.Principal{}, errors.New("invalid token")
	}
	return authz.Principal{UserID: apiToken.UserID, CredentialType: authz.CredentialAPIToken, Scopes: scopes}, nil
}

func (s *APITokenService) ValidateToken(token string) (uint, error) {
	principal, err := s.ValidatePrincipal(token)
	if err != nil {
		return 0, err
	}
	return principal.UserID, nil
}

// ListTokens 返回用户的所有令牌
func (s *APITokenService) ListTokens(userID uint) ([]APITokenSummary, error) {
	tokens, err := s.repo.FindByUserID(userID)
	if err != nil {
		return nil, err
	}
	result := make([]APITokenSummary, 0, len(tokens))
	for _, token := range tokens {
		scopes, err := decodeAPITokenScopes(token.Scopes)
		if err != nil {
			return nil, err
		}
		result = append(result, APITokenSummary{
			ID: token.ID, Name: token.Name, TokenPrefix: token.TokenPrefix,
			Scopes: scopes, LastUsedAt: token.LastUsedAt,
			ExpiresAt: token.ExpiresAt, CreatedAt: token.CreatedAt,
		})
	}
	return result, nil
}

// DeleteToken 删除令牌
func (s *APITokenService) DeleteToken(id uint, userID uint) error {
	if err := s.repo.Delete(id, userID); err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrAPITokenNotFound
		}
		return err
	}
	return nil
}

func decodeAPITokenScopes(encoded string) ([]string, error) {
	if strings.TrimSpace(encoded) == "" {
		return append([]string(nil), authz.AllowedAPITokenScopes...), nil
	}
	var stored []string
	if err := json.Unmarshal([]byte(encoded), &stored); err != nil {
		return nil, errors.New("invalid token scopes")
	}
	normalized, ok := authz.NormalizeScopes(stored)
	if !ok || len(normalized) == 0 {
		return nil, errors.New("invalid token scopes")
	}
	return normalized, nil
}

func hashAPIToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}
