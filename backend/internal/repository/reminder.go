package repository

import (
	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

type ReminderRepository struct {
	db *gorm.DB
}

func NewReminderRepository(db *gorm.DB) *ReminderRepository {
	return &ReminderRepository{db: db}
}

func (r *ReminderRepository) Create(reminder *model.Reminder) error {
	return r.db.Create(reminder).Error
}

func (r *ReminderRepository) GetByID(id string) (*model.Reminder, error) {
	var reminder model.Reminder
	err := r.db.Preload("Account").First(&reminder, "id = ?", id).Error
	if err != nil {
		return nil, err
	}
	return &reminder, nil
}

func (r *ReminderRepository) GetByUserID(userID uint) ([]model.Reminder, error) {
	var reminders []model.Reminder
	err := r.db.Preload("Account").Where("user_id = ?", userID).Find(&reminders).Error
	return reminders, err
}

func (r *ReminderRepository) ListByAccountID(userID uint, accountID string) ([]model.Reminder, error) {
	var reminders []model.Reminder
	err := r.db.Preload("Account").Where("user_id = ? AND account_id = ?", userID, accountID).Find(&reminders).Error
	return reminders, err
}

func (r *ReminderRepository) Update(reminder *model.Reminder) error {
	return r.db.Save(reminder).Error
}

func (r *ReminderRepository) Delete(id string) error {
	return r.db.Delete(&model.Reminder{}, "id = ?", id).Error
}
