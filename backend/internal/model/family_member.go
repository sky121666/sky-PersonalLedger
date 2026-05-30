package model

import (
	"time"

	"gorm.io/gorm"
)

type FamilyMember struct {
	ID           string         `gorm:"primaryKey;size:36" json:"id"`
	UserID       uint           `gorm:"not null;index" json:"user_id"`
	Name         string         `gorm:"size:100;not null" json:"name"`
	Relationship string         `gorm:"size:30" json:"relationship"`
	Avatar       string         `gorm:"size:255" json:"avatar"`
	Color        string         `gorm:"size:20" json:"color"`
	SortOrder    int            `gorm:"default:0" json:"sort_order"`
	IsDefault    bool           `gorm:"default:false;index" json:"is_default"`
	IsEnabled    bool           `gorm:"default:true;index" json:"is_enabled"`
	CreatedAt    time.Time      `json:"created_at"`
	UpdatedAt    time.Time      `json:"updated_at"`
	DeletedAt    gorm.DeletedAt `gorm:"index" json:"-"`
}
