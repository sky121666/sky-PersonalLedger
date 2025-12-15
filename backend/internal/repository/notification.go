package repository

import (
	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

type NotificationRepository struct {
	db *gorm.DB
}

func NewNotificationRepository(db *gorm.DB) *NotificationRepository {
	return &NotificationRepository{db: db}
}

func (r *NotificationRepository) GetByUserID(userID uint) (*model.NotificationSetting, error) {
	var setting model.NotificationSetting
	err := r.db.Where("user_id = ?", userID).First(&setting).Error
	if err != nil {
		return nil, err
	}
	return &setting, nil
}

func (r *NotificationRepository) Create(setting *model.NotificationSetting) error {
	return r.db.Create(setting).Error
}

func (r *NotificationRepository) Update(setting *model.NotificationSetting) error {
	return r.db.Save(setting).Error
}

func (r *NotificationRepository) Upsert(setting *model.NotificationSetting) error {
	var existing model.NotificationSetting
	err := r.db.Where("user_id = ?", setting.UserID).First(&existing).Error
	if err == gorm.ErrRecordNotFound {
		return r.db.Create(setting).Error
	}
	if err != nil {
		return err
	}
	setting.ID = existing.ID
	return r.db.Save(setting).Error
}
