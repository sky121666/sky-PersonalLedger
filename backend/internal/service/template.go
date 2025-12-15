package service

import (
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

var (
	ErrTemplateNotFound = errors.New("template not found")
)

type TemplateService struct {
	templateRepo *repository.TemplateRepository
	txRepo       *repository.TransactionRepository
	accountRepo  *repository.AccountRepository
}

func NewTemplateService(
	templateRepo *repository.TemplateRepository,
	txRepo *repository.TransactionRepository,
	accountRepo *repository.AccountRepository,
) *TemplateService {
	return &TemplateService{
		templateRepo: templateRepo,
		txRepo:       txRepo,
		accountRepo:  accountRepo,
	}
}

type CreateTemplateRequest struct {
	Name       string  `json:"name" binding:"required"`
	Type       string  `json:"type" binding:"required,oneof=income expense"`
	Amount     float64 `json:"amount"`
	AccountID  string  `json:"account_id"`
	CategoryID *string `json:"category_id"`
	Remark     string  `json:"remark"`
}

func (s *TemplateService) Create(userID uint, req CreateTemplateRequest) (*model.QuickTemplate, error) {
	template := &model.QuickTemplate{
		ID:         uuid.New().String(),
		UserID:     userID,
		Name:       req.Name,
		Type:       req.Type,
		Amount:     req.Amount,
		AccountID:  req.AccountID,
		CategoryID: req.CategoryID,
		Remark:     req.Remark,
	}

	if err := s.templateRepo.Create(template); err != nil {
		return nil, err
	}

	return template, nil
}

func (s *TemplateService) GetByID(id string, userID uint) (*model.QuickTemplate, error) {
	template, err := s.templateRepo.GetByID(id)
	if err != nil {
		return nil, ErrTemplateNotFound
	}
	if template.UserID != userID {
		return nil, ErrTemplateNotFound
	}
	return template, nil
}

func (s *TemplateService) List(userID uint) ([]model.QuickTemplate, error) {
	return s.templateRepo.GetByUserID(userID)
}

func (s *TemplateService) Delete(id string, userID uint) error {
	_, err := s.GetByID(id, userID)
	if err != nil {
		return err
	}
	return s.templateRepo.Delete(id)
}

type ApplyTemplateRequest struct {
	TransactionDate string   `json:"transaction_date"`
	Amount          *float64 `json:"amount"`
}

func (s *TemplateService) Apply(id string, userID uint, req ApplyTemplateRequest) (*model.Transaction, error) {
	template, err := s.GetByID(id, userID)
	if err != nil {
		return nil, err
	}

	txDate := time.Now()
	if req.TransactionDate != "" {
		txDate, _ = time.Parse("2006-01-02", req.TransactionDate)
	}

	amount := template.Amount
	if req.Amount != nil {
		amount = *req.Amount
	}

	tx := &model.Transaction{
		ID:              uuid.New().String(),
		UserID:          userID,
		AccountID:       template.AccountID,
		CategoryID:      template.CategoryID,
		Type:            template.Type,
		Amount:          amount,
		TransactionDate: txDate,
		Remark:          template.Remark,
		Source:          "template",
	}

	if err := s.txRepo.Create(tx); err != nil {
		return nil, err
	}

	// Update account balance
	switch template.Type {
	case "expense":
		s.accountRepo.UpdateBalance(template.AccountID, -amount)
	case "income":
		s.accountRepo.UpdateBalance(template.AccountID, amount)
	}

	// Update template usage
	now := time.Now()
	template.UsedCount++
	template.LastUsedAt = &now
	s.templateRepo.Update(template)

	return s.txRepo.GetByID(tx.ID)
}
