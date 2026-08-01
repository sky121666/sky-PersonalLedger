package service

import (
	"testing"
	"time"
)

func TestCalendarDayDifferenceIgnoresDaylightSavingDuration(t *testing.T) {
	location, err := time.LoadLocation("America/New_York")
	if err != nil {
		t.Fatalf("load timezone: %v", err)
	}

	tests := []struct {
		name  string
		start time.Time
		end   time.Time
	}{
		{
			name:  "spring forward is still one calendar day",
			start: time.Date(2026, time.March, 8, 0, 0, 0, 0, location),
			end:   time.Date(2026, time.March, 9, 0, 0, 0, 0, location),
		},
		{
			name:  "fall back is still one calendar day",
			start: time.Date(2026, time.November, 1, 0, 0, 0, 0, location),
			end:   time.Date(2026, time.November, 2, 0, 0, 0, 0, location),
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := calendarDayDifference(test.start, test.end); got != 1 {
				t.Fatalf("calendar day difference = %d, want 1; elapsed=%s", got, test.end.Sub(test.start))
			}
		})
	}
}

func TestEndOfCalendarDayIncludesFinalNanosecond(t *testing.T) {
	location := time.FixedZone("UTC+08", 8*60*60)
	day := time.Date(2026, time.July, 31, 12, 30, 0, 0, location)
	nextDay := time.Date(2026, time.August, 1, 0, 0, 0, 0, location)

	if got, want := endOfCalendarDay(day), nextDay.Add(-time.Nanosecond); !got.Equal(want) {
		t.Fatalf("end of day = %s, want %s", got, want)
	}
}

func TestDateOnlyParsingAndReportRangeUseLocalCalendarBoundaries(t *testing.T) {
	location := time.FixedZone("UTC+08", 8*60*60)
	previousLocal := time.Local
	time.Local = location
	t.Cleanup(func() { time.Local = previousLocal })

	parsed, err := parseLocalDate("2026-07-31")
	if err != nil {
		t.Fatalf("parse local date: %v", err)
	}
	if parsed.Location() != location || parsed.Hour() != 0 {
		t.Fatalf("parsed date = %s in %s, want local midnight", parsed, parsed.Location())
	}

	start, end, err := parseAIReportPeriod("2026-07-01", "2026-07-31")
	if err != nil {
		t.Fatalf("parse report period: %v", err)
	}
	if !start.Equal(time.Date(2026, time.July, 1, 0, 0, 0, 0, location)) {
		t.Fatalf("report start = %s", start)
	}
	wantEnd := time.Date(2026, time.August, 1, 0, 0, 0, 0, location).Add(-time.Nanosecond)
	if !end.Equal(wantEnd) {
		t.Fatalf("report end = %s, want %s", end, wantEnd)
	}
}

func TestStatisticsRangesIncludeSubsecondTailAndCountCivilDays(t *testing.T) {
	location, err := time.LoadLocation("America/New_York")
	if err != nil {
		t.Fatalf("load timezone: %v", err)
	}
	previousLocal := time.Local
	time.Local = location
	t.Cleanup(func() { time.Local = previousLocal })

	rangeValue, err := statisticsDateRange("2026-03", "month")
	if err != nil {
		t.Fatalf("statistics date range: %v", err)
	}
	wantEnd := time.Date(2026, time.April, 1, 0, 0, 0, 0, location).Add(-time.Nanosecond)
	if !rangeValue.End.Equal(wantEnd) {
		t.Fatalf("range end = %s, want %s", rangeValue.End, wantEnd)
	}
	if got := rangeValue.ElapsedDays(); got != 31 {
		t.Fatalf("elapsed days = %d, want 31", got)
	}

	previousStart, previousEnd := rangeValue.Previous()
	if !previousStart.Equal(time.Date(2026, time.February, 1, 0, 0, 0, 0, location)) {
		t.Fatalf("previous start = %s", previousStart)
	}
	wantPreviousEnd := rangeValue.Start.Add(-time.Nanosecond)
	if !previousEnd.Equal(wantPreviousEnd) {
		t.Fatalf("previous end = %s, want %s", previousEnd, wantPreviousEnd)
	}
}
