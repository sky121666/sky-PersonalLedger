package service

import (
	"errors"
	"math"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"gorm.io/gorm"
)

var (
	ErrTemplateNotFound      = errors.New("template not found")
	ErrInvalidTemplateType   = errors.New("invalid template type")
	ErrInvalidTemplateAmount = errors.New("template amount must not be negative")
)

type TemplateService struct {
	templateRepo *repository.TemplateRepository
	txService    *TransactionService
}

func NewTemplateService(
	templateRepo *repository.TemplateRepository,
	txService *TransactionService,
) *TemplateService {
	return &TemplateService{
		templateRepo: templateRepo,
		txService:    txService,
	}
}

type CreateTemplateRequest struct {
	Name       string  `json:"name" binding:"required"`
	Type       string  `json:"type" binding:"required,oneof=income expense"`
	Amount     float64 `json:"amount"`
	AccountID  string  `json:"account_id" binding:"required"`
	CategoryID *string `json:"category_id"`
	Remark     string  `json:"remark"`
}

func (s *TemplateService) Create(userID uint, req CreateTemplateRequest) (*model.QuickTemplate, error) {
	if req.Type != "income" && req.Type != "expense" {
		return nil, ErrInvalidTemplateType
	}
	if req.Amount < 0 || math.IsNaN(req.Amount) || math.IsInf(req.Amount, 0) {
		return nil, ErrInvalidTemplateAmount
	}

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

	err := s.txService.txRepo.DB().Transaction(func(txdb *gorm.DB) error {
		if err := s.txService.validateTransactionReferencesTx(txdb, userID, CreateTransactionRequest{
			Type:       req.Type,
			AccountID:  req.AccountID,
			CategoryID: req.CategoryID,
		}); err != nil {
			return err
		}
		return s.templateRepo.CreateWithDB(txdb, template)
	})
	if err != nil {
		return nil, err
	}

	return template, nil
}

func (s *TemplateService) GetByID(id string, userID uint) (*model.QuickTemplate, error) {
	template, err := s.templateRepo.GetByIDForUser(id, userID)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrTemplateNotFound
		}
		return nil, err
	}
	return template, nil
}

func (s *TemplateService) List(userID uint) ([]model.QuickTemplate, error) {
	return s.templateRepo.GetByUserID(userID)
}

func (s *TemplateService) Delete(id string, userID uint) error {
	if err := s.templateRepo.DeleteForUser(id, userID); err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrTemplateNotFound
		}
		return err
	}
	return nil
}

type ApplyTemplateRequest struct {
	TransactionDate string   `json:"transaction_date"`
	Amount          *float64 `json:"amount"`
}

func (s *TemplateService) Apply(id string, userID uint, req ApplyTemplateRequest) (*model.Transaction, error) {
	var transaction *model.Transaction
	err := s.txService.txRepo.DB().Transaction(func(txdb *gorm.DB) error {
		template, err := s.templateRepo.GetByIDForUserWithDB(txdb, id, userID)
		if err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return ErrTemplateNotFound
			}
			return err
		}

		amount := template.Amount
		if req.Amount != nil {
			amount = *req.Amount
		}
		transactionDate := req.TransactionDate
		if transactionDate == "" {
			transactionDate = time.Now().Format(time.RFC3339Nano)
		}

		transaction, err = s.txService.createWithTx(txdb, userID, CreateTransactionRequest{
			Type:            template.Type,
			Amount:          amount,
			AccountID:       template.AccountID,
			CategoryID:      template.CategoryID,
			TransactionDate: transactionDate,
			Remark:          template.Remark,
		}, "template")
		if err != nil {
			return err
		}

		if err := s.templateRepo.IncrementUsageWithDB(txdb, id, userID, time.Now()); err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return ErrTemplateNotFound
			}
			return err
		}
		return nil
	})
	if err != nil {
		return nil, err
	}

	return transaction, nil
}
