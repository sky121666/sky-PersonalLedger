package service

import (
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

const notificationScheduleInterval = time.Hour

type NotificationScheduler struct {
	notificationService *NotificationService
	notificationRepo    *repository.NotificationRepository
	notificationLogRepo *repository.NotificationLogRepository
	reminderRepo        *repository.ReminderRepository
	lendingRepo         *repository.LendingRepository
	budgetService       *BudgetService
	userRepo            *repository.UserRepository
	stopChan            chan struct{}
	now                 func() time.Time
	mu                  sync.Mutex
	checkMu             sync.Mutex
	running             bool
	sendChannel         func(*model.NotificationSetting, uint, string, string, string) error
}

type NotificationScheduleRunResult struct {
	Users     int
	Attempted int
	Sent      int
	Skipped   int
	Failed    int
}

func NewNotificationScheduler(
	notificationService *NotificationService,
	notificationRepo *repository.NotificationRepository,
	notificationLogRepo *repository.NotificationLogRepository,
	reminderRepo *repository.ReminderRepository,
	lendingRepo *repository.LendingRepository,
	budgetService *BudgetService,
	userRepo *repository.UserRepository,
) *NotificationScheduler {
	scheduler := &NotificationScheduler{
		notificationService: notificationService,
		notificationRepo:    notificationRepo,
		notificationLogRepo: notificationLogRepo,
		reminderRepo:        reminderRepo,
		lendingRepo:         lendingRepo,
		budgetService:       budgetService,
		userRepo:            userRepo,
		stopChan:            make(chan struct{}),
		now:                 time.Now,
	}
	scheduler.sendChannel = notificationService.sendNotificationChannel
	return scheduler
}

func (s *NotificationScheduler) Start() {
	s.mu.Lock()
	if s.running {
		s.mu.Unlock()
		return
	}
	s.running = true
	s.mu.Unlock()
	go s.run()
}

func (s *NotificationScheduler) Stop() {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.running {
		close(s.stopChan)
		s.running = false
	}
}

func (s *NotificationScheduler) run() {
	ticker := time.NewTicker(notificationScheduleInterval)
	defer ticker.Stop()
	s.CheckAndNotify()
	for {
		select {
		case <-ticker.C:
			s.CheckAndNotify()
		case <-s.stopChan:
			return
		}
	}
}

func (s *NotificationScheduler) CheckAndNotify() NotificationScheduleRunResult {
	s.checkMu.Lock()
	defer s.checkMu.Unlock()

	result := NotificationScheduleRunResult{}
	users, err := s.userRepo.GetAll()
	if err != nil {
		result.Failed++
		return result
	}
	now := s.now()
	for _, user := range users {
		setting, err := s.notificationService.Get(user.ID)
		if err != nil || !setting.Enabled || !notificationSettingHasChannel(setting) {
			result.Skipped++
			continue
		}
		result.Users++
		s.checkPaymentReminders(user.ID, setting, now, &result)
		s.checkLendings(user.ID, setting, now, &result)
		s.checkBudgets(user.ID, setting, now, &result)
		s.checkAnnualReport(user.ID, setting, now, &result)
	}
	return result
}

func (s *NotificationScheduler) checkPaymentReminders(
	userID uint,
	setting *model.NotificationSetting,
	now time.Time,
	result *NotificationScheduleRunResult,
) {
	if !setting.NotifyPaymentDue {
		return
	}
	reminders, err := s.reminderRepo.GetByUserID(userID)
	if err != nil {
		result.Failed++
		return
	}
	for _, reminder := range reminders {
		if !reminder.IsEnabled || reminder.PaymentDay < 1 || reminder.PaymentDay > 31 {
			continue
		}
		amount := reminderNotificationAmount(&reminder)
		if amount <= 0 {
			continue
		}
		advanceDays := reminder.AdvanceDays
		if advanceDays <= 0 {
			advanceDays = setting.AdvanceDays
		}
		advanceDays = clampNotificationAdvanceDays(advanceDays)
		daysUntilDue := daysUntilNextMonthDay(now, reminder.PaymentDay)
		if daysUntilDue != 0 && daysUntilDue != advanceDays {
			continue
		}
		dueDate := startOfLocalDay(now).AddDate(0, 0, daysUntilDue)
		dedupeKey := fmt.Sprintf("payment:%s:%s:%d", reminder.ID, dueDate.Format("2006-01-02"), daysUntilDue)
		title, content := paymentDueNotificationMessage(reminder.Name, amount, reminder.PaymentDay, daysUntilDue)
		s.deliver(result, userID, setting, "payment_due", dedupeKey, title, content)
	}
}

func (s *NotificationScheduler) checkLendings(
	userID uint,
	setting *model.NotificationSetting,
	now time.Time,
	result *NotificationScheduleRunResult,
) {
	if !setting.NotifyLendingDue {
		return
	}
	lendings, err := s.lendingRepo.GetByUserID(userID, false)
	if err != nil {
		result.Failed++
		return
	}
	advanceDays := clampNotificationAdvanceDays(setting.AdvanceDays)
	for _, lending := range lendings {
		if lending.DueDate == nil || lending.CurrentBalance <= 0 {
			continue
		}
		daysUntilDue := localCalendarDayDifference(now, *lending.DueDate)
		if daysUntilDue != advanceDays && daysUntilDue != 0 && daysUntilDue != -1 {
			continue
		}
		dedupeKey := fmt.Sprintf("lending:%s:%s:%d", lending.ID, lending.DueDate.Format("2006-01-02"), daysUntilDue)
		title, content := lendingDueNotificationMessage(
			lending.ContactName,
			lending.Type,
			lending.CurrentBalance.Float64(),
			*lending.DueDate,
			daysUntilDue,
		)
		s.deliver(result, userID, setting, "lending_due", dedupeKey, title, content)
	}
}

func (s *NotificationScheduler) checkBudgets(
	userID uint,
	setting *model.NotificationSetting,
	now time.Time,
	result *NotificationScheduleRunResult,
) {
	if !setting.NotifyBudgetAlert {
		return
	}
	list, err := s.budgetService.List(userID, now.Format("2006-01"))
	if err != nil {
		result.Failed++
		return
	}
	items := make([]BudgetItem, 0, 1+len(list.CategoryBudgets)+len(list.MemberBudgets))
	if list.TotalBudget != nil {
		items = append(items, *list.TotalBudget)
	}
	items = append(items, list.CategoryBudgets...)
	items = append(items, list.MemberBudgets...)
	for _, item := range items {
		if item.Amount <= 0 || item.Percentage < item.AlertThreshold {
			continue
		}
		name := budgetNotificationName(item)
		dedupeKey := fmt.Sprintf("budget:%s:%s", item.ID, now.Format("2006-01"))
		title, content := budgetAlertNotificationMessage(name, item.Amount.Float64(), item.Spent.Float64(), item.Percentage)
		s.deliver(result, userID, setting, "budget_alert", dedupeKey, title, content)
	}
}

func (s *NotificationScheduler) checkAnnualReport(
	userID uint,
	setting *model.NotificationSetting,
	now time.Time,
	result *NotificationScheduleRunResult,
) {
	if !setting.NotifyAnnualReport || now.Month() != time.January || now.Day() != 1 {
		return
	}
	year := now.Year() - 1
	dedupeKey := fmt.Sprintf("annual:%d:%d", userID, year)
	title, content := annualReportNotificationMessage(year)
	s.deliver(result, userID, setting, "annual_report", dedupeKey, title, content)
}

func (s *NotificationScheduler) deliver(
	result *NotificationScheduleRunResult,
	userID uint,
	setting *model.NotificationSetting,
	notificationType string,
	dedupeKey string,
	title string,
	content string,
) {
	for _, channel := range enabledNotificationChannels(setting) {
		sent, err := s.notificationLogRepo.HasSent(userID, notificationType, channel, dedupeKey)
		if err != nil {
			result.Failed++
			continue
		}
		if sent {
			result.Skipped++
			continue
		}
		result.Attempted++
		if err := s.sendChannel(setting, userID, channel, title, content); err != nil {
			result.Failed++
			_ = s.notificationLogRepo.Record(userID, notificationType, channel, dedupeKey, title, content, "failed", err.Error())
			continue
		}
		if err := s.notificationLogRepo.Record(userID, notificationType, channel, dedupeKey, title, content, "sent", ""); err != nil {
			result.Failed++
			log.Printf("Warning: failed to record %s notification delivery for %s: %v", notificationType, channel, err)
			continue
		}
		result.Sent++
	}
}

func notificationSettingHasChannel(setting *model.NotificationSetting) bool {
	return len(enabledNotificationChannels(setting)) > 0
}

func reminderNotificationAmount(reminder *model.Reminder) float64 {
	if reminder.CurrentBalance != nil && *reminder.CurrentBalance > 0 {
		return reminder.CurrentBalance.Float64()
	}
	if reminder.Amount != nil && *reminder.Amount > 0 {
		return reminder.Amount.Float64()
	}
	return 0
}

func budgetNotificationName(item BudgetItem) string {
	if item.MemberName != "" && item.CategoryName != "" {
		return item.MemberName + " · " + item.CategoryName
	}
	if item.MemberName != "" {
		return item.MemberName
	}
	if item.CategoryName != "" {
		return item.CategoryName
	}
	return "总预算"
}

func clampNotificationAdvanceDays(value int) int {
	if value < 0 {
		return 0
	}
	if value > 30 {
		return 30
	}
	return value
}

func daysUntilNextMonthDay(now time.Time, paymentDay int) int {
	today := startOfLocalDay(now)
	due := clampedMonthDay(today.Year(), today.Month(), paymentDay, today.Location())
	if due.Before(today) {
		nextMonth := today.AddDate(0, 1, 0)
		due = clampedMonthDay(nextMonth.Year(), nextMonth.Month(), paymentDay, today.Location())
	}
	return calendarDayDifference(today, due)
}

func localCalendarDayDifference(now, target time.Time) int {
	return calendarDayDifference(now, target)
}

func clampedMonthDay(year int, month time.Month, day int, location *time.Location) time.Time {
	lastDay := time.Date(year, month+1, 0, 0, 0, 0, 0, location).Day()
	if day > lastDay {
		day = lastDay
	}
	return time.Date(year, month, day, 0, 0, 0, 0, location)
}
