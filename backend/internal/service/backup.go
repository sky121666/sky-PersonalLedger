package service

import (
	"encoding/json"
	"io"
	"mime/multipart"
	"time"

	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

type BackupService struct {
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

	// Clear existing data before restore
	s.clearUserData(userID)

	// Restore user profile
	if backup.UserProfile != nil {
		if user, err := s.userRepo.GetByID(userID); err == nil {
			user.Nickname = backup.UserProfile.Nickname
			user.Email = backup.UserProfile.Email
			user.Avatar = backup.UserProfile.Avatar
			user.Bio = backup.UserProfile.Bio
			s.userRepo.Update(user)
		}
	}

	// Restore accounts
	for _, acc := range backup.Accounts {
		acc.UserID = userID
		s.accountRepo.Create(&acc)
	}

	// Restore categories
	for _, cat := range backup.Categories {
		cat.UserID = userID
		s.categoryRepo.Create(&cat)
	}

	// Restore transactions
	for _, tx := range backup.Transactions {
		tx.UserID = userID
		s.transactionRepo.Create(&tx)
	}

	// Restore budgets
	for _, budget := range backup.Budgets {
		budget.UserID = userID
		s.budgetRepo.Create(&budget)
	}

	// Restore reminders
	for _, reminder := range backup.Reminders {
		reminder.UserID = userID
		s.reminderRepo.Create(&reminder)
	}

	// Restore lendings
	for _, lending := range backup.Lendings {
		lending.UserID = userID
		s.lendingRepo.Create(lending)
	}

	// Restore lending records
	for _, record := range backup.LendingRecords {
		record.UserID = userID
		s.lendingRepo.CreateRecord(record)
	}

	// Restore templates
	for _, template := range backup.Templates {
		template.UserID = userID
		s.templateRepo.Create(&template)
	}

	// Restore tags
	for _, tag := range backup.Tags {
		tag.UserID = userID
		s.tagRepo.Create(&tag)
	}

	// Restore notification settings
	if backup.NotificationSettings != nil {
		backup.NotificationSettings.UserID = userID
		s.notificationRepo.Upsert(backup.NotificationSettings)
	}

	return nil
}

func (s *BackupService) clearUserData(userID uint) {
	// Delete in reverse order of dependencies
	s.transactionRepo.DeleteAllByUserID(userID)
	s.budgetRepo.DeleteAllByUserID(userID)
	s.lendingRepo.DeleteAllByUserID(userID)
	s.reminderRepo.DeleteAllByUserID(userID)
	s.templateRepo.DeleteAllByUserID(userID)
	s.tagRepo.DeleteAllByUserID(userID)
	s.categoryRepo.DeleteAllByUserID(userID)
	s.accountRepo.DeleteAllByUserID(userID)
}
