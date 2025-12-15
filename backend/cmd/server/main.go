package main

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"

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

	// Initialize logger
	logger.Init(cfg.Log.Level, cfg.Log.Format)

	// Initialize database
	db, err := database.Init(cfg.Database.Path)
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

	// Initialize handlers
	handlers := handler.NewHandlers(services)

	// Setup Gin
	if cfg.Server.Mode == "release" {
		gin.SetMode(gin.ReleaseMode)
	}

	r := gin.Default()

	// Apply middlewares
	r.Use(middleware.CORS("*")) // Use "*" for dev, configure specific origins for production
	r.Use(middleware.SecurityHeaders())
	r.Use(middleware.Logger())

	// Setup API routes
	handler.SetupRoutes(r, handlers, services.Auth)

	// Serve uploaded files (requires auth via JWT in query or header)
	if cfg.Storage.UploadPath != "" {
		setupUploadFiles(r, cfg.Storage.UploadPath, services.Auth)
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

func setupUploadFiles(r *gin.Engine, uploadPath string, authService *service.AuthService) {
	// Create upload directory if not exists
	if err := os.MkdirAll(uploadPath, 0755); err != nil {
		log.Printf("Warning: Failed to create upload directory: %v", err)
		return
	}

	// Serve uploaded files with JWT authentication
	r.GET("/uploads/*filepath", func(c *gin.Context) {
		// Check JWT token from query parameter or header
		token := c.Query("token")
		if token == "" {
			token = c.GetHeader("Authorization")
			if strings.HasPrefix(token, "Bearer ") {
				token = token[7:]
			}
		}

		if token == "" {
			c.JSON(401, gin.H{"error": "unauthorized"})
			return
		}

		// Validate token
		_, err := authService.GetJWTManager().ValidateToken(token)
		if err != nil {
			c.JSON(401, gin.H{"error": "invalid token"})
			return
		}

		filePath := c.Param("filepath")
		fullPath := filepath.Join(uploadPath, filePath)

		// Security check: ensure path is within upload directory
		absUploadPath, _ := filepath.Abs(uploadPath)
		absFullPath, _ := filepath.Abs(fullPath)
		if !strings.HasPrefix(absFullPath, absUploadPath) {
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
			log.Printf("[EntryPath] Entry path accessed: %s, setting cookie and redirecting", requestPath)
			// Set verification cookie with entry path hash and redirect to root
			c.SetCookie(cookieName, expectedCookieValue, cookieMaxAge, "/", "", false, true)
			c.Redirect(302, "/")
			c.Abort()
			return false
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
