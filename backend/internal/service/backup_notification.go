package service

import (
	"errors"
	"strings"

	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

// NotificationSettingsBackup contains only portable reminder preferences.
// Delivery identity, endpoints, credentials, and channel switches are
// target-instance state and must never be rebound by a restore.
type NotificationSettingsBackup struct {
	NotifyPaymentDue   bool `json:"notify_payment_due"`
	NotifyBudgetAlert  bool `json:"notify_budget_alert"`
	NotifyLendingDue   bool `json:"notify_lending_due"`
	NotifyLogin        bool `json:"notify_login"`
	NotifyAnnualReport bool `json:"notify_annual_report"`
	AdvanceDays        int  `json:"advance_days"`
}

func newNotificationSettingsBackup(setting *model.NotificationSetting) *NotificationSettingsBackup {
	if setting == nil {
		return nil
	}
	return &NotificationSettingsBackup{
		NotifyPaymentDue:   setting.NotifyPaymentDue,
		NotifyBudgetAlert:  setting.NotifyBudgetAlert,
		NotifyLendingDue:   setting.NotifyLendingDue,
		NotifyLogin:        setting.NotifyLogin,
		NotifyAnnualReport: setting.NotifyAnnualReport,
		AdvanceDays:        setting.AdvanceDays,
	}
}

// restoreNotificationSettingsTx deliberately treats notification credentials
// as target-instance state. They are excluded from backup JSON, so replacing a
// row from the decoded backup would silently erase working credentials.
//
// Backups without notification_settings leave the target row untouched.
// Supported backups restore portable preferences while retaining endpoint and
// secret material already stored on the target instance.
func restoreNotificationSettingsTx(tx *gorm.DB, userID uint, backup *NotificationSettingsBackup) error {
	if backup == nil {
		return nil
	}

	var existing model.NotificationSetting
	err := tx.Where("user_id = ?", userID).First(&existing).Error
	if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
		return err
	}

	preferences := map[string]any{
		"notify_payment_due":   backup.NotifyPaymentDue,
		"notify_budget_alert":  backup.NotifyBudgetAlert,
		"notify_lending_due":   backup.NotifyLendingDue,
		"notify_login":         backup.NotifyLogin,
		"notify_annual_report": backup.NotifyAnnualReport,
		"advance_days":         backup.AdvanceDays,
	}
	if err == nil {
		return tx.Model(&existing).Updates(preferences).Error
	}

	// No target delivery identity exists. Create a disabled local row carrying
	// only the portable reminder preferences.
	created := model.NotificationSetting{
		UserID:             userID,
		NotifyPaymentDue:   backup.NotifyPaymentDue,
		NotifyBudgetAlert:  backup.NotifyBudgetAlert,
		NotifyLendingDue:   backup.NotifyLendingDue,
		NotifyLogin:        backup.NotifyLogin,
		NotifyAnnualReport: backup.NotifyAnnualReport,
		AdvanceDays:        backup.AdvanceDays,
	}
	if err := tx.Create(&created).Error; err != nil {
		return err
	}
	// GORM applies model default:true tags to zero bools during Create. Force
	// the portable backup values afterward so false preferences round-trip.
	return tx.Model(&created).Updates(preferences).Error
}

// pinNotificationEmailRecipientBeforeProfileRestoreTx prevents restoring a
// profile email from silently redirecting a locally configured SMTP channel
// that relied on the profile-email fallback.
func pinNotificationEmailRecipientBeforeProfileRestoreTx(tx *gorm.DB, userID uint) error {
	var setting model.NotificationSetting
	if err := tx.Where("user_id = ?", userID).First(&setting).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil
		}
		return err
	}
	if !setting.EmailEnabled || strings.TrimSpace(setting.EmailTo) != "" {
		return nil
	}

	var user model.User
	if err := tx.Select("id", "email").First(&user, "id = ?", userID).Error; err != nil {
		return err
	}
	currentEmail := strings.TrimSpace(user.Email)
	if currentEmail == "" {
		return tx.Model(&setting).Update("email_enabled", false).Error
	}
	return tx.Model(&setting).Update("email_to", currentEmail).Error
}
