package repository

import (
	"crypto/sha256"
	"encoding/hex"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

type NotificationLogRepository struct {
	db *gorm.DB
}

func NewNotificationLogRepository(db *gorm.DB) *NotificationLogRepository {
	return &NotificationLogRepository{db: db}
}

func (r *NotificationLogRepository) HasSent(userID uint, notificationType, channel, dedupeKey string) (bool, error) {
	var count int64
	err := r.db.Model(&model.NotificationLog{}).
		Where(
			"user_id = ? AND type = ? AND channel = ? AND status = ?",
			userID,
			notificationType,
			notificationLogDedupeChannel(channel, dedupeKey),
			"sent",
		).
		Count(&count).Error
	return count > 0, err
}

func (r *NotificationLogRepository) Record(
	userID uint,
	notificationType string,
	channel string,
	dedupeKey string,
	title string,
	content string,
	status string,
	errorMessage string,
) error {
	return r.db.Create(&model.NotificationLog{
		ID:      uuid.NewString(),
		UserID:  userID,
		Type:    notificationType,
		Title:   title,
		Content: content,
		Channel: notificationLogDedupeChannel(channel, dedupeKey),
		Status:  status,
		Error:   errorMessage,
	}).Error
}

func notificationLogDedupeChannel(channel, dedupeKey string) string {
	sum := sha256.Sum256([]byte(dedupeKey))
	return "scheduler:" + channel + ":" + hex.EncodeToString(sum[:12])
}
