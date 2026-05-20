package service

import (
	"bytes"
	"encoding/json"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

func TestRestoreBackupCanRunTwiceWithSameIDs(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "ledger.db")
	db, err := database.Init(dbPath)
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	backupSvc := NewBackupService(db, repos.Account, repos.Category, repos.Transaction, repos.Budget, repos.Reminder, repos.Lending, repos.Template, repos.Notification, repos.Tag, repos.User)

	user := &model.User{Username: "admin", PasswordHash: "hash"}
	if err := repos.User.Create(user); err != nil {
		t.Fatalf("create user: %v", err)
	}

	accountID := uuid.NewString()
	categoryID := uuid.NewString()
	txID := uuid.NewString()
	if err := db.Create(&model.Account{ID: accountID, UserID: user.ID, Name: "Cash", Type: "cash"}).Error; err != nil {
		t.Fatalf("create account: %v", err)
	}
	if err := db.Create(&model.Category{ID: categoryID, UserID: user.ID, Name: "Food", Type: "expense"}).Error; err != nil {
		t.Fatalf("create category: %v", err)
	}
	if err := db.Create(&model.Transaction{
		ID:              txID,
		UserID:          user.ID,
		AccountID:       accountID,
		CategoryID:      &categoryID,
		Type:            "expense",
		Amount:          12.5,
		TransactionDate: time.Now(),
	}).Error; err != nil {
		t.Fatalf("create transaction: %v", err)
	}

	backup, err := backupSvc.CreateBackup(user.ID)
	if err != nil {
		t.Fatalf("create backup: %v", err)
	}
	file := writeBackupFile(t, backup)

	if err := backupSvc.RestoreBackup(user.ID, file); err != nil {
		t.Fatalf("first restore: %v", err)
	}
	if err := backupSvc.RestoreBackup(user.ID, file); err != nil {
		t.Fatalf("second restore should not conflict with soft-deleted IDs: %v", err)
	}

	var accountCount int64
	if err := db.Model(&model.Account{}).Where("user_id = ?", user.ID).Count(&accountCount).Error; err != nil {
		t.Fatalf("count accounts: %v", err)
	}
	if accountCount != 1 {
		t.Fatalf("active account count = %d, want 1", accountCount)
	}
}

func TestRestoreBackupRejectsEmptyPayloadWithoutClearingData(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "ledger.db")
	db, err := database.Init(dbPath)
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	backupSvc := NewBackupService(db, repos.Account, repos.Category, repos.Transaction, repos.Budget, repos.Reminder, repos.Lending, repos.Template, repos.Notification, repos.Tag, repos.User)

	user := &model.User{Username: "admin", PasswordHash: "hash"}
	if err := repos.User.Create(user); err != nil {
		t.Fatalf("create user: %v", err)
	}
	if err := db.Create(&model.Account{ID: uuid.NewString(), UserID: user.ID, Name: "Cash", Type: "cash"}).Error; err != nil {
		t.Fatalf("create account: %v", err)
	}

	if err := backupSvc.RestoreBackup(user.ID, writeRawBackupFile(t, []byte(`{}`))); err == nil {
		t.Fatal("empty backup restore succeeded, want error")
	}

	var accountCount int64
	if err := db.Model(&model.Account{}).Where("user_id = ?", user.ID).Count(&accountCount).Error; err != nil {
		t.Fatalf("count accounts: %v", err)
	}
	if accountCount != 1 {
		t.Fatalf("active account count = %d, want original account to remain", accountCount)
	}
}

func writeBackupFile(t *testing.T, backup *FullBackupData) *multipart.FileHeader {
	t.Helper()
	path := filepath.Join(t.TempDir(), "backup.json")
	data, err := json.Marshal(backup)
	if err != nil {
		t.Fatalf("marshal backup: %v", err)
	}
	if err := os.WriteFile(path, data, 0600); err != nil {
		t.Fatalf("write backup: %v", err)
	}
	return mustFileHeader(t, path)
}

func writeRawBackupFile(t *testing.T, data []byte) *multipart.FileHeader {
	t.Helper()
	path := filepath.Join(t.TempDir(), "backup.json")
	if err := os.WriteFile(path, data, 0600); err != nil {
		t.Fatalf("write backup: %v", err)
	}
	return mustFileHeader(t, path)
}

func mustFileHeader(t *testing.T, path string) *multipart.FileHeader {
	t.Helper()
	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)
	part, err := writer.CreateFormFile("file", filepath.Base(path))
	if err != nil {
		t.Fatalf("create form file: %v", err)
	}
	src, err := os.Open(path)
	if err != nil {
		t.Fatalf("open backup: %v", err)
	}
	defer src.Close()
	if _, err := io.Copy(part, src); err != nil {
		t.Fatalf("copy backup: %v", err)
	}
	if err := writer.Close(); err != nil {
		t.Fatalf("close multipart writer: %v", err)
	}
	request, err := http.NewRequest("POST", "/restore", body)
	if err != nil {
		t.Fatalf("new request: %v", err)
	}
	request.Header.Set("Content-Type", writer.FormDataContentType())
	if err := request.ParseMultipartForm(32 << 20); err != nil {
		t.Fatalf("parse multipart: %v", err)
	}
	return request.MultipartForm.File["file"][0]
}
