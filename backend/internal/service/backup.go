package service

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"mime/multipart"
	"sync"
	"time"

	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

var ErrInvalidBackupData = errors.New("backup contains no restorable data")
var ErrInvalidBackupFormat = errors.New("invalid backup file")
var ErrBackupFileTooLarge = errors.New("backup file exceeds restore size limit")
var ErrBackupRecordLimitExceeded = errors.New("backup record limit exceeded")
var ErrAttachmentRecoveryPending = errors.New("committed attachment recovery is pending")

const defaultMaxBackupRestoreBytes int64 = 64 << 20

type BackupService struct {
	db                 *gorm.DB
	accountRepo        *repository.AccountRepository
	categoryRepo       *repository.CategoryRepository
	transactionRepo    *repository.TransactionRepository
	budgetRepo         *repository.BudgetRepository
	reminderRepo       *repository.ReminderRepository
	lendingRepo        *repository.LendingRepository
	templateRepo       *repository.TemplateRepository
	notificationRepo   *repository.NotificationRepository
	tagRepo            *repository.TagRepository
	userRepo           *repository.UserRepository
	familyMemberRepo   *repository.FamilyMemberRepository
	aiReportRepo       *repository.AIReportRepository
	maxRestoreBytes    int64
	uploadService      *UploadService
	dbTransaction      func(func(*gorm.DB) error) error
	attachmentCommit   func(*attachmentRestorePlan) error
	attachmentRetry    func(*attachmentRestorePlan) error
	orphanStageCleanup func(map[string]struct{}) error
	cleanupWarning     func(error)
	restoreMu          sync.Mutex
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
	familyMemberRepo *repository.FamilyMemberRepository,
	aiReportRepo *repository.AIReportRepository,
	maxRestoreBytes ...int64,
) *BackupService {
	limit := defaultMaxBackupRestoreBytes
	if len(maxRestoreBytes) > 0 && maxRestoreBytes[0] > 0 {
		limit = maxRestoreBytes[0]
	}
	service := &BackupService{
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
		familyMemberRepo: familyMemberRepo,
		aiReportRepo:     aiReportRepo,
		maxRestoreBytes:  limit,
		dbTransaction:    func(callback func(*gorm.DB) error) error { return db.Transaction(callback) },
		attachmentCommit: func(plan *attachmentRestorePlan) error { return plan.commit() },
		cleanupWarning: func(err error) {
			log.Printf("Warning: attachment restore finalization: %v", err)
		},
	}
	service.attachmentRetry = service.retryCommittedAttachmentRestore
	service.orphanStageCleanup = service.cleanupOrphanAttachmentStages
	return service
}

func (s *BackupService) MaxRestoreBytes() int64 {
	if s == nil || s.maxRestoreBytes <= 0 {
		return defaultMaxBackupRestoreBytes
	}
	return s.maxRestoreBytes
}

// WithUploadService enables attachment content backup and restore. Keeping the
// upload service optional preserves compatibility for callers that only use
// the database portion of the backup service.
func (s *BackupService) WithUploadService(uploadService *UploadService) *BackupService {
	s.uploadService = uploadService
	return s
}

type FullBackupData struct {
	Version              string                      `json:"version"`
	ExportedAt           time.Time                   `json:"exported_at"`
	SourceUserID         uint                        `json:"source_user_id,omitempty"`
	UserProfile          *UserProfileBackup          `json:"user_profile,omitempty"`
	Accounts             []model.Account             `json:"accounts"`
	Categories           []model.Category            `json:"categories"`
	Transactions         []model.Transaction         `json:"transactions"`
	Budgets              []model.Budget              `json:"budgets"`
	Reminders            []model.Reminder            `json:"reminders"`
	Lendings             []*model.Lending            `json:"lendings"`
	LendingRecords       []*model.LendingRecord      `json:"lending_records"`
	Templates            []model.QuickTemplate       `json:"templates"`
	Tags                 []model.Tag                 `json:"tags"`
	FamilyMembers        []model.FamilyMember        `json:"family_members"`
	AIReports            []model.AIReport            `json:"ai_reports"`
	AccountLogs          []model.AccountLog          `json:"account_logs"`
	NotificationLogs     []model.NotificationLog     `json:"notification_logs"`
	NotificationSettings *NotificationSettingsBackup `json:"notification_settings,omitempty"`
	// Attachments is nil when file data was not included (legacy backup or a
	// 2.3 null attachment value). A non-nil empty slice is authoritative and
	// means that the backed-up user directory was empty.
	Attachments []BackupAttachment `json:"attachments"`
}

type UserProfileBackup struct {
	Nickname string `json:"nickname"`
	Email    string `json:"email"`
	Avatar   string `json:"avatar"`
	Bio      string `json:"bio"`
}

func (s *BackupService) CreateBackup(userID uint) (*FullBackupData, error) {
	releaseStorage := acquireAttachmentStorageRead()
	defer releaseStorage()
	if !AttachmentStorageAvailable(userID) {
		return nil, ErrAttachmentRecoveryPending
	}

	var accounts []model.Account
	if err := s.db.Unscoped().Where("user_id = ?", userID).Find(&accounts).Error; err != nil {
		return nil, err
	}

	var categories []model.Category
	if err := s.db.Unscoped().Where("user_id = ?", userID).Find(&categories).Error; err != nil {
		return nil, err
	}

	var transactions []model.Transaction
	if err := s.db.Unscoped().Where("user_id = ?", userID).
		Order("transaction_date ASC, created_at ASC, id ASC").Find(&transactions).Error; err != nil {
		return nil, err
	}

	var budgets []model.Budget
	if err := s.db.Unscoped().Where("user_id = ?", userID).Find(&budgets).Error; err != nil {
		return nil, err
	}

	var reminders []model.Reminder
	if err := s.db.Unscoped().Where("user_id = ?", userID).Find(&reminders).Error; err != nil {
		return nil, err
	}

	var lendings []*model.Lending
	if err := s.db.Unscoped().Where("user_id = ?", userID).Find(&lendings).Error; err != nil {
		return nil, err
	}

	var allLendingRecords []*model.LendingRecord
	if err := s.db.Unscoped().Where("user_id = ?", userID).Find(&allLendingRecords).Error; err != nil {
		return nil, err
	}

	var templates []model.QuickTemplate
	if err := s.db.Unscoped().Where("user_id = ?", userID).Find(&templates).Error; err != nil {
		return nil, err
	}

	var tags []model.Tag
	if err := s.db.Unscoped().Where("user_id = ?", userID).Find(&tags).Error; err != nil {
		return nil, err
	}

	var familyMembers []model.FamilyMember
	if err := s.db.Unscoped().Where("user_id = ?", userID).Find(&familyMembers).Error; err != nil {
		return nil, err
	}

	var aiReports []model.AIReport
	if err := s.db.Unscoped().Where("user_id = ?", userID).Find(&aiReports).Error; err != nil {
		return nil, err
	}

	var accountLogs []model.AccountLog
	if err := s.db.Where("user_id = ?", userID).Order("created_at ASC, id ASC").Find(&accountLogs).Error; err != nil {
		return nil, err
	}
	var notificationLogs []model.NotificationLog
	if err := s.db.Where("user_id = ?", userID).Order("created_at ASC, id ASC").Find(&notificationLogs).Error; err != nil {
		return nil, err
	}

	notificationSettings, err := s.notificationRepo.GetByUserID(userID)
	if err != nil {
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, err
		}
		notificationSettings = nil
	}

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

	attachments, err := s.createBackupAttachments(userID)
	if err != nil {
		return nil, fmt.Errorf("backup attachments: %w", err)
	}
	backup := &FullBackupData{
		Version:              "2.3",
		ExportedAt:           time.Now(),
		SourceUserID:         userID,
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
		FamilyMembers:        familyMembers,
		AIReports:            aiReports,
		AccountLogs:          accountLogs,
		NotificationLogs:     notificationLogs,
		NotificationSettings: newNotificationSettingsBackup(notificationSettings),
		Attachments:          attachments,
	}
	serialized, err := json.Marshal(backup)
	if err != nil {
		return nil, fmt.Errorf("serialize backup for size validation: %w", err)
	}
	if int64(len(serialized)) > s.MaxRestoreBytes() {
		return nil, ErrBackupFileTooLarge
	}
	// Keep creation and restore limits symmetric. Without this preflight a
	// sufficiently dense database could produce a backup that is below the
	// byte limit but is rejected by RestoreBackup's record-count guard.
	if _, err := preflightBackupJSON(serialized); err != nil {
		return nil, fmt.Errorf("validate generated backup: %w", err)
	}
	return backup, nil
}

func (s *BackupService) RestoreBackup(userID uint, file *multipart.FileHeader) error {
	if file == nil {
		return ErrInvalidBackupFormat
	}
	limit := s.MaxRestoreBytes()
	if file.Size > limit {
		return ErrBackupFileTooLarge
	}
	f, err := file.Open()
	if err != nil {
		return err
	}
	defer f.Close()

	data, err := io.ReadAll(io.LimitReader(f, limit+1))
	if err != nil {
		return err
	}
	if int64(len(data)) > limit {
		return ErrBackupFileTooLarge
	}
	if _, err := preflightBackupJSON(data); err != nil {
		return err
	}

	var backup FullBackupData
	if err := json.Unmarshal(data, &backup); err != nil {
		return fmt.Errorf("%w: %v", ErrInvalidBackupFormat, err)
	}
	if err := validateBackupForRestore(backup); err != nil {
		return err
	}
	if err := normalizeBackupForRestore(&backup, userID); err != nil {
		return err
	}
	if err := s.rejectCrossUserBackupReferences(userID, &backup); err != nil {
		return err
	}

	s.restoreMu.Lock()
	defer s.restoreMu.Unlock()
	releaseStorage := acquireAttachmentStorageWrite()
	defer releaseStorage()
	if !AttachmentStorageAvailable(userID) {
		return ErrAttachmentRecoveryPending
	}
	if err := s.validateBackupAttachmentMetadataFiles(userID, &backup); err != nil {
		return err
	}

	attachmentPlan, err := s.prepareAttachmentRestore(userID, backup.Attachments)
	if err != nil {
		return err
	}

	dbTransaction := s.dbTransaction
	if dbTransaction == nil {
		dbTransaction = func(callback func(*gorm.DB) error) error { return s.db.Transaction(callback) }
	}
	restoreErr := dbTransaction(func(tx *gorm.DB) error {
		if err := s.clearUserDataTx(tx, userID); err != nil {
			return err
		}

		if backup.UserProfile != nil {
			if err := pinNotificationEmailRecipientBeforeProfileRestoreTx(tx, userID); err != nil {
				return err
			}
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
			if err := tx.Omit(clause.Associations).Create(&acc).Error; err != nil {
				return err
			}
		}

		for _, cat := range backup.Categories {
			cat.UserID = userID
			if err := tx.Omit(clause.Associations).Create(&cat).Error; err != nil {
				return err
			}
		}

		for _, member := range backup.FamilyMembers {
			member.UserID = userID
			if err := tx.Omit(clause.Associations).Create(&member).Error; err != nil {
				return err
			}
		}

		for _, item := range backup.Transactions {
			item.UserID = userID
			if err := tx.Omit(clause.Associations).Create(&item).Error; err != nil {
				return err
			}
		}

		for _, budget := range backup.Budgets {
			budget.UserID = userID
			if err := tx.Omit(clause.Associations).Create(&budget).Error; err != nil {
				return err
			}
		}

		for _, reminder := range backup.Reminders {
			reminder.UserID = userID
			if err := tx.Omit(clause.Associations).Create(&reminder).Error; err != nil {
				return err
			}
		}

		for _, lending := range backup.Lendings {
			lending.UserID = userID
			if err := tx.Omit(clause.Associations).Create(lending).Error; err != nil {
				return err
			}
		}

		for _, record := range backup.LendingRecords {
			record.UserID = userID
			if err := tx.Omit(clause.Associations).Create(record).Error; err != nil {
				return err
			}
		}

		for _, template := range backup.Templates {
			template.UserID = userID
			if err := tx.Omit(clause.Associations).Create(&template).Error; err != nil {
				return err
			}
		}

		for _, tag := range backup.Tags {
			tag.UserID = userID
			if err := tx.Omit(clause.Associations).Create(&tag).Error; err != nil {
				return err
			}
		}

		for _, report := range backup.AIReports {
			report.UserID = userID
			if err := tx.Omit(clause.Associations).Create(&report).Error; err != nil {
				return err
			}
		}

		for _, accountLog := range backup.AccountLogs {
			accountLog.UserID = userID
			if err := tx.Omit(clause.Associations).Create(&accountLog).Error; err != nil {
				return err
			}
		}

		for _, notificationLog := range backup.NotificationLogs {
			notificationLog.UserID = userID
			if err := tx.Omit(clause.Associations).Create(&notificationLog).Error; err != nil {
				return err
			}
		}

		if err := restoreNotificationSettingsTx(tx, userID, backup.NotificationSettings); err != nil {
			return err
		}

		if err := persistAttachmentRestoreMarkerTx(tx, attachmentPlan); err != nil {
			return err
		}

		return nil
	})
	if restoreErr != nil {
		if attachmentPlan == nil {
			return restoreErr
		}
		committed, markerErr := s.attachmentRestoreMarkerCommitted(attachmentPlan)
		if markerErr != nil {
			// The commit outcome is uncertain. Preserve the staged generation so
			// startup recovery can decide from the permanent database marker.
			markAttachmentRecoveryPending(userID)
			return fmt.Errorf("%w: %v", ErrAttachmentRecoveryPending, errors.Join(restoreErr, fmt.Errorf("verify attachment restore commit: %w", markerErr), attachmentPlan.close()))
		}
		if !committed {
			return errors.Join(restoreErr, attachmentPlan.rollback())
		}
		s.cleanupWarning(fmt.Errorf("database reported an error after committing attachment restore: %w", restoreErr))
	}
	if attachmentPlan != nil {
		if err := s.finalizeCommittedAttachmentRestore(attachmentPlan); err != nil {
			markAttachmentRecoveryPending(userID)
			return err
		}
		clearAttachmentRecoveryPending(userID)
	}
	return nil
}

func (s *BackupService) finalizeCommittedAttachmentRestore(plan *attachmentRestorePlan) error {
	commitErr := s.attachmentCommit(plan)
	if commitErr == nil {
		return nil
	}
	commitErr = errors.Join(commitErr, plan.close())

	// A typed forward error (including rename/fsync/verification) is retried
	// immediately. Unknown injected errors are retried unless the desired
	// generation is already active, in which case they are cleanup-only.
	active, activeErr := s.attachmentRestoreGenerationActive(plan)
	if !errors.Is(commitErr, ErrAttachmentRecoveryPending) && active {
		s.cleanupWarning(fmt.Errorf("finalize committed attachment restore: %w", errors.Join(commitErr, activeErr)))
		return nil
	}

	retry := s.attachmentRetry
	if retry == nil {
		retry = s.retryCommittedAttachmentRestore
	}
	retryErr := retry(plan)
	if retryErr == nil {
		s.cleanupWarning(fmt.Errorf("attachment restore required an immediate forward retry: %w", commitErr))
		return nil
	}
	retryActive, retryActiveErr := s.attachmentRestoreGenerationActive(plan)
	if !errors.Is(retryErr, ErrAttachmentRecoveryPending) && retryActive {
		s.cleanupWarning(fmt.Errorf("finalize committed attachment restore after retry: %w", errors.Join(commitErr, retryErr)))
		return nil
	}
	return fmt.Errorf("%w: %v", ErrAttachmentRecoveryPending, errors.Join(commitErr, activeErr, retryErr, retryActiveErr))
}

func validateBackupForRestore(backup FullBackupData) error {
	if backup.UserProfile != nil || backup.NotificationSettings != nil {
		return nil
	}
	if len(backup.Accounts) > 0 ||
		len(backup.Categories) > 0 ||
		len(backup.Transactions) > 0 ||
		len(backup.Budgets) > 0 ||
		len(backup.Reminders) > 0 ||
		len(backup.Lendings) > 0 ||
		len(backup.LendingRecords) > 0 ||
		len(backup.Templates) > 0 ||
		len(backup.Tags) > 0 ||
		len(backup.FamilyMembers) > 0 ||
		len(backup.AIReports) > 0 ||
		len(backup.AccountLogs) > 0 ||
		len(backup.NotificationLogs) > 0 {
		return nil
	}
	return ErrInvalidBackupData
}

func (s *BackupService) clearUserData(userID uint) {
	// Delete in reverse order of dependencies
	s.db.Unscoped().Where("user_id = ?", userID).Delete(&model.AccountLog{})
	s.db.Where("user_id = ?", userID).Delete(&model.NotificationLog{})
	s.transactionRepo.DeleteAllByUserID(userID)
	s.budgetRepo.DeleteAllByUserID(userID)
	s.lendingRepo.DeleteAllByUserID(userID)
	s.reminderRepo.DeleteAllByUserID(userID)
	s.templateRepo.DeleteAllByUserID(userID)
	s.tagRepo.DeleteAllByUserID(userID)
	s.db.Unscoped().Where("user_id = ?", userID).Delete(&model.FamilyMember{})
	s.db.Unscoped().Where("user_id = ?", userID).Delete(&model.AIReport{})
	s.categoryRepo.DeleteAllByUserID(userID)
	s.accountRepo.DeleteAllByUserID(userID)
}

func (s *BackupService) clearUserDataTx(tx *gorm.DB, userID uint) error {
	if err := tx.Unscoped().Where("user_id = ?", userID).Delete(&model.AccountLog{}).Error; err != nil {
		return err
	}
	if err := tx.Where("user_id = ?", userID).Delete(&model.NotificationLog{}).Error; err != nil {
		return err
	}
	if err := tx.Unscoped().Where("user_id = ?", userID).Delete(&model.LendingRecord{}).Error; err != nil {
		return err
	}
	if err := tx.Unscoped().Where("user_id = ?", userID).Delete(&model.Budget{}).Error; err != nil {
		return err
	}
	if err := tx.Unscoped().Where("user_id = ?", userID).Delete(&model.Transaction{}).Error; err != nil {
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
	if err := tx.Unscoped().Where("user_id = ?", userID).Delete(&model.FamilyMember{}).Error; err != nil {
		return err
	}
	if err := tx.Unscoped().Where("user_id = ?", userID).Delete(&model.AIReport{}).Error; err != nil {
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
