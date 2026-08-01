package service

import (
	"encoding/json"
	"errors"

	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

var (
	ErrTagNotFound = errors.New("tag not found")
	ErrTagExists   = errors.New("tag with this name already exists")
)

type TagService struct {
	repo *repository.TagRepository
}

func NewTagService(repo *repository.TagRepository) *TagService {
	return &TagService{repo: repo}
}

type CreateTagRequest struct {
	Name  string `json:"name" binding:"required"`
	Color string `json:"color"`
	Icon  string `json:"icon"`
}

func (s *TagService) Create(userID uint, req CreateTagRequest) (*model.Tag, error) {
	// Check if tag with same name exists
	existing, err := s.repo.GetByName(userID, req.Name)
	if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, err
	}
	if existing != nil {
		return nil, ErrTagExists
	}

	tag := &model.Tag{
		UserID: userID,
		Name:   req.Name,
		Color:  req.Color,
		Icon:   req.Icon,
	}

	if err := s.repo.Create(tag); err != nil {
		return nil, err
	}

	return s.repo.GetByID(tag.ID)
}

func (s *TagService) GetByID(id string, userID uint) (*model.Tag, error) {
	tag, err := s.repo.GetByID(id)
	if err != nil {
		return nil, ErrTagNotFound
	}
	if tag.UserID != userID {
		return nil, ErrTagNotFound
	}
	return tag, nil
}

func (s *TagService) List(userID uint) ([]model.Tag, error) {
	return s.repo.GetByUserID(userID)
}

func (s *TagService) Update(id string, userID uint, req CreateTagRequest) (*model.Tag, error) {
	var updated model.Tag
	err := s.repo.DB().Transaction(func(txdb *gorm.DB) error {
		var tag model.Tag
		if err := txdb.Clauses(clause.Locking{Strength: "UPDATE"}).
			First(&tag, "id = ? AND user_id = ?", id, userID).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return ErrTagNotFound
			}
			return err
		}

		var duplicateCount int64
		if err := txdb.Model(&model.Tag{}).
			Where("user_id = ? AND name = ? AND id <> ?", userID, req.Name, id).
			Count(&duplicateCount).Error; err != nil {
			return err
		}
		if duplicateCount > 0 {
			return ErrTagExists
		}

		usedCount := tag.UsedCount
		if tag.Name != req.Name {
			var err error
			usedCount, err = rewriteTransactionTagNameTx(txdb, userID, tag.Name, req.Name)
			if err != nil {
				return err
			}
		}

		result := txdb.Model(&model.Tag{}).
			Where("id = ? AND user_id = ?", id, userID).
			Updates(map[string]any{
				"name":       req.Name,
				"color":      req.Color,
				"icon":       req.Icon,
				"used_count": usedCount,
			})
		if result.Error != nil {
			return result.Error
		}
		return txdb.First(&updated, "id = ? AND user_id = ?", id, userID).Error
	})
	if err != nil {
		return nil, err
	}
	return &updated, nil
}

func rewriteTransactionTagNameTx(txdb *gorm.DB, userID uint, oldName, newName string) (int, error) {
	var transactions []model.Transaction
	if err := txdb.Select("id", "tags").
		Where("user_id = ? AND COALESCE(tags, '') <> ''", userID).
		Find(&transactions).Error; err != nil {
		return 0, err
	}

	usedCount := 0
	for _, transaction := range transactions {
		names := transactionTagNames(transaction.Tags)
		changed := false
		for index, name := range names {
			if name == oldName {
				names[index] = newName
				changed = true
			}
		}
		names = uniqueSortedStrings(names)
		if containsTagName(names, newName) {
			usedCount++
		}
		if !changed {
			continue
		}
		encoded, err := json.Marshal(names)
		if err != nil {
			return 0, err
		}
		result := txdb.Model(&model.Transaction{}).
			Where("id = ? AND user_id = ?", transaction.ID, userID).
			Update("tags", string(encoded))
		if result.Error != nil {
			return 0, result.Error
		}
		if result.RowsAffected != 1 {
			return 0, ErrTransactionNotFound
		}
	}
	return usedCount, nil
}

func containsTagName(values []string, target string) bool {
	for _, value := range values {
		if value == target {
			return true
		}
	}
	return false
}

func (s *TagService) Delete(id string, userID uint) error {
	tag, err := s.GetByID(id, userID)
	if err != nil {
		return err
	}
	if tag.IsSystem {
		return errors.New("cannot delete system tag")
	}
	return s.repo.Delete(id)
}

func (s *TagService) EnsureSystemTags(userID uint) error {
	return s.repo.CreateSystemTags(userID)
}
