package repository

import (
	"errors"

	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

var ErrAccountBalancePreventsDeletion = errors.New("account balance prevents deletion")
var ErrAccountReferencesPreventDeletion = errors.New("account references prevent deletion")
var ErrUnsafeAccountFieldUpdate = errors.New("unsafe account field update")

var accountMetadataFields = map[string]struct{}{
	"name":               {},
	"icon":               {},
	"color":              {},
	"payment_day":        {},
	"billing_day":        {},
	"credit_limit_cents": {},
	"interest_rate":      {},
	"start_date":         {},
	"target_date":        {},
	"remark":             {},
	"is_archived":        {},
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
	return FinanceWriteTransaction(r.db, func(tx *gorm.DB) error {
		var account model.Account
		if err := FinanceQueryForUpdate(tx).First(&account, "id = ? AND user_id = ?", id, userID).Error; err != nil {
			return err
		}
		// Query references only after the account lock has been acquired. A
		// separate statement observes the writer that released the lock, rather
		// than retaining a pre-wait subquery snapshot on PostgreSQL READ COMMITTED.
		for _, ref := range accountDeletionReferences(id) {
			var count int64
			if err := tx.Unscoped().Table(ref.table).Where(ref.condition, ref.args...).Count(&count).Error; err != nil {
				return err
			}
			if count > 0 {
				return ErrAccountReferencesPreventDeletion
			}
		}
		if !account.IsArchived && account.CurrentBalance != 0 {
			return ErrAccountBalancePreventsDeletion
		}
		result := tx.Where("id = ? AND user_id = ?", id, userID).Delete(&model.Account{})
		if result.Error != nil {
			return result.Error
		}
		if result.RowsAffected != 1 {
			return gorm.ErrRecordNotFound
		}
		return nil
	})
}

type accountDeletionReference struct {
	table, condition string
	args             []any
}

func accountDeletionReferences(id string) []accountDeletionReference {
	refs := []accountDeletionReference{{"transactions", "account_id = ? OR to_account_id = ?", []any{id, id}}}
	for _, table := range []string{"account_logs", "reminders", "lendings", "lending_records", "quick_templates", "recurring_transactions", "debt_plans", "debt_operations"} {
		refs = append(refs, accountDeletionReference{table, "account_id = ?", []any{id}})
	}
	return refs
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
