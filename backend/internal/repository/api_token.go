package repository

import (
	"time"

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
	err := r.db.Where("token = ? AND revoked_at IS NULL", token).First(&t).Error
	if err != nil {
		return nil, err
	}
	return &t, nil
}

func (r *APITokenRepository) FindByUserID(userID uint) ([]model.APIToken, error) {
	var tokens []model.APIToken
	err := r.db.Where("user_id = ? AND revoked_at IS NULL", userID).Order("created_at DESC").Find(&tokens).Error
	return tokens, err
}

func (r *APITokenRepository) Delete(id uint, userID uint) error {
	result := r.db.Model(&model.APIToken{}).
		Where("id = ? AND user_id = ? AND revoked_at IS NULL", id, userID).
		Update("revoked_at", gorm.Expr("CURRENT_TIMESTAMP"))
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return gorm.ErrRecordNotFound
	}
	return nil
}

func (r *APITokenRepository) UpdateLastUsed(id uint) error {
	// Last-used is operational metadata, not an accounting event. Updating it
	// at most once every five minutes avoids a database write on every API call.
	cutoff := time.Now().Add(-5 * time.Minute)
	result := r.db.Model(&model.APIToken{}).
		Where("id = ? AND revoked_at IS NULL AND (last_used_at IS NULL OR last_used_at < ?)", id, cutoff).
		Update("last_used_at", gorm.Expr("CURRENT_TIMESTAMP"))
	return result.Error
}

func (r *APITokenRepository) UpdateToken(id uint, tokenHash string) error {
	return r.db.Model(&model.APIToken{}).Where("id = ?", id).Update("token", tokenHash).Error
}

func (r *APITokenRepository) DB() *gorm.DB {
	return r.db
}
