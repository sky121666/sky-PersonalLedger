package repository

import (
	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

type FamilyMemberRepository struct {
	db *gorm.DB
}

func NewFamilyMemberRepository(db *gorm.DB) *FamilyMemberRepository {
	return &FamilyMemberRepository{db: db}
}

func (r *FamilyMemberRepository) Create(member *model.FamilyMember) error {
	if member.ID == "" {
		member.ID = uuid.NewString()
	}
	return r.db.Create(member).Error
}

func (r *FamilyMemberRepository) GetByID(id string) (*model.FamilyMember, error) {
	var member model.FamilyMember
	if err := r.db.First(&member, "id = ?", id).Error; err != nil {
		return nil, err
	}
	return &member, nil
}

func (r *FamilyMemberRepository) GetByUserID(userID uint) ([]model.FamilyMember, error) {
	var members []model.FamilyMember
	err := r.db.Where("user_id = ?", userID).
		Order("is_default DESC, sort_order ASC, created_at ASC").
		Find(&members).Error
	return members, err
}

func (r *FamilyMemberRepository) CountByUserID(userID uint) (int64, error) {
	var count int64
	err := r.db.Model(&model.FamilyMember{}).Where("user_id = ?", userID).Count(&count).Error
	return count, err
}

func (r *FamilyMemberRepository) Update(member *model.FamilyMember) error {
	return r.db.Save(member).Error
}

func (r *FamilyMemberRepository) ClearDefault(userID uint, exceptID string) error {
	query := r.db.Model(&model.FamilyMember{}).Where("user_id = ?", userID)
	if exceptID != "" {
		query = query.Where("id <> ?", exceptID)
	}
	return query.Update("is_default", false).Error
}
