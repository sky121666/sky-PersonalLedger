package model

import (
	"time"

	"gorm.io/gorm"
)

type AIProvider struct {
	ID               string         `gorm:"primaryKey;size:36" json:"id"`
	UserID           uint           `gorm:"not null;index" json:"user_id"`
	Name             string         `gorm:"size:100;not null" json:"name"`
	ProviderType     string         `gorm:"size:50;not null;default:openai_compatible" json:"provider_type"`
	BaseURL          string         `gorm:"size:500;not null" json:"base_url"`
	APIKeyCiphertext string         `gorm:"type:text" json:"-"`
	Model            string         `gorm:"size:100;not null" json:"model"`
	Enabled          bool           `gorm:"default:true" json:"enabled"`
	CreatedAt        time.Time      `json:"created_at"`
	UpdatedAt        time.Time      `json:"updated_at"`
	DeletedAt        gorm.DeletedAt `gorm:"index" json:"-"`
}

type AIReport struct {
	ID            string         `gorm:"primaryKey;size:36" json:"id"`
	UserID        uint           `gorm:"not null;index" json:"user_id"`
	ReportType    string         `gorm:"size:30;not null;index" json:"report_type"`
	PeriodStart   time.Time      `gorm:"not null;index" json:"period_start"`
	PeriodEnd     time.Time      `gorm:"not null;index" json:"period_end"`
	Status        string         `gorm:"size:30;not null;default:pending" json:"status"`
	SnapshotJSON  string         `gorm:"type:text" json:"snapshot_json"`
	ContentJSON   string         `gorm:"type:text" json:"content_json"`
	ProviderID    string         `gorm:"size:36;index" json:"provider_id"`
	ProviderName  string         `gorm:"size:100" json:"provider_name"`
	Model         string         `gorm:"size:100" json:"model"`
	PromptVersion string         `gorm:"size:30" json:"prompt_version"`
	ErrorMessage  string         `gorm:"type:text" json:"error_message,omitempty"`
	CreatedAt     time.Time      `json:"created_at"`
	UpdatedAt     time.Time      `json:"updated_at"`
	DeletedAt     gorm.DeletedAt `gorm:"index" json:"-"`
}
