package model

import (
	"time"
)

// APIToken API令牌，用于App身份验证
type APIToken struct {
	ID          uint       `gorm:"primarykey" json:"id"`
	UserID      uint       `gorm:"index" json:"user_id"`
	Name        string     `gorm:"size:100" json:"name"`
	Token       string     `gorm:"size:64;uniqueIndex" json:"-"` // 不暴露完整令牌
	TokenPrefix string     `gorm:"size:16" json:"token_prefix"`  // 安全前缀用于识别
	Scopes      string     `gorm:"size:512;not null;default:''" json:"-"`
	LastUsedAt  *time.Time `json:"last_used_at"`
	ExpiresAt   *time.Time `json:"expires_at"` // nil表示永不过期
	RevokedAt   *time.Time `gorm:"index" json:"revoked_at,omitempty"`
	CreatedAt   time.Time  `json:"created_at"`
}

// APITokenResponse 创建新令牌时返回（仅此一次显示完整令牌）
type APITokenResponse struct {
	ID          uint       `json:"id"`
	Name        string     `json:"name"`
	Token       string     `json:"token"` // 完整令牌，仅显示一次
	TokenPrefix string     `json:"token_prefix"`
	Scopes      []string   `json:"scopes"`
	ExpiresAt   *time.Time `json:"expires_at"`
	CreatedAt   time.Time  `json:"created_at"`
}
