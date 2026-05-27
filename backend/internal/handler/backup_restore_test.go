package handler

import (
	"bytes"
	"encoding/json"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"github.com/sky/personal-ledger/internal/service"
)

func TestRestoreCreatesPreRestoreBackupBeforeReplacingData(t *testing.T) {
	gin.SetMode(gin.TestMode)
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	backupSvc := service.NewBackupService(
		db,
		repos.Account,
		repos.Category,
		repos.Transaction,
		repos.Budget,
		repos.Reminder,
		repos.Lending,
		repos.Template,
		repos.Notification,
		repos.Tag,
		repos.User,
		repos.FamilyMember,
		repos.AIReport,
	)
	backupPath := t.TempDir()
	scheduler := service.NewBackupScheduler(
		backupSvc,
		repos.System,
		repos.User,
		backupPath,
	)
	backupHandler := NewBackupHandler(backupSvc, scheduler)

	user := &model.User{Username: "admin", PasswordHash: "hash"}
	if err := repos.User.Create(user); err != nil {
		t.Fatalf("create user: %v", err)
	}
	if err := db.Create(&model.Account{
		ID:             uuid.NewString(),
		UserID:         user.ID,
		Name:           "Current Cash",
		Type:           "cash",
		CurrentBalance: 99,
	}).Error; err != nil {
		t.Fatalf("create current account: %v", err)
	}

	restoreBackup := &service.FullBackupData{
		Version:    "2.1",
		ExportedAt: time.Now(),
		Accounts: []model.Account{{
			ID:             uuid.NewString(),
			UserID:         user.ID,
			Name:           "Imported Cash",
			Type:           "cash",
			CurrentBalance: 12,
		}},
	}
	request := newRestoreRequest(t, restoreBackup)
	response := httptest.NewRecorder()
	router := gin.New()
	router.POST("/restore", func(c *gin.Context) {
		c.Set("userID", user.ID)
		backupHandler.Restore(c)
	})

	router.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("restore status = %d, body = %s", response.Code, response.Body.String())
	}
	files, err := filepath.Glob(filepath.Join(backupPath, "pre_restore_backup_user*.json"))
	if err != nil {
		t.Fatalf("glob pre-restore backups: %v", err)
	}
	if len(files) != 1 {
		t.Fatalf("pre-restore backup count = %d, want 1", len(files))
	}
	var preRestore service.FullBackupData
	data, err := os.ReadFile(files[0])
	if err != nil {
		t.Fatalf("read pre-restore backup: %v", err)
	}
	if err := json.Unmarshal(data, &preRestore); err != nil {
		t.Fatalf("unmarshal pre-restore backup: %v", err)
	}
	if len(preRestore.Accounts) != 1 || preRestore.Accounts[0].Name != "Current Cash" {
		t.Fatalf("pre-restore accounts = %#v, want current data snapshot", preRestore.Accounts)
	}

	var restoredAccount model.Account
	if err := db.Where("user_id = ? AND name = ?", user.ID, "Imported Cash").First(&restoredAccount).Error; err != nil {
		t.Fatalf("imported account missing after restore: %v", err)
	}
}

func TestRestoreRejectsEmptyBackupPayload(t *testing.T) {
	gin.SetMode(gin.TestMode)
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	backupSvc := service.NewBackupService(
		db,
		repos.Account,
		repos.Category,
		repos.Transaction,
		repos.Budget,
		repos.Reminder,
		repos.Lending,
		repos.Template,
		repos.Notification,
		repos.Tag,
		repos.User,
		repos.FamilyMember,
		repos.AIReport,
	)
	backupHandler := NewBackupHandler(backupSvc, nil)

	user := &model.User{Username: "admin", PasswordHash: "hash"}
	if err := repos.User.Create(user); err != nil {
		t.Fatalf("create user: %v", err)
	}
	if err := db.Create(&model.Account{
		ID:     uuid.NewString(),
		UserID: user.ID,
		Name:   "Current Cash",
		Type:   "cash",
	}).Error; err != nil {
		t.Fatalf("create current account: %v", err)
	}

	request := newRawRestoreRequest(t, []byte(`{}`))
	response := httptest.NewRecorder()
	router := gin.New()
	router.POST("/restore", func(c *gin.Context) {
		c.Set("userID", user.ID)
		backupHandler.Restore(c)
	})

	router.ServeHTTP(response, request)

	if response.Code != http.StatusBadRequest {
		t.Fatalf("restore status = %d, body = %s", response.Code, response.Body.String())
	}

	var accountCount int64
	if err := db.Model(&model.Account{}).Where("user_id = ?", user.ID).Count(&accountCount).Error; err != nil {
		t.Fatalf("count accounts: %v", err)
	}
	if accountCount != 1 {
		t.Fatalf("active account count = %d, want original account to remain", accountCount)
	}
}

func TestRestoreRejectsMalformedBackupPayload(t *testing.T) {
	gin.SetMode(gin.TestMode)
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	backupSvc := service.NewBackupService(
		db,
		repos.Account,
		repos.Category,
		repos.Transaction,
		repos.Budget,
		repos.Reminder,
		repos.Lending,
		repos.Template,
		repos.Notification,
		repos.Tag,
		repos.User,
		repos.FamilyMember,
		repos.AIReport,
	)
	backupHandler := NewBackupHandler(backupSvc, nil)

	user := &model.User{Username: "admin", PasswordHash: "hash"}
	if err := repos.User.Create(user); err != nil {
		t.Fatalf("create user: %v", err)
	}

	request := newRawRestoreRequest(t, []byte(`{"accounts":`))
	response := httptest.NewRecorder()
	router := gin.New()
	router.POST("/restore", func(c *gin.Context) {
		c.Set("userID", user.ID)
		backupHandler.Restore(c)
	})

	router.ServeHTTP(response, request)

	if response.Code != http.StatusBadRequest {
		t.Fatalf("restore status = %d, body = %s", response.Code, response.Body.String())
	}
}

func newRestoreRequest(t *testing.T, backup *service.FullBackupData) *http.Request {
	t.Helper()
	data, err := json.Marshal(backup)
	if err != nil {
		t.Fatalf("marshal backup: %v", err)
	}
	return newRawRestoreRequest(t, data)
}

func newRawRestoreRequest(t *testing.T, data []byte) *http.Request {
	t.Helper()
	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)
	part, err := writer.CreateFormFile("file", "backup.json")
	if err != nil {
		t.Fatalf("create form file: %v", err)
	}
	if _, err := part.Write(data); err != nil {
		t.Fatalf("write backup multipart: %v", err)
	}
	if err := writer.Close(); err != nil {
		t.Fatalf("close multipart writer: %v", err)
	}
	request := httptest.NewRequest(http.MethodPost, "/restore", body)
	request.Header.Set("Content-Type", writer.FormDataContentType())
	return request
}
