package model

import "time"

// RepaymentRequest is committed atomically with its financial effects. Hashes
// retain retry protection without storing the client key or request payload.
type RepaymentRequest struct {
	UserID      uint      `gorm:"primaryKey;autoIncrement:false" json:"user_id"`
	Operation   string    `gorm:"primaryKey;size:20" json:"operation"`
	TargetID    string    `gorm:"primaryKey;size:36" json:"target_id"`
	KeyHash     string    `gorm:"primaryKey;size:64" json:"key_hash"`
	PayloadHash string    `gorm:"size:64;not null" json:"payload_hash"`
	CreatedAt   time.Time `json:"created_at"`
}
