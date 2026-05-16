package service

import (
	"encoding/json"
	"io"
	"mime/multipart"
	"time"

	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"gorm.io/gorm"
)

type BackupService struct {
	db               *gorm.DB
	accountRepo      *repository.AccountRepository
	categoryRepo     *repository.CategoryRepository
	transactionRepo  *repository.TransactionRepository
	budgetRepo       *repository.BudgetRepository
	reminderRepo     *repository.ReminderRepository
	lendingRepo      *repository.LendingRepository
	templateRepo     *repository.TemplateRepository
	notificationRepo *repository.NotificationRepository
	tagRepo          *repository.TagRepository
	userRepo         *repository.UserRepository
}

func NewBackupService(
	db *gorm.DB,
	accountRepo *repository.AccountRepository,
	categoryRepo *repository.CategoryRepository,
	transactionRepo *repository.TransactionRepository,
	budgetRepo *repository.BudgetRepository,
	reminderRepo *repository.ReminderRepository,
	lendingRepo *repository.LendingRepository,
	templateRepo *repository.TemplateRepository,
	notificationRepo *repository.NotificationRepository,
	tagRepo *repository.TagRepository,
	userRepo *repository.UserRepository,
) *BackupService {
	return &BackupService{
		db:               db,
		accountRepo:      accountRepo,
		categoryRepo:     categoryRepo,
		transactionRepo:  transactionRepo,
		budgetRepo:       budgetRepo,
		reminderRepo:     reminderRepo,
		lendingRepo:      lendingRepo,
		templateRepo:     templateRepo,
		notificationRepo: notificationRepo,
		tagRepo:          tagRepo,
		userRepo:         userRepo,
	}
}

type FullBackupData struct {
	Version              string                     `json:"version"`
	ExportedAt           time.Time                  `json:"exported_at"`
	UserProfile          *UserProfileBackup         `json:"user_profile,omitempty"`
	Accounts             []model.Account            `json:"accounts"`
	Categories           []model.Category           `json:"categories"`
	Transactions         []model.Transaction        `json:"transactions"`
	Budgets              []model.Budget             `json:"budgets"`
	Reminders            []model.Reminder           `json:"reminders"`
	Lendings             []*model.Lending           `json:"lendings"`
	LendingRecords       []*model.LendingRecord     `json:"lending_records"`
	Templates            []model.QuickTemplate      `json:"templates"`
	Tags                 []model.Tag                `json:"tags"`
	NotificationSettings *model.NotificationSetting `json:"notification_settings,omitempty"`
}

type UserProfileBackup struct {
	Nickname string `json:"nickname"`
	Email    string `json:"email"`
	Avatar   string `json:"avatar"`
	Bio      string `json:"bio"`
}

func (s *BackupService) CreateBackup(userID uint) (*FullBackupData, error) {
	accounts, err := s.accountRepo.GetByUserID(userID, true) // include archived
	if err != nil {
		return nil, err
	}

	categories, err := s.categoryRepo.GetByUserID(userID, "") // all types
	if err != nil {
		return nil, err
	}

	transactions, err := s.transactionRepo.GetAllForExport(userID, nil, nil)
	if err != nil {
		return nil, err
	}

	budgets, err := s.budgetRepo.GetByUserID(userID)
	if err != nil {
		return nil, err
	}

	reminders, err := s.reminderRepo.GetByUserID(userID)
	if err != nil {
		return nil, err
	}

	lendings, err := s.lendingRepo.GetByUserID(userID, true) // include settled
	if err != nil {
		return nil, err
	}

	// Get all lending records
	var allLendingRecords []*model.LendingRecord
	for _, lending := range lendings {
		records, err := s.lendingRepo.GetRecordsByLendingID(lending.ID)
		if err != nil {
			return nil, err
		}
		allLendingRecords = append(allLendingRecords, records...)
	}

	templates, err := s.templateRepo.GetByUserID(userID)
	if err != nil {
		return nil, err
	}

	tags, err := s.tagRepo.GetByUserID(userID)
	if err != nil {
		return nil, err
	}

	notificationSettings, _ := s.notificationRepo.GetByUserID(userID) // ignore error if not found

	// Get user profile
	var userProfile *UserProfileBackup
	if user, err := s.userRepo.GetByID(userID); err == nil {
		userProfile = &UserProfileBackup{
			Nickname: user.Nickname,
			Email:    user.Email,
			Avatar:   user.Avatar,
			Bio:      user.Bio,
		}
	}

	return &FullBackupData{
		Version:              "2.1",
		ExportedAt:           time.Now(),
		UserProfile:          userProfile,
		Accounts:             accounts,
		Categories:           categories,
		Transactions:         transactions,
		Budgets:              budgets,
		Reminders:            reminders,
		Lendings:             lendings,
		LendingRecords:       allLendingRecords,
		Templates:            templates,
		Tags:                 tags,
		NotificationSettings: notificationSettings,
	}, nil
}

func (s *BackupService) RestoreBackup(userID uint, file *multipart.FileHeader) error {
	f, err := file.Open()
	if err != nil {
		return err
	}
	defer f.Close()

	data, err := io.ReadAll(f)
	if err != nil {
		return err
	}

	var backup FullBackupData
	if err := json.Unmarshal(data, &backup); err != nil {
		return err
	}

	return s.db.Transaction(func(tx *gorm.DB) error {
		if err := s.clearUserDataTx(tx, userID); err != nil {
			return err
		}

		if backup.UserProfile != nil {
			if err := tx.Model(&model.User{}).Where("id = ?", userID).Updates(map[string]any{
				"nickname": backup.UserProfile.Nickname,
				"email":    backup.UserProfile.Email,
				"avatar":   backup.UserProfile.Avatar,
				"bio":      backup.UserProfile.Bio,
			}).Error; err != nil {
				return err
			}
		}

		for _, acc := range backup.Accounts {
			acc.UserID = userID
			if err := tx.Create(&acc).Error; err != nil {
				return err
			}
		}

		for _, cat := range backup.Categories {
			cat.UserID = userID
			if err := tx.Create(&cat).Error; err != nil {
				return err
			}
		}

		for _, item := range backup.Transactions {
			item.UserID = userID
			if err := tx.Create(&item).Error; err != nil {
				return err
			}
		}

		for _, budget := range backup.Budgets {
			budget.UserID = userID
			if err := tx.Create(&budget).Error; err != nil {
				return err
			}
		}

		for _, reminder := range backup.Reminders {
			reminder.UserID = userID
			if err := tx.Create(&reminder).Error; err != nil {
				return err
			}
		}

		for _, lending := range backup.Lendings {
			lending.UserID = userID
			if err := tx.Create(lending).Error; err != nil {
				return err
			}
		}

		for _, record := range backup.LendingRecords {
			record.UserID = userID
			if err := tx.Create(record).Error; err != nil {
				return err
			}
		}

		for _, template := range backup.Templates {
			template.UserID = userID
			if err := tx.Create(&template).Error; err != nil {
				return err
			}
		}

		for _, tag := range backup.Tags {
			tag.UserID = userID
			if err := tx.Create(&tag).Error; err != nil {
				return err
			}
		}

		if backup.NotificationSettings != nil {
			backup.NotificationSettings.UserID = userID
			if err := tx.Where("user_id = ?", userID).Delete(&model.NotificationSetting{}).Error; err != nil {
				return err
			}
			if err := tx.Create(backup.NotificationSettings).Error; err != nil {
				return err
			}
		}

		return nil
	})
}

func (s *BackupService) clearUserData(userID uint) {
	// Delete in reverse order of dependencies
	s.db.Unscoped().Where("user_id = ?", userID).Delete(&model.AccountLog{})
	s.transactionRepo.DeleteAllByUserID(userID)
	s.budgetRepo.DeleteAllByUserID(userID)
	s.lendingRepo.DeleteAllByUserID(userID)
	s.reminderRepo.DeleteAllByUserID(userID)
	s.templateRepo.DeleteAllByUserID(userID)
	s.tagRepo.DeleteAllByUserID(userID)
	s.categoryRepo.DeleteAllByUserID(userID)
	s.accountRepo.DeleteAllByUserID(userID)
}

func (s *BackupService) clearUserDataTx(tx *gorm.DB, userID uint) error {
	if err := tx.Unscoped().Where("user_id = ?", userID).Delete(&model.AccountLog{}).Error; err != nil {
		return err
	}
	if err := tx.Unscoped().Where("user_id = ?", userID).Delete(&model.Transaction{}).Error; err != nil {
		return err
	}
	if err := tx.Unscoped().Where("user_id = ?", userID).Delete(&model.Budget{}).Error; err != nil {
		return err
	}
	if err := tx.Unscoped().Where("user_id = ?", userID).Delete(&model.LendingRecord{}).Error; err != nil {
		return err
	}
	if err := tx.Unscoped().Where("user_id = ?", userID).Delete(&model.Lending{}).Error; err != nil {
		return err
	}
	if err := tx.Unscoped().Where("user_id = ?", userID).Delete(&model.Reminder{}).Error; err != nil {
		return err
	}
	if err := tx.Unscoped().Where("user_id = ?", userID).Delete(&model.QuickTemplate{}).Error; err != nil {
		return err
	}
	if err := tx.Unscoped().Where("user_id = ?", userID).Delete(&model.Tag{}).Error; err != nil {
		return err
	}
	if err := tx.Where("user_id = ?", userID).Delete(&model.NotificationSetting{}).Error; err != nil {
		return err
	}
	if err := tx.Unscoped().Where("user_id = ?", userID).Delete(&model.Category{}).Error; err != nil {
		return err
	}
	if err := tx.Unscoped().Where("user_id = ?", userID).Delete(&model.Account{}).Error; err != nil {
		return err
	}
	return nil
}
