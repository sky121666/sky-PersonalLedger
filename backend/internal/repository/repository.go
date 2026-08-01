package repository

import (
	"gorm.io/gorm"
)

type Repositories struct {
	User            *UserRepository
	Account         *AccountRepository
	Category        *CategoryRepository
	Transaction     *TransactionRepository
	Budget          *BudgetRepository
	Reminder        *ReminderRepository
	RefreshToken    *RefreshTokenRepository
	Template        *TemplateRepository
	Notification    *NotificationRepository
	NotificationLog *NotificationLogRepository
	Lending         *LendingRepository
	System          *SystemRepository
	AccountLog      *AccountLogRepository
	Tag             *TagRepository
	APIToken        *APITokenRepository
	FamilyMember    *FamilyMemberRepository
	AIProvider      *AIProviderRepository
	AIReport        *AIReportRepository
}

func NewRepositories(db *gorm.DB) *Repositories {
	return &Repositories{
		User:            NewUserRepository(db),
		Account:         NewAccountRepository(db),
		Category:        NewCategoryRepository(db),
		Transaction:     NewTransactionRepository(db),
		Budget:          NewBudgetRepository(db),
		Reminder:        NewReminderRepository(db),
		RefreshToken:    NewRefreshTokenRepository(db),
		Template:        NewTemplateRepository(db),
		Notification:    NewNotificationRepository(db),
		NotificationLog: NewNotificationLogRepository(db),
		Lending:         NewLendingRepository(db),
		System:          NewSystemRepository(db),
		AccountLog:      NewAccountLogRepository(db),
		Tag:             NewTagRepository(db),
		APIToken:        NewAPITokenRepository(db),
		FamilyMember:    NewFamilyMemberRepository(db),
		AIProvider:      NewAIProviderRepository(db),
		AIReport:        NewAIReportRepository(db),
	}
}
