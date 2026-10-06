package repository

import (
	"errors"
	"sync"

	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

var systemSettingWriteMu sync.Mutex

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
	return r.Update(key, func(string) (string, error) { return value, nil })
}

// Update atomically merges a setting with its current persisted value. The
// callback must be short and must not perform network or database operations.
// The process lock also handles first creation on the single-writer deployment.
func (r *SystemRepository) Update(key string, update func(string) (string, error)) error {
	systemSettingWriteMu.Lock()
	defer systemSettingWriteMu.Unlock()
	return r.db.Transaction(func(tx *gorm.DB) error {
		if tx.Dialector.Name() == "sqlite" {
			// Reserve the writer before the SELECT, rather than upgrading a WAL
			// reader after an unrelated writer has committed.
			if err := tx.Model(&model.SystemSetting{}).Where(systemSettingKeyEquals(key)).UpdateColumn("value", gorm.Expr("value")).Error; err != nil {
				return err
			}
		}
		var setting model.SystemSetting
		err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).Where(systemSettingKeyEquals(key)).First(&setting).Error
		missing := errors.Is(err, gorm.ErrRecordNotFound)
		if err != nil && !missing {
			return err
		}
		value, err := update(setting.Value)
		if err != nil {
			return err
		}
		if missing {
			return tx.Create(&model.SystemSetting{Key: key, Value: value}).Error
		}
		return tx.Model(&setting).Update("value", value).Error
	})
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
