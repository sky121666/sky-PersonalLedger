package repository

import (
	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

type BudgetRepository struct {
	db *gorm.DB
}

func NewBudgetRepository(db *gorm.DB) *BudgetRepository {
	return &BudgetRepository{db: db}
}

func (r *BudgetRepository) Create(budget *model.Budget) error {
	return r.db.Create(budget).Error
}

func (r *BudgetRepository) GetByID(id string) (*model.Budget, error) {
	var budget model.Budget
	err := r.db.First(&budget, "id = ?", id).Error
	if err != nil {
		return nil, err
	}
	return &budget, nil
}

func (r *BudgetRepository) GetByUserID(userID uint) ([]model.Budget, error) {
	var budgets []model.Budget
	err := r.db.Preload("Category").Where("user_id = ?", userID).Find(&budgets).Error
	return budgets, err
}

func (r *BudgetRepository) GetTotalBudget(userID uint) (*model.Budget, error) {
	var budget model.Budget
	err := r.db.Where("user_id = ? AND category_id IS NULL", userID).First(&budget).Error
	if err != nil {
		return nil, err
	}
	return &budget, nil
}

func (r *BudgetRepository) Update(budget *model.Budget) error {
	return r.db.Save(budget).Error
}

func (r *BudgetRepository) Delete(id string) error {
	return r.db.Delete(&model.Budget{}, "id = ?", id).Error
}

func (r *BudgetRepository) DeleteAllByUserID(userID uint) error {
	return r.db.Where("user_id = ?", userID).Delete(&model.Budget{}).Error
}
