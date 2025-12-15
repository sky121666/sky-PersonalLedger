package repository

import (
	"gorm.io/gorm"
)

type Repositories struct {
	User         *UserRepository
	Account      *AccountRepository
	Category     *CategoryRepository
	Transaction  *TransactionRepository
	Budget       *BudgetRepository
	Reminder     *ReminderRepository
	RefreshToken *RefreshTokenRepository
	Template     *TemplateRepository
	Notification *NotificationRepository
	Lending      *LendingRepository
	System       *SystemRepository
}

func NewRepositories(db *gorm.DB) *Repositories {
	return &Repositories{
		User:         NewUserRepository(db),
		Account:      NewAccountRepository(db),
		Category:     NewCategoryRepository(db),
		Transaction:  NewTransactionRepository(db),
		Budget:       NewBudgetRepository(db),
		Reminder:     NewReminderRepository(db),
		RefreshToken: NewRefreshTokenRepository(db),
		Template:     NewTemplateRepository(db),
		Notification: NewNotificationRepository(db),
		Lending:      NewLendingRepository(db),
		System:       NewSystemRepository(db),
	}
}
