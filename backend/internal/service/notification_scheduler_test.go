package service

import (
	"errors"
	"path/filepath"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

func TestNotificationSchedulerSendsDueItemsOnceAndRetriesFailures(t *testing.T) {
	scheduler, repos, userID := newNotificationSchedulerTestSubject(t)
	now := time.Date(2026, time.July, 10, 9, 0, 0, 0, time.Local)
	scheduler.now = func() time.Time { return now }
	amount := 300.0
	if err := repos.Reminder.Create(&model.Reminder{
		ID:          uuid.NewString(),
		UserID:      userID,
		Name:        "信用卡",
		PaymentDay:  13,
		AdvanceDays: 3,
		Amount:      &amount,
		IsEnabled:   true,
	}); err != nil {
		t.Fatalf("create reminder: %v", err)
	}
	dueDate := now.AddDate(0, 0, 3)
	if err := repos.Lending.Create(&model.Lending{
		ID:             uuid.NewString(),
		UserID:         userID,
		Type:           "lend_out",
		ContactName:    "张三",
		Principal:      500,
		CurrentBalance: 500,
		LendDate:       now.AddDate(0, -1, 0),
		DueDate:        &dueDate,
	}); err != nil {
		t.Fatalf("create lending: %v", err)
	}

	paymentCalls := 0
	lendingCalls := 0
	scheduler.sendChannel = func(_ *model.NotificationSetting, _ uint, _ string, title string, _ string) error {
		switch title {
		case "还款日提醒":
			paymentCalls++
			return nil
		default:
			lendingCalls++
			if lendingCalls == 1 {
				return errors.New("temporary failure")
			}
			return nil
		}
	}

	first := scheduler.CheckAndNotify()
	if paymentCalls != 1 || lendingCalls != 1 || first.Sent != 1 || first.Failed != 1 {
		t.Fatalf("first run = %+v, payment=%d lending=%d", first, paymentCalls, lendingCalls)
	}
	second := scheduler.CheckAndNotify()
	if paymentCalls != 1 || lendingCalls != 2 || second.Sent != 1 {
		t.Fatalf("second run = %+v, payment=%d lending=%d", second, paymentCalls, lendingCalls)
	}
	third := scheduler.CheckAndNotify()
	if paymentCalls != 1 || lendingCalls != 2 || third.Attempted != 0 {
		t.Fatalf("third run = %+v, payment=%d lending=%d", third, paymentCalls, lendingCalls)
	}
}

func TestNotificationSchedulerSendsBudgetAndAnnualAlertsOnce(t *testing.T) {
	scheduler, repos, userID := newNotificationSchedulerTestSubject(t)
	now := time.Date(2027, time.January, 1, 9, 0, 0, 0, time.Local)
	scheduler.now = func() time.Time { return now }
	accountID := createAccountForTest(t, repos, userID, 1000)
	categoryID := createBudgetCategoryForTest(t, repos, userID, "餐饮")
	if err := repos.Budget.Create(&model.Budget{
		ID:             uuid.NewString(),
		UserID:         userID,
		CategoryID:     &categoryID,
		Amount:         100,
		AlertThreshold: 80,
		IsActive:       true,
	}); err != nil {
		t.Fatalf("create budget: %v", err)
	}
	if err := repos.Transaction.Create(&model.Transaction{
		ID:              uuid.NewString(),
		UserID:          userID,
		AccountID:       accountID,
		CategoryID:      &categoryID,
		Type:            "expense",
		Amount:          90,
		TransactionDate: now,
		Source:          "manual",
	}); err != nil {
		t.Fatalf("create transaction: %v", err)
	}

	budgetCalls := 0
	annualCalls := 0
	scheduler.sendChannel = func(_ *model.NotificationSetting, _ uint, _ string, title string, _ string) error {
		if title == "预算使用提醒" {
			budgetCalls++
		} else {
			annualCalls++
		}
		return nil
	}

	first := scheduler.CheckAndNotify()
	second := scheduler.CheckAndNotify()
	if budgetCalls != 1 || annualCalls != 1 || first.Sent != 2 || second.Attempted != 0 {
		t.Fatalf("runs = first %+v second %+v, budget=%d annual=%d", first, second, budgetCalls, annualCalls)
	}
}

func TestNotificationSchedulerRetriesOnlyFailedChannel(t *testing.T) {
	scheduler, repos, userID := newNotificationSchedulerTestSubject(t)
	now := time.Date(2026, time.July, 10, 9, 0, 0, 0, time.Local)
	scheduler.now = func() time.Time { return now }
	setting, err := repos.Notification.GetByUserID(userID)
	if err != nil {
		t.Fatalf("get notification settings: %v", err)
	}
	setting.WebhookEnabled = true
	setting.WebhookURL = "https://example.com/secondary-hook"
	if err := repos.Notification.Update(setting); err != nil {
		t.Fatalf("enable second channel: %v", err)
	}
	amount := 100.0
	if err := repos.Reminder.Create(&model.Reminder{
		ID:          uuid.NewString(),
		UserID:      userID,
		Name:        "信用卡",
		PaymentDay:  13,
		AdvanceDays: 3,
		Amount:      &amount,
		IsEnabled:   true,
	}); err != nil {
		t.Fatalf("create reminder: %v", err)
	}

	calls := map[string]int{}
	scheduler.sendChannel = func(_ *model.NotificationSetting, _ uint, channel string, _ string, _ string) error {
		calls[channel]++
		if channel == notificationChannelWebhook && calls[channel] == 1 {
			return errors.New("temporary failure")
		}
		return nil
	}

	first := scheduler.CheckAndNotify()
	if first.Attempted != 2 || first.Sent != 1 || first.Failed != 1 {
		t.Fatalf("first run = %+v, want two attempts with one success and one failure", first)
	}
	second := scheduler.CheckAndNotify()
	if second.Attempted != 1 || second.Sent != 1 || second.Failed != 0 {
		t.Fatalf("second run = %+v, want only failed channel retried", second)
	}
	third := scheduler.CheckAndNotify()
	if third.Attempted != 0 {
		t.Fatalf("third run = %+v, want no attempts", third)
	}
	if calls[notificationChannelWecom] != 1 || calls[notificationChannelWebhook] != 2 {
		t.Fatalf("channel calls = %#v, want wecom once and webhook twice", calls)
	}
}

func TestDaysUntilNextMonthDayClampsShortMonths(t *testing.T) {
	now := time.Date(2026, time.February, 27, 12, 0, 0, 0, time.Local)
	if got := daysUntilNextMonthDay(now, 31); got != 1 {
		t.Fatalf("days until clamped February payment = %d, want 1", got)
	}
}

func newNotificationSchedulerTestSubject(t *testing.T) (*NotificationScheduler, *repository.Repositories, uint) {
	t.Helper()
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	user := &model.User{Username: "notification-user", PasswordHash: "hash", Email: "user@example.com"}
	if err := repos.User.Create(user); err != nil {
		t.Fatalf("create user: %v", err)
	}
	if err := repos.Notification.Upsert(&model.NotificationSetting{
		UserID:             user.ID,
		Enabled:            true,
		WecomEnabled:       true,
		WecomWebhook:       "https://example.com/hook",
		NotifyPaymentDue:   true,
		NotifyBudgetAlert:  true,
		NotifyLendingDue:   true,
		NotifyAnnualReport: true,
		AdvanceDays:        3,
	}); err != nil {
		t.Fatalf("create notification settings: %v", err)
	}
	budgetService := NewBudgetService(repos.Budget, repos.Transaction, repos.FamilyMember, repos.Category)
	notificationService := NewNotificationService(repos.Notification, repos.User)
	scheduler := NewNotificationScheduler(
		notificationService,
		repos.Notification,
		repos.NotificationLog,
		repos.Reminder,
		repos.Lending,
		budgetService,
		repos.User,
	)
	return scheduler, repos, user.ID
}
