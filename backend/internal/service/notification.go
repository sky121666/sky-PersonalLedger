package service

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/smtp"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"gorm.io/gorm"
)

var (
	ErrNotificationNotFound              = errors.New("notification setting not found")
	ErrNotificationEndpointInvalid       = errors.New("notification endpoint is not allowed")
	ErrNotificationCredentialUnavailable = errors.New("notification credential is unavailable")
)

type NotificationService struct {
	repo                  *repository.NotificationRepository
	userRepo              *repository.UserRepository
	httpClient            *http.Client
	outboundNetworkPolicy *outboundNetworkPolicy
	secret                string
	secretMu              sync.Mutex
}

func NewNotificationService(repo *repository.NotificationRepository, userRepo *repository.UserRepository, encryptionSecrets ...string) *NotificationService {
	secret := ""
	if len(encryptionSecrets) > 0 {
		secret = encryptionSecrets[0]
	}
	return (&NotificationService{repo: repo, userRepo: userRepo, secret: secret}).WithPrivateOutboundNetworks(false)
}

// WithPrivateOutboundNetworks is an operator-controlled compatibility switch
// for local gateways. It must never be derived from a user request.
func (s *NotificationService) WithPrivateOutboundNetworks(allow bool) *NotificationService {
	s.outboundNetworkPolicy = newOutboundNetworkPolicy(allow)
	s.httpClient = newSafeOutboundHTTPClient(allow)
	return s
}

type NotificationSettingRequest struct {
	Enabled bool `json:"enabled"`

	WecomEnabled bool   `json:"wecom_enabled"`
	WecomWebhook string `json:"wecom_webhook"`

	DingtalkEnabled bool   `json:"dingtalk_enabled"`
	DingtalkWebhook string `json:"dingtalk_webhook"`
	DingtalkSecret  string `json:"dingtalk_secret"`

	EmailEnabled bool   `json:"email_enabled"`
	SmtpHost     string `json:"smtp_host"`
	SmtpPort     int    `json:"smtp_port"`
	SmtpUser     string `json:"smtp_user"`
	SmtpPassword string `json:"smtp_password"`
	SmtpFrom     string `json:"smtp_from"`
	EmailTo      string `json:"email_to"`

	WebhookEnabled bool   `json:"webhook_enabled"`
	WebhookURL     string `json:"webhook_url"`
	WebhookSecret  string `json:"webhook_secret"`

	NotifyPaymentDue   bool `json:"notify_payment_due"`
	NotifyBudgetAlert  bool `json:"notify_budget_alert"`
	NotifyLendingDue   bool `json:"notify_lending_due"`
	NotifyAnnualReport bool `json:"notify_annual_report"`
	AdvanceDays        int  `json:"advance_days"`
}

func (s *NotificationService) Get(userID uint) (*model.NotificationSetting, error) {
	s.secretMu.Lock()
	defer s.secretMu.Unlock()

	setting, err := s.repo.GetByUserID(userID)
	if err != nil {
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, err
		}
		return &model.NotificationSetting{
			UserID:             userID,
			SmtpPort:           587,
			NotifyPaymentDue:   true,
			NotifyBudgetAlert:  true,
			NotifyLendingDue:   true,
			NotifyLogin:        true,
			NotifyAnnualReport: true,
			AdvanceDays:        3,
		}, nil
	}
	if err := s.migrateSettingSecrets(setting); err != nil {
		return nil, err
	}
	return setting, nil
}

func (s *NotificationService) Update(userID uint, req NotificationSettingRequest) (*model.NotificationSetting, error) {
	if err := s.validateSettingRequest(req); err != nil {
		return nil, err
	}

	s.secretMu.Lock()
	defer s.secretMu.Unlock()

	existing, err := s.repo.GetByUserID(userID)
	if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, err
	}
	if existing != nil {
		if err := s.migrateSettingSecrets(existing); err != nil {
			return nil, err
		}
	}
	setting := &model.NotificationSetting{
		UserID:             userID,
		Enabled:            req.Enabled,
		WecomEnabled:       req.WecomEnabled,
		WecomWebhook:       req.WecomWebhook,
		DingtalkEnabled:    req.DingtalkEnabled,
		DingtalkWebhook:    req.DingtalkWebhook,
		EmailEnabled:       req.EmailEnabled,
		SmtpHost:           req.SmtpHost,
		SmtpPort:           req.SmtpPort,
		SmtpUser:           req.SmtpUser,
		SmtpFrom:           req.SmtpFrom,
		EmailTo:            req.EmailTo,
		WebhookEnabled:     req.WebhookEnabled,
		WebhookURL:         req.WebhookURL,
		NotifyPaymentDue:   req.NotifyPaymentDue,
		NotifyBudgetAlert:  req.NotifyBudgetAlert,
		NotifyLendingDue:   req.NotifyLendingDue,
		NotifyAnnualReport: req.NotifyAnnualReport,
		AdvanceDays:        req.AdvanceDays,
	}

	if req.DingtalkSecret != "" {
		setting.DingtalkSecret, err = protectNotificationSecret(req.DingtalkSecret, s.secret)
		if err != nil {
			return nil, fmt.Errorf("protect dingtalk notification credential: %w", err)
		}
	} else if existing != nil {
		setting.DingtalkSecret = existing.DingtalkSecret
	}

	// Only update password if provided
	if req.SmtpPassword != "" {
		setting.SmtpPassword, err = protectNotificationSecret(req.SmtpPassword, s.secret)
		if err != nil {
			return nil, fmt.Errorf("protect smtp notification credential: %w", err)
		}
	} else if existing != nil {
		setting.SmtpPassword = existing.SmtpPassword
	}

	if req.WebhookSecret != "" {
		setting.WebhookSecret, err = protectNotificationSecret(req.WebhookSecret, s.secret)
		if err != nil {
			return nil, fmt.Errorf("protect webhook notification credential: %w", err)
		}
	} else if existing != nil {
		setting.WebhookSecret = existing.WebhookSecret
	}

	if err := s.repo.Upsert(setting); err != nil {
		return nil, err
	}

	return s.repo.GetByUserID(userID)
}

// MigrateStoredSecrets is called during startup and is safe to call repeatedly.
// It also validates existing encrypted values so an incompatible JWT secret is
// detected before background deliveries start.
func (s *NotificationService) MigrateStoredSecrets() error {
	s.secretMu.Lock()
	defer s.secretMu.Unlock()

	settings, err := s.repo.GetAll()
	if err != nil {
		return fmt.Errorf("load notification settings for credential migration: %w", err)
	}
	changedSettings := make([]model.NotificationSetting, 0, len(settings))
	for index := range settings {
		changed, err := s.prepareSettingSecrets(&settings[index])
		if err != nil {
			return err
		}
		if changed {
			changedSettings = append(changedSettings, settings[index])
		}
	}
	if err := s.repo.UpdateSecretsBatch(changedSettings); err != nil {
		return fmt.Errorf("persist migrated notification credentials: %w", err)
	}
	return nil
}

func (s *NotificationService) migrateSettingSecrets(setting *model.NotificationSetting) error {
	changed, err := s.prepareSettingSecrets(setting)
	if err != nil {
		return err
	}
	if changed {
		if err := s.repo.UpdateSecrets(setting); err != nil {
			return fmt.Errorf("persist migrated notification credentials for setting %d: %w", setting.ID, err)
		}
	}
	return nil
}

func (s *NotificationService) prepareSettingSecrets(setting *model.NotificationSetting) (bool, error) {
	if setting == nil {
		return false, nil
	}

	changed := false
	credentials := []struct {
		name  string
		value *string
	}{
		{name: "dingtalk", value: &setting.DingtalkSecret},
		{name: "smtp", value: &setting.SmtpPassword},
		{name: "webhook", value: &setting.WebhookSecret},
	}
	for _, credential := range credentials {
		if *credential.value == "" {
			continue
		}
		if isProtectedNotificationSecret(*credential.value) {
			if _, err := revealNotificationSecret(*credential.value, s.secret); err != nil {
				return false, fmt.Errorf("validate %s notification credential for setting %d: %w", credential.name, setting.ID, err)
			}
			continue
		}

		protectedValue, err := protectNotificationSecret(*credential.value, s.secret)
		if err != nil {
			return false, fmt.Errorf("migrate %s notification credential for setting %d: %w", credential.name, setting.ID, err)
		}
		if protectedValue != *credential.value {
			*credential.value = protectedValue
			changed = true
		}
	}

	return changed, nil
}

func (s *NotificationService) validateSettingRequest(req NotificationSettingRequest) error {
	allowPrivate := s.outboundNetworkPolicy != nil && s.outboundNetworkPolicy.allowPrivateNetworks
	endpoints := []struct {
		enabled  bool
		endpoint string
	}{
		{enabled: req.WecomEnabled, endpoint: req.WecomWebhook},
		{enabled: req.DingtalkEnabled, endpoint: req.DingtalkWebhook},
		{enabled: req.WebhookEnabled, endpoint: req.WebhookURL},
	}
	for _, candidate := range endpoints {
		if candidate.enabled && validateOutboundURL(candidate.endpoint, allowPrivate) != nil {
			return ErrNotificationEndpointInvalid
		}
	}
	if req.EmailEnabled && validateOutboundHostPort(req.SmtpHost, req.SmtpPort, allowPrivate) != nil {
		return ErrNotificationEndpointInvalid
	}
	return nil
}

type TestResult struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
}

func (s *NotificationService) TestWecom(webhook string) *TestResult {
	payload := map[string]interface{}{
		"msgtype": "text",
		"text": map[string]string{
			"content": "【个人记账】测试通知\n这是一条测试消息，如果您收到此消息，说明企业微信通知配置成功！",
		},
	}
	return s.sendWebhook(webhook, payload)
}

func (s *NotificationService) TestDingtalk(webhook, secret string) *TestResult {
	timestamp := time.Now().UnixMilli()
	endpoint, err := s.dingtalkWebhookURL(webhook, secret, timestamp)
	if err != nil {
		return &TestResult{Success: false, Message: "通知发送失败，请检查通知地址或密钥"}
	}

	payload := map[string]interface{}{
		"msgtype": "text",
		"text": map[string]string{
			"content": "【个人记账】测试通知\n这是一条测试消息，如果您收到此消息，说明钉钉通知配置成功！",
		},
	}
	return s.sendWebhook(endpoint, payload)
}

func (s *NotificationService) TestDingtalkForUser(userID uint, webhook, suppliedSecret string) *TestResult {
	secret, err := s.notificationCredentialForTest(userID, suppliedSecret, notificationChannelDingtalk)
	if err != nil {
		return &TestResult{Success: false, Message: "通知发送失败，请检查通知地址或密钥"}
	}
	return s.TestDingtalk(webhook, secret)
}

func (s *NotificationService) TestEmail(setting *model.NotificationSetting, userID uint) *TestResult {
	subject := "【个人记账】测试通知"
	body := "这是一条测试消息，如果您收到此邮件，说明邮箱通知配置成功！"

	err := s.sendEmail(setting, userID, subject, body)
	if err != nil {
		return &TestResult{Success: false, Message: sanitizeNotificationEmailError(err)}
	}
	return &TestResult{Success: true, Message: "邮件发送成功"}
}

func (s *NotificationService) TestWebhook(url, secret string) *TestResult {
	payload := map[string]interface{}{
		"event":     "test",
		"message":   "这是一条测试消息",
		"timestamp": time.Now().Unix(),
	}
	return s.sendWebhookWithSecret(url, payload, secret)
}

func (s *NotificationService) TestWebhookForUser(userID uint, endpoint, suppliedSecret string) *TestResult {
	secret, err := s.notificationCredentialForTest(userID, suppliedSecret, notificationChannelWebhook)
	if err != nil {
		return &TestResult{Success: false, Message: "通知发送失败，请检查通知地址或密钥"}
	}
	return s.TestWebhook(endpoint, secret)
}

func (s *NotificationService) dingtalkSign(timestamp int64, secret string) string {
	stringToSign := fmt.Sprintf("%d\n%s", timestamp, secret)
	h := hmac.New(sha256.New, []byte(secret))
	h.Write([]byte(stringToSign))
	return base64.StdEncoding.EncodeToString(h.Sum(nil))
}

func (s *NotificationService) dingtalkWebhookURL(webhook, protectedSecret string, timestamp int64) (string, error) {
	secret, err := revealNotificationSecret(protectedSecret, s.secret)
	if err != nil {
		return "", fmt.Errorf("%w: dingtalk", ErrNotificationCredentialUnavailable)
	}
	if secret == "" {
		return webhook, nil
	}

	parsed, err := url.ParseRequestURI(webhook)
	if err != nil || parsed == nil {
		return "", ErrNotificationEndpointInvalid
	}
	query := parsed.Query()
	query.Set("timestamp", strconv.FormatInt(timestamp, 10))
	query.Set("sign", s.dingtalkSign(timestamp, secret))
	parsed.RawQuery = query.Encode()
	return parsed.String(), nil
}

func (s *NotificationService) sendWebhook(url string, payload interface{}) *TestResult {
	return s.sendWebhookRequest(url, payload, "", true)
}

// Custom webhook receivers can authenticate the exact JSON request body by
// comparing this HMAC-SHA256 header with their configured shared secret.
const webhookSignatureHeader = "X-Webhook-Signature"

func (s *NotificationService) sendWebhookWithSecret(endpoint string, payload interface{}, protectedSecret string) *TestResult {
	return s.sendWebhookRequest(endpoint, payload, protectedSecret, false)
}

func (s *NotificationService) sendWebhookRequest(endpoint string, payload interface{}, protectedSecret string, validateRobotResponse bool) *TestResult {
	allowPrivate := s.outboundNetworkPolicy != nil && s.outboundNetworkPolicy.allowPrivateNetworks
	if validateOutboundURL(endpoint, allowPrivate) != nil {
		return &TestResult{Success: false, Message: "通知发送失败，请检查通知地址或网络"}
	}
	data, err := json.Marshal(payload)
	if err != nil {
		return &TestResult{Success: false, Message: "通知发送失败，请检查通知配置"}
	}
	secret, err := revealNotificationSecret(protectedSecret, s.secret)
	if err != nil {
		return &TestResult{Success: false, Message: "通知发送失败，请检查通知地址或密钥"}
	}

	req, err := http.NewRequest("POST", endpoint, bytes.NewBuffer(data))
	if err != nil {
		return &TestResult{Success: false, Message: "通知发送失败，请检查通知地址或网络"}
	}
	req.Header.Set("Content-Type", "application/json")
	if secret != "" {
		req.Header.Set(webhookSignatureHeader, signWebhookPayload(data, secret))
	}

	client := s.httpClient
	if client == nil {
		client = newSafeOutboundHTTPClient(false)
	}
	resp, err := client.Do(req)
	if err != nil {
		return &TestResult{Success: false, Message: "通知发送失败，请检查通知地址或网络"}
	}
	defer resp.Body.Close()

	if resp.StatusCode < http.StatusOK || resp.StatusCode >= http.StatusMultipleChoices {
		return &TestResult{Success: false, Message: fmt.Sprintf("HTTP %d", resp.StatusCode)}
	}
	if validateRobotResponse {
		body, err := io.ReadAll(io.LimitReader(resp.Body, 64<<10))
		if err != nil {
			return &TestResult{Success: false, Message: "通知发送失败，请检查通知配置或网络"}
		}
		if robotWebhookRejected(body) {
			return &TestResult{Success: false, Message: "通知服务拒绝了请求，请检查通知配置"}
		}
	}

	return &TestResult{Success: true, Message: "发送成功"}
}

func robotWebhookRejected(body []byte) bool {
	var result map[string]any
	if json.Unmarshal(body, &result) != nil {
		return false
	}
	value, exists := result["errcode"]
	if !exists {
		return false
	}
	switch code := value.(type) {
	case float64:
		return code != 0
	case string:
		return strings.TrimSpace(code) != "" && strings.TrimSpace(code) != "0"
	default:
		return true
	}
}

func signWebhookPayload(payload []byte, secret string) string {
	mac := hmac.New(sha256.New, []byte(secret))
	_, _ = mac.Write(payload)
	return "sha256=" + hex.EncodeToString(mac.Sum(nil))
}

func (s *NotificationService) sendEmail(setting *model.NotificationSetting, userID uint, subject, body string) error {
	if setting.SmtpHost == "" || setting.SmtpUser == "" {
		return errors.New("邮箱配置不完整")
	}

	recipient, err := s.notificationEmailRecipient(setting, userID)
	if err != nil {
		return err
	}

	from := setting.SmtpFrom
	if from == "" {
		from = setting.SmtpUser
	}

	msg := fmt.Sprintf("From: %s\r\nTo: %s\r\nSubject: %s\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n%s",
		from, recipient, subject, body)

	auth, err := s.smtpAuth(setting)
	if err != nil {
		return err
	}

	return sendSMTPMessage(s.outboundNetworkPolicy, setting.SmtpHost, setting.SmtpPort, auth, from, []string{recipient}, []byte(msg))
}

func (s *NotificationService) smtpAuth(setting *model.NotificationSetting) (smtp.Auth, error) {
	password, err := revealNotificationSecret(setting.SmtpPassword, s.secret)
	if err != nil {
		return nil, fmt.Errorf("%w: smtp", ErrNotificationCredentialUnavailable)
	}
	if password == "" {
		return nil, nil
	}
	return smtp.PlainAuth("", setting.SmtpUser, password, setting.SmtpHost), nil
}

func (s *NotificationService) notificationCredentialForTest(userID uint, suppliedSecret, channel string) (string, error) {
	if suppliedSecret != "" {
		return suppliedSecret, nil
	}
	setting, err := s.Get(userID)
	if err != nil {
		return "", err
	}
	switch channel {
	case notificationChannelDingtalk:
		return setting.DingtalkSecret, nil
	case notificationChannelWebhook:
		return setting.WebhookSecret, nil
	default:
		return "", errors.New("unsupported notification credential channel")
	}
}

func (s *NotificationService) notificationEmailRecipient(setting *model.NotificationSetting, userID uint) (string, error) {
	if recipient := strings.TrimSpace(setting.EmailTo); recipient != "" {
		return recipient, nil
	}

	// Fall back to the profile email for existing web clients that do not
	// expose a separate recipient field.
	user, err := s.userRepo.GetByID(userID)
	if err != nil || strings.TrimSpace(user.Email) == "" {
		return "", errors.New("用户邮箱未设置，请在个人信息中设置邮箱地址")
	}
	return strings.TrimSpace(user.Email), nil
}

const (
	notificationChannelWecom    = "wecom"
	notificationChannelDingtalk = "dingtalk"
	notificationChannelEmail    = "email"
	notificationChannelWebhook  = "webhook"
)

func enabledNotificationChannels(setting *model.NotificationSetting) []string {
	channels := make([]string, 0, 4)
	if setting.WecomEnabled && setting.WecomWebhook != "" {
		channels = append(channels, notificationChannelWecom)
	}
	if setting.DingtalkEnabled && setting.DingtalkWebhook != "" {
		channels = append(channels, notificationChannelDingtalk)
	}
	if setting.EmailEnabled {
		channels = append(channels, notificationChannelEmail)
	}
	if setting.WebhookEnabled && setting.WebhookURL != "" {
		channels = append(channels, notificationChannelWebhook)
	}
	return channels
}

func notificationChannelLabel(channel string) string {
	switch channel {
	case notificationChannelWecom:
		return "企业微信"
	case notificationChannelDingtalk:
		return "钉钉"
	case notificationChannelEmail:
		return "邮箱"
	case notificationChannelWebhook:
		return "Webhook"
	default:
		return channel
	}
}

func (s *NotificationService) sendNotificationChannel(
	setting *model.NotificationSetting,
	userID uint,
	channel string,
	title string,
	content string,
) error {
	switch channel {
	case notificationChannelWecom:
		payload := map[string]interface{}{
			"msgtype": "text",
			"text": map[string]string{
				"content": fmt.Sprintf("【%s】\n%s", title, content),
			},
		}
		result := s.sendWebhook(setting.WecomWebhook, payload)
		if !result.Success {
			return errors.New(result.Message)
		}
	case notificationChannelDingtalk:
		timestamp := time.Now().UnixMilli()
		endpoint, err := s.dingtalkWebhookURL(setting.DingtalkWebhook, setting.DingtalkSecret, timestamp)
		if err != nil {
			return err
		}
		payload := map[string]interface{}{
			"msgtype": "text",
			"text": map[string]string{
				"content": fmt.Sprintf("【%s】\n%s", title, content),
			},
		}
		result := s.sendWebhook(endpoint, payload)
		if !result.Success {
			return errors.New(result.Message)
		}
	case notificationChannelEmail:
		if err := s.sendEmail(setting, userID, title, content); err != nil {
			return errors.New(sanitizeNotificationEmailError(err))
		}
	case notificationChannelWebhook:
		payload := map[string]interface{}{
			"title":     title,
			"content":   content,
			"timestamp": time.Now().Unix(),
		}
		result := s.sendWebhookWithSecret(setting.WebhookURL, payload, setting.WebhookSecret)
		if !result.Success {
			return errors.New(result.Message)
		}
	default:
		return fmt.Errorf("unsupported notification channel")
	}
	return nil
}

// SendNotification sends a notification through all enabled channels
func (s *NotificationService) SendNotification(userID uint, title, content string) error {
	setting, err := s.Get(userID)
	if err != nil {
		return err
	}
	if !setting.Enabled {
		return nil
	}

	var errs []string
	for _, channel := range enabledNotificationChannels(setting) {
		if err := s.sendNotificationChannel(setting, userID, channel, title, content); err != nil {
			errs = append(errs, notificationChannelLabel(channel)+": "+err.Error())
		}
	}

	if len(errs) > 0 {
		return errors.New(strings.Join(errs, "; "))
	}
	return nil
}

func sanitizeNotificationEmailError(err error) string {
	if err == nil {
		return ""
	}
	switch err.Error() {
	case "邮箱配置不完整", "用户邮箱未设置，请在个人信息中设置邮箱地址":
		return err.Error()
	default:
		return "邮件发送失败，请检查邮箱配置或网络"
	}
}

func lendingDueNotificationMessage(
	contactName string,
	lendingType string,
	amount float64,
	dueDate time.Time,
	daysUntilDue int,
) (string, string) {
	var title, content string
	if lendingType == "lend_out" {
		title = "借出款项到期提醒"
		if daysUntilDue == 0 {
			content = fmt.Sprintf("您借给 %s 的 ¥%.2f 今天到期\n请及时跟进收款", contactName, amount)
		} else if daysUntilDue < 0 {
			content = fmt.Sprintf("您借给 %s 的 ¥%.2f 已逾期 %d 天\n请及时跟进收款", contactName, amount, -daysUntilDue)
		} else {
			content = fmt.Sprintf("您借给 %s 的 ¥%.2f 将于 %d 天后到期\n到期日: %s", contactName, amount, daysUntilDue, dueDate.Format("2006-01-02"))
		}
	} else {
		title = "借入款项到期提醒"
		if daysUntilDue == 0 {
			content = fmt.Sprintf("您向 %s 借的 ¥%.2f 今天到期\n请及时安排还款", contactName, amount)
		} else if daysUntilDue < 0 {
			content = fmt.Sprintf("您向 %s 借的 ¥%.2f 已逾期 %d 天\n请尽快安排还款", contactName, amount, -daysUntilDue)
		} else {
			content = fmt.Sprintf("您向 %s 借的 ¥%.2f 将于 %d 天后到期\n到期日: %s", contactName, amount, daysUntilDue, dueDate.Format("2006-01-02"))
		}
	}
	return title, content
}

func annualReportNotificationMessage(year int) (string, string) {
	title := fmt.Sprintf("%d年度财务报告", year)
	content := fmt.Sprintf("您的%d年度财务报告已生成！\n\n快来查看您这一年的收支情况、消费习惯和理财成就吧！\n\n祝您新年快乐，财运亨通！🎉", year)
	return title, content
}

func budgetAlertNotificationMessage(
	name string,
	budgetAmount float64,
	spentAmount float64,
	percentage int,
) (string, string) {
	return "预算使用提醒", fmt.Sprintf(
		"【%s】本月已使用 ¥%.2f / ¥%.2f（%d%%）\n请及时检查后续支出安排",
		name,
		spentAmount,
		budgetAmount,
		percentage,
	)
}

func paymentDueNotificationMessage(
	loanName string,
	amount float64,
	paymentDay int,
	daysUntilDue int,
) (string, string) {
	title := "还款日提醒"
	if daysUntilDue == 0 {
		return title, fmt.Sprintf("【%s】今天是还款日\n应还金额: ¥%.2f\n请及时还款，避免逾期", loanName, amount)
	}
	return title, fmt.Sprintf("【%s】还款日临近\n还款日: 每月%d日（%d天后）\n应还金额: ¥%.2f\n请提前准备资金", loanName, paymentDay, daysUntilDue, amount)
}

// SendLendingDueNotification sends notification for lending due dates
func (s *NotificationService) SendLendingDueNotification(userID uint, contactName string, lendingType string, amount float64, dueDate time.Time, daysUntilDue int) error {
	setting, err := s.Get(userID)
	if err != nil {
		return err
	}
	if !setting.Enabled || !setting.NotifyLendingDue {
		return nil
	}

	title, content := lendingDueNotificationMessage(contactName, lendingType, amount, dueDate, daysUntilDue)
	return s.SendNotification(userID, title, content)
}

// SendAnnualReportNotification sends notification for annual report availability
func (s *NotificationService) SendAnnualReportNotification(userID uint, year int) error {
	setting, err := s.Get(userID)
	if err != nil {
		return err
	}
	if !setting.Enabled || !setting.NotifyAnnualReport {
		return nil
	}

	title, content := annualReportNotificationMessage(year)
	return s.SendNotification(userID, title, content)
}

func (s *NotificationService) SendBudgetAlertNotification(userID uint, name string, budgetAmount, spentAmount float64, percentage int) error {
	setting, err := s.Get(userID)
	if err != nil {
		return err
	}
	if !setting.Enabled || !setting.NotifyBudgetAlert {
		return nil
	}

	title, content := budgetAlertNotificationMessage(name, budgetAmount, spentAmount, percentage)
	return s.SendNotification(userID, title, content)
}

// SendPaymentDueNotification sends notification for loan payment due
func (s *NotificationService) SendPaymentDueNotification(userID uint, loanName string, amount float64, paymentDay int, daysUntilDue int) error {
	setting, err := s.Get(userID)
	if err != nil {
		return err
	}
	if !setting.Enabled || !setting.NotifyPaymentDue {
		return nil
	}

	title, content := paymentDueNotificationMessage(loanName, amount, paymentDay, daysUntilDue)
	return s.SendNotification(userID, title, content)
}
