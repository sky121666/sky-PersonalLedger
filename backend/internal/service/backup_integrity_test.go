package service

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/config"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"gorm.io/gorm"
)

func TestRestoreBackupPreservesNotificationCredentials(t *testing.T) {
	fixture := newBackupIntegrityFixture(t)
	existing := &model.NotificationSetting{
		UserID:             fixture.user.ID,
		Enabled:            true,
		DingtalkEnabled:    true,
		DingtalkWebhook:    "https://target.example/dingtalk",
		DingtalkSecret:     "target-dingtalk-secret",
		EmailEnabled:       true,
		SmtpHost:           "smtp.target.example",
		SmtpPort:           465,
		SmtpUser:           "target-user",
		SmtpPassword:       "target-smtp-password",
		WebhookEnabled:     true,
		WebhookURL:         "https://target.example/webhook",
		WebhookSecret:      "target-webhook-secret",
		NotifyPaymentDue:   true,
		NotifyBudgetAlert:  true,
		NotifyLendingDue:   true,
		NotifyAnnualReport: true,
		AdvanceDays:        3,
	}
	if err := fixture.db.Create(existing).Error; err != nil {
		t.Fatalf("seed notification settings: %v", err)
	}

	backup := &FullBackupData{
		Version:     "2.2",
		Attachments: []BackupAttachment{},
		Accounts: []model.Account{{
			ID:     uuid.NewString(),
			UserID: fixture.user.ID,
			Name:   "Restored Cash",
			Type:   "cash",
		}},
		NotificationSettings: &model.NotificationSetting{
			UserID:             fixture.user.ID,
			Enabled:            false,
			DingtalkEnabled:    false,
			DingtalkWebhook:    "https://backup.example/dingtalk",
			DingtalkSecret:     "must-not-enter-json",
			EmailEnabled:       false,
			SmtpHost:           "smtp.backup.example",
			SmtpPort:           587,
			SmtpUser:           "backup-user",
			SmtpPassword:       "must-not-enter-json",
			WebhookEnabled:     false,
			WebhookURL:         "https://backup.example/webhook",
			WebhookSecret:      "must-not-enter-json",
			NotifyPaymentDue:   false,
			NotifyBudgetAlert:  false,
			NotifyLendingDue:   false,
			NotifyAnnualReport: false,
			AdvanceDays:        9,
		},
	}
	data, err := json.Marshal(backup)
	if err != nil {
		t.Fatalf("marshal backup: %v", err)
	}
	if strings.Contains(string(data), "must-not-enter-json") {
		t.Fatalf("notification secret leaked into backup JSON: %s", data)
	}

	if err := fixture.service.RestoreBackup(fixture.user.ID, writeRawBackupFile(t, data)); err != nil {
		t.Fatalf("restore backup: %v", err)
	}

	var restored model.NotificationSetting
	if err := fixture.db.Where("user_id = ?", fixture.user.ID).First(&restored).Error; err != nil {
		t.Fatalf("load restored notification settings: %v", err)
	}
	if restored.ID != existing.ID {
		t.Fatalf("notification row id = %d, want preserved id %d", restored.ID, existing.ID)
	}
	if restored.DingtalkSecret != existing.DingtalkSecret ||
		restored.SmtpPassword != existing.SmtpPassword ||
		restored.WebhookSecret != existing.WebhookSecret {
		t.Fatalf("notification credentials were not preserved: %#v", restored)
	}
	if restored.AdvanceDays != 9 || restored.SmtpHost != "smtp.backup.example" || restored.Enabled {
		t.Fatalf("serializable notification settings were not restored: %#v", restored)
	}
}

func TestRestoreLegacyBackupWithoutNotificationSettingsPreservesTargetSettings(t *testing.T) {
	fixture := newBackupIntegrityFixture(t)
	existing := &model.NotificationSetting{
		UserID:           fixture.user.ID,
		Enabled:          true,
		WecomEnabled:     true,
		WecomWebhook:     "https://target.example/wecom",
		DingtalkSecret:   "target-dingtalk-secret",
		SmtpPassword:     "target-smtp-password",
		WebhookSecret:    "target-webhook-secret",
		NotifyPaymentDue: true,
		AdvanceDays:      6,
	}
	if err := fixture.db.Create(existing).Error; err != nil {
		t.Fatalf("seed notification settings: %v", err)
	}

	legacy := &FullBackupData{
		Version: "2.1",
		Accounts: []model.Account{{
			ID:   uuid.NewString(),
			Name: "Legacy Cash",
			Type: "cash",
		}},
		NotificationSettings: nil,
		Attachments:          nil,
	}
	if err := fixture.service.RestoreBackup(fixture.user.ID, writeBackupFile(t, legacy)); err != nil {
		t.Fatalf("restore legacy backup: %v", err)
	}

	var restored model.NotificationSetting
	if err := fixture.db.Where("user_id = ?", fixture.user.ID).First(&restored).Error; err != nil {
		t.Fatalf("load notification settings: %v", err)
	}
	if restored.ID != existing.ID || restored.WecomWebhook != existing.WecomWebhook ||
		restored.DingtalkSecret != existing.DingtalkSecret || restored.SmtpPassword != existing.SmtpPassword ||
		restored.WebhookSecret != existing.WebhookSecret || restored.AdvanceDays != existing.AdvanceDays {
		t.Fatalf("legacy restore changed target notification settings: got %#v want %#v", restored, existing)
	}
}

func TestBackupAttachmentsRoundTripWithIntegrityMetadata(t *testing.T) {
	fixture := newBackupIntegrityFixture(t)
	relativePath := filepath.Join("transactions", "tx-1", "receipt.txt")
	originalContent := []byte("verified receipt content")
	writeIntegrityFixture(t, fixture.uploadPath, filepath.Join(fixture.userDirectory(), relativePath), originalContent)
	writeIntegrityFixture(t, fixture.uploadPath, filepath.Join("999", "transactions", "tx-other", "other.txt"), []byte("other user"))

	backup, err := fixture.service.CreateBackup(fixture.user.ID)
	if err != nil {
		t.Fatalf("create backup: %v", err)
	}
	if backup.Version != "2.2" {
		t.Fatalf("backup version = %q, want 2.2", backup.Version)
	}
	if backup.Attachments == nil || len(backup.Attachments) != 1 {
		t.Fatalf("backup attachments = %#v, want one explicit attachment", backup.Attachments)
	}
	attachment := backup.Attachments[0]
	if attachment.RelativePath != filepath.ToSlash(relativePath) || attachment.Size != int64(len(originalContent)) {
		t.Fatalf("attachment metadata = %#v", attachment)
	}
	wantHash := sha256.Sum256(originalContent)
	if attachment.SHA256 != hex.EncodeToString(wantHash[:]) {
		t.Fatalf("attachment sha256 = %q, want %x", attachment.SHA256, wantHash)
	}
	decoded, err := base64.StdEncoding.DecodeString(attachment.ContentBase64)
	if err != nil || string(decoded) != string(originalContent) {
		t.Fatalf("attachment content = %q, err=%v", decoded, err)
	}

	if err := os.WriteFile(filepath.Join(fixture.uploadPath, fixture.userDirectory(), relativePath), []byte("changed"), 0600); err != nil {
		t.Fatalf("change attachment before restore: %v", err)
	}
	writeIntegrityFixture(t, fixture.uploadPath, filepath.Join(fixture.userDirectory(), "reminders", "old", "obsolete.txt"), []byte("obsolete"))

	if err := fixture.service.RestoreBackup(fixture.user.ID, writeBackupFile(t, backup)); err != nil {
		t.Fatalf("restore backup: %v", err)
	}
	restoredContent, err := os.ReadFile(filepath.Join(fixture.uploadPath, fixture.userDirectory(), relativePath))
	if err != nil || string(restoredContent) != string(originalContent) {
		t.Fatalf("restored attachment = %q, err=%v", restoredContent, err)
	}
	if _, err := os.Stat(filepath.Join(fixture.uploadPath, fixture.userDirectory(), "reminders", "old", "obsolete.txt")); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("obsolete attachment survived complete restore: %v", err)
	}
	otherContent, err := os.ReadFile(filepath.Join(fixture.uploadPath, "999", "transactions", "tx-other", "other.txt"))
	if err != nil || string(otherContent) != "other user" {
		t.Fatalf("other user's attachment changed: %q, err=%v", otherContent, err)
	}
	assertNoAttachmentRestoreArtifacts(t, fixture.uploadPath)
}

func TestBackupEmitsExplicitEmptyAttachmentManifest(t *testing.T) {
	fixture := newBackupIntegrityFixture(t)
	backup, err := fixture.service.CreateBackup(fixture.user.ID)
	if err != nil {
		t.Fatalf("create empty attachment backup: %v", err)
	}
	if backup.Attachments == nil || len(backup.Attachments) != 0 {
		t.Fatalf("empty attachment manifest = %#v, want non-nil empty slice", backup.Attachments)
	}
	data, err := json.Marshal(backup)
	if err != nil {
		t.Fatalf("marshal backup: %v", err)
	}
	if !strings.Contains(string(data), `"attachments":[]`) {
		t.Fatalf("backup did not preserve explicit empty attachment manifest: %s", data)
	}
}

func TestBackupRejectsSymlinkedAttachment(t *testing.T) {
	fixture := newBackupIntegrityFixture(t)
	otherPath := filepath.Join(fixture.uploadPath, "999", "transactions", "other", "secret.txt")
	writeIntegrityFixture(t, fixture.uploadPath, filepath.Join("999", "transactions", "other", "secret.txt"), []byte("other user secret"))
	linkPath := filepath.Join(fixture.uploadPath, fixture.userDirectory(), "transactions", "tx", "linked.txt")
	if err := os.MkdirAll(filepath.Dir(linkPath), 0755); err != nil {
		t.Fatalf("create symlink fixture directory: %v", err)
	}
	if err := os.Symlink(otherPath, linkPath); err != nil {
		t.Skipf("symlinks are unavailable on this platform: %v", err)
	}

	if _, err := fixture.service.CreateBackup(fixture.user.ID); err == nil {
		t.Fatal("backup unexpectedly followed a symlinked attachment")
	}
}

func TestCreateBackupRejectsPayloadLargerThanRestoreLimit(t *testing.T) {
	fixture := newBackupIntegrityFixture(t)
	if err := fixture.db.Model(&model.User{}).Where("id = ?", fixture.user.ID).Update("bio", strings.Repeat("x", 2048)).Error; err != nil {
		t.Fatalf("expand profile for backup: %v", err)
	}
	limited := NewBackupService(
		fixture.db,
		fixture.repos.Account,
		fixture.repos.Category,
		fixture.repos.Transaction,
		fixture.repos.Budget,
		fixture.repos.Reminder,
		fixture.repos.Lending,
		fixture.repos.Template,
		fixture.repos.Notification,
		fixture.repos.Tag,
		fixture.repos.User,
		fixture.repos.FamilyMember,
		fixture.repos.AIReport,
		512,
	).WithUploadService(fixture.service.uploadService)

	if _, err := limited.CreateBackup(fixture.user.ID); !errors.Is(err, ErrBackupFileTooLarge) {
		t.Fatalf("create backup error = %v, want ErrBackupFileTooLarge", err)
	}
}

func TestRestoreLegacyBackupWithoutAttachmentManifestPreservesFiles(t *testing.T) {
	fixture := newBackupIntegrityFixture(t)
	currentPath := filepath.Join(fixture.userDirectory(), "transactions", "tx-current", "current.txt")
	writeIntegrityFixture(t, fixture.uploadPath, currentPath, []byte("current attachment"))
	legacy := &FullBackupData{
		Version:  "2.1",
		Accounts: []model.Account{{ID: uuid.NewString(), Name: "Legacy Cash", Type: "cash"}},
	}

	if err := fixture.service.RestoreBackup(fixture.user.ID, writeBackupFile(t, legacy)); err != nil {
		t.Fatalf("restore legacy backup: %v", err)
	}
	content, err := os.ReadFile(filepath.Join(fixture.uploadPath, currentPath))
	if err != nil || string(content) != "current attachment" {
		t.Fatalf("legacy restore changed current attachment: %q, err=%v", content, err)
	}
}

func TestRestoreRemapsAttachmentReferencesToTargetUser(t *testing.T) {
	fixture := newBackupIntegrityFixture(t)
	const sourceUserID uint = 77
	accountID := uuid.NewString()
	transactionID := uuid.NewString()
	receiptPath := "transactions/" + transactionID + "/receipt.txt"
	avatarPath := "avatars/profile/avatar.txt"
	backup := &FullBackupData{
		Version:      "2.2",
		SourceUserID: sourceUserID,
		UserProfile: &UserProfileBackup{
			Avatar: "/uploads/77/" + avatarPath,
		},
		Accounts: []model.Account{{
			ID:     accountID,
			UserID: sourceUserID,
			Name:   "Imported Cash",
			Type:   "cash",
		}},
		Transactions: []model.Transaction{{
			ID:        transactionID,
			UserID:    sourceUserID,
			AccountID: accountID,
			Type:      "expense",
			Amount:    12,
			Images:    `["77/` + receiptPath + `"]`,
		}},
		Attachments: []BackupAttachment{
			backupAttachmentForContent(receiptPath, []byte("receipt")),
			backupAttachmentForContent(avatarPath, []byte("avatar")),
		},
	}

	if err := fixture.service.RestoreBackup(fixture.user.ID, writeBackupFile(t, backup)); err != nil {
		t.Fatalf("restore cross-instance backup: %v", err)
	}
	var transaction model.Transaction
	if err := fixture.db.Where("user_id = ? AND id = ?", fixture.user.ID, transactionID).First(&transaction).Error; err != nil {
		t.Fatalf("load restored transaction: %v", err)
	}
	wantImages := `[` + `"` + fixture.userDirectory() + `/` + receiptPath + `"` + `]`
	if transaction.Images != wantImages {
		t.Fatalf("restored transaction images = %q, want %q", transaction.Images, wantImages)
	}
	var user model.User
	if err := fixture.db.First(&user, fixture.user.ID).Error; err != nil {
		t.Fatalf("load restored user: %v", err)
	}
	wantAvatar := "/uploads/" + fixture.userDirectory() + "/" + avatarPath
	if user.Avatar != wantAvatar {
		t.Fatalf("restored avatar = %q, want %q", user.Avatar, wantAvatar)
	}
	if content, err := os.ReadFile(filepath.Join(fixture.uploadPath, fixture.userDirectory(), filepath.FromSlash(receiptPath))); err != nil || string(content) != "receipt" {
		t.Fatalf("restored remapped receipt = %q, err=%v", content, err)
	}
}

func TestRestoreRejectsCrossUserDatabaseAttachmentReference(t *testing.T) {
	fixture := newBackupIntegrityFixture(t)
	original := &model.Account{ID: uuid.NewString(), UserID: fixture.user.ID, Name: "Current Cash", Type: "cash"}
	if err := fixture.db.Create(original).Error; err != nil {
		t.Fatalf("seed current account: %v", err)
	}
	backup := &FullBackupData{
		Version:      "2.2",
		SourceUserID: 77,
		Accounts:     []model.Account{{ID: uuid.NewString(), UserID: 77, Name: "Imported", Type: "cash"}},
		UserProfile:  &UserProfileBackup{Avatar: "/uploads/88/avatars/profile/stolen.txt"},
		Attachments:  []BackupAttachment{},
	}

	err := fixture.service.RestoreBackup(fixture.user.ID, writeBackupFile(t, backup))
	if !errors.Is(err, ErrInvalidBackupFormat) {
		t.Fatalf("restore error = %v, want ErrInvalidBackupFormat", err)
	}
	var account model.Account
	if err := fixture.db.Where("user_id = ?", fixture.user.ID).First(&account).Error; err != nil || account.ID != original.ID {
		t.Fatalf("cross-user reference mutated current data: %#v, err=%v", account, err)
	}
}

func TestRestoreRejectsUnsafeOrCorruptAttachmentManifestWithoutMutation(t *testing.T) {
	tests := []struct {
		name        string
		attachments []BackupAttachment
	}{
		{
			name: "path traversal",
			attachments: []BackupAttachment{
				backupAttachmentForContent("../2/transactions/stolen.txt", []byte("stolen")),
			},
		},
		{
			name: "cross user shaped path",
			attachments: []BackupAttachment{
				backupAttachmentForContent("2/transactions/stolen.txt", []byte("stolen")),
			},
		},
		{
			name: "duplicate path",
			attachments: []BackupAttachment{
				backupAttachmentForContent("transactions/tx/new.txt", []byte("first")),
				backupAttachmentForContent("transactions/tx/new.txt", []byte("second")),
			},
		},
		{
			name: "file directory collision",
			attachments: []BackupAttachment{
				backupAttachmentForContent("transactions/collision", []byte("file")),
				backupAttachmentForContent("transactions/collision/nested.txt", []byte("nested")),
			},
		},
		{
			name: "case folded collision",
			attachments: []BackupAttachment{
				backupAttachmentForContent("transactions/tx/Receipt.txt", []byte("first")),
				backupAttachmentForContent("transactions/tx/receipt.txt", []byte("second")),
			},
		},
		{
			name: "unicode nfc collision",
			attachments: []BackupAttachment{
				backupAttachmentForContent("transactions/tx/caf\u00e9.txt", []byte("first")),
				backupAttachmentForContent("transactions/tx/cafe\u0301.txt", []byte("second")),
			},
		},
		{
			name: "windows reserved name",
			attachments: []BackupAttachment{
				backupAttachmentForContent("transactions/tx/CON.txt", []byte("reserved")),
			},
		},
		{
			name: "windows superscript reserved name",
			attachments: []BackupAttachment{
				backupAttachmentForContent("transactions/tx/COM¹.txt", []byte("reserved")),
			},
		},
		{
			name: "windows illegal character",
			attachments: []BackupAttachment{
				backupAttachmentForContent("transactions/tx/bad?.txt", []byte("illegal")),
			},
		},
		{
			name: "windows trailing dot",
			attachments: []BackupAttachment{
				backupAttachmentForContent("transactions/tx/trailing.", []byte("trailing")),
			},
		},
		{
			name: "hash mismatch",
			attachments: []BackupAttachment{
				func() BackupAttachment {
					attachment := backupAttachmentForContent("transactions/tx/new.txt", []byte("content"))
					attachment.SHA256 = strings.Repeat("0", sha256.Size*2)
					return attachment
				}(),
			},
		},
		{
			name: "size mismatch",
			attachments: []BackupAttachment{
				func() BackupAttachment {
					attachment := backupAttachmentForContent("transactions/tx/new.txt", []byte("content"))
					attachment.Size++
					return attachment
				}(),
			},
		},
		{
			name: "invalid base64",
			attachments: []BackupAttachment{
				func() BackupAttachment {
					attachment := backupAttachmentForContent("transactions/tx/new.txt", []byte("content"))
					attachment.ContentBase64 = "%%%"
					return attachment
				}(),
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			fixture := newBackupIntegrityFixture(t)
			originalAccount := &model.Account{ID: uuid.NewString(), UserID: fixture.user.ID, Name: "Current Cash", Type: "cash"}
			if err := fixture.db.Create(originalAccount).Error; err != nil {
				t.Fatalf("seed current account: %v", err)
			}
			currentPath := filepath.Join(fixture.userDirectory(), "transactions", "tx-current", "current.txt")
			writeIntegrityFixture(t, fixture.uploadPath, currentPath, []byte("current attachment"))

			backup := &FullBackupData{
				Version:     "2.2",
				Accounts:    []model.Account{{ID: uuid.NewString(), Name: "Replacement", Type: "cash"}},
				Attachments: tt.attachments,
			}
			err := fixture.service.RestoreBackup(fixture.user.ID, writeBackupFile(t, backup))
			if !errors.Is(err, ErrInvalidBackupFormat) {
				t.Fatalf("restore error = %v, want ErrInvalidBackupFormat", err)
			}

			var account model.Account
			if err := fixture.db.Where("user_id = ?", fixture.user.ID).First(&account).Error; err != nil {
				t.Fatalf("load current account: %v", err)
			}
			if account.ID != originalAccount.ID {
				t.Fatalf("account changed after rejected restore: %#v", account)
			}
			content, err := os.ReadFile(filepath.Join(fixture.uploadPath, currentPath))
			if err != nil || string(content) != "current attachment" {
				t.Fatalf("attachment changed after rejected restore: %q, err=%v", content, err)
			}
			assertNoAttachmentRestoreArtifacts(t, fixture.uploadPath)
		})
	}
}

func TestRestoreRejectsAttachmentOverUploadLimitWithoutMutation(t *testing.T) {
	fixture := newBackupIntegrityFixture(t)
	original := &model.Account{ID: uuid.NewString(), UserID: fixture.user.ID, Name: "Current Cash", Type: "cash"}
	if err := fixture.db.Create(original).Error; err != nil {
		t.Fatalf("seed current account: %v", err)
	}
	backup := &FullBackupData{
		Version:  "2.2",
		Accounts: []model.Account{{ID: uuid.NewString(), Name: "Replacement", Type: "cash"}},
		Attachments: []BackupAttachment{{
			RelativePath:  "transactions/tx/huge.txt",
			Size:          (1 << 20) + 1,
			SHA256:        strings.Repeat("0", sha256.Size*2),
			ContentBase64: "",
		}},
	}

	err := fixture.service.RestoreBackup(fixture.user.ID, writeBackupFile(t, backup))
	if !errors.Is(err, ErrBackupFileTooLarge) {
		t.Fatalf("restore error = %v, want ErrBackupFileTooLarge", err)
	}
	var account model.Account
	if err := fixture.db.Where("user_id = ?", fixture.user.ID).First(&account).Error; err != nil || account.ID != original.ID {
		t.Fatalf("current account changed after oversized restore: %#v, err=%v", account, err)
	}
	assertNoAttachmentRestoreArtifacts(t, fixture.uploadPath)
}

func TestRestoreDatabaseFailureKeepsCurrentAttachmentsAndRollsBackData(t *testing.T) {
	fixture := newBackupIntegrityFixture(t)
	original := &model.Account{ID: uuid.NewString(), UserID: fixture.user.ID, Name: "Current Cash", Type: "cash"}
	if err := fixture.db.Create(original).Error; err != nil {
		t.Fatalf("seed current account: %v", err)
	}
	currentPath := filepath.Join(fixture.userDirectory(), "transactions", "tx-current", "current.txt")
	writeIntegrityFixture(t, fixture.uploadPath, currentPath, []byte("current attachment"))

	duplicateID := uuid.NewString()
	backup := &FullBackupData{
		Version: "2.2",
		Accounts: []model.Account{
			{ID: duplicateID, Name: "Duplicate One", Type: "cash"},
			{ID: duplicateID, Name: "Duplicate Two", Type: "cash"},
		},
		Attachments: []BackupAttachment{
			backupAttachmentForContent("transactions/tx-new/new.txt", []byte("new attachment")),
		},
	}

	if err := fixture.service.RestoreBackup(fixture.user.ID, writeBackupFile(t, backup)); err == nil {
		t.Fatal("restore unexpectedly succeeded with duplicate account ids")
	}
	var account model.Account
	if err := fixture.db.Where("user_id = ?", fixture.user.ID).First(&account).Error; err != nil || account.ID != original.ID {
		t.Fatalf("database rollback did not preserve current account: %#v, err=%v", account, err)
	}
	content, err := os.ReadFile(filepath.Join(fixture.uploadPath, currentPath))
	if err != nil || string(content) != "current attachment" {
		t.Fatalf("database failure changed current attachment: %q, err=%v", content, err)
	}
	if _, err := os.Stat(filepath.Join(fixture.uploadPath, fixture.userDirectory(), "transactions", "tx-new", "new.txt")); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("database failure activated new attachment: %v", err)
	}
	assertNoAttachmentRestoreArtifacts(t, fixture.uploadPath)
}

type backupIntegrityFixture struct {
	db         *gorm.DB
	repos      *repository.Repositories
	service    *BackupService
	user       *model.User
	uploadPath string
}

func newBackupIntegrityFixture(t *testing.T) *backupIntegrityFixture {
	t.Helper()
	root := t.TempDir()
	db, err := database.Init(filepath.Join(root, "ledger.db"))
	if err != nil {
		t.Fatalf("init database: %v", err)
	}
	repos := repository.NewRepositories(db)
	user := &model.User{Username: "integrity-" + uuid.NewString(), PasswordHash: "hash"}
	if err := repos.User.Create(user); err != nil {
		t.Fatalf("create user: %v", err)
	}
	uploadPath := filepath.Join(root, "uploads")
	uploadService := NewUploadService(&config.StorageConfig{
		UploadPath:   uploadPath,
		MaxFileSize:  1,
		AllowedTypes: "txt",
	})
	backupService := NewBackupService(
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
		8<<20,
	).WithUploadService(uploadService)
	return &backupIntegrityFixture{
		db:         db,
		repos:      repos,
		service:    backupService,
		user:       user,
		uploadPath: uploadPath,
	}
}

func (f *backupIntegrityFixture) userDirectory() string {
	return strconv.FormatUint(uint64(f.user.ID), 10)
}

func backupAttachmentForContent(relativePath string, content []byte) BackupAttachment {
	hash := sha256.Sum256(content)
	return BackupAttachment{
		RelativePath:  relativePath,
		Size:          int64(len(content)),
		SHA256:        hex.EncodeToString(hash[:]),
		ContentBase64: base64.StdEncoding.EncodeToString(content),
	}
}

func writeIntegrityFixture(t *testing.T, root string, relativePath string, content []byte) {
	t.Helper()
	fullPath := filepath.Join(root, relativePath)
	if err := os.MkdirAll(filepath.Dir(fullPath), 0755); err != nil {
		t.Fatalf("create fixture directory: %v", err)
	}
	if err := os.WriteFile(fullPath, content, 0600); err != nil {
		t.Fatalf("write fixture: %v", err)
	}
}

func assertNoAttachmentRestoreArtifacts(t *testing.T, uploadPath string) {
	t.Helper()
	entries, err := os.ReadDir(uploadPath)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return
		}
		t.Fatalf("read upload root: %v", err)
	}
	for _, entry := range entries {
		if strings.HasPrefix(entry.Name(), ".restore-") {
			t.Fatalf("restore staging artifact remains: %s", entry.Name())
		}
	}
}
