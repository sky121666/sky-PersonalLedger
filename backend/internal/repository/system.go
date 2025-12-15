package repository

import (
	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

type SystemRepository struct {
	db *gorm.DB
}

func NewSystemRepository(db *gorm.DB) *SystemRepository {
	return &SystemRepository{db: db}
}

func (r *SystemRepository) Get(key string) (string, error) {
	var setting model.SystemSetting
	err := r.db.Where("key = ?", key).First(&setting).Error
	if err != nil {
		if err == gorm.ErrRecordNotFound {
			return "", nil
		}
		return "", err
	}
	return setting.Value, nil
}

func (r *SystemRepository) Set(key, value string) error {
	var setting model.SystemSetting
	err := r.db.Where("key = ?", key).First(&setting).Error
	if err == gorm.ErrRecordNotFound {
		setting = model.SystemSetting{
			Key:   key,
			Value: value,
		}
		return r.db.Create(&setting).Error
	}
	if err != nil {
		return err
	}
	setting.Value = value
	return r.db.Save(&setting).Error
}

func (r *SystemRepository) Delete(key string) error {
	return r.db.Where("key = ?", key).Delete(&model.SystemSetting{}).Error
}
