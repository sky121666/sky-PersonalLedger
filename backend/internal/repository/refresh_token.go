package repository

import (
	"time"

	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

type RefreshTokenRepository struct {
	db *gorm.DB
}

func NewRefreshTokenRepository(db *gorm.DB) *RefreshTokenRepository {
	return &RefreshTokenRepository{db: db}
}

func (r *RefreshTokenRepository) Create(token *model.RefreshToken) error {
	return r.db.Create(token).Error
}

func (r *RefreshTokenRepository) GetByToken(token string) (*model.RefreshToken, error) {
	var rt model.RefreshToken
	err := r.db.Where("token = ?", token).First(&rt).Error
	if err != nil {
		return nil, err
	}
	return &rt, nil
}

// Consume atomically removes one unexpired refresh token. RowsAffected is the
// compare-and-swap result: concurrent callers can never consume the same token
// twice, even when both validated the JWT before reaching the database.
func (r *RefreshTokenRepository) Consume(token string, userID uint, now time.Time) (bool, error) {
	result := r.db.Where("token = ? AND user_id = ? AND expires_at > ?", token, userID, now).
		Delete(&model.RefreshToken{})
	if result.Error != nil {
		return false, result.Error
	}
	return result.RowsAffected == 1, nil
}

func (r *RefreshTokenRepository) UpdateToken(id string, token string) error {
	return r.db.Model(&model.RefreshToken{}).Where("id = ?", id).Update("token", token).Error
}

func (r *RefreshTokenRepository) Delete(id string) error {
	return r.db.Delete(&model.RefreshToken{}, "id = ?", id).Error
}

func (r *RefreshTokenRepository) DeleteByUserID(userID uint) error {
	return r.db.Where("user_id = ?", userID).Delete(&model.RefreshToken{}).Error
}

func (r *RefreshTokenRepository) DeleteExpired() error {
	return r.db.Where("expires_at < ?", time.Now()).Delete(&model.RefreshToken{}).Error
}
