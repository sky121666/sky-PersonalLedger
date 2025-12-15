package repository

import (
	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

type TagRepository struct {
	db *gorm.DB
}

func NewTagRepository(db *gorm.DB) *TagRepository {
	return &TagRepository{db: db}
}

func (r *TagRepository) Create(tag *model.Tag) error {
	if tag.ID == "" {
		tag.ID = uuid.New().String()
	}
	return r.db.Create(tag).Error
}

func (r *TagRepository) GetByID(id string) (*model.Tag, error) {
	var tag model.Tag
	if err := r.db.First(&tag, "id = ?", id).Error; err != nil {
		return nil, err
	}
	return &tag, nil
}

func (r *TagRepository) GetByUserID(userID uint) ([]model.Tag, error) {
	var tags []model.Tag
	if err := r.db.Where("user_id = ?", userID).Order("used_count DESC, name ASC").Find(&tags).Error; err != nil {
		return nil, err
	}
	return tags, nil
}

func (r *TagRepository) GetByName(userID uint, name string) (*model.Tag, error) {
	var tag model.Tag
	if err := r.db.Where("user_id = ? AND name = ?", userID, name).First(&tag).Error; err != nil {
		return nil, err
	}
	return &tag, nil
}

func (r *TagRepository) Update(tag *model.Tag) error {
	return r.db.Save(tag).Error
}

func (r *TagRepository) Delete(id string) error {
	return r.db.Delete(&model.Tag{}, "id = ?", id).Error
}

func (r *TagRepository) DeleteAllByUserID(userID uint) error {
	return r.db.Where("user_id = ?", userID).Delete(&model.Tag{}).Error
}

func (r *TagRepository) IncrementUsedCount(id string) error {
	return r.db.Model(&model.Tag{}).Where("id = ?", id).UpdateColumn("used_count", gorm.Expr("used_count + 1")).Error
}

func (r *TagRepository) DecrementUsedCount(id string) error {
	return r.db.Model(&model.Tag{}).Where("id = ?", id).UpdateColumn("used_count", gorm.Expr("CASE WHEN used_count > 0 THEN used_count - 1 ELSE 0 END")).Error
}

// CreateSystemTags creates default system tags for a user
func (r *TagRepository) CreateSystemTags(userID uint) error {
	systemTags := []model.Tag{
		{ID: uuid.New().String(), UserID: userID, Name: "分期还款", Color: "#F59E0B", Icon: "credit-card", IsSystem: true},
		{ID: uuid.New().String(), UserID: userID, Name: "借贷还款", Color: "#10B981", Icon: "banknote", IsSystem: true},
		{ID: uuid.New().String(), UserID: userID, Name: "定期支出", Color: "#6366F1", Icon: "repeat", IsSystem: true},
		{ID: uuid.New().String(), UserID: userID, Name: "工资收入", Color: "#22C55E", Icon: "wallet", IsSystem: true},
	}

	for _, tag := range systemTags {
		// Check if exists
		var count int64
		r.db.Model(&model.Tag{}).Where("user_id = ? AND name = ?", userID, tag.Name).Count(&count)
		if count == 0 {
			r.db.Create(&tag)
		}
	}
	return nil
}
