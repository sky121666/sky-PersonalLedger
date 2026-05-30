package handler

import (
	"errors"
	"fmt"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/middleware"
	"github.com/sky/personal-ledger/internal/service"
	"github.com/sky/personal-ledger/pkg/response"
)

type BackupHandler struct {
	backupService   *service.BackupService
	backupScheduler *service.BackupScheduler
}

func NewBackupHandler(backupService *service.BackupService, backupScheduler *service.BackupScheduler) *BackupHandler {
	return &BackupHandler{backupService: backupService, backupScheduler: backupScheduler}
}

func (h *BackupHandler) Create(c *gin.Context) {
	userID := middleware.GetUserID(c)

	backup, err := h.backupService.CreateBackup(userID)
	if err != nil {
		response.InternalError(c, err.Error())
		return
	}

	filename := fmt.Sprintf("backup_%s.json", time.Now().Format("20060102_150405"))
	c.Header("Content-Type", "application/json; charset=utf-8")
	setAttachmentHeader(c, filename)
	c.JSON(200, backup)
}

func (h *BackupHandler) Restore(c *gin.Context) {
	userID := middleware.GetUserID(c)

	file, err := c.FormFile("file")
	if err != nil {
		response.BadRequest(c, "file is required")
		return
	}

	var preRestoreBackup *service.BackupFileInfo
	if h.backupScheduler != nil {
		preRestoreBackup, err = h.backupScheduler.CreatePreRestoreBackup(userID)
		if err != nil {
			response.InternalError(c, "failed to create pre-restore backup: "+err.Error())
			return
		}
	}

	err = h.backupService.RestoreBackup(userID, file)
	if err != nil {
		if errors.Is(err, service.ErrInvalidBackupData) || errors.Is(err, service.ErrInvalidBackupFormat) {
			response.BadRequest(c, err.Error())
			return
		}
		response.InternalError(c, err.Error())
		return
	}

	payload := gin.H{"message": "restore successful"}
	if preRestoreBackup != nil {
		payload["pre_restore_backup"] = preRestoreBackup
	}
	response.Success(c, payload)
}

func (h *BackupHandler) GetAutoBackupSettings(c *gin.Context) {
	settings, err := h.backupScheduler.GetSettings()
	if err != nil {
		response.InternalError(c, err.Error())
		return
	}
	response.Success(c, settings)
}

type UpdateAutoBackupRequest struct {
	Enabled    bool   `json:"enabled"`
	Frequency  string `json:"frequency"`
	Hour       int    `json:"hour"`
	MaxBackups int    `json:"max_backups"`
}

func (h *BackupHandler) UpdateAutoBackupSettings(c *gin.Context) {
	var req UpdateAutoBackupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, err.Error())
		return
	}

	settings := &service.AutoBackupSettings{
		Enabled:    req.Enabled,
		Frequency:  req.Frequency,
		Hour:       req.Hour,
		MaxBackups: req.MaxBackups,
	}

	if err := h.backupScheduler.SaveSettings(settings); err != nil {
		if errors.Is(err, service.ErrAutoBackupSettingsInvalid) {
			response.BadRequest(c, err.Error())
			return
		}
		response.InternalError(c, err.Error())
		return
	}

	response.Success(c, settings)
}

func (h *BackupHandler) TriggerAutoBackup(c *gin.Context) {
	if err := h.backupScheduler.TriggerBackup(); err != nil {
		response.InternalError(c, err.Error())
		return
	}
	response.Success(c, gin.H{"message": "backup triggered"})
}

func (h *BackupHandler) ListAutoBackups(c *gin.Context) {
	files, err := h.backupScheduler.ListBackups()
	if err != nil {
		response.InternalError(c, err.Error())
		return
	}
	response.Success(c, gin.H{"files": files})
}
