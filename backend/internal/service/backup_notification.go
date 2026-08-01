package service

import (
	"errors"

	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

// restoreNotificationSettingsTx deliberately treats notification credentials
// as target-instance state. They are excluded from backup JSON, so replacing a
// row from the decoded backup would silently erase working credentials.
//
// Legacy backups omit notification_settings entirely; in that case the target
// row is left untouched. Newer backups restore the serializable settings while
// retaining secrets already stored on the target instance.
func restoreNotificationSettingsTx(tx *gorm.DB, userID uint, backup *model.NotificationSetting) error {
	if backup == nil {
		return nil
	}

	var existing model.NotificationSetting
	err := tx.Where("user_id = ?", userID).First(&existing).Error
	if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
		return err
	}

	restored := *backup
	restored.ID = 0
	restored.UserID = userID
	if err == nil {
		// Update only fields that are intentionally represented in backup JSON.
		// Any current or future json:"-" credential columns remain untouched.
		return tx.Model(&existing).Updates(map[string]any{
			"enabled":              restored.Enabled,
			"wecom_enabled":        restored.WecomEnabled,
			"wecom_webhook":        restored.WecomWebhook,
			"dingtalk_enabled":     restored.DingtalkEnabled,
			"dingtalk_webhook":     restored.DingtalkWebhook,
			"email_enabled":        restored.EmailEnabled,
			"smtp_host":            restored.SmtpHost,
			"smtp_port":            restored.SmtpPort,
			"smtp_user":            restored.SmtpUser,
			"smtp_from":            restored.SmtpFrom,
			"email_to":             restored.EmailTo,
			"webhook_enabled":      restored.WebhookEnabled,
			"webhook_url":          restored.WebhookURL,
			"notify_payment_due":   restored.NotifyPaymentDue,
			"notify_budget_alert":  restored.NotifyBudgetAlert,
			"notify_lending_due":   restored.NotifyLendingDue,
			"notify_login":         restored.NotifyLogin,
			"notify_annual_report": restored.NotifyAnnualReport,
			"advance_days":         restored.AdvanceDays,
		}).Error
	}

	// No target credentials exist to preserve. Sensitive fields are empty after
	// JSON decoding and are intentionally not accepted from a backup payload.
	restored.DingtalkSecret = ""
	restored.SmtpPassword = ""
	restored.WebhookSecret = ""
	return tx.Create(&restored).Error
}
