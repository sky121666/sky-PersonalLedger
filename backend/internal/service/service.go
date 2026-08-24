package service

import (
	"github.com/sky/personal-ledger/internal/config"
	"github.com/sky/personal-ledger/internal/repository"
	"github.com/sky/personal-ledger/pkg/jwt"
)

type Services struct {
	Auth                 *AuthService
	Account              *AccountService
	Category             *CategoryService
	Transaction          *TransactionService
	TransactionImport    *TransactionImportService
	Budget               *BudgetService
	Reminder             *ReminderService
	Statistics           *StatisticsService
	Template             *TemplateService
	Backup               *BackupService
	Notification         *NotificationService
	Lending              *LendingService
	Export               *ExportService
	System               *SystemService
	Upload               *UploadService
	UploadGC             *UploadGarbageCollector
	AccountLog           *AccountLogService
	Tag                  *TagService
	APIToken             *APITokenService
	FamilyMember         *FamilyMemberService
	AIProvider           *AIProviderService
	AIReport             *AIReportService
	AIReportSchedule     *AIReportScheduler
	NotificationSchedule *NotificationScheduler
	Health               *HealthService
}

func NewServices(repos *repository.Repositories, cfg *config.Config) *Services {
	jwtManager := jwt.NewManager(cfg.JWT.Secret, cfg.JWT.AccessExpire, cfg.JWT.RefreshExpire)
	credentialSecrets := credentialEncryptionSecrets(cfg)
	accountLogService := NewAccountLogService(repos.AccountLog, repos.Account)
	uploadService := NewUploadService(&cfg.Storage, repos.User.DB())
	transactionService := NewTransactionService(repos.Transaction, repos.Account, repos.Reminder, repos.Lending, repos.FamilyMember, accountLogService).
		WithUploadService(uploadService)
	allowPrivateOutbound := cfg.Security.AllowPrivateOutbound
	budgetService := NewBudgetService(repos.Budget, repos.Transaction, repos.FamilyMember, repos.Category)
	notificationService := NewNotificationService(repos.Notification, repos.User, credentialSecrets...).WithPrivateOutboundNetworks(allowPrivateOutbound)
	backupService := NewBackupService(
		repos.Account.DB(),
		repos.Account,
		repos.Category,
		repos.Transaction,
		repos.Budget,
		repos.Reminder,
		repos.Lending,
		repos.Template,
		repos.Notification,
		repos.Tag,
		repos.User,
		repos.FamilyMember,
		repos.AIReport,
		cfg.Storage.RestoreMaxFileSize<<20,
	).WithUploadService(uploadService)

	aiReportService := NewAIReportService(repos.AIReport, repos.AIProvider, repos.Transaction, repos.Category, repos.FamilyMember, NewOpenAICompatibleClient(nil, allowPrivateOutbound), credentialSecrets...).
		WithBudgetRepository(repos.Budget).
		WithAccountRepository(repos.Account)

	return &Services{
		Auth:              NewAuthService(repos.User, repos.RefreshToken, repos.Category, repos.Account, jwtManager),
		Account:           NewAccountService(repos.Account),
		Category:          NewCategoryService(repos.Category),
		Transaction:       transactionService,
		TransactionImport: NewTransactionImportService(transactionService),
		Budget:            budgetService,
		Reminder:          NewReminderService(repos.Reminder, repos.Account, repos.Transaction, repos.Category, accountLogService).WithUploadService(uploadService),
		Statistics:        NewStatisticsService(repos.Transaction, repos.Category, repos.Account, repos.AccountLog),
		Template:          NewTemplateService(repos.Template, transactionService),
		Backup:            backupService,
		Notification:      notificationService,
		Lending:           NewLendingService(repos.Lending, repos.Account, repos.Transaction, repos.Category, accountLogService).WithUploadService(uploadService),
		Export:            NewExportService(repos.Transaction, repos.Category, repos.Account),
		System:            NewSystemService(repos.System),
		Upload:            uploadService,
		UploadGC:          NewUploadGarbageCollector(uploadService, repos.User),
		AccountLog:        accountLogService,
		Tag:               NewTagService(repos.Tag),
		APIToken:          NewAPITokenService(repos.APIToken),
		FamilyMember:      NewFamilyMemberService(repos.FamilyMember, repos.Transaction).WithCategoryRepository(repos.Category),
		AIProvider:        NewAIProviderService(repos.AIProvider, NewOpenAICompatibleClient(nil, allowPrivateOutbound), credentialSecrets...).WithPrivateOutboundNetworks(allowPrivateOutbound),
		AIReport:          aiReportService,
		AIReportSchedule:  NewAIReportScheduler(aiReportService, repos.System, repos.User),
		NotificationSchedule: NewNotificationScheduler(
			notificationService,
			repos.Notification,
			repos.NotificationLog,
			repos.Reminder,
			repos.Lending,
			budgetService,
			repos.User,
		),
		Health: NewHealthService(repos.Account.DB(), cfg.Storage.UploadPath, cfg.Storage.BackupPath),
	}
}
