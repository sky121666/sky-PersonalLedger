package repository

import (
	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

// APITokenRepository API令牌仓库
type APITokenRepository struct {
	db *gorm.DB
}

func NewAPITokenRepository(db *gorm.DB) *APITokenRepository {
	return &APITokenRepository{db: db}
}

func (r *APITokenRepository) Create(token *model.APIToken) error {
	return r.db.Create(token).Error
}

func (r *APITokenRepository) FindByToken(token string) (*model.APIToken, error) {
	var t model.APIToken
	err := r.db.Where("token = ?", token).First(&t).Error
	if err != nil {
		return nil, err
	}
	return &t, nil
}

func (r *APITokenRepository) FindByUserID(userID uint) ([]model.APIToken, error) {
	var tokens []model.APIToken
	err := r.db.Where("user_id = ?", userID).Order("created_at DESC").Find(&tokens).Error
	return tokens, err
}

func (r *APITokenRepository) Delete(id uint, userID uint) error {
	return r.db.Where("id = ? AND user_id = ?", id, userID).Delete(&model.APIToken{}).Error
}

func (r *APITokenRepository) UpdateLastUsed(id uint) error {
	return r.db.Model(&model.APIToken{}).Where("id = ?", id).Update("last_used_at", gorm.Expr("CURRENT_TIMESTAMP")).Error
}

func (r *APITokenRepository) UpdateToken(id uint, tokenHash string) error {
	return r.db.Model(&model.APIToken{}).Where("id = ?", id).Update("token", tokenHash).Error
}

func (r *APITokenRepository) DB() *gorm.DB {
	return r.db
}
