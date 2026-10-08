package repository

import (
	"time"

	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

type UserRepository struct {
	db *gorm.DB
}

func NewUserRepository(db *gorm.DB) *UserRepository {
	return &UserRepository{db: db}
}

func (r *UserRepository) Create(user *model.User) error {
	return r.db.Create(user).Error
}

func (r *UserRepository) GetByID(id uint) (*model.User, error) {
	var user model.User
	err := r.db.First(&user, id).Error
	if err != nil {
		return nil, err
	}
	return &user, nil
}

func (r *UserRepository) GetByUsername(username string) (*model.User, error) {
	var user model.User
	err := r.db.Where("username = ?", username).First(&user).Error
	if err != nil {
		return nil, err
	}
	return &user, nil
}

// GetByIDForUpdate serializes authentication state changes for this user on
// databases with row locks. SQLite authentication writers are serialized by
// the service before opening their transaction.
func (r *UserRepository) GetByIDForUpdate(id uint) (*model.User, error) {
	if r.db.Dialector.Name() == "sqlite" {
		// Reserve SQLite's writer lock before the SELECT. A deferred read
		// transaction could otherwise fail to upgrade after an unrelated ledger
		// writer commits. UpdateColumn skips timestamps; the value is unchanged.
		if err := r.db.Model(&model.User{}).Where("id = ?", id).
			UpdateColumn("id", gorm.Expr("id")).Error; err != nil {
			return nil, err
		}
	}
	var user model.User
	err := r.db.Clauses(clause.Locking{Strength: "UPDATE"}).First(&user, id).Error
	return &user, err
}

// UpdateProfile deliberately writes only display fields. Saving a previously
// loaded User would also overwrite a concurrent password or login-state change.
func (r *UserRepository) UpdateProfile(user *model.User) error {
	return r.updateColumns(user.ID, map[string]any{
		"nickname": user.Nickname,
		"email":    user.Email,
		"avatar":   user.Avatar,
		"bio":      user.Bio,
	})
}

func (r *UserRepository) UpdatePasswordHash(id uint, hash string) error {
	return r.updateColumns(id, map[string]any{"password_hash": hash})
}

func (r *UserRepository) RecordFailedLogin(id uint, failCount int, lockedUntil *time.Time) error {
	return r.updateColumns(id, map[string]any{
		"login_fail_count": failCount,
		"locked_until":     lockedUntil,
	})
}

func (r *UserRepository) RecordSuccessfulLogin(id uint, at time.Time) error {
	return r.updateColumns(id, map[string]any{
		"login_fail_count": 0,
		"locked_until":     nil,
		"last_login_at":    at,
	})
}

func (r *UserRepository) updateColumns(id uint, values map[string]any) error {
	result := r.db.Model(&model.User{}).Where("id = ?", id).Updates(values)
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		// MySQL normally reports changed rows, so an idempotent update can
		// return zero for an existing user. Confirm the same active row exists
		// instead of turning an unchanged profile into a false 404. This query
		// keeps the soft-delete scope and still fails for a removed user.
		var user model.User
		return r.db.Select("id").First(&user, "id = ?", id).Error
	}
	return nil
}

func (r *UserRepository) Count() (int64, error) {
	var count int64
	err := r.db.Model(&model.User{}).Count(&count).Error
	return count, err
}

func (r *UserRepository) GetAll() ([]*model.User, error) {
	var users []*model.User
	err := r.db.Find(&users).Error
	return users, err
}

func (r *UserRepository) DB() *gorm.DB {
	return r.db
}
