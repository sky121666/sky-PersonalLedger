package repository

import (
	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

type AIReportRepository struct {
	db *gorm.DB
}

func NewAIReportRepository(db *gorm.DB) *AIReportRepository {
	return &AIReportRepository{db: db}
}

func (r *AIReportRepository) Create(report *model.AIReport) error {
	if report.ID == "" {
		report.ID = uuid.NewString()
	}
	return r.db.Create(report).Error
}

func (r *AIReportRepository) GetByID(id string) (*model.AIReport, error) {
	var report model.AIReport
	if err := r.db.First(&report, "id = ?", id).Error; err != nil {
		return nil, err
	}
	return &report, nil
}

func (r *AIReportRepository) GetByUserID(userID uint) ([]model.AIReport, error) {
	var reports []model.AIReport
	err := r.db.Where("user_id = ?", userID).
		Order("period_start DESC, created_at DESC").
		Find(&reports).Error
	return reports, err
}

func (r *AIReportRepository) Update(report *model.AIReport) error {
	return r.db.Save(report).Error
}

func (r *AIReportRepository) Delete(report *model.AIReport) error {
	return r.db.Delete(report).Error
}
