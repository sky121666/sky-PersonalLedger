package middleware

import (
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

type LoginAttempt struct {
	attempts    []time.Time
	lockedUntil time.Time
	mu          sync.Mutex
}

type RateLimiter struct {
	ipAttempts      map[string]*LoginAttempt
	accountAttempts map[string]*LoginAttempt
	mu              sync.RWMutex

	// Configuration
	maxAttempts  int
	timeWindow   time.Duration
	lockDuration time.Duration
}

func NewRateLimiter() *RateLimiter {
	rl := &RateLimiter{
		ipAttempts:      make(map[string]*LoginAttempt),
		accountAttempts: make(map[string]*LoginAttempt),
		maxAttempts:     5,
		timeWindow:      5 * time.Minute,
		lockDuration:    30 * time.Minute,
	}

	// Start cleanup goroutine
	go rl.cleanup()

	return rl
}

// CheckIP checks if an IP is rate limited
func (rl *RateLimiter) CheckIP(ip string) (bool, time.Time) {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	attempt, exists := rl.ipAttempts[ip]
	if !exists {
		attempt = &LoginAttempt{
			attempts: make([]time.Time, 0),
		}
		rl.ipAttempts[ip] = attempt
	}

	attempt.mu.Lock()
	defer attempt.mu.Unlock()

	now := time.Now()

	// Check if locked
	if now.Before(attempt.lockedUntil) {
		return false, attempt.lockedUntil
	}

	// Clean old attempts
	var recentAttempts []time.Time
	for _, t := range attempt.attempts {
		if now.Sub(t) < rl.timeWindow {
			recentAttempts = append(recentAttempts, t)
		}
	}
	attempt.attempts = recentAttempts

	// Check if exceeded
	if len(attempt.attempts) >= rl.maxAttempts {
		attempt.lockedUntil = now.Add(rl.lockDuration)
		return false, attempt.lockedUntil
	}

	return true, time.Time{}
}

// CheckAccount checks if an account is rate limited
func (rl *RateLimiter) CheckAccount(username string) (bool, time.Time) {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	attempt, exists := rl.accountAttempts[username]
	if !exists {
		attempt = &LoginAttempt{
			attempts: make([]time.Time, 0),
		}
		rl.accountAttempts[username] = attempt
	}

	attempt.mu.Lock()
	defer attempt.mu.Unlock()

	now := time.Now()

	// Check if locked
	if now.Before(attempt.lockedUntil) {
		return false, attempt.lockedUntil
	}

	// Clean old attempts
	var recentAttempts []time.Time
	for _, t := range attempt.attempts {
		if now.Sub(t) < rl.timeWindow {
			recentAttempts = append(recentAttempts, t)
		}
	}
	attempt.attempts = recentAttempts

	// Check if exceeded
	if len(attempt.attempts) >= rl.maxAttempts {
		attempt.lockedUntil = now.Add(rl.lockDuration)
		return false, attempt.lockedUntil
	}

	return true, time.Time{}
}

// RecordAttempt records a failed login attempt
func (rl *RateLimiter) RecordAttempt(ip, username string) {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	now := time.Now()

	// Record IP attempt
	if attempt, exists := rl.ipAttempts[ip]; exists {
		attempt.mu.Lock()
		attempt.attempts = append(attempt.attempts, now)
		attempt.mu.Unlock()
	} else {
		rl.ipAttempts[ip] = &LoginAttempt{
			attempts: []time.Time{now},
		}
	}

	// Record account attempt
	if attempt, exists := rl.accountAttempts[username]; exists {
		attempt.mu.Lock()
		attempt.attempts = append(attempt.attempts, now)
		attempt.mu.Unlock()
	} else {
		rl.accountAttempts[username] = &LoginAttempt{
			attempts: []time.Time{now},
		}
	}
}

// ResetAccount resets attempts for an account (on successful login)
func (rl *RateLimiter) ResetAccount(username string) {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	if attempt, exists := rl.accountAttempts[username]; exists {
		attempt.mu.Lock()
		attempt.attempts = make([]time.Time, 0)
		attempt.lockedUntil = time.Time{}
		attempt.mu.Unlock()
	}
}

// cleanup periodically removes old entries
func (rl *RateLimiter) cleanup() {
	ticker := time.NewTicker(10 * time.Minute)
	defer ticker.Stop()

	for range ticker.C {
		rl.mu.Lock()
		now := time.Now()

		// Clean IP attempts
		for ip, attempt := range rl.ipAttempts {
			attempt.mu.Lock()
			if len(attempt.attempts) == 0 && now.After(attempt.lockedUntil) {
				delete(rl.ipAttempts, ip)
			}
			attempt.mu.Unlock()
		}

		// Clean account attempts
		for username, attempt := range rl.accountAttempts {
			attempt.mu.Lock()
			if len(attempt.attempts) == 0 && now.After(attempt.lockedUntil) {
				delete(rl.accountAttempts, username)
			}
			attempt.mu.Unlock()
		}

		rl.mu.Unlock()
	}
}

// Middleware returns a gin middleware for rate limiting (login only)
func (rl *RateLimiter) Middleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Only apply to login endpoint
		if c.Request.URL.Path != "/api/v1/auth/login" && c.Request.URL.Path != "/api/v1/auth/register" {
			c.Next()
			return
		}

		ip := c.ClientIP()

		// Check IP rate limit
		allowed, lockedUntil := rl.CheckIP(ip)
		if !allowed {
			remainingSeconds := int(time.Until(lockedUntil).Seconds())
			c.JSON(429, gin.H{
				"code":         42901,
				"message":      "Too many login attempts. Please try again later.",
				"locked_until": lockedUntil.Format(time.RFC3339),
				"retry_after":  remainingSeconds,
			})
			c.Abort()
			return
		}

		c.Next()
	}
}

// GlobalRateLimiter provides global API rate limiting
type GlobalRateLimiter struct {
	requests    map[string][]time.Time
	mu          sync.RWMutex
	maxRequests int
	window      time.Duration
}

func NewGlobalRateLimiter(maxRequests int, window time.Duration) *GlobalRateLimiter {
	grl := &GlobalRateLimiter{
		requests:    make(map[string][]time.Time),
		maxRequests: maxRequests,
		window:      window,
	}
	go grl.cleanup()
	return grl
}

func (grl *GlobalRateLimiter) Allow(ip string) bool {
	grl.mu.Lock()
	defer grl.mu.Unlock()

	now := time.Now()
	requests, exists := grl.requests[ip]

	if !exists {
		grl.requests[ip] = []time.Time{now}
		return true
	}

	// Remove old requests outside the window
	var validRequests []time.Time
	for _, t := range requests {
		if now.Sub(t) < grl.window {
			validRequests = append(validRequests, t)
		}
	}

	// Check if limit exceeded
	if len(validRequests) >= grl.maxRequests {
		grl.requests[ip] = validRequests
		return false
	}

	// Add current request
	validRequests = append(validRequests, now)
	grl.requests[ip] = validRequests
	return true
}

func (grl *GlobalRateLimiter) cleanup() {
	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()

	for range ticker.C {
		grl.mu.Lock()
		now := time.Now()
		for ip, requests := range grl.requests {
			var validRequests []time.Time
			for _, t := range requests {
				if now.Sub(t) < grl.window {
					validRequests = append(validRequests, t)
				}
			}
			if len(validRequests) == 0 {
				delete(grl.requests, ip)
			} else {
				grl.requests[ip] = validRequests
			}
		}
		grl.mu.Unlock()
	}
}

func (grl *GlobalRateLimiter) Middleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Skip rate limiting for public endpoints
		path := c.Request.URL.Path
		if path == "/api/v1/auth/status" || path == "/api/v1/auth/init" {
			c.Next()
			return
		}

		ip := c.ClientIP()
		if !grl.Allow(ip) {
			c.JSON(429, gin.H{
				"code":    42903,
				"message": "Too many requests. Please slow down.",
			})
			c.Abort()
			return
		}

		c.Next()
	}
}
