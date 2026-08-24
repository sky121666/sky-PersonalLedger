package service

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"net/smtp"
	"net/url"
	"strconv"
	"strings"
	"testing"

	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"gorm.io/gorm"
	gormlogger "gorm.io/gorm/logger"
)

const notificationTestEncryptionSecret = "notification-test-jwt-secret-with-at-least-32-characters"

func TestNotificationSettingJSONDoesNotExposeSecrets(t *testing.T) {
	payload, err := json.Marshal(model.NotificationSetting{
		WecomWebhook:    "https://example.com/wecom?key=wecom-token",
		DingtalkWebhook: "https://example.com/dingtalk?access_token=dingtalk-token",
		DingtalkSecret:  "dingtalk-secret",
		WebhookURL:      "https://example.com/custom?token=webhook-token",
		WebhookSecret:   "webhook-secret",
		SmtpPassword:    "smtp-secret",
	})
	if err != nil {
		t.Fatalf("marshal notification setting: %v", err)
	}

	body := string(payload)
	for _, secret := range []string{"wecom-token", "dingtalk-token", "dingtalk-secret", "webhook-token", "webhook-secret", "smtp-secret"} {
		if strings.Contains(body, secret) {
			t.Fatalf("notification JSON leaked %q: %s", secret, body)
		}
	}
	for _, field := range []string{"wecom_webhook", "dingtalk_webhook", "webhook_url"} {
		if strings.Contains(body, field) {
			t.Fatalf("notification JSON exposed credential field %q: %s", field, body)
		}
	}
}

func TestNotificationUpdateDoesNotWritePlaintextCredentialsToSQLLogs(t *testing.T) {
	db, err := database.Init(t.TempDir() + "/ledger.db")
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	var logs bytes.Buffer
	loggedDB := db.Session(&gorm.Session{Logger: gormlogger.New(
		log.New(&logs, "", 0),
		gormlogger.Config{LogLevel: gormlogger.Info, ParameterizedQueries: false},
	)})
	repos := repository.NewRepositories(loggedDB)
	svc := NewNotificationService(repos.Notification, repos.User, notificationTestEncryptionSecret)
	plainTexts := []string{
		"log-wecom-token",
		"log-dingtalk-token",
		"log-custom-webhook-token",
		"log-dingtalk-secret",
		"log-smtp-password",
		"log-webhook-secret",
	}
	if _, err := svc.Update(1, NotificationSettingRequest{
		WecomWebhook:    "https://example.com/wecom?key=" + plainTexts[0],
		DingtalkWebhook: "https://example.com/dingtalk?access_token=" + plainTexts[1],
		WebhookURL:      "https://example.com/custom?token=" + plainTexts[2],
		DingtalkSecret:  plainTexts[3],
		SmtpPassword:    plainTexts[4],
		WebhookSecret:   plainTexts[5],
	}); err != nil {
		t.Fatalf("update notification credentials: %v", err)
	}
	for _, plainText := range plainTexts {
		if strings.Contains(logs.String(), plainText) {
			t.Fatalf("SQL log exposed plaintext notification credential %q", plainText)
		}
	}
}

func TestNotificationUpdatePreservesStoredSecretsWhenRequestOmitsThem(t *testing.T) {
	svc, repos := newNotificationTestService(t)
	const userID uint = 1

	if _, err := svc.Update(userID, NotificationSettingRequest{
		Enabled:         true,
		WecomWebhook:    "https://example.com/wecom?key=wecom-token",
		DingtalkWebhook: "https://example.com/dingtalk?access_token=dingtalk-token",
		DingtalkSecret:  "dingtalk-secret",
		SmtpPassword:    "smtp-secret",
		WebhookURL:      "https://example.com/custom?token=webhook-token",
		WebhookSecret:   "webhook-secret",
	}); err != nil {
		t.Fatalf("seed notification settings: %v", err)
	}
	initial, err := repos.Notification.GetByUserID(userID)
	if err != nil {
		t.Fatalf("get initially stored notification settings: %v", err)
	}
	assertProtectedNotificationCredential(t, initial.WecomWebhook, "https://example.com/wecom?key=wecom-token")
	assertProtectedNotificationCredential(t, initial.DingtalkWebhook, "https://example.com/dingtalk?access_token=dingtalk-token")
	assertProtectedNotificationCredential(t, initial.DingtalkSecret, "dingtalk-secret")
	assertProtectedNotificationCredential(t, initial.SmtpPassword, "smtp-secret")
	assertProtectedNotificationCredential(t, initial.WebhookURL, "https://example.com/custom?token=webhook-token")
	assertProtectedNotificationCredential(t, initial.WebhookSecret, "webhook-secret")

	if _, err := svc.Update(userID, NotificationSettingRequest{
		Enabled: true,
	}); err != nil {
		t.Fatalf("update notification settings: %v", err)
	}

	stored, err := repos.Notification.GetByUserID(userID)
	if err != nil {
		t.Fatalf("get stored notification settings: %v", err)
	}
	if stored.WecomWebhook != initial.WecomWebhook {
		t.Fatal("wecom endpoint ciphertext changed when request omitted the endpoint")
	}
	if stored.DingtalkWebhook != initial.DingtalkWebhook {
		t.Fatal("dingtalk endpoint ciphertext changed when request omitted the endpoint")
	}
	if stored.DingtalkSecret != initial.DingtalkSecret {
		t.Fatal("dingtalk ciphertext changed when request omitted the secret")
	}
	if stored.SmtpPassword != initial.SmtpPassword {
		t.Fatal("smtp ciphertext changed when request omitted the password")
	}
	if stored.WebhookURL != initial.WebhookURL {
		t.Fatal("webhook endpoint ciphertext changed when request omitted the endpoint")
	}
	if stored.WebhookSecret != initial.WebhookSecret {
		t.Fatal("webhook ciphertext changed when request omitted the secret")
	}
}

func TestNotificationUpdateBindsSecretsOnlyToUnchangedEndpoints(t *testing.T) {
	svc, repos := newNotificationTestService(t)
	const userID uint = 42
	const dingtalkEndpoint = "https://oapi.dingtalk.com/robot/send?access_token=old"
	const webhookEndpoint = "https://hooks.example.test/old"
	initial, err := svc.Update(userID, NotificationSettingRequest{
		DingtalkWebhook: dingtalkEndpoint,
		DingtalkSecret:  "stored-dingtalk-secret",
		WebhookURL:      webhookEndpoint,
		WebhookSecret:   "stored-webhook-secret",
	})
	if err != nil {
		t.Fatalf("seed notification credentials: %v", err)
	}

	if _, err := svc.Update(userID, NotificationSettingRequest{
		DingtalkWebhook: dingtalkEndpoint,
		WebhookURL:      webhookEndpoint,
	}); err != nil {
		t.Fatalf("save explicit unchanged endpoints: %v", err)
	}
	unchanged, err := repos.Notification.GetByUserID(userID)
	if err != nil {
		t.Fatalf("load unchanged endpoints: %v", err)
	}
	if unchanged.DingtalkSecret != initial.DingtalkSecret || unchanged.WebhookSecret != initial.WebhookSecret {
		t.Fatal("explicit unchanged endpoints did not preserve their stored secrets")
	}

	if _, err := svc.Update(userID, NotificationSettingRequest{
		DingtalkWebhook: "https://oapi.dingtalk.com/robot/send?access_token=new",
		WebhookURL:      "https://hooks.example.test/new",
	}); err != nil {
		t.Fatalf("save changed endpoints without secrets: %v", err)
	}
	changed, err := repos.Notification.GetByUserID(userID)
	if err != nil {
		t.Fatalf("load changed endpoints: %v", err)
	}
	if changed.DingtalkSecret != "" || changed.WebhookSecret != "" {
		t.Fatal("changed endpoints silently inherited secrets bound to the old endpoints")
	}
}

func TestNotificationGetMigratesLegacyPlaintextSecrets(t *testing.T) {
	svc, repos := newNotificationTestService(t)
	const userID uint = 42
	if err := repos.Notification.Upsert(&model.NotificationSetting{
		UserID:          userID,
		WecomWebhook:    "https://example.com/wecom?key=legacy-wecom",
		DingtalkWebhook: "https://example.com/dingtalk?access_token=legacy-dingtalk-token",
		DingtalkSecret:  "legacy-dingtalk",
		SmtpPassword:    " legacy-smtp-password ",
		WebhookURL:      "https://example.com/custom?token=legacy-webhook-token",
		WebhookSecret:   "legacy-webhook",
		NotifyLogin:     true,
		AdvanceDays:     3,
	}); err != nil {
		t.Fatalf("seed legacy notification settings: %v", err)
	}

	setting, err := svc.Get(userID)
	if err != nil {
		t.Fatalf("get and migrate legacy notification settings: %v", err)
	}
	assertProtectedNotificationCredential(t, setting.WecomWebhook, "https://example.com/wecom?key=legacy-wecom")
	assertProtectedNotificationCredential(t, setting.DingtalkWebhook, "https://example.com/dingtalk?access_token=legacy-dingtalk-token")
	assertProtectedNotificationCredential(t, setting.DingtalkSecret, "legacy-dingtalk")
	assertProtectedNotificationCredential(t, setting.SmtpPassword, " legacy-smtp-password ")
	assertProtectedNotificationCredential(t, setting.WebhookURL, "https://example.com/custom?token=legacy-webhook-token")
	assertProtectedNotificationCredential(t, setting.WebhookSecret, "legacy-webhook")

	stored, err := repos.Notification.GetByUserID(userID)
	if err != nil {
		t.Fatalf("reload migrated notification settings: %v", err)
	}
	if stored.WecomWebhook != setting.WecomWebhook ||
		stored.DingtalkWebhook != setting.DingtalkWebhook ||
		stored.DingtalkSecret != setting.DingtalkSecret ||
		stored.SmtpPassword != setting.SmtpPassword ||
		stored.WebhookURL != setting.WebhookURL ||
		stored.WebhookSecret != setting.WebhookSecret {
		t.Fatal("read migration was not persisted")
	}
}

func TestNotificationStartupMigrationIsIdempotentAndValidatesCiphertext(t *testing.T) {
	svc, repos := newNotificationTestService(t)
	if err := repos.Notification.Upsert(&model.NotificationSetting{
		UserID:         1,
		DingtalkSecret: "legacy-dingtalk",
		SmtpPassword:   "legacy-smtp",
		WebhookSecret:  "legacy-webhook",
	}); err != nil {
		t.Fatalf("seed legacy notification settings: %v", err)
	}

	if err := svc.MigrateStoredSecrets(); err != nil {
		t.Fatalf("migrate stored notification credentials: %v", err)
	}
	first, err := repos.Notification.GetByUserID(1)
	if err != nil {
		t.Fatalf("load first migration result: %v", err)
	}
	if err := svc.MigrateStoredSecrets(); err != nil {
		t.Fatalf("repeat notification credential migration: %v", err)
	}
	second, err := repos.Notification.GetByUserID(1)
	if err != nil {
		t.Fatalf("load second migration result: %v", err)
	}
	if first.DingtalkSecret != second.DingtalkSecret ||
		first.SmtpPassword != second.SmtpPassword ||
		first.WebhookSecret != second.WebhookSecret {
		t.Fatal("idempotent migration rewrote protected credentials")
	}

	wrongKeyService := NewNotificationService(repos.Notification, repos.User, "different-jwt-secret-with-at-least-32-characters")
	err = wrongKeyService.MigrateStoredSecrets()
	if err == nil {
		t.Fatal("migration with an incompatible JWT secret unexpectedly succeeded")
	}
	assertNotificationMessageDoesNotExpose(t, err.Error(), []string{
		"legacy-dingtalk",
		"legacy-smtp",
		"legacy-webhook",
		first.DingtalkSecret,
		first.SmtpPassword,
		first.WebhookSecret,
	})
}

func TestNotificationStartupMigrationReencryptsFallbackKey(t *testing.T) {
	_, repos := newNotificationTestService(t)
	oldKey := "old-notification-key-with-at-least-32-characters"
	newKey := "new-notification-key-with-at-least-32-characters"
	oldCiphertext, err := protectNotificationSecret("rotated-notification-secret", oldKey)
	if err != nil {
		t.Fatalf("protect old notification credential: %v", err)
	}
	if err := repos.Notification.Upsert(&model.NotificationSetting{
		UserID:        1,
		WebhookSecret: oldCiphertext,
	}); err != nil {
		t.Fatalf("seed old notification credential: %v", err)
	}

	svc := NewNotificationService(repos.Notification, repos.User, newKey, oldKey)
	if err := svc.MigrateStoredSecrets(); err != nil {
		t.Fatalf("migrate fallback-key notification credential: %v", err)
	}
	first, err := repos.Notification.GetByUserID(1)
	if err != nil {
		t.Fatalf("load migrated notification credential: %v", err)
	}
	if first.WebhookSecret == oldCiphertext {
		t.Fatal("fallback-key notification ciphertext was not rotated")
	}
	plainText, err := revealNotificationSecret(first.WebhookSecret, newKey)
	if err != nil || plainText != "rotated-notification-secret" {
		t.Fatalf("reveal migrated notification credential: plaintext=%q err=%v", plainText, err)
	}
	if _, err := revealNotificationSecret(first.WebhookSecret, oldKey); err == nil {
		t.Fatal("migrated notification credential still decrypts with fallback key")
	}

	if err := svc.MigrateStoredSecrets(); err != nil {
		t.Fatalf("repeat notification credential migration: %v", err)
	}
	second, err := repos.Notification.GetByUserID(1)
	if err != nil {
		t.Fatalf("reload notification credential: %v", err)
	}
	if second.WebhookSecret != first.WebhookSecret {
		t.Fatal("idempotent notification migration rewrote active-key ciphertext")
	}
}

func TestNotificationStartupMigrationDoesNotPartiallyWriteOnKeyMismatch(t *testing.T) {
	_, repos := newNotificationTestService(t)
	if err := repos.Notification.Upsert(&model.NotificationSetting{
		UserID:         1,
		DingtalkSecret: "still-plaintext",
	}); err != nil {
		t.Fatalf("seed legacy plaintext credential: %v", err)
	}
	protectedValue, err := protectNotificationSecret("protected-with-original-key", notificationTestEncryptionSecret)
	if err != nil {
		t.Fatalf("protect existing credential: %v", err)
	}
	if err := repos.Notification.Upsert(&model.NotificationSetting{
		UserID:        2,
		WebhookSecret: protectedValue,
	}); err != nil {
		t.Fatalf("seed existing encrypted credential: %v", err)
	}

	wrongKeyService := NewNotificationService(repos.Notification, repos.User, "different-jwt-secret-with-at-least-32-characters")
	if err := wrongKeyService.MigrateStoredSecrets(); err == nil {
		t.Fatal("migration with an incompatible JWT secret unexpectedly succeeded")
	}
	first, err := repos.Notification.GetByUserID(1)
	if err != nil {
		t.Fatalf("reload legacy plaintext credential: %v", err)
	}
	if first.DingtalkSecret != "still-plaintext" {
		t.Fatalf("failed startup migration partially rewrote earlier credential: %q", first.DingtalkSecret)
	}
}

func TestNotificationCredentialUsesIndependentEncryptionDomain(t *testing.T) {
	aiCiphertext, err := protectAISecret("ai-provider-secret", notificationTestEncryptionSecret)
	if err != nil {
		t.Fatalf("protect AI secret: %v", err)
	}
	if isProtectedNotificationSecret(aiCiphertext) {
		t.Fatal("AI provider ciphertext was accepted as a notification credential envelope")
	}

	notificationCiphertext, err := protectNotificationSecret("notification-secret", notificationTestEncryptionSecret)
	if err != nil {
		t.Fatalf("protect notification secret: %v", err)
	}
	if strings.HasPrefix(notificationCiphertext, aiSecretPrefix) {
		t.Fatal("notification credential reused the AI provider envelope")
	}
}

func TestNotificationDeliveryRevealsProtectedCredentials(t *testing.T) {
	svc, _ := newNotificationTestService(t)

	dingtalkCiphertext, err := protectNotificationSecret("dingtalk-signing-secret", notificationTestEncryptionSecret)
	if err != nil {
		t.Fatalf("protect dingtalk secret: %v", err)
	}
	dingtalkEndpoint, err := protectNotificationSecret("https://oapi.dingtalk.com/robot/send?access_token=test", notificationTestEncryptionSecret)
	if err != nil {
		t.Fatalf("protect dingtalk endpoint: %v", err)
	}
	endpoint, err := svc.dingtalkWebhookURL(dingtalkEndpoint, dingtalkCiphertext, 123456789)
	if err != nil {
		t.Fatalf("build signed dingtalk endpoint: %v", err)
	}
	parsed, err := url.Parse(endpoint)
	if err != nil {
		t.Fatalf("parse signed dingtalk endpoint: %v", err)
	}
	if got, want := parsed.Query().Get("sign"), svc.dingtalkSign(123456789, "dingtalk-signing-secret"); got != want {
		t.Fatalf("dingtalk signature = %q, want %q", got, want)
	}
	if strings.Contains(endpoint, "dingtalk-signing-secret") {
		t.Fatal("signed dingtalk endpoint exposed the signing secret")
	}

	smtpCiphertext, err := protectNotificationSecret(" smtp password with spaces ", notificationTestEncryptionSecret)
	if err != nil {
		t.Fatalf("protect smtp password: %v", err)
	}
	auth, err := svc.smtpAuth(&model.NotificationSetting{
		SmtpHost:     "smtp.example.com",
		SmtpUser:     "mail-user",
		SmtpPassword: smtpCiphertext,
	})
	if err != nil {
		t.Fatalf("build smtp auth: %v", err)
	}
	protocol, response, err := auth.Start(&smtp.ServerInfo{
		Name: "smtp.example.com",
		TLS:  true,
		Auth: []string{"PLAIN"},
	})
	if err != nil {
		t.Fatalf("start smtp auth: %v", err)
	}
	if protocol != "PLAIN" || string(response) != "\x00mail-user\x00 smtp password with spaces " {
		t.Fatalf("smtp auth did not receive the original password bytes")
	}
}

func TestNotificationWebhookSignsWithRevealedProtectedSecret(t *testing.T) {
	svc, _ := newNotificationTestService(t)
	protectedSecret, err := protectNotificationSecret("webhook-signing-secret", notificationTestEncryptionSecret)
	if err != nil {
		t.Fatalf("protect webhook secret: %v", err)
	}
	protectedEndpoint, err := protectNotificationSecret("https://hooks.example.com/ledger?token=stored-token", notificationTestEncryptionSecret)
	if err != nil {
		t.Fatalf("protect webhook endpoint: %v", err)
	}

	svc.httpClient = &http.Client{Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
		if got := req.URL.Query().Get("token"); got != "stored-token" {
			t.Fatalf("webhook endpoint was not revealed before delivery: token=%q", got)
		}
		body, err := io.ReadAll(req.Body)
		if err != nil {
			t.Fatalf("read webhook request: %v", err)
		}
		if got, want := req.Header.Get(webhookSignatureHeader), signWebhookPayload(body, "webhook-signing-secret"); got != want {
			t.Fatalf("webhook signature = %q, want %q", got, want)
		}
		if strings.Contains(req.Header.Get(webhookSignatureHeader), "webhook-signing-secret") {
			t.Fatal("webhook signature header exposed the raw secret")
		}
		return &http.Response{
			StatusCode: http.StatusOK,
			Body:       io.NopCloser(strings.NewReader("ok")),
			Header:     make(http.Header),
		}, nil
	})}

	result := svc.TestWebhook(protectedEndpoint, protectedSecret)
	if !result.Success {
		t.Fatalf("signed webhook test failed: %s", result.Message)
	}
}

func TestNotificationCustomWebhookAcceptsAnySuccessfulHTTPStatus(t *testing.T) {
	svc, _ := newNotificationTestService(t)
	svc.httpClient = &http.Client{Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
		return &http.Response{
			StatusCode: http.StatusNoContent,
			Body:       io.NopCloser(strings.NewReader("")),
			Header:     make(http.Header),
		}, nil
	})}

	result := svc.TestWebhook("https://hooks.example.com/ledger", "")
	if !result.Success {
		t.Fatalf("204 webhook response was treated as failure: %s", result.Message)
	}
}

func TestNotificationRobotWebhookRejectsBusinessErrorOnHTTP200(t *testing.T) {
	svc, _ := newNotificationTestService(t)
	svc.httpClient = &http.Client{Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
		return &http.Response{
			StatusCode: http.StatusOK,
			Body:       io.NopCloser(strings.NewReader(`{"errcode":310000,"errmsg":"invalid access_token=secret-token"}`)),
			Header:     make(http.Header),
		}, nil
	})}

	result := svc.TestWecom("https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=test")
	if result.Success {
		t.Fatal("robot business error was reported as success")
	}
	assertNotificationMessageDoesNotExpose(t, result.Message, []string{"310000", "access_token", "secret-token"})
}

func TestNotificationDingtalkTestReusesStoredSecretWhenRequestOmitsIt(t *testing.T) {
	svc, _ := newNotificationTestService(t)
	const userID uint = 9
	if _, err := svc.Update(userID, NotificationSettingRequest{
		DingtalkWebhook: "https://oapi.dingtalk.com/robot/send?access_token=test",
		DingtalkSecret:  "stored-dingtalk-secret",
	}); err != nil {
		t.Fatalf("store dingtalk credential: %v", err)
	}

	svc.httpClient = &http.Client{Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
		timestamp, err := strconv.ParseInt(req.URL.Query().Get("timestamp"), 10, 64)
		if err != nil {
			t.Fatalf("parse dingtalk timestamp: %v", err)
		}
		if got, want := req.URL.Query().Get("sign"), svc.dingtalkSign(timestamp, "stored-dingtalk-secret"); got != want {
			t.Fatalf("dingtalk signature = %q, want %q", got, want)
		}
		return &http.Response{
			StatusCode: http.StatusOK,
			Body:       io.NopCloser(strings.NewReader("ok")),
			Header:     make(http.Header),
		}, nil
	})}

	result := svc.TestDingtalkForUser(userID, "", "")
	if !result.Success {
		t.Fatalf("dingtalk test with stored credential failed: %s", result.Message)
	}
}

func TestNotificationWebhookTestCredentialMatrixDoesNotPersist(t *testing.T) {
	svc, repos := newNotificationTestService(t)
	const userID uint = 19
	const oldEndpoint = "https://hooks.example.test/stored"
	const newEndpoint = "https://hooks.example.test/one-time"
	const oldSecret = "stored-webhook-secret"
	const newSecret = "one-time-webhook-secret"
	if _, err := svc.Update(userID, NotificationSettingRequest{
		WebhookURL:    oldEndpoint,
		WebhookSecret: oldSecret,
	}); err != nil {
		t.Fatalf("store webhook credentials: %v", err)
	}
	storedBefore, err := repos.Notification.GetByUserID(userID)
	if err != nil {
		t.Fatalf("load stored credentials: %v", err)
	}

	tests := []struct {
		name             string
		suppliedEndpoint string
		suppliedSecret   string
		wantEndpoint     string
		wantSecret       string
	}{
		{name: "stored endpoint and stored secret", wantEndpoint: oldEndpoint, wantSecret: oldSecret},
		{name: "stored endpoint and one-time secret", suppliedSecret: newSecret, wantEndpoint: oldEndpoint, wantSecret: newSecret},
		{name: "one-time endpoint and one-time secret", suppliedEndpoint: newEndpoint, suppliedSecret: newSecret, wantEndpoint: newEndpoint, wantSecret: newSecret},
		{name: "one-time endpoint and blank secret", suppliedEndpoint: newEndpoint, wantEndpoint: newEndpoint},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			called := false
			svc.httpClient = &http.Client{Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
				called = true
				if req.URL.String() != tt.wantEndpoint {
					t.Fatalf("test request endpoint = %q, want %q", req.URL.String(), tt.wantEndpoint)
				}
				body, err := io.ReadAll(req.Body)
				if err != nil {
					t.Fatalf("read webhook body: %v", err)
				}
				wantSignature := ""
				if tt.wantSecret != "" {
					wantSignature = signWebhookPayload(body, tt.wantSecret)
				}
				if req.Header.Get(webhookSignatureHeader) != wantSignature {
					t.Fatal("test request used the wrong one-time/stored secret boundary")
				}
				return &http.Response{
					StatusCode: http.StatusOK,
					Body:       io.NopCloser(strings.NewReader("ok")),
					Header:     make(http.Header),
				}, nil
			})}

			result := svc.TestWebhookForUser(userID, tt.suppliedEndpoint, tt.suppliedSecret)
			if !result.Success || !called {
				t.Fatalf("webhook test failed: %s", result.Message)
			}
			storedAfter, err := repos.Notification.GetByUserID(userID)
			if err != nil {
				t.Fatalf("reload stored credentials: %v", err)
			}
			if storedAfter.WebhookURL != storedBefore.WebhookURL || storedAfter.WebhookSecret != storedBefore.WebhookSecret {
				t.Fatal("one-time webhook test persisted endpoint or secret")
			}
		})
	}
}

func TestNotificationWecomTestReusesStoredEndpoint(t *testing.T) {
	svc, _ := newNotificationTestService(t)
	const userID uint = 29
	const endpoint = "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=test"
	if _, err := svc.Update(userID, NotificationSettingRequest{WecomWebhook: endpoint}); err != nil {
		t.Fatalf("store wecom endpoint: %v", err)
	}
	svc.httpClient = &http.Client{Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
		if req.URL.String() != endpoint {
			t.Fatalf("wecom endpoint = %q, want stored endpoint", req.URL.String())
		}
		return &http.Response{StatusCode: http.StatusOK, Body: io.NopCloser(strings.NewReader(`{"errcode":0}`)), Header: make(http.Header)}, nil
	})}
	if result := svc.TestWecomForUser(userID, ""); !result.Success {
		t.Fatalf("wecom test with stored endpoint failed: %s", result.Message)
	}
}

func TestNotificationTestsFailSafelyWithoutStoredEndpoint(t *testing.T) {
	svc, _ := newNotificationTestService(t)
	if result := svc.TestWecomForUser(999, ""); result.Success {
		t.Fatal("wecom test unexpectedly succeeded without configuration")
	}
	if result := svc.TestDingtalkForUser(999, "", ""); result.Success {
		t.Fatal("dingtalk test unexpectedly succeeded without configuration")
	}
	if result := svc.TestWebhookForUser(999, "", ""); result.Success {
		t.Fatal("webhook test unexpectedly succeeded without configuration")
	}
}

func TestNotificationUpdateRejectsPrivateEndpointsByDefault(t *testing.T) {
	svc, _ := newNotificationTestService(t)
	_, err := svc.Update(1, NotificationSettingRequest{
		Enabled:        true,
		WebhookEnabled: true,
		WebhookURL:     "https://169.254.169.254/latest/meta-data",
	})
	if !errors.Is(err, ErrNotificationEndpointInvalid) {
		t.Fatalf("update error = %v, want ErrNotificationEndpointInvalid", err)
	}

	_, err = svc.Update(1, NotificationSettingRequest{
		Enabled:      true,
		EmailEnabled: true,
		SmtpHost:     "127.0.0.1",
		SmtpPort:     25,
	})
	if !errors.Is(err, ErrNotificationEndpointInvalid) {
		t.Fatalf("SMTP update error = %v, want ErrNotificationEndpointInvalid", err)
	}
}

func TestNotificationEmailRecipientUsesConfiguredAddressAndFallsBackToProfile(t *testing.T) {
	svc, repos := newNotificationTestService(t)

	recipient, err := svc.notificationEmailRecipient(&model.NotificationSetting{
		EmailTo: "  alerts@example.test  ",
	}, 999)
	if err != nil {
		t.Fatalf("configured recipient: %v", err)
	}
	if recipient != "alerts@example.test" {
		t.Fatalf("configured recipient = %q, want trimmed email_to", recipient)
	}

	user := &model.User{
		Username:     "recipient-user",
		PasswordHash: "hashed",
		Email:        "  profile@example.test  ",
	}
	if err := repos.User.Create(user); err != nil {
		t.Fatalf("create user: %v", err)
	}
	recipient, err = svc.notificationEmailRecipient(&model.NotificationSetting{}, user.ID)
	if err != nil {
		t.Fatalf("profile recipient: %v", err)
	}
	if recipient != "profile@example.test" {
		t.Fatalf("profile recipient = %q, want trimmed profile email", recipient)
	}
}

func TestNotificationPrivateEndpointRequiresOperatorOptIn(t *testing.T) {
	svc, _ := newNotificationTestService(t)
	svc.WithPrivateOutboundNetworks(true)
	if _, err := svc.Update(1, NotificationSettingRequest{
		Enabled:        true,
		WebhookEnabled: true,
		WebhookURL:     "http://127.0.0.1:8080/hook",
	}); err != nil {
		t.Fatalf("opted-in private webhook update: %v", err)
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

func assertProtectedNotificationCredential(t *testing.T, protectedValue, plainText string) {
	t.Helper()
	if protectedValue == plainText || !strings.HasPrefix(protectedValue, notificationSecretPrefix) {
		t.Fatalf("notification credential was not protected: %q", protectedValue)
	}
	revealed, err := revealNotificationSecret(protectedValue, notificationTestEncryptionSecret)
	if err != nil {
		t.Fatalf("reveal protected notification credential: %v", err)
	}
	if revealed != plainText {
		t.Fatalf("revealed notification credential = %q, want %q", revealed, plainText)
	}
}

type roundTripFunc func(*http.Request) (*http.Response, error)

func (fn roundTripFunc) RoundTrip(req *http.Request) (*http.Response, error) {
	return fn(req)
}

func newNotificationTestService(t *testing.T) (*NotificationService, *repository.Repositories) {
	t.Helper()

	db, err := database.Init(t.TempDir() + "/ledger.db")
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	return NewNotificationService(repos.Notification, repos.User, notificationTestEncryptionSecret), repos
}
