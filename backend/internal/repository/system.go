package repository

import (
	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

type SystemRepository struct {
	db *gorm.DB
}

func NewSystemRepository(db *gorm.DB) *SystemRepository {
	return &SystemRepository{db: db}
}

func (r *SystemRepository) Get(key string) (string, error) {
	var setting model.SystemSetting
	err := r.db.Where(systemSettingKeyEquals(key)).First(&setting).Error
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
	err := r.db.Where(systemSettingKeyEquals(key)).First(&setting).Error
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
	return r.db.Where(systemSettingKeyEquals(key)).Delete(&model.SystemSetting{}).Error
}

func systemSettingKeyEquals(key string) clause.Expression {
	return clause.Eq{
		Column: clause.Column{Name: "key"},
		Value:  key,
	}
}
