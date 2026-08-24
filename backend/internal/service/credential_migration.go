package service

import (
	"fmt"

	"github.com/sky/personal-ledger/internal/repository"
	"gorm.io/gorm"
)

// MigrateStoredCredentials first validates and prepares every notification and
// AI provider credential. It then commits both groups in one database
// transaction, avoiding a partially migrated startup state.
func MigrateStoredCredentials(notification *NotificationService, aiProvider *AIProviderService) error {
	if notification == nil || aiProvider == nil {
		return fmt.Errorf("credential migration services are not configured")
	}

	notification.secretMu.Lock()
	defer notification.secretMu.Unlock()

	notificationSettings, err := notification.prepareStoredSecretMigration()
	if err != nil {
		return err
	}
	aiProviders, err := aiProvider.prepareStoredSecretMigration()
	if err != nil {
		return err
	}

	return notification.repo.DB().Transaction(func(txdb *gorm.DB) error {
		if err := repository.NewNotificationRepository(txdb).UpdateSecretsBatch(notificationSettings); err != nil {
			return fmt.Errorf("persist migrated notification credentials: %w", err)
		}
		if err := repository.NewAIProviderRepository(txdb).UpdateSecretsBatch(aiProviders); err != nil {
			return fmt.Errorf("persist migrated AI provider credentials: %w", err)
		}
		return nil
	})
}
