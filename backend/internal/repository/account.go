package repository

import (
	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

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

func (r *AccountRepository) Update(account *model.Account) error {
	return r.db.Save(account).Error
}

func (r *AccountRepository) Delete(id string) error {
	return r.db.Delete(&model.Account{}, "id = ?", id).Error
}

func (r *AccountRepository) DeleteAllByUserID(userID uint) error {
	return r.db.Where("user_id = ?", userID).Delete(&model.Account{}).Error
}

func (r *AccountRepository) UpdateBalance(id string, amount float64) error {
	return r.db.Model(&model.Account{}).Where("id = ?", id).
		Update("current_balance", gorm.Expr("current_balance + ?", amount)).Error
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
