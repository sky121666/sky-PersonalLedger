package main

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
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

	// Initialize logger
	logger.Init(cfg.Log.Level, cfg.Log.Format)

	// Initialize database
	db, err := database.InitWithConfig(cfg.Database)
	if err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}

	// Initialize repositories
	repos := repository.NewRepositories(db)

	// Initialize services
	services := service.NewServices(repos, cfg)

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
		setupStaticFiles(r, cfg.Server.WebPath, services.System)
		log.Printf("Serving frontend from %s", cfg.Server.WebPath)
	}

	// Start server
	addr := ":" + cfg.Server.Port
	log.Printf("Server starting on %s", addr)
	if err := r.Run(addr); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
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

func setupUploadFiles(r *gin.Engine, uploadPath string, authService *service.AuthService, systemService *service.SystemService) {
	// Create upload directory if not exists
	if err := os.MkdirAll(uploadPath, 0755); err != nil {
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

		// 头像文件公开访问，无需认证 (路径格式: /1/avatars/profile/xxx.gif)
		if len(pathParts) >= 3 && pathParts[1] == "avatars" {
			// 直接允许访问头像
		} else {
			// 其他文件需要认证
			token := c.Query("token")
			if token == "" {
				token = strings.TrimPrefix(c.GetHeader("Authorization"), "Bearer ")
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

		fullPath := filepath.Join(uploadPath, cleanPath)

		// Security check: ensure path is within upload directory
		absUploadPath, _ := filepath.Abs(uploadPath)
		absFullPath, _ := filepath.Abs(fullPath)
		if absFullPath != absUploadPath && !strings.HasPrefix(absFullPath, absUploadPath+string(os.PathSeparator)) {
			c.JSON(403, gin.H{"error": "forbidden"})
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
	})
}

func setupStaticFiles(r *gin.Engine, webPath string, systemService *service.SystemService) {
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

		// Cookie value should match the entry path (simple hash)
		expectedCookieValue := fmt.Sprintf("%x", len(entryPath)*31+int(entryPath[1]))
		requestPath := c.Request.URL.Path

		// Check if already verified via cookie with matching entry path
		if cookie, err := c.Cookie(cookieName); err == nil {
			if cookie == expectedCookieValue {
				log.Printf("[EntryPath] Valid cookie found, allowing access to: %s", requestPath)
				return true
			}
			log.Printf("[EntryPath] Invalid cookie: got '%s', expected '%s'", cookie, expectedCookieValue)
		}

		// Check if accessing the entry path
		if strings.HasPrefix(requestPath, entryPath) {
			log.Printf("[EntryPath] Entry path accessed: %s, setting cookie and allowing access", requestPath)
			// Set verification cookie with entry path hash and allow access
			c.SetCookie(cookieName, expectedCookieValue, cookieMaxAge, "/", "", false, true)
			return true // 允许访问，不重定向
		}

		// Not verified, return 404
		log.Printf("[EntryPath] Access denied to: %s (no valid cookie, entry path is: %s)", requestPath, entryPath)
		c.String(404, "404 page not found")
		c.Abort()
		return false
	}

	// Serve assets (protected)
	r.GET("/assets/*filepath", func(c *gin.Context) {
		if !checkEntryAccess(c) {
			return
		}
		c.File(filepath.Join(webPath, "assets", c.Param("filepath")))
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
