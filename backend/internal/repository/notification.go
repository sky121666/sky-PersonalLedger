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

func (r *NotificationRepository) GetAll() ([]model.NotificationSetting, error) {
	var settings []model.NotificationSetting
	if err := r.db.Order("id ASC").Find(&settings).Error; err != nil {
		return nil, err
	}
	return settings, nil
}

// UpdateSecrets updates only credential columns. Keeping this narrow avoids
// overwriting notification preferences while a legacy credential is migrated.
func (r *NotificationRepository) UpdateSecrets(setting *model.NotificationSetting) error {
	return updateNotificationSecrets(r.db, setting)
}

func (r *NotificationRepository) UpdateSecretsBatch(settings []model.NotificationSetting) error {
	if len(settings) == 0 {
		return nil
	}
	return r.db.Transaction(func(tx *gorm.DB) error {
		for index := range settings {
			if err := updateNotificationSecrets(tx, &settings[index]); err != nil {
				return err
			}
		}
		return nil
	})
}

func updateNotificationSecrets(db *gorm.DB, setting *model.NotificationSetting) error {
	return db.Model(&model.NotificationSetting{}).
		Where("id = ?", setting.ID).
		Select("dingtalk_secret", "smtp_password", "webhook_secret").
		Updates(map[string]interface{}{
			"dingtalk_secret": setting.DingtalkSecret,
			"smtp_password":   setting.SmtpPassword,
			"webhook_secret":  setting.WebhookSecret,
		}).Error
}
