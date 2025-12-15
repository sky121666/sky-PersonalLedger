package repository

import (
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

func (r *TemplateRepository) GetByID(id string) (*model.QuickTemplate, error) {
	var template model.QuickTemplate
	err := r.db.First(&template, "id = ?", id).Error
	if err != nil {
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

func (r *TemplateRepository) Delete(id string) error {
	return r.db.Delete(&model.QuickTemplate{}, "id = ?", id).Error
}
