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
	backupSvc := NewBackupService(db, repos.Account, repos.Category, repos.Transaction, repos.Budget, repos.Reminder, repos.Lending, repos.Template, repos.Notification, repos.Tag, repos.User, repos.FamilyMember, repos.AIReport)

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
	backupSvc := NewBackupService(db, repos.Account, repos.Category, repos.Transaction, repos.Budget, repos.Reminder, repos.Lending, repos.Template, repos.Notification, repos.Tag, repos.User, repos.FamilyMember, repos.AIReport)

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

func TestBackupRestoreRehearsalIncludesFamilyTransactionsAndAIReports(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "ledger.db")
	db, err := database.Init(dbPath)
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	backupSvc := NewBackupService(db, repos.Account, repos.Category, repos.Transaction, repos.Budget, repos.Reminder, repos.Lending, repos.Template, repos.Notification, repos.Tag, repos.User, repos.FamilyMember, repos.AIReport)

	user := &model.User{Username: "admin", PasswordHash: "hash"}
	if err := repos.User.Create(user); err != nil {
		t.Fatalf("create user: %v", err)
	}

	accountID := uuid.NewString()
	categoryID := uuid.NewString()
	memberID := uuid.NewString()
	txID := uuid.NewString()
	reportID := uuid.NewString()
	if err := db.Create(&model.Account{ID: accountID, UserID: user.ID, Name: "Household Cash", Type: "cash"}).Error; err != nil {
		t.Fatalf("create account: %v", err)
	}
	if err := db.Create(&model.Category{ID: categoryID, UserID: user.ID, Name: "Groceries", Type: "expense"}).Error; err != nil {
		t.Fatalf("create category: %v", err)
	}
	if err := db.Create(&model.FamilyMember{
		ID:           memberID,
		UserID:       user.ID,
		Name:         "Alice",
		Relationship: "spouse",
		Color:        "#2F80ED",
		IsDefault:    true,
		IsEnabled:    true,
	}).Error; err != nil {
		t.Fatalf("create family member: %v", err)
	}
	if err := db.Create(&model.Transaction{
		ID:              txID,
		UserID:          user.ID,
		AccountID:       accountID,
		CategoryID:      &categoryID,
		MemberID:        &memberID,
		PaidByMemberID:  &memberID,
		Type:            "expense",
		Amount:          88.8,
		TransactionDate: time.Date(2026, 5, 27, 9, 0, 0, 0, time.UTC),
	}).Error; err != nil {
		t.Fatalf("create transaction: %v", err)
	}
	if err := db.Create(&model.AIReport{
		ID:            reportID,
		UserID:        user.ID,
		ReportType:    "weekly",
		PeriodStart:   time.Date(2026, 5, 18, 0, 0, 0, 0, time.UTC),
		PeriodEnd:     time.Date(2026, 5, 24, 0, 0, 0, 0, time.UTC),
		Status:        "completed",
		SnapshotJSON:  `{"expense_total":88.8}`,
		ContentJSON:   `{"title":"Weekly summary"}`,
		ProviderName:  "DeepSeek",
		Model:         "deepseek-chat",
		PromptVersion: "personal-ledger-v1",
	}).Error; err != nil {
		t.Fatalf("create ai report: %v", err)
	}

	backup, err := backupSvc.CreateBackup(user.ID)
	if err != nil {
		t.Fatalf("create backup: %v", err)
	}
	if len(backup.FamilyMembers) != 1 {
		t.Fatalf("backup family member count = %d, want 1", len(backup.FamilyMembers))
	}
	if len(backup.Transactions) != 1 || backup.Transactions[0].MemberID == nil || *backup.Transactions[0].MemberID != memberID {
		t.Fatalf("backup transactions = %#v, want member-linked transaction", backup.Transactions)
	}
	if len(backup.AIReports) != 1 || backup.AIReports[0].ID != reportID {
		t.Fatalf("backup ai reports = %#v, want report %s", backup.AIReports, reportID)
	}

	if err := db.Create(&model.Account{ID: uuid.NewString(), UserID: user.ID, Name: "Temporary Account", Type: "cash"}).Error; err != nil {
		t.Fatalf("create temporary account: %v", err)
	}
	if err := backupSvc.RestoreBackup(user.ID, writeBackupFile(t, backup)); err != nil {
		t.Fatalf("restore backup: %v", err)
	}

	var restoredMember model.FamilyMember
	if err := db.Where("user_id = ? AND id = ?", user.ID, memberID).First(&restoredMember).Error; err != nil {
		t.Fatalf("restored family member missing: %v", err)
	}
	var restoredTx model.Transaction
	if err := db.Where("user_id = ? AND id = ?", user.ID, txID).First(&restoredTx).Error; err != nil {
		t.Fatalf("restored transaction missing: %v", err)
	}
	if restoredTx.MemberID == nil || *restoredTx.MemberID != memberID {
		t.Fatalf("restored transaction member id = %#v, want %s", restoredTx.MemberID, memberID)
	}
	var restoredReport model.AIReport
	if err := db.Where("user_id = ? AND id = ?", user.ID, reportID).First(&restoredReport).Error; err != nil {
		t.Fatalf("restored ai report missing: %v", err)
	}
	var temporaryCount int64
	if err := db.Model(&model.Account{}).Where("user_id = ? AND name = ?", user.ID, "Temporary Account").Count(&temporaryCount).Error; err != nil {
		t.Fatalf("count temporary account: %v", err)
	}
	if temporaryCount != 0 {
		t.Fatalf("temporary account count after restore = %d, want 0", temporaryCount)
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
