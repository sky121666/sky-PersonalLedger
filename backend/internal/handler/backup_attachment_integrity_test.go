package handler

import (
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/config"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/service"
)

func TestCreateBackupReportsMissingHistoricalAttachment(t *testing.T) {
	handler, repos, userID := newCreateBackupHandlerForTest(t, "", 0)
	handler.backupService.WithUploadService(service.NewUploadService(&config.StorageConfig{
		UploadPath: t.TempDir(), MaxFileSize: 1, AllowedTypes: "txt",
	}, repos.Account.DB()))
	accountID, transactionID := uuid.NewString(), uuid.NewString()
	if err := repos.Account.Create(&model.Account{ID: accountID, UserID: userID, Name: "Synthetic", Type: "cash"}); err != nil {
		t.Fatal(err)
	}
	transaction := &model.Transaction{
		ID: transactionID, UserID: userID, AccountID: accountID, Type: "expense",
		Amount: 1, TransactionDate: time.Now(),
		Images: fmt.Sprintf(`["%d/transactions/%s/missing.txt"]`, userID, transactionID),
	}
	if err := repos.Transaction.DB().Create(transaction).Error; err != nil {
		t.Fatal(err)
	}
	if err := repos.Transaction.DB().Delete(transaction).Error; err != nil {
		t.Fatal(err)
	}
	result := performCreateBackupRequest(handler, userID)
	if result.Code != http.StatusConflict {
		t.Fatalf("incomplete backup status=%d, want 409; body=%s", result.Code, result.Body.String())
	}
	if result.Header().Get("Content-Disposition") != "" {
		t.Fatal("failed backup was offered as a download")
	}
}

func TestR5CreateBackupRejectsMissingAvatars(t *testing.T) {
	for _, kind := range []string{"profile", "deleted_member"} {
		t.Run(kind, func(t *testing.T) {
			handler, repos, userID := newCreateBackupHandlerForTest(t, "", 0)
			db := repos.Account.DB()
			handler.backupService.WithUploadService(service.NewUploadService(&config.StorageConfig{
				UploadPath: t.TempDir(), MaxFileSize: 1, AllowedTypes: "png",
			}, db))
			avatar := fmt.Sprintf("/uploads/%d/avatars/profile/missing.png", userID)
			if kind == "profile" {
				if err := db.Model(&model.User{}).Where("id = ?", userID).Update("avatar", avatar).Error; err != nil {
					t.Fatal(err)
				}
			} else {
				member := &model.FamilyMember{ID: uuid.NewString(), UserID: userID, Name: "Historical", Avatar: avatar}
				if err := db.Create(member).Error; err != nil {
					t.Fatal(err)
				}
				if err := db.Delete(member).Error; err != nil {
					t.Fatal(err)
				}
			}
			result := performCreateBackupRequest(handler, userID)
			assertBackupCreateError(t, result, http.StatusConflict, 40905, "备份附件不完整，请先核对缺失附件；未生成备份")
			if result.Header().Get("Content-Disposition") != "" {
				t.Fatal("incomplete backup offered as download")
			}
		})
	}
}
