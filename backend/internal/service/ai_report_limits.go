package service

import (
	"sync"
	"time"
)

const (
	aiReportMaxConcurrentPerUser = 2
	aiReportMaxAttemptsPerMinute = 6
)

type aiReportUserUsage struct {
	active   int
	attempts []time.Time
}

type aiReportGenerationLimits struct {
	mu    sync.Mutex
	users map[uint]*aiReportUserUsage
	now   func() time.Time
}

func newAIReportGenerationLimits() *aiReportGenerationLimits {
	return &aiReportGenerationLimits{users: make(map[uint]*aiReportUserUsage), now: time.Now}
}

// Limits only actual provider attempts. Cache hits and database failures do not
// spend an allowance. These process-local limits match the single writer scope.
func (l *aiReportGenerationLimits) acquire(userID uint) (func(), error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := l.now()
	usage := l.users[userID]
	if usage == nil {
		usage = &aiReportUserUsage{}
		l.users[userID] = usage
	}
	current := usage.attempts[:0]
	for _, attempt := range usage.attempts {
		if attempt.After(now.Add(-time.Minute)) {
			current = append(current, attempt)
		}
	}
	usage.attempts = current
	if usage.active >= aiReportMaxConcurrentPerUser || len(usage.attempts) >= aiReportMaxAttemptsPerMinute {
		return nil, ErrAIReportGenerationLimited
	}
	usage.active++
	usage.attempts = append(usage.attempts, now)
	var once sync.Once
	return func() { once.Do(func() { l.mu.Lock(); usage.active--; l.mu.Unlock() }) }, nil
}
