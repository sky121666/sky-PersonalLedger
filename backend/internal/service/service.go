package service

import (
	"github.com/sky/personal-ledger/internal/config"
	"github.com/sky/personal-ledger/internal/repository"
	"github.com/sky/personal-ledger/pkg/jwt"
)

type Services struct {
	Auth         *AuthService
	Account      *AccountService
	Category     *CategoryService
	Transaction  *TransactionService
	Budget       *BudgetService
	Reminder     *ReminderService
	Statistics   *StatisticsService
	Template     *TemplateService
	Backup       *BackupService
	Notification *NotificationService
	Lending      *LendingService
	Export       *ExportService
	System       *SystemService
	Upload       *UploadService
	AccountLog   *AccountLogService
	Tag          *TagService
	APIToken     *APITokenService
}

func NewServices(repos *repository.Repositories, cfg *config.Config) *Services {
	jwtManager := jwt.NewManager(cfg.JWT.Secret, cfg.JWT.AccessExpire, cfg.JWT.RefreshExpire)
	accountLogService := NewAccountLogService(repos.AccountLog, repos.Account)

	return &Services{
		Auth:         NewAuthService(repos.User, repos.RefreshToken, repos.Category, repos.Account, jwtManager),
		Account:      NewAccountService(repos.Account, repos.Transaction, repos.Category),
		Category:     NewCategoryService(repos.Category),
		Transaction:  NewTransactionService(repos.Transaction, repos.Account, repos.Reminder, repos.Lending, accountLogService),
		Budget:       NewBudgetService(repos.Budget, repos.Transaction),
		Reminder:     NewReminderService(repos.Reminder, repos.Account, repos.Transaction, repos.Category, accountLogService),
		Statistics:   NewStatisticsService(repos.Transaction, repos.Category, repos.Account),
		Template:     NewTemplateService(repos.Template, repos.Transaction, repos.Account),
		Backup:       NewBackupService(repos.Account.DB(), repos.Account, repos.Category, repos.Transaction, repos.Budget, repos.Reminder, repos.Lending, repos.Template, repos.Notification, repos.Tag, repos.User),
		Notification: NewNotificationService(repos.Notification, repos.User),
		Lending:      NewLendingService(repos.Lending, repos.Account, repos.Transaction, repos.Category, accountLogService),
		Export:       NewExportService(repos.Transaction, repos.Category, repos.Account),
		System:       NewSystemService(repos.System),
		Upload:       NewUploadService(&cfg.Storage),
		AccountLog:   accountLogService,
		Tag:          NewTagService(repos.Tag),
		APIToken:     NewAPITokenService(repos.APIToken),
	}
}
