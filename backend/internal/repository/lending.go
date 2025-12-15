package repository

import (
	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

type LendingRepository struct {
	db *gorm.DB
}

func NewLendingRepository(db *gorm.DB) *LendingRepository {
	return &LendingRepository{db: db}
}

func (r *LendingRepository) Create(lending *model.Lending) error {
	return r.db.Create(lending).Error
}

func (r *LendingRepository) GetByID(id string) (*model.Lending, error) {
	var lending model.Lending
	err := r.db.Preload("Account").First(&lending, "id = ?", id).Error
	return &lending, err
}

func (r *LendingRepository) GetByUserID(userID uint, includeSettled bool) ([]*model.Lending, error) {
	var lendings []*model.Lending
	query := r.db.Where("user_id = ?", userID).Preload("Account").Order("lend_date DESC")

	if !includeSettled {
		query = query.Where("is_settled = ?", false)
	}

	err := query.Find(&lendings).Error
	return lendings, err
}

func (r *LendingRepository) Update(lending *model.Lending) error {
	return r.db.Save(lending).Error
}

func (r *LendingRepository) Delete(id string) error {
	return r.db.Delete(&model.Lending{}, "id = ?", id).Error
}

func (r *LendingRepository) CreateRecord(record *model.LendingRecord) error {
	return r.db.Create(record).Error
}

func (r *LendingRepository) GetRecordsByLendingID(lendingID string) ([]*model.LendingRecord, error) {
	var records []*model.LendingRecord
	err := r.db.Where("lending_id = ?", lendingID).
		Preload("Account").
		Preload("Transaction").
		Order("record_date DESC").
		Find(&records).Error
	return records, err
}

func (r *LendingRepository) GetRecordByID(id string) (*model.LendingRecord, error) {
	var record model.LendingRecord
	err := r.db.Preload("Account").Preload("Transaction").First(&record, "id = ?", id).Error
	return &record, err
}

func (r *LendingRepository) DeleteRecord(id string) error {
	return r.db.Delete(&model.LendingRecord{}, "id = ?", id).Error
}
