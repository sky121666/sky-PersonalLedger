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

func TestNotificationWebhookTestDoesNotExposeEndpointDetails(t *testing.T) {
	svc, _ := newNotificationTestService(t)

	result := svc.TestWebhook("http://127.0.0.1:1/hook?token=webhook-secret-token", "webhook-secret")
	if result.Success {
		t.Fatalf("webhook test unexpectedly succeeded")
	}

	assertNotificationMessageDoesNotExpose(t, result.Message, []string{
		"127.0.0.1",
		"webhook-secret-token",
		"webhook-secret",
		"/hook",
		"connect",
	})
}

func TestNotificationEmailTestDoesNotExposeSmtpDetails(t *testing.T) {
	svc, repos := newNotificationTestService(t)
	user := &model.User{
		Username:     "mail-user",
		PasswordHash: "hashed",
		Email:        "mail-user@example.test",
	}
	if err := repos.User.Create(user); err != nil {
		t.Fatalf("create user: %v", err)
	}

	result := svc.TestEmail(&model.NotificationSetting{
		SmtpHost:     "smtp.secret.internal",
		SmtpPort:     2525,
		SmtpUser:     "smtp-user@example.test",
		SmtpPassword: "smtp-secret-password",
	}, user.ID)
	if result.Success {
		t.Fatalf("email test unexpectedly succeeded")
	}

	assertNotificationMessageDoesNotExpose(t, result.Message, []string{
		"smtp.secret.internal",
		"smtp-user@example.test",
		"smtp-secret-password",
		"2525",
		"lookup",
		"dial",
	})
}

func TestSendNotificationDoesNotExposeChannelDetails(t *testing.T) {
	svc, repos := newNotificationTestService(t)
	user := &model.User{
		Username:     "notify-user",
		PasswordHash: "hashed",
		Email:        "notify-user@example.test",
	}
	if err := repos.User.Create(user); err != nil {
		t.Fatalf("create user: %v", err)
	}
	if err := repos.Notification.Upsert(&model.NotificationSetting{
		UserID:         user.ID,
		Enabled:        true,
		EmailEnabled:   true,
		SmtpHost:       "smtp.secret.internal",
		SmtpPort:       2525,
		SmtpUser:       "smtp-user@example.test",
		SmtpPassword:   "smtp-secret-password",
		WebhookEnabled: true,
		WebhookURL:     "http://127.0.0.1:1/hook?token=webhook-secret-token",
	}); err != nil {
		t.Fatalf("seed notification settings: %v", err)
	}

	err := svc.SendNotification(user.ID, "测试", "内容")
	if err == nil {
		t.Fatalf("send notification unexpectedly succeeded")
	}

	assertNotificationMessageDoesNotExpose(t, err.Error(), []string{
		"127.0.0.1",
		"webhook-secret-token",
		"smtp.secret.internal",
		"smtp-user@example.test",
		"smtp-secret-password",
		"connect",
		"lookup",
		"dial",
	})
}

func assertNotificationMessageDoesNotExpose(t *testing.T, message string, forbidden []string) {
	t.Helper()

	lowerMessage := strings.ToLower(message)
	for _, value := range forbidden {
		if strings.Contains(lowerMessage, strings.ToLower(value)) {
			t.Fatalf("notification message exposed %q: %q", value, message)
		}
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
