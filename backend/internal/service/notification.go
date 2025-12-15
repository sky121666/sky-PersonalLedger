package service

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/smtp"
	"strings"
	"time"

	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

var (
	ErrNotificationNotFound = errors.New("notification setting not found")
)

type NotificationService struct {
	repo     *repository.NotificationRepository
	userRepo *repository.UserRepository
}

func NewNotificationService(repo *repository.NotificationRepository, userRepo *repository.UserRepository) *NotificationService {
	return &NotificationService{repo: repo, userRepo: userRepo}
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
	NotifyLogin        bool `json:"notify_login"`
	NotifyAnnualReport bool `json:"notify_annual_report"`
	AdvanceDays        int  `json:"advance_days"`
}

func (s *NotificationService) Get(userID uint) (*model.NotificationSetting, error) {
	setting, err := s.repo.GetByUserID(userID)
	if err != nil {
		// Return default settings if not found
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
	return setting, nil
}

func (s *NotificationService) Update(userID uint, req NotificationSettingRequest) (*model.NotificationSetting, error) {
	setting := &model.NotificationSetting{
		UserID:             userID,
		Enabled:            req.Enabled,
		WecomEnabled:       req.WecomEnabled,
		WecomWebhook:       req.WecomWebhook,
		DingtalkEnabled:    req.DingtalkEnabled,
		DingtalkWebhook:    req.DingtalkWebhook,
		DingtalkSecret:     req.DingtalkSecret,
		EmailEnabled:       req.EmailEnabled,
		SmtpHost:           req.SmtpHost,
		SmtpPort:           req.SmtpPort,
		SmtpUser:           req.SmtpUser,
		SmtpFrom:           req.SmtpFrom,
		EmailTo:            req.EmailTo,
		WebhookEnabled:     req.WebhookEnabled,
		WebhookURL:         req.WebhookURL,
		WebhookSecret:      req.WebhookSecret,
		NotifyPaymentDue:   req.NotifyPaymentDue,
		NotifyBudgetAlert:  req.NotifyBudgetAlert,
		NotifyLendingDue:   req.NotifyLendingDue,
		NotifyLogin:        req.NotifyLogin,
		NotifyAnnualReport: req.NotifyAnnualReport,
		AdvanceDays:        req.AdvanceDays,
	}

	// Only update password if provided
	if req.SmtpPassword != "" {
		setting.SmtpPassword = req.SmtpPassword
	} else {
		existing, _ := s.repo.GetByUserID(userID)
		if existing != nil {
			setting.SmtpPassword = existing.SmtpPassword
		}
	}

	if err := s.repo.Upsert(setting); err != nil {
		return nil, err
	}

	return s.repo.GetByUserID(userID)
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
	url := webhook

	if secret != "" {
		sign := s.dingtalkSign(timestamp, secret)
		url = fmt.Sprintf("%s&timestamp=%d&sign=%s", webhook, timestamp, sign)
	}

	payload := map[string]interface{}{
		"msgtype": "text",
		"text": map[string]string{
			"content": "【个人记账】测试通知\n这是一条测试消息，如果您收到此消息，说明钉钉通知配置成功！",
		},
	}
	return s.sendWebhook(url, payload)
}

func (s *NotificationService) TestEmail(setting *model.NotificationSetting, userID uint) *TestResult {
	subject := "【个人记账】测试通知"
	body := "这是一条测试消息，如果您收到此邮件，说明邮箱通知配置成功！"

	err := s.sendEmail(setting, userID, subject, body)
	if err != nil {
		return &TestResult{Success: false, Message: err.Error()}
	}
	return &TestResult{Success: true, Message: "邮件发送成功"}
}

func (s *NotificationService) TestWebhook(url, secret string) *TestResult {
	payload := map[string]interface{}{
		"event":     "test",
		"message":   "这是一条测试消息",
		"timestamp": time.Now().Unix(),
	}
	return s.sendWebhook(url, payload)
}

func (s *NotificationService) dingtalkSign(timestamp int64, secret string) string {
	stringToSign := fmt.Sprintf("%d\n%s", timestamp, secret)
	h := hmac.New(sha256.New, []byte(secret))
	h.Write([]byte(stringToSign))
	return base64.StdEncoding.EncodeToString(h.Sum(nil))
}

func (s *NotificationService) sendWebhook(url string, payload interface{}) *TestResult {
	data, _ := json.Marshal(payload)

	req, err := http.NewRequest("POST", url, bytes.NewBuffer(data))
	if err != nil {
		return &TestResult{Success: false, Message: err.Error()}
	}
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return &TestResult{Success: false, Message: err.Error()}
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return &TestResult{Success: false, Message: fmt.Sprintf("HTTP %d", resp.StatusCode)}
	}

	return &TestResult{Success: true, Message: "发送成功"}
}

func (s *NotificationService) sendEmail(setting *model.NotificationSetting, userID uint, subject, body string) error {
	if setting.SmtpHost == "" || setting.SmtpUser == "" {
		return errors.New("邮箱配置不完整")
	}

	// Get user email from profile
	user, err := s.userRepo.GetByID(userID)
	if err != nil || user.Email == "" {
		return errors.New("用户邮箱未设置，请在个人信息中设置邮箱地址")
	}

	from := setting.SmtpFrom
	if from == "" {
		from = setting.SmtpUser
	}

	msg := fmt.Sprintf("From: %s\r\nTo: %s\r\nSubject: %s\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n%s",
		from, user.Email, subject, body)

	addr := fmt.Sprintf("%s:%d", setting.SmtpHost, setting.SmtpPort)

	var auth smtp.Auth
	if setting.SmtpPassword != "" {
		auth = smtp.PlainAuth("", setting.SmtpUser, setting.SmtpPassword, setting.SmtpHost)
	}

	return smtp.SendMail(addr, auth, from, []string{user.Email}, []byte(msg))
}

// SendNotification sends a notification through all enabled channels
func (s *NotificationService) SendNotification(userID uint, title, content string) error {
	setting, err := s.repo.GetByUserID(userID)
	if err != nil || !setting.Enabled {
		return nil
	}

	var errs []string

	if setting.WecomEnabled && setting.WecomWebhook != "" {
		payload := map[string]interface{}{
			"msgtype": "text",
			"text": map[string]string{
				"content": fmt.Sprintf("【%s】\n%s", title, content),
			},
		}
		result := s.sendWebhook(setting.WecomWebhook, payload)
		if !result.Success {
			errs = append(errs, "企业微信: "+result.Message)
		}
	}

	if setting.DingtalkEnabled && setting.DingtalkWebhook != "" {
		timestamp := time.Now().UnixMilli()
		url := setting.DingtalkWebhook
		if setting.DingtalkSecret != "" {
			sign := s.dingtalkSign(timestamp, setting.DingtalkSecret)
			url = fmt.Sprintf("%s&timestamp=%d&sign=%s", setting.DingtalkWebhook, timestamp, sign)
		}
		payload := map[string]interface{}{
			"msgtype": "text",
			"text": map[string]string{
				"content": fmt.Sprintf("【%s】\n%s", title, content),
			},
		}
		result := s.sendWebhook(url, payload)
		if !result.Success {
			errs = append(errs, "钉钉: "+result.Message)
		}
	}

	if setting.EmailEnabled {
		err := s.sendEmail(setting, userID, title, content)
		if err != nil {
			errs = append(errs, "邮箱: "+err.Error())
		}
	}

	if setting.WebhookEnabled && setting.WebhookURL != "" {
		payload := map[string]interface{}{
			"title":     title,
			"content":   content,
			"timestamp": time.Now().Unix(),
		}
		result := s.sendWebhook(setting.WebhookURL, payload)
		if !result.Success {
			errs = append(errs, "Webhook: "+result.Message)
		}
	}

	if len(errs) > 0 {
		return errors.New(strings.Join(errs, "; "))
	}
	return nil
}

// SendLoginNotification sends a notification when user logs in from new device/IP
func (s *NotificationService) SendLoginNotification(userID uint, ip, userAgent, device string) error {
	setting, err := s.repo.GetByUserID(userID)
	if err != nil || !setting.Enabled || !setting.NotifyLogin {
		return nil
	}

	now := time.Now()
	title := "登录提醒"
	content := fmt.Sprintf("您的账户刚刚登录\n\n时间: %s\nIP地址: %s\n设备: %s\n\n如果不是您本人操作，请立即修改密码！",
		now.Format("2006-01-02 15:04:05"),
		ip,
		device,
	)

	return s.SendNotification(userID, title, content)
}

// SendLendingDueNotification sends notification for lending due dates
func (s *NotificationService) SendLendingDueNotification(userID uint, contactName string, lendingType string, amount float64, dueDate time.Time, daysUntilDue int) error {
	setting, err := s.repo.GetByUserID(userID)
	if err != nil || !setting.Enabled || !setting.NotifyLendingDue {
		return nil
	}

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

	return s.SendNotification(userID, title, content)
}

// SendAnnualReportNotification sends notification for annual report availability
func (s *NotificationService) SendAnnualReportNotification(userID uint, year int) error {
	setting, err := s.repo.GetByUserID(userID)
	if err != nil || !setting.Enabled || !setting.NotifyAnnualReport {
		return nil
	}

	title := fmt.Sprintf("%d年度财务报告", year)
	content := fmt.Sprintf("您的%d年度财务报告已生成！\n\n快来查看您这一年的收支情况、消费习惯和理财成就吧！\n\n祝您新年快乐，财运亨通！🎉", year)

	return s.SendNotification(userID, title, content)
}

// SendPaymentDueNotification sends notification for loan payment due
func (s *NotificationService) SendPaymentDueNotification(userID uint, loanName string, amount float64, paymentDay int, daysUntilDue int) error {
	setting, err := s.repo.GetByUserID(userID)
	if err != nil || !setting.Enabled || !setting.NotifyPaymentDue {
		return nil
	}

	title := "还款日提醒"
	var content string
	if daysUntilDue == 0 {
		content = fmt.Sprintf("【%s】今天是还款日\n应还金额: ¥%.2f\n请及时还款，避免逾期", loanName, amount)
	} else {
		content = fmt.Sprintf("【%s】还款日临近\n还款日: 每月%d日（%d天后）\n应还金额: ¥%.2f\n请提前准备资金", loanName, paymentDay, daysUntilDue, amount)
	}

	return s.SendNotification(userID, title, content)
}
