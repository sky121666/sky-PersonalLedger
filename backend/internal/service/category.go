package service

import (
	"errors"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

var (
	ErrCategoryNotFound        = errors.New("category not found")
	ErrSystemCategoryProtected = errors.New("system category cannot be modified or deleted")
)

type CategoryService struct {
	repo *repository.CategoryRepository
}

func NewCategoryService(repo *repository.CategoryRepository) *CategoryService {
	return &CategoryService{repo: repo}
}

type CreateCategoryRequest struct {
	Name  string `json:"name" binding:"required"`
	Type  string `json:"type" binding:"required,oneof=income expense"`
	Icon  string `json:"icon"`
	Color string `json:"color"`
}

func (s *CategoryService) Create(userID uint, req CreateCategoryRequest) (*model.Category, error) {
	category := &model.Category{
		ID:     uuid.New().String(),
		UserID: userID,
		Name:   req.Name,
		Type:   req.Type,
		Icon:   req.Icon,
		Color:  req.Color,
	}

	if err := s.repo.Create(category); err != nil {
		return nil, err
	}

	return category, nil
}

func (s *CategoryService) GetByID(id string, userID uint) (*model.Category, error) {
	category, err := s.repo.GetByID(id)
	if err != nil {
		return nil, ErrCategoryNotFound
	}
	if category.UserID != userID {
		return nil, ErrCategoryNotFound
	}
	return category, nil
}

func (s *CategoryService) List(userID uint, categoryType string) ([]model.Category, error) {
	return s.repo.GetByUserID(userID, categoryType)
}

type UpdateCategoryRequest struct {
	Name  string `json:"name"`
	Icon  string `json:"icon"`
	Color string `json:"color"`
}

func (s *CategoryService) Update(id string, userID uint, req UpdateCategoryRequest) (*model.Category, error) {
	category, err := s.GetByID(id, userID)
	if err != nil {
		return nil, err
	}
	if category.IsSystem {
		return nil, ErrSystemCategoryProtected
	}

	if req.Name != "" {
		category.Name = req.Name
	}
	if req.Icon != "" {
		category.Icon = req.Icon
	}
	if req.Color != "" {
		category.Color = req.Color
	}

	if err := s.repo.Update(category); err != nil {
		return nil, err
	}

	return category, nil
}

func (s *CategoryService) Delete(id string, userID uint) error {
	category, err := s.GetByID(id, userID)
	if err != nil {
		return err
	}
	if category.IsSystem {
		return ErrSystemCategoryProtected
	}
	return s.repo.Delete(id)
}
