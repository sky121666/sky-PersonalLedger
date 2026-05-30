package repository

import (
	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

type CategoryRepository struct {
	db *gorm.DB
}

func NewCategoryRepository(db *gorm.DB) *CategoryRepository {
	return &CategoryRepository{db: db}
}

func (r *CategoryRepository) Create(category *model.Category) error {
	return r.db.Create(category).Error
}

func (r *CategoryRepository) GetByID(id string) (*model.Category, error) {
	var category model.Category
	err := r.db.First(&category, "id = ?", id).Error
	if err != nil {
		return nil, err
	}
	return &category, nil
}

func (r *CategoryRepository) GetByUserID(userID uint, categoryType string) ([]model.Category, error) {
	var categories []model.Category
	query := r.db.Where("user_id = ?", userID)
	if categoryType != "" {
		query = query.Where("type = ?", categoryType)
	}
	err := query.Order("sort_order ASC, created_at ASC").Find(&categories).Error
	return categories, err
}

func (r *CategoryRepository) Update(category *model.Category) error {
	return r.db.Save(category).Error
}

func (r *CategoryRepository) Delete(id string) error {
	return r.db.Delete(&model.Category{}, "id = ?", id).Error
}

func (r *CategoryRepository) DeleteAllByUserID(userID uint) error {
	return r.db.Where("user_id = ?", userID).Delete(&model.Category{}).Error
}

func (r *CategoryRepository) CreateBatch(categories []model.Category) error {
	return r.db.Create(&categories).Error
}

func (r *CategoryRepository) DB() *gorm.DB {
	return r.db
}
