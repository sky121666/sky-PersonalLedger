package service

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

func TestNotificationSettingJSONDoesNotExposeSecrets(t *testing.T) {
	payload, err := json.Marshal(model.NotificationSetting{
		DingtalkSecret: "dingtalk-secret",
		WebhookSecret:  "webhook-secret",
		SmtpPassword:   "smtp-secret",
	})
	if err != nil {
		t.Fatalf("marshal notification setting: %v", err)
	}

	body := string(payload)
	for _, secret := range []string{"dingtalk-secret", "webhook-secret", "smtp-secret"} {
		if strings.Contains(body, secret) {
			t.Fatalf("notification JSON leaked %q: %s", secret, body)
		}
	}
}

func TestNotificationUpdatePreservesStoredSecretsWhenRequestOmitsThem(t *testing.T) {
	svc, repos := newNotificationTestService(t)
	const userID uint = 1

	if _, err := svc.Update(userID, NotificationSettingRequest{
		Enabled:        true,
		DingtalkSecret: "dingtalk-secret",
		SmtpPassword:   "smtp-secret",
		WebhookSecret:  "webhook-secret",
	}); err != nil {
		t.Fatalf("seed notification settings: %v", err)
	}

	if _, err := svc.Update(userID, NotificationSettingRequest{
		Enabled: true,
	}); err != nil {
		t.Fatalf("update notification settings: %v", err)
	}

	stored, err := repos.Notification.GetByUserID(userID)
	if err != nil {
		t.Fatalf("get stored notification settings: %v", err)
	}
	if stored.DingtalkSecret != "dingtalk-secret" {
		t.Fatalf("dingtalk secret = %q, want preserved", stored.DingtalkSecret)
	}
	if stored.SmtpPassword != "smtp-secret" {
		t.Fatalf("smtp password = %q, want preserved", stored.SmtpPassword)
	}
	if stored.WebhookSecret != "webhook-secret" {
		t.Fatalf("webhook secret = %q, want preserved", stored.WebhookSecret)
	}
}

func newNotificationTestService(t *testing.T) (*NotificationService, *repository.Repositories) {
	t.Helper()

	db, err := database.Init(t.TempDir() + "/ledger.db")
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	return NewNotificationService(repos.Notification, repos.User), repos
}
