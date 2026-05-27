package repository

import (
	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

type AIProviderRepository struct {
	db *gorm.DB
}

func NewAIProviderRepository(db *gorm.DB) *AIProviderRepository {
	return &AIProviderRepository{db: db}
}

func (r *AIProviderRepository) Create(provider *model.AIProvider) error {
	if provider.ID == "" {
		provider.ID = uuid.NewString()
	}
	return r.db.Create(provider).Error
}

func (r *AIProviderRepository) GetByID(id string) (*model.AIProvider, error) {
	var provider model.AIProvider
	if err := r.db.First(&provider, "id = ?", id).Error; err != nil {
		return nil, err
	}
	return &provider, nil
}

func (r *AIProviderRepository) GetByUserID(userID uint) ([]model.AIProvider, error) {
	var providers []model.AIProvider
	err := r.db.Where("user_id = ?", userID).
		Order("enabled DESC, created_at ASC").
		Find(&providers).Error
	return providers, err
}

func (r *AIProviderRepository) Update(provider *model.AIProvider) error {
	return r.db.Save(provider).Error
}

func (r *AIProviderRepository) Delete(provider *model.AIProvider) error {
	return r.db.Delete(provider).Error
}

func (r *AIProviderRepository) DB() *gorm.DB {
	return r.db
}
