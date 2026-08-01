package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/sky/personal-ledger/internal/config"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/handler"
	"github.com/sky/personal-ledger/internal/middleware"
	"github.com/sky/personal-ledger/internal/repository"
	"github.com/sky/personal-ledger/internal/service"
	"github.com/sky/personal-ledger/pkg/logger"

	"github.com/gin-gonic/gin"
)

func main() {
	// Load config
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	// Validate critical security settings
	if err := validateJWTSecret(cfg.JWT.Secret); err != nil {
		log.Fatal(err)
	}
	if err := validateProductionCORS(cfg.Server.Mode, cfg.CORS.AllowedOrigins); err != nil {
		log.Fatal(err)
	}
	if err := validateSetupToken(cfg.Setup.Token); err != nil {
		log.Fatal(err)
	}
	if err := validateStorageLimits(cfg.Storage); err != nil {
		log.Fatal(err)
	}

	// Initialize logger
	logger.Init(cfg.Log.Level, cfg.Log.Format)

	// Initialize database
	db, err := database.InitWithConfig(cfg.Database, cfg.Log)
	if err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}

	// Initialize repositories
	repos := repository.NewRepositories(db)

	// Initialize services
	services := service.NewServices(repos, cfg)
	if err := services.Notification.MigrateStoredSecrets(); err != nil {
		log.Fatalf("Failed to migrate notification credentials: %v", err)
	}

	// Sync security settings from config to database (config takes priority)
	if cfg.Security.BasePath != "" {
		if err := services.System.SetEntryPath(cfg.Security.BasePath); err != nil {
			log.Printf("Warning: Failed to sync security base_path: %v", err)
		} else {
			log.Printf("Security entry path set to: %s", cfg.Security.BasePath)
		}
	}

	// Initialize backup scheduler
	backupScheduler := service.NewBackupScheduler(services.Backup, repos.System, repos.User, cfg.Storage.BackupPath)
	backupScheduler.Start()
	services.AIReportSchedule.Start()
	services.NotificationSchedule.Start()
	services.UploadGC.Start()

	// Initialize rate limiter
	rateLimiter := middleware.NewRateLimiter()
	var globalRateLimiter *middleware.GlobalRateLimiter
	// 开发环境禁用全局限速
	if cfg.Server.Mode == "release" {
		globalRateLimiter = middleware.NewGlobalRateLimiter(
			cfg.RateLimit.MaxRequests,
			time.Duration(cfg.RateLimit.WindowSecs)*time.Second,
		)
		log.Printf("Rate limit: %d requests per %d seconds", cfg.RateLimit.MaxRequests, cfg.RateLimit.WindowSecs)
	} else {
		log.Printf("Rate limit: disabled in debug mode")
	}

	// Initialize handlers
	handlers := handler.NewHandlers(services, backupScheduler, rateLimiter, cfg)

	// Setup Gin
	if cfg.Server.Mode == "release" {
		gin.SetMode(gin.ReleaseMode)
	}

	r := gin.Default()
	if err := configureTrustedProxies(r, cfg.Server.TrustedProxies); err != nil {
		log.Fatalf("FATAL: invalid LEDGER_SERVER_TRUSTED_PROXIES: %v", err)
	}

	// Apply middlewares
	r.Use(middleware.CORS(cfg.CORS.AllowedOrigins))
	r.Use(middleware.SecurityHeaders())
	r.Use(middleware.AuditLog())    // Security audit logging
	r.Use(rateLimiter.Middleware()) // Rate limiting for login attempts
	if globalRateLimiter != nil {
		r.Use(globalRateLimiter.Middleware()) // Global API rate limiting (仅生产环境)
	}

	// Setup API routes
	handler.SetupRoutes(r, handlers, services.Auth, services.APIToken)

	// Serve uploaded files (requires auth via JWT in query or header)
	if cfg.Storage.UploadPath != "" {
		setupUploadFiles(r, cfg.Storage.UploadPath, services.Auth, services.System)
		log.Printf("Serving uploads from %s", cfg.Storage.UploadPath)
	}

	// Serve frontend static files with security entry path protection
	if cfg.Server.WebPath != "" {
		setupStaticFiles(r, cfg.Server.WebPath, services.System, cfg.JWT.Secret)
		log.Printf("Serving frontend from %s", cfg.Server.WebPath)
	}

	// Start server
	addr := ":" + cfg.Server.Port
	log.Printf("Server starting on %s", addr)
	server := newHTTPServer(addr, r)
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("Failed to start server: %v", err)
	}
}

const (
	serverReadHeaderTimeout = 5 * time.Second
	serverReadTimeout       = 60 * time.Second
	serverWriteTimeout      = 60 * time.Second
	serverIdleTimeout       = 120 * time.Second
	serverMaxHeaderBytes    = 1 << 20
)

func newHTTPServer(addr string, handler http.Handler) *http.Server {
	return &http.Server{
		Addr:              addr,
		Handler:           handler,
		ReadHeaderTimeout: serverReadHeaderTimeout,
		ReadTimeout:       serverReadTimeout,
		WriteTimeout:      serverWriteTimeout,
		IdleTimeout:       serverIdleTimeout,
		MaxHeaderBytes:    serverMaxHeaderBytes,
	}
}

func configureTrustedProxies(router *gin.Engine, configured string) error {
	var trusted []string
	for _, value := range strings.Split(configured, ",") {
		value = strings.TrimSpace(value)
		if value != "" {
			trusted = append(trusted, value)
		}
	}
	// nil explicitly disables Gin's legacy trust-all proxy default.
	if len(trusted) == 0 {
		return router.SetTrustedProxies(nil)
	}
	return router.SetTrustedProxies(trusted)
}

func validateJWTSecret(secret string) error {
	value := strings.TrimSpace(secret)
	placeholderSecrets := map[string]struct{}{
		"change-me":                                 {},
		"change-this-secret":                        {},
		"change-this-to-a-random-secret-key":        {},
		"please-change-this-to-a-random-secret-key": {},
		"your-jwt-secret-change-this-in-production": {},
	}
	if value == "" {
		return fmt.Errorf("FATAL: LEDGER_JWT_SECRET must be set to a secure random value")
	}
	if _, ok := placeholderSecrets[value]; ok {
		return fmt.Errorf("FATAL: LEDGER_JWT_SECRET uses a public placeholder value; set it to a secure random value")
	}
	if len(value) < 32 {
		return fmt.Errorf("FATAL: LEDGER_JWT_SECRET must be at least 32 characters long for security")
	}
	return nil
}

func validateProductionCORS(serverMode string, allowedOrigins string) error {
	if strings.EqualFold(strings.TrimSpace(serverMode), "release") && strings.TrimSpace(allowedOrigins) == "*" {
		return fmt.Errorf("FATAL: LEDGER_CORS_ALLOWED_ORIGINS cannot be * in release mode; leave it empty for same-site deployment or set explicit origins")
	}
	return nil
}

func validateSetupToken(token string) error {
	value := strings.TrimSpace(token)
	if value != "" && len(value) < 32 {
		return fmt.Errorf("FATAL: LEDGER_SETUP_TOKEN must be at least 32 characters long when configured")
	}
	return nil
}

func validateStorageLimits(storage config.StorageConfig) error {
	if storage.MaxFileSize < 1 || storage.MaxFileSize > 1024 {
		return fmt.Errorf("FATAL: LEDGER_STORAGE_MAX_FILE_SIZE must be between 1 and 1024 MB")
	}
	if storage.RestoreMaxFileSize < 1 || storage.RestoreMaxFileSize > 4096 {
		return fmt.Errorf("FATAL: LEDGER_STORAGE_RESTORE_MAX_FILE_SIZE must be between 1 and 4096 MB")
	}
	return nil
}

func setupUploadFiles(r *gin.Engine, uploadPath string, authService *service.AuthService, systemService *service.SystemService) {
	// Create upload directory if not exists
	if err := os.MkdirAll(uploadPath, 0700); err != nil {
		log.Printf("Warning: Failed to create upload directory: %v", err)
		return
	}

	// Serve uploaded files
	r.GET("/uploads/*filepath", func(c *gin.Context) {
		filePath := c.Param("filepath")
		cleanPath := filepath.Clean(strings.TrimPrefix(filePath, "/"))
		if cleanPath == "." ||
			cleanPath == ".." ||
			strings.HasPrefix(cleanPath, ".."+string(os.PathSeparator)) {
			c.JSON(403, gin.H{"error": "forbidden"})
			return
		}
		pathParts := strings.Split(filepath.ToSlash(cleanPath), "/")

		// 头像文件公开访问，无需认证（严格限制为用户头像目录）。
		publicAvatar := len(pathParts) == 4 && pathParts[1] == "avatars" && pathParts[2] == "profile"
		if publicAvatar {
			if userID, err := strconv.ParseUint(pathParts[0], 10, 64); err != nil || userID == 0 {
				c.JSON(404, gin.H{"error": "not found"})
				return
			}
		} else {
			// 其他文件需要认证
			authHeader := c.GetHeader("Authorization")
			parts := strings.SplitN(authHeader, " ", 2)
			token := ""
			if len(parts) == 2 && parts[0] == "Bearer" {
				token = parts[1]
			}

			authenticated := false
			var userID uint

			if token != "" {
				claims, err := authService.GetJWTManager().ValidateToken(token)
				if err == nil {
					authenticated = true
					userID = claims.UserID
				}
			}

			if !authenticated {
				c.JSON(401, gin.H{"error": "unauthorized"})
				return
			}

			if len(pathParts) == 0 || pathParts[0] != fmt.Sprintf("%d", userID) {
				c.JSON(403, gin.H{"error": "forbidden"})
				return
			}
		}

		fullPath, err := resolveExistingFileWithinRoot(uploadPath, cleanPath)
		if errors.Is(err, errUnsafeStaticPath) {
			c.JSON(403, gin.H{"error": "forbidden"})
			return
		}
		if err != nil {
			c.JSON(404, gin.H{"error": "not found"})
			return
		}
		info, err := os.Stat(fullPath)
		if err != nil {
			c.JSON(404, gin.H{"error": "not found"})
			return
		}
		if info.IsDir() {
			c.JSON(403, gin.H{"error": "forbidden"})
			return
		}
		if publicAvatar {
			if !service.IsSafeStoredAvatar(fullPath) {
				c.JSON(http.StatusUnsupportedMediaType, gin.H{"error": "invalid avatar content"})
				return
			}
			c.Header("Cache-Control", "public, max-age=86400")
		}
		c.Header("X-Content-Type-Options", "nosniff")

		c.File(fullPath)
	})
}

var errUnsafeStaticPath = errors.New("unsafe static path")

func resolveExistingFileWithinRoot(rootPath string, relativePath string) (string, error) {
	fullPath := filepath.Join(rootPath, relativePath)
	absRootPath, err := filepath.Abs(rootPath)
	if err != nil {
		return "", err
	}
	absFullPath, err := filepath.Abs(fullPath)
	if err != nil {
		return "", err
	}
	if absFullPath != absRootPath && !strings.HasPrefix(absFullPath, absRootPath+string(os.PathSeparator)) {
		return "", errUnsafeStaticPath
	}
	resolvedRoot, err := filepath.EvalSymlinks(absRootPath)
	if err != nil {
		return "", err
	}
	resolvedFile, err := filepath.EvalSymlinks(absFullPath)
	if err != nil {
		return "", err
	}
	if resolvedFile != resolvedRoot && !strings.HasPrefix(resolvedFile, resolvedRoot+string(os.PathSeparator)) {
		return "", errUnsafeStaticPath
	}
	return resolvedFile, nil
}

func setupStaticFiles(r *gin.Engine, webPath string, systemService *service.SystemService, cookieSecret string) {
	// Check if dist folder exists
	if _, err := os.Stat(webPath); os.IsNotExist(err) {
		log.Printf("Warning: Frontend dist folder not found at %s", webPath)
		return
	}

	const cookieName = "entry_verified"
	const cookieMaxAge = 86400 * 30 // 30 days

	// Helper function to check entry path access
	checkEntryAccess := func(c *gin.Context) bool {
		entryPath, err := systemService.GetEntryPath()
		if err != nil || entryPath == "" {
			log.Printf("[EntryPath] No entry path configured, allowing access")
			return true // No entry path configured, allow access
		}

		expectedCookieValue := entryAccessCookieValue(cookieSecret, entryPath)
		requestPath := c.Request.URL.Path

		// Check if already verified via cookie with matching entry path
		if cookie, err := c.Cookie(cookieName); err == nil {
			if hmac.Equal([]byte(cookie), []byte(expectedCookieValue)) {
				return true
			}
		}

		// Check if accessing the entry path
		if service.MatchesEntryPath(requestPath, entryPath) {
			secureCookie := c.Request.TLS != nil || strings.EqualFold(strings.TrimSpace(c.GetHeader("X-Forwarded-Proto")), "https")
			c.SetSameSite(http.SameSiteStrictMode)
			c.SetCookie(cookieName, expectedCookieValue, cookieMaxAge, "/", "", secureCookie, true)
			return true // 允许访问，不重定向
		}

		// Not verified, return 404
		c.String(404, "404 page not found")
		c.Abort()
		return false
	}

	// Serve assets (protected)
	r.GET("/assets/*filepath", func(c *gin.Context) {
		if !checkEntryAccess(c) {
			return
		}
		serveStaticFile(c, filepath.Join(webPath, "assets"), c.Param("filepath"))
	})

	// Serve static files in root (favicon.svg, manifest.json, etc.)
	r.GET("/favicon.svg", func(c *gin.Context) {
		if !checkEntryAccess(c) {
			return
		}
		c.File(filepath.Join(webPath, "favicon.svg"))
	})

	r.GET("/manifest.json", func(c *gin.Context) {
		// manifest.json 公开访问 - 只包含应用名称/图标，无敏感信息
		c.File(filepath.Join(webPath, "manifest.json"))
	})

	// Serve index.html for SPA routing (protected)
	r.NoRoute(func(c *gin.Context) {
		path := c.Request.URL.Path

		// Skip API routes - API is always accessible
		if strings.HasPrefix(path, "/api/") {
			return
		}

		// Check entry path access for frontend
		if !checkEntryAccess(c) {
			return
		}

		// For SPA, serve index.html
		c.File(filepath.Join(webPath, "index.html"))
	})
}

func entryAccessCookieValue(secret string, entryPath string) string {
	mac := hmac.New(sha256.New, []byte(secret))
	_, _ = mac.Write([]byte("entry-access\x00" + entryPath))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

func serveStaticFile(c *gin.Context, rootPath string, requestPath string) {
	cleanPath := filepath.Clean(strings.TrimPrefix(requestPath, "/"))
	if cleanPath == "." ||
		cleanPath == ".." ||
		filepath.IsAbs(cleanPath) ||
		strings.HasPrefix(cleanPath, ".."+string(os.PathSeparator)) {
		c.JSON(403, gin.H{"error": "forbidden"})
		return
	}

	fullPath, err := resolveExistingFileWithinRoot(rootPath, cleanPath)
	if errors.Is(err, errUnsafeStaticPath) {
		c.JSON(403, gin.H{"error": "forbidden"})
		return
	}
	if err != nil {
		c.JSON(404, gin.H{"error": "not found"})
		return
	}
	info, err := os.Stat(fullPath)
	if err != nil {
		c.JSON(404, gin.H{"error": "not found"})
		return
	}
	if info.IsDir() {
		c.JSON(403, gin.H{"error": "forbidden"})
		return
	}

	c.File(fullPath)
}
