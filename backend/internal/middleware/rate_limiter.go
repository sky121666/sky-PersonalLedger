package middleware

import (
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

type LoginAttempt struct {
	attempts    []time.Time
	lockedUntil time.Time
	lastSeen    time.Time
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
	maxEntries   int
}

const defaultRateLimitMaxEntries = 10000

func NewRateLimiter() *RateLimiter {
	rl := &RateLimiter{
		ipAttempts:      make(map[string]*LoginAttempt),
		accountAttempts: make(map[string]*LoginAttempt),
		maxAttempts:     5,
		timeWindow:      5 * time.Minute,
		lockDuration:    30 * time.Minute,
		maxEntries:      defaultRateLimitMaxEntries,
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
		return true, time.Time{}
	}

	attempt.mu.Lock()
	defer attempt.mu.Unlock()

	now := time.Now()
	attempt.lastSeen = now

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
	if len(recentAttempts) == 0 && !now.Before(attempt.lockedUntil) {
		delete(rl.ipAttempts, ip)
		return true, time.Time{}
	}

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
		return true, time.Time{}
	}

	attempt.mu.Lock()
	defer attempt.mu.Unlock()

	now := time.Now()
	attempt.lastSeen = now

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
	if len(recentAttempts) == 0 && !now.Before(attempt.lockedUntil) {
		delete(rl.accountAttempts, username)
		return true, time.Time{}
	}

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
		attempt.lastSeen = now
		attempt.mu.Unlock()
	} else {
		rl.ensureLoginMapCapacity(rl.ipAttempts)
		rl.ipAttempts[ip] = &LoginAttempt{
			attempts: []time.Time{now},
			lastSeen: now,
		}
	}

	// Record account attempt
	if attempt, exists := rl.accountAttempts[username]; exists {
		attempt.mu.Lock()
		attempt.attempts = append(attempt.attempts, now)
		attempt.lastSeen = now
		attempt.mu.Unlock()
	} else {
		rl.ensureLoginMapCapacity(rl.accountAttempts)
		rl.accountAttempts[username] = &LoginAttempt{
			attempts: []time.Time{now},
			lastSeen: now,
		}
	}
}

// ResetAccount resets attempts for an account (on successful login)
func (rl *RateLimiter) ResetAccount(username string) {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	delete(rl.accountAttempts, username)
}

// cleanup periodically removes old entries
func (rl *RateLimiter) cleanup() {
	ticker := time.NewTicker(10 * time.Minute)
	defer ticker.Stop()

	for range ticker.C {
		rl.mu.Lock()
		rl.cleanupMapAt(rl.ipAttempts, time.Now())
		rl.cleanupMapAt(rl.accountAttempts, time.Now())
		rl.mu.Unlock()
	}
}

func (rl *RateLimiter) cleanupMapAt(entries map[string]*LoginAttempt, now time.Time) {
	for key, attempt := range entries {
		attempt.mu.Lock()
		recent := attempt.attempts[:0]
		for _, recordedAt := range attempt.attempts {
			if now.Sub(recordedAt) < rl.timeWindow {
				recent = append(recent, recordedAt)
			}
		}
		attempt.attempts = recent
		expired := len(recent) == 0 && !now.Before(attempt.lockedUntil)
		attempt.mu.Unlock()
		if expired {
			delete(entries, key)
		}
	}
}

func (rl *RateLimiter) ensureLoginMapCapacity(entries map[string]*LoginAttempt) {
	if rl.maxEntries <= 0 || len(entries) < rl.maxEntries {
		return
	}
	oldestKey := ""
	var oldest time.Time
	for key, attempt := range entries {
		attempt.mu.Lock()
		lastSeen := attempt.lastSeen
		attempt.mu.Unlock()
		if oldestKey == "" || lastSeen.Before(oldest) {
			oldestKey = key
			oldest = lastSeen
		}
	}
	if oldestKey != "" {
		delete(entries, oldestKey)
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
	maxEntries  int
}

func NewGlobalRateLimiter(maxRequests int, window time.Duration) *GlobalRateLimiter {
	grl := &GlobalRateLimiter{
		requests:    make(map[string][]time.Time),
		maxRequests: maxRequests,
		window:      window,
		maxEntries:  defaultRateLimitMaxEntries,
	}
	if grl.maxRequests < 1 {
		grl.maxRequests = 1
	}
	if grl.window <= 0 {
		grl.window = time.Minute
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
		if grl.maxEntries > 0 && len(grl.requests) >= grl.maxEntries {
			grl.cleanupAt(now)
		}
		grl.ensureCapacity()
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
		grl.cleanupAt(time.Now())
		grl.mu.Unlock()
	}
}

func (grl *GlobalRateLimiter) cleanupAt(now time.Time) {
	for ip, requests := range grl.requests {
		validRequests := requests[:0]
		for _, recordedAt := range requests {
			if now.Sub(recordedAt) < grl.window {
				validRequests = append(validRequests, recordedAt)
			}
		}
		if len(validRequests) == 0 {
			delete(grl.requests, ip)
		} else {
			grl.requests[ip] = validRequests
		}
	}
}

func (grl *GlobalRateLimiter) ensureCapacity() {
	if grl.maxEntries <= 0 || len(grl.requests) < grl.maxEntries {
		return
	}
	oldestIP := ""
	var oldest time.Time
	for ip, requests := range grl.requests {
		lastSeen := requests[len(requests)-1]
		if oldestIP == "" || lastSeen.Before(oldest) {
			oldestIP = ip
			oldest = lastSeen
		}
	}
	if oldestIP != "" {
		delete(grl.requests, oldestIP)
	}
}

func (grl *GlobalRateLimiter) Middleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		path := c.Request.URL.Path

		// 跳过静态资源和公共端点的限速；私有上传文件仍受全局限速保护。
		if strings.HasPrefix(path, "/assets/") ||
			isPublicUploadPath(path) ||
			strings.HasPrefix(path, "/.well-known/") ||
			path == "/favicon.svg" ||
			path == "/favicon.ico" ||
			path == "/manifest.json" ||
			path == "/api/v1/auth/status" {
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

func isPublicUploadPath(path string) bool {
	parts := strings.Split(strings.Trim(path, "/"), "/")
	if len(parts) != 5 || parts[0] != "uploads" || parts[2] != "avatars" || parts[3] != "profile" {
		return false
	}
	userID, err := strconv.ParseUint(parts[1], 10, 64)
	if err != nil || userID == 0 {
		return false
	}
	switch strings.ToLower(filepath.Ext(parts[4])) {
	case ".jpg", ".jpeg", ".png", ".webp":
		return true
	default:
		return false
	}
}
