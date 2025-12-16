package service

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"time"

	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

// APITokenService API令牌服务
type APITokenService struct {
	repo *repository.APITokenRepository
}

func NewAPITokenService(repo *repository.APITokenRepository) *APITokenService {
	return &APITokenService{repo: repo}
}

// GenerateToken 生成新的API令牌
func (s *APITokenService) GenerateToken(userID uint, name string, expiresInDays int) (*model.APITokenResponse, error) {
	// 生成随机令牌
	tokenBytes := make([]byte, 32)
	if _, err := rand.Read(tokenBytes); err != nil {
		return nil, err
	}
	token := hex.EncodeToString(tokenBytes)

	var expiresAt *time.Time
	if expiresInDays > 0 {
		t := time.Now().AddDate(0, 0, expiresInDays)
		expiresAt = &t
	}

	apiToken := &model.APIToken{
		UserID:      userID,
		Name:        name,
		Token:       token,
		TokenPrefix: token[:8],
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
		ExpiresAt:   apiToken.ExpiresAt,
		CreatedAt:   apiToken.CreatedAt,
	}, nil
}

// ValidateToken 验证API令牌并返回用户ID
func (s *APITokenService) ValidateToken(token string) (uint, error) {
	apiToken, err := s.repo.FindByToken(token)
	if err != nil {
		return 0, errors.New("invalid token")
	}

	// 检查过期
	if apiToken.ExpiresAt != nil && time.Now().After(*apiToken.ExpiresAt) {
		return 0, errors.New("token expired")
	}

	// 更新最后使用时间
	go s.repo.UpdateLastUsed(apiToken.ID)

	return apiToken.UserID, nil
}

// ListTokens 返回用户的所有令牌
func (s *APITokenService) ListTokens(userID uint) ([]model.APIToken, error) {
	return s.repo.FindByUserID(userID)
}

// DeleteToken 删除令牌
func (s *APITokenService) DeleteToken(id uint, userID uint) error {
	return s.repo.Delete(id, userID)
}
