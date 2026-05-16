package handler

import (
	"github.com/sky/personal-ledger/internal/middleware"
	"github.com/sky/personal-ledger/internal/service"

	"github.com/gin-gonic/gin"
)

type Handlers struct {
	Auth         *AuthHandler
	Account      *AccountHandler
	Category     *CategoryHandler
	Transaction  *TransactionHandler
	Budget       *BudgetHandler
	Reminder     *ReminderHandler
	Statistics   *StatisticsHandler
	Template     *TemplateHandler
	Backup       *BackupHandler
	Notification *NotificationHandler
	Lending      *LendingHandler
	Export       *ExportHandler
	System       *SystemHandler
	Upload       *UploadHandler
	AccountLog   *AccountLogHandler
	Tag          *TagHandler
	APIToken     *APITokenHandler
}

func NewHandlers(services *service.Services, backupScheduler *service.BackupScheduler, rateLimiter *middleware.RateLimiter) *Handlers {
	return &Handlers{
		Auth:         NewAuthHandler(services.Auth, services.APIToken, services.Notification, rateLimiter),
		Account:      NewAccountHandler(services.Account),
		Category:     NewCategoryHandler(services.Category),
		Transaction:  NewTransactionHandler(services.Transaction),
		Budget:       NewBudgetHandler(services.Budget),
		Reminder:     NewReminderHandler(services.Reminder),
		Statistics:   NewStatisticsHandler(services.Statistics),
		Template:     NewTemplateHandler(services.Template),
		Backup:       NewBackupHandler(services.Backup, backupScheduler),
		Notification: NewNotificationHandler(services.Notification),
		Lending:      NewLendingHandler(services.Lending),
		Export:       NewExportHandler(services.Export),
		System:       NewSystemHandler(services.System),
		Upload:       NewUploadHandler(services.Upload, services.APIToken, services.Auth),
		AccountLog:   NewAccountLogHandler(services.AccountLog),
		Tag:          NewTagHandler(services.Tag),
		APIToken:     NewAPITokenHandler(services.APIToken),
	}
}

func SetupRoutes(r *gin.Engine, h *Handlers, authService *service.AuthService, apiTokenService *service.APITokenService) {
	api := r.Group("/api/v1")
	SetupRoutesWithGroup(api, h, authService, apiTokenService)
}

func SetupRoutesWithGroup(api *gin.RouterGroup, h *Handlers, authService *service.AuthService, apiTokenService *service.APITokenService) {
	// Public routes
	auth := api.Group("/auth")
	{
		auth.GET("/status", h.Auth.Status)
		auth.POST("/init", h.Auth.Init)
		auth.POST("/login", h.Auth.Login)
		auth.POST("/refresh", h.Auth.Refresh)
		auth.POST("/verify-token", h.Auth.VerifyAPIToken) // API Token 验证（App 端使用）
	}

	// Protected routes - 支持 JWT 和 API Token
	protected := api.Group("")
	protected.Use(middleware.AuthWithAPIToken(authService.GetJWTManager(), apiTokenService))
	{
		// Auth
		protected.POST("/auth/logout", h.Auth.Logout)
		protected.POST("/auth/change-password", h.Auth.ChangePassword)
		protected.GET("/auth/profile", h.Auth.GetProfile)
		protected.PUT("/auth/profile", h.Auth.UpdateProfile)

		// Accounts
		accounts := protected.Group("/accounts")
		{
			accounts.GET("", h.Account.List)
			accounts.POST("", h.Account.Create)
			accounts.GET("/:id", h.Account.GetByID)
			accounts.PUT("/:id", h.Account.Update)
			accounts.DELETE("/:id", h.Account.Delete)
			accounts.PATCH("/:id/archive", h.Account.Archive)
			accounts.PUT("/sort", h.Account.UpdateSortOrder)
		}

		// Categories
		categories := protected.Group("/categories")
		{
			categories.GET("", h.Category.List)
			categories.POST("", h.Category.Create)
			categories.GET("/:id", h.Category.GetByID)
			categories.PUT("/:id", h.Category.Update)
			categories.DELETE("/:id", h.Category.Delete)
		}

		// Transactions
		transactions := protected.Group("/transactions")
		{
			transactions.GET("", h.Transaction.List)
			transactions.POST("", h.Transaction.Create)
			transactions.GET("/:id", h.Transaction.GetByID)
			transactions.PUT("/:id", h.Transaction.Update)
			transactions.DELETE("/:id", h.Transaction.Delete)
			transactions.POST("/batch-delete", h.Transaction.BatchDelete)
		}

		// Budgets
		budgets := protected.Group("/budgets")
		{
			budgets.GET("", h.Budget.List)
			budgets.GET("/summary", h.Budget.GetSummary)
			budgets.POST("/total", h.Budget.SetTotal)
			budgets.POST("/category", h.Budget.SetCategory)
			budgets.DELETE("/:id", h.Budget.Delete)
		}

		// Debt summary (using reminder-based tracking)
		protected.GET("/debt/summary", h.Reminder.GetDebtSummary)
		reminders := protected.Group("/reminders")
		{
			reminders.GET("", h.Reminder.List)
			reminders.POST("", h.Reminder.Create)
			reminders.GET("/:id", h.Reminder.GetByID)
			reminders.PUT("/:id", h.Reminder.Update)
			reminders.DELETE("/:id", h.Reminder.Delete)
			reminders.PATCH("/:id/toggle", h.Reminder.Toggle)
			reminders.POST("/:id/payment", h.Reminder.RecordPayment)
		}

		// Statistics
		statistics := protected.Group("/statistics")
		{
			statistics.GET("/overview", h.Statistics.Overview)
			statistics.GET("/categories", h.Statistics.Categories)
			statistics.GET("/trend", h.Statistics.Trend)
			statistics.GET("/asset-trend", h.Statistics.AssetTrend)
		}

		// Backup & Restore
		protected.GET("/backup", h.Backup.Create)
		protected.POST("/restore", h.Backup.Restore)
		protected.GET("/backup/auto/settings", h.Backup.GetAutoBackupSettings)
		protected.PUT("/backup/auto/settings", h.Backup.UpdateAutoBackupSettings)
		protected.POST("/backup/auto/trigger", h.Backup.TriggerAutoBackup)
		protected.GET("/backup/auto/list", h.Backup.ListAutoBackups)

		// Templates
		templates := protected.Group("/templates")
		{
			templates.GET("", h.Template.List)
			templates.POST("", h.Template.Create)
			templates.DELETE("/:id", h.Template.Delete)
			templates.POST("/:id/apply", h.Template.Apply)
		}

		// Notifications
		notifications := protected.Group("/notifications")
		{
			notifications.GET("/settings", h.Notification.Get)
			notifications.PUT("/settings", h.Notification.Update)
			notifications.POST("/test/wecom", h.Notification.TestWecom)
			notifications.POST("/test/dingtalk", h.Notification.TestDingtalk)
			notifications.POST("/test/email", h.Notification.TestEmail)
			notifications.POST("/test/webhook", h.Notification.TestWebhook)
		}

		// Lendings
		lendings := protected.Group("/lendings")
		{
			lendings.GET("", h.Lending.List)
			lendings.POST("", h.Lending.Create)
			lendings.GET("/summary", h.Lending.GetSummary)
			lendings.GET("/:id", h.Lending.GetByID)
			lendings.PUT("/:id", h.Lending.Update)
			lendings.DELETE("/:id", h.Lending.Delete)
			lendings.POST("/:id/repay", h.Lending.RecordRepayment)
			lendings.GET("/:id/records", h.Lending.GetRecords)
		}

		// Export & Reports
		export := protected.Group("/export")
		{
			export.GET("/transactions/csv", h.Export.ExportCSV)
			export.GET("/report/yearly", h.Export.GetYearlyReport)
			export.GET("/years", h.Export.GetAvailableYears)
		}

		// System Settings
		system := protected.Group("/system")
		{
			system.GET("/entry-path", h.System.GetEntryPath)
			system.PUT("/entry-path", h.System.SetEntryPath)
			system.POST("/entry-path/generate", h.System.GenerateEntryPath)
			system.DELETE("/entry-path", h.System.DisableEntryPath)
		}

		// File Upload
		upload := protected.Group("/upload")
		{
			upload.POST("", h.Upload.Upload)
			upload.POST("/avatar", h.Upload.UploadAvatar)
			upload.DELETE("", h.Upload.Delete)
			upload.GET("/list", h.Upload.List)
			upload.GET("/download", h.Upload.Download)
		}

		// Account Logs
		accountLogs := protected.Group("/account-logs")
		{
			accountLogs.GET("", h.AccountLog.GetAll)
			accountLogs.GET("/account/:id", h.AccountLog.GetByAccountID)
		}

		// Tags
		tags := protected.Group("/tags")
		{
			tags.GET("", h.Tag.List)
			tags.POST("", h.Tag.Create)
			tags.GET("/:id", h.Tag.GetByID)
			tags.PUT("/:id", h.Tag.Update)
			tags.DELETE("/:id", h.Tag.Delete)
		}

		// API Tokens
		apiTokens := protected.Group("/api-tokens")
		{
			apiTokens.GET("", h.APIToken.List)
			apiTokens.POST("", h.APIToken.Create)
			apiTokens.DELETE("/:id", h.APIToken.Delete)
		}
	}
}
