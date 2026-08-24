package service

import (
	"errors"
	"path/filepath"
	"sync/atomic"
	"testing"

	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"gorm.io/gorm"
)

func TestStoredCredentialMigrationValidatesAIBeforeChangingNotification(t *testing.T) {
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	if err := repos.Notification.Upsert(&model.NotificationSetting{
		UserID:         1,
		DingtalkSecret: "legacy-notification-plaintext",
	}); err != nil {
		t.Fatalf("seed notification credential: %v", err)
	}
	unknownCiphertext, err := protectAISecret(
		"sk-unknown",
		"unknown-ai-credential-key-with-at-least-32-characters",
	)
	if err != nil {
		t.Fatalf("protect incompatible AI credential: %v", err)
	}
	if err := repos.AIProvider.Create(&model.AIProvider{
		UserID:           1,
		Name:             "Unknown key provider",
		ProviderType:     aiProviderTypeOpenAICompatible,
		BaseURL:          "https://api.example.com",
		APIKeyCiphertext: unknownCiphertext,
		Model:            "example-model",
	}); err != nil {
		t.Fatalf("seed incompatible AI credential: %v", err)
	}

	activeKey := "active-credential-key-with-at-least-32-characters"
	notification := NewNotificationService(repos.Notification, repos.User, activeKey)
	aiProvider := NewAIProviderService(repos.AIProvider, NewOpenAICompatibleClient(nil), activeKey)
	if err := MigrateStoredCredentials(notification, aiProvider); err == nil {
		t.Fatal("combined migration unexpectedly accepted incompatible AI ciphertext")
	}

	stored, err := repos.Notification.GetByUserID(1)
	if err != nil {
		t.Fatalf("reload notification setting: %v", err)
	}
	if stored.DingtalkSecret != "legacy-notification-plaintext" {
		t.Fatalf("failed combined migration changed notification credential: %q", stored.DingtalkSecret)
	}
}

func TestStoredCredentialMigrationRollsBackNotificationWhenAIPersistFails(t *testing.T) {
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	if err := repos.Notification.Upsert(&model.NotificationSetting{
		UserID:         1,
		DingtalkSecret: "legacy-notification-plaintext",
	}); err != nil {
		t.Fatalf("seed notification credential: %v", err)
	}
	provider := &model.AIProvider{
		UserID:           1,
		Name:             "Plaintext provider",
		ProviderType:     aiProviderTypeOpenAICompatible,
		BaseURL:          "https://api.example.com",
		APIKeyCiphertext: "sk-legacy-plaintext",
		Model:            "example-model",
	}
	if err := repos.AIProvider.Create(provider); err != nil {
		t.Fatalf("seed AI credential: %v", err)
	}

	forcedErr := errors.New("forced AI credential persistence failure")
	callbackName := "test:fail-ai-credential-migration-update"
	var updateCount atomic.Int32
	if err := db.Callback().Update().Before("gorm:update").Register(callbackName, func(tx *gorm.DB) {
		// The combined migration persists notifications first and AI providers
		// second. Fail the second update to exercise the outer transaction.
		if updateCount.Add(1) == 2 {
			tx.AddError(forcedErr)
		}
	}); err != nil {
		t.Fatalf("register update callback: %v", err)
	}
	t.Cleanup(func() { _ = db.Callback().Update().Remove(callbackName) })

	activeKey := "active-credential-key-with-at-least-32-characters"
	notification := NewNotificationService(repos.Notification, repos.User, activeKey)
	aiProvider := NewAIProviderService(repos.AIProvider, NewOpenAICompatibleClient(nil), activeKey)
	if err := MigrateStoredCredentials(notification, aiProvider); !errors.Is(err, forcedErr) {
		t.Fatalf("combined migration error = %v, want forced persistence failure", err)
	}

	storedNotification, err := repos.Notification.GetByUserID(1)
	if err != nil {
		t.Fatalf("reload notification setting: %v", err)
	}
	if storedNotification.DingtalkSecret != "legacy-notification-plaintext" {
		t.Fatalf("AI persistence failure did not roll back notification: %q", storedNotification.DingtalkSecret)
	}
	storedProvider, err := repos.AIProvider.GetByID(provider.ID)
	if err != nil {
		t.Fatalf("reload AI provider: %v", err)
	}
	if storedProvider.APIKeyCiphertext != "sk-legacy-plaintext" {
		t.Fatalf("failed AI migration changed credential: %q", storedProvider.APIKeyCiphertext)
	}
}
