package service

import (
	"errors"
	"time"
)

var ErrInvalidLocalDate = errors.New("invalid local date")

// parseLocalDate treats a date-only value as a calendar date in the server's
// configured local timezone. time.Parse would silently assign UTC and can
// shift the displayed date when the value is read back in another timezone.
func parseLocalDate(value string) (time.Time, error) {
	return time.ParseInLocation("2006-01-02", value, time.Local)
}

func endOfCalendarDay(value time.Time) time.Time {
	year, month, day := value.Date()
	start := time.Date(year, month, day, 0, 0, 0, 0, value.Location())
	return start.AddDate(0, 0, 1).Add(-time.Nanosecond)
}

// calendarDayDifference compares civil dates instead of elapsed hours. This
// remains correct across 23-hour and 25-hour daylight-saving days.
func calendarDayDifference(start, end time.Time) int {
	startYear, startMonth, startDay := start.Date()
	endYear, endMonth, endDay := end.Date()
	startUTC := time.Date(startYear, startMonth, startDay, 0, 0, 0, 0, time.UTC)
	endUTC := time.Date(endYear, endMonth, endDay, 0, 0, 0, 0, time.UTC)
	return int(endUTC.Unix()/secondsPerDay - startUTC.Unix()/secondsPerDay)
}

func startOfLocalDay(value time.Time) time.Time {
	year, month, day := value.Date()
	return time.Date(year, month, day, 0, 0, 0, 0, value.Location())
}

const secondsPerDay int64 = 24 * 60 * 60
