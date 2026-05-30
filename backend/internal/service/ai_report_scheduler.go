package service

import (
	"encoding/json"
	"errors"
	"sync"
	"time"

	"github.com/sky/personal-ledger/internal/repository"
)

const aiReportScheduleSettingKey = "ai_report_schedule"

type AIReportScheduler struct {
	reportService *AIReportService
	systemRepo    *repository.SystemRepository
	userRepo      *repository.UserRepository
	stopChan      chan struct{}
	now           func() time.Time
	mu            sync.Mutex
	running       bool
}

type AIReportScheduleSettings struct {
	Enabled        bool   `json:"enabled"`
	WeeklyEnabled  bool   `json:"weekly_enabled"`
	MonthlyEnabled bool   `json:"monthly_enabled"`
	Hour           int    `json:"hour"`
	LastWeeklyRun  string `json:"last_weekly_run,omitempty"`
	LastMonthlyRun string `json:"last_monthly_run,omitempty"`
}

type AIReportScheduleRunResult struct {
	ReportType  string `json:"report_type"`
	PeriodStart string `json:"period_start"`
	PeriodEnd   string `json:"period_end"`
	Attempted   int    `json:"attempted"`
	Succeeded   int    `json:"succeeded"`
	Skipped     int    `json:"skipped"`
	Failed      int    `json:"failed"`
}

func NewAIReportScheduler(reportService *AIReportService, systemRepo *repository.SystemRepository, userRepo *repository.UserRepository) *AIReportScheduler {
	return &AIReportScheduler{
		reportService: reportService,
		systemRepo:    systemRepo,
		userRepo:      userRepo,
		stopChan:      make(chan struct{}),
		now:           time.Now,
	}
}

func (s *AIReportScheduler) Start() {
	s.mu.Lock()
	if s.running {
		s.mu.Unlock()
		return
	}
	s.running = true
	s.mu.Unlock()

	go s.run()
}

func (s *AIReportScheduler) Stop() {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.running {
		close(s.stopChan)
		s.running = false
	}
}

func (s *AIReportScheduler) run() {
	ticker := time.NewTicker(1 * time.Hour)
	defer ticker.Stop()

	s.CheckAndGenerate()

	for {
		select {
		case <-ticker.C:
			s.CheckAndGenerate()
		case <-s.stopChan:
			return
		}
	}
}

func (s *AIReportScheduler) GetSettings() (*AIReportScheduleSettings, error) {
	value, err := s.systemRepo.Get(aiReportScheduleSettingKey)
	if err != nil || value == "" {
		return defaultAIReportScheduleSettings(), err
	}

	var settings AIReportScheduleSettings
	if err := json.Unmarshal([]byte(value), &settings); err != nil {
		return defaultAIReportScheduleSettings(), nil
	}
	normalizeAIReportScheduleSettings(&settings)
	return &settings, nil
}

func (s *AIReportScheduler) SaveSettings(settings *AIReportScheduleSettings) error {
	normalizeAIReportScheduleSettings(settings)
	data, err := json.Marshal(settings)
	if err != nil {
		return err
	}
	return s.systemRepo.Set(aiReportScheduleSettingKey, string(data))
}

func (s *AIReportScheduler) CheckAndGenerate() []AIReportScheduleRunResult {
	settings, err := s.GetSettings()
	if err != nil || !settings.Enabled {
		return nil
	}

	now := s.now()
	if now.Hour() != settings.Hour {
		return nil
	}

	results := s.generateDueReports(settings, now, false)
	if len(results) > 0 {
		_ = s.SaveSettings(settings)
	}
	return results
}

func (s *AIReportScheduler) TriggerDueReports() ([]AIReportScheduleRunResult, error) {
	settings, err := s.GetSettings()
	if err != nil {
		return nil, err
	}
	results := s.generateDueReports(settings, s.now(), true)
	if len(results) > 0 {
		if err := s.SaveSettings(settings); err != nil {
			return results, err
		}
	}
	return results, nil
}

func (s *AIReportScheduler) generateDueReports(settings *AIReportScheduleSettings, now time.Time, force bool) []AIReportScheduleRunResult {
	today := now.Format("2006-01-02")
	var results []AIReportScheduleRunResult

	if settings.WeeklyEnabled && (force || settings.LastWeeklyRun != today) {
		start, end := previousFullWeek(now)
		result := s.generateForAllUsers("weekly", start, end)
		results = append(results, result)
		settings.LastWeeklyRun = today
	}
	if settings.MonthlyEnabled && (force || settings.LastMonthlyRun != today) {
		start, end := previousFullMonth(now)
		result := s.generateForAllUsers("monthly", start, end)
		results = append(results, result)
		settings.LastMonthlyRun = today
	}
	return results
}

func (s *AIReportScheduler) generateForAllUsers(reportType string, start time.Time, end time.Time) AIReportScheduleRunResult {
	result := AIReportScheduleRunResult{
		ReportType:  reportType,
		PeriodStart: start.Format("2006-01-02"),
		PeriodEnd:   end.Format("2006-01-02"),
	}
	users, err := s.userRepo.GetAll()
	if err != nil {
		result.Failed++
		return result
	}

	for _, user := range users {
		result.Attempted++
		_, err := s.reportService.Generate(user.ID, GenerateAIReportRequest{
			ReportType:  reportType,
			PeriodStart: result.PeriodStart,
			PeriodEnd:   result.PeriodEnd,
			MaskNames:   true,
		})
		if err == nil {
			result.Succeeded++
			continue
		}
		if errors.Is(err, ErrAIReportProviderNotFound) {
			result.Skipped++
			continue
		}
		result.Failed++
	}
	return result
}

func defaultAIReportScheduleSettings() *AIReportScheduleSettings {
	return &AIReportScheduleSettings{
		Enabled:        false,
		WeeklyEnabled:  true,
		MonthlyEnabled: true,
		Hour:           8,
	}
}

func normalizeAIReportScheduleSettings(settings *AIReportScheduleSettings) {
	if settings.Hour < 0 || settings.Hour > 23 {
		settings.Hour = 8
	}
}

func previousFullWeek(now time.Time) (time.Time, time.Time) {
	currentDay := dateOnly(now)
	daysSinceMonday := (int(currentDay.Weekday()) + 6) % 7
	thisWeekStart := currentDay.AddDate(0, 0, -daysSinceMonday)
	start := thisWeekStart.AddDate(0, 0, -7)
	end := thisWeekStart.AddDate(0, 0, -1)
	return start, end
}

func previousFullMonth(now time.Time) (time.Time, time.Time) {
	currentDay := dateOnly(now)
	thisMonthStart := time.Date(currentDay.Year(), currentDay.Month(), 1, 0, 0, 0, 0, currentDay.Location())
	start := thisMonthStart.AddDate(0, -1, 0)
	end := thisMonthStart.AddDate(0, 0, -1)
	return start, end
}

func dateOnly(value time.Time) time.Time {
	return time.Date(value.Year(), value.Month(), value.Day(), 0, 0, 0, 0, value.Location())
}
