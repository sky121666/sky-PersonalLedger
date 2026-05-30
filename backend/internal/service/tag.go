package service

import (
	"errors"

	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"gorm.io/gorm"
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
	tag, err := s.GetByID(id, userID)
	if err != nil {
		return nil, err
	}

	// Check if another tag with same name exists
	existing, err := s.repo.GetByName(userID, req.Name)
	if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, err
	}
	if existing != nil && existing.ID != id {
		return nil, ErrTagExists
	}

	tag.Name = req.Name
	tag.Color = req.Color
	tag.Icon = req.Icon

	if err := s.repo.Update(tag); err != nil {
		return nil, err
	}

	return s.repo.GetByID(id)
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
