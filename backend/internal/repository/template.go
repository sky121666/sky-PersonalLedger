package repository

import (
	"time"

	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

type TemplateRepository struct {
	db *gorm.DB
}

func NewTemplateRepository(db *gorm.DB) *TemplateRepository {
	return &TemplateRepository{db: db}
}

func (r *TemplateRepository) Create(template *model.QuickTemplate) error {
	return r.db.Create(template).Error
}

func (r *TemplateRepository) CreateWithDB(db *gorm.DB, template *model.QuickTemplate) error {
	return db.Create(template).Error
}

func (r *TemplateRepository) GetByID(id string) (*model.QuickTemplate, error) {
	var template model.QuickTemplate
	err := r.db.First(&template, "id = ?", id).Error
	if err != nil {
		return nil, err
	}
	return &template, nil
}

func (r *TemplateRepository) GetByIDForUser(id string, userID uint) (*model.QuickTemplate, error) {
	return r.GetByIDForUserWithDB(r.db, id, userID)
}

func (r *TemplateRepository) GetByIDForUserWithDB(db *gorm.DB, id string, userID uint) (*model.QuickTemplate, error) {
	var template model.QuickTemplate
	if err := db.First(&template, "id = ? AND user_id = ?", id, userID).Error; err != nil {
		return nil, err
	}
	return &template, nil
}

func (r *TemplateRepository) GetByUserID(userID uint) ([]model.QuickTemplate, error) {
	var templates []model.QuickTemplate
	err := r.db.Where("user_id = ?", userID).Order("used_count DESC, last_used_at DESC").Find(&templates).Error
	return templates, err
}

func (r *TemplateRepository) Update(template *model.QuickTemplate) error {
	return r.db.Save(template).Error
}

func (r *TemplateRepository) IncrementUsageWithDB(db *gorm.DB, id string, userID uint, usedAt time.Time) error {
	result := db.Model(&model.QuickTemplate{}).
		Where("id = ? AND user_id = ?", id, userID).
		Updates(map[string]any{
			"used_count":   gorm.Expr("used_count + 1"),
			"last_used_at": usedAt,
		})
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected != 1 {
		return gorm.ErrRecordNotFound
	}
	return nil
}

func (r *TemplateRepository) Delete(id string) error {
	return r.db.Delete(&model.QuickTemplate{}, "id = ?", id).Error
}

func (r *TemplateRepository) DeleteForUser(id string, userID uint) error {
	result := r.db.Where("id = ? AND user_id = ?", id, userID).Delete(&model.QuickTemplate{})
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected != 1 {
		return gorm.ErrRecordNotFound
	}
	return nil
}

func (r *TemplateRepository) DeleteAllByUserID(userID uint) error {
	return r.db.Where("user_id = ?", userID).Delete(&model.QuickTemplate{}).Error
}
