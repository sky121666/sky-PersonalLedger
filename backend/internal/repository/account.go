package repository

import (
	"errors"

	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

var ErrAccountBalancePreventsDeletion = errors.New("account balance prevents deletion")
var ErrUnsafeAccountFieldUpdate = errors.New("unsafe account field update")

var accountMetadataFields = map[string]struct{}{
	"name":          {},
	"icon":          {},
	"color":         {},
	"payment_day":   {},
	"billing_day":   {},
	"credit_limit":  {},
	"interest_rate": {},
	"start_date":    {},
	"target_date":   {},
	"remark":        {},
	"is_archived":   {},
}

type AccountRepository struct {
	db *gorm.DB
}

func NewAccountRepository(db *gorm.DB) *AccountRepository {
	return &AccountRepository{db: db}
}

func (r *AccountRepository) Create(account *model.Account) error {
	return r.db.Create(account).Error
}

func (r *AccountRepository) GetByID(id string) (*model.Account, error) {
	var account model.Account
	err := r.db.First(&account, "id = ?", id).Error
	if err != nil {
		return nil, err
	}
	return &account, nil
}

func (r *AccountRepository) GetByUserID(userID uint, includeArchived bool) ([]model.Account, error) {
	var accounts []model.Account
	query := r.db.Where("user_id = ?", userID)
	if !includeArchived {
		query = query.Where("is_archived = ?", false)
	}
	err := query.Order("sort_order ASC, created_at ASC").Find(&accounts).Error
	return accounts, err
}

func (r *AccountRepository) GetByUserIDForHistory(userID uint) ([]model.Account, error) {
	var accounts []model.Account
	err := r.db.Unscoped().Where("user_id = ?", userID).
		Order("created_at ASC, id ASC").
		Find(&accounts).Error
	return accounts, err
}

func (r *AccountRepository) UpdateMetadataForUser(id string, userID uint, updates map[string]any) error {
	for field := range updates {
		if _, ok := accountMetadataFields[field]; !ok {
			return ErrUnsafeAccountFieldUpdate
		}
	}
	result := r.db.Model(&model.Account{}).
		Where("id = ? AND user_id = ?", id, userID).
		Updates(updates)
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected != 1 {
		var count int64
		if err := r.db.Model(&model.Account{}).Where("id = ? AND user_id = ?", id, userID).Count(&count).Error; err != nil {
			return err
		}
		if count == 0 {
			return gorm.ErrRecordNotFound
		}
	}
	return nil
}

func (r *AccountRepository) DeleteForUserIfBalanceAllows(id string, userID uint) error {
	result := r.db.
		Where("id = ? AND user_id = ? AND (is_archived = ? OR current_balance = ?)", id, userID, true, 0).
		Delete(&model.Account{})
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 1 {
		return nil
	}

	var account model.Account
	if err := r.db.Select("id", "current_balance", "is_archived").
		First(&account, "id = ? AND user_id = ?", id, userID).Error; err != nil {
		return err
	}
	if !account.IsArchived && account.CurrentBalance != 0 {
		return ErrAccountBalancePreventsDeletion
	}
	return gorm.ErrRecordNotFound
}

func (r *AccountRepository) DeleteAllByUserID(userID uint) error {
	return r.db.Where("user_id = ?", userID).Delete(&model.Account{}).Error
}

func (r *AccountRepository) UpdateSortOrder(ids []string) error {
	return r.db.Transaction(func(tx *gorm.DB) error {
		for i, id := range ids {
			if err := tx.Model(&model.Account{}).Where("id = ?", id).
				Update("sort_order", i).Error; err != nil {
				return err
			}
		}
		return nil
	})
}

func (r *AccountRepository) CreateBatch(accounts []model.Account) error {
	return r.db.Create(&accounts).Error
}

func (r *AccountRepository) DB() *gorm.DB {
	return r.db
}
