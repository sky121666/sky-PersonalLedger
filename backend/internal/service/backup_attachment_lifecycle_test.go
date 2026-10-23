package service

import (
	"bytes"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/sky/personal-ledger/internal/config"
	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

const attachmentLifecycleReceipt = "synthetic attachment lifecycle receipt\n"

type attachmentLifecycleScenario struct {
	deleted bool
	aged    bool
	runGC   bool
}

type attachmentLifecycleSource struct {
	fixture     *backupIntegrityFixture
	transaction model.Transaction
	uploadPath  string
	backup      *FullBackupData
}

type attachmentLifecycleTarget struct {
	fixture     *backupIntegrityFixture
	account     model.Account
	user        model.User
	filePath    string
	deleteCalls int
}

func attachmentLifecycleFixture(t *testing.T) *backupIntegrityFixture {
	t.Helper()
	f := newBackupIntegrityFixture(t)
	relative, err := filepath.Rel(os.TempDir(), f.uploadPath)
	if err != nil || strings.HasPrefix(relative, "..") || filepath.IsAbs(relative) {
		t.Fatalf("fixture escaped isolated TMPDIR: %s, %v", f.uploadPath, err)
	}
	sqlDB, err := f.db.DB()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := sqlDB.Close(); err != nil {
			t.Errorf("close isolated database: %v", err)
		}
	})
	return f
}

func attachmentLifecycleCreateSource(t *testing.T, scenario attachmentLifecycleScenario) *attachmentLifecycleSource {
	t.Helper()
	f := attachmentLifecycleFixture(t)
	uploads := NewUploadService(&config.StorageConfig{
		UploadPath: f.uploadPath, MaxFileSize: 1, AllowedTypes: "txt",
	}, f.db)
	f.service.WithUploadService(uploads)
	transactions := NewTransactionService(
		f.repos.Transaction, f.repos.Account, f.repos.Reminder, f.repos.Lending,
		f.repos.FamilyMember, NewAccountLogService(f.repos.AccountLog, f.repos.Account),
	).WithUploadService(uploads)
	accountID := createAccountForTest(t, f.repos, f.user.ID, 100)
	transaction, err := transactions.Create(f.user.ID, CreateTransactionRequest{
		Type: "expense", Amount: 25, AccountID: accountID, TransactionDate: "2026-10-18",
	})
	if err != nil {
		t.Fatalf("create transaction: %v", err)
	}
	upload, err := uploads.Upload(f.user.ID, "transactions", transaction.ID,
		newUploadFileHeader(t, "receipt.txt", attachmentLifecycleReceipt))
	if err != nil {
		t.Fatalf("upload receipt: %v", err)
	}
	encoded, err := json.Marshal([]string{upload.Path})
	if err != nil {
		t.Fatal(err)
	}
	images := string(encoded)
	if _, err := transactions.UpdateAttachments(transaction.ID, f.user.ID,
		UpdateTransactionAttachmentsRequest{Images: &images}); err != nil {
		t.Fatalf("attach receipt through public service: %v", err)
	}
	if referenced, err := uploads.IsReferenced(f.user.ID, upload.Path); err != nil || !referenced {
		t.Fatalf("live transaction must reference uploaded receipt: referenced=%t err=%v", referenced, err)
	}
	if scenario.deleted {
		if err := transactions.Delete(transaction.ID, f.user.ID); err != nil {
			t.Fatalf("soft-delete through public service: %v", err)
		}
	}
	fullPath := uploads.GetFilePath(upload.Path)
	if scenario.aged {
		old := time.Now().Add(-48 * time.Hour)
		if err := os.Chtimes(fullPath, old, old); err != nil {
			t.Fatalf("age synthetic attachment only: %v", err)
		}
	}
	info, err := os.Stat(fullPath)
	if err != nil {
		t.Fatal(err)
	}
	referenced, err := uploads.IsReferenced(f.user.ID, upload.Path)
	if err != nil {
		t.Fatal(err)
	}
	removed := 0
	if scenario.runGC {
		removed, err = NewUploadGarbageCollector(uploads, f.repos.User).RunOnce(time.Now())
		if err != nil {
			t.Fatalf("GC RunOnce: %v", err)
		}
	}
	var stored model.Transaction
	if err := f.db.Unscoped().First(&stored, "id = ?", transaction.ID).Error; err != nil {
		t.Fatalf("read stored transaction after lifecycle: %v", err)
	}
	if stored.DeletedAt.Valid != scenario.deleted || stored.Images != images {
		t.Fatalf("lifecycle changed transaction metadata: deleted=%t images=%q",
			stored.DeletedAt.Valid, stored.Images)
	}
	backup, err := f.service.CreateBackup(f.user.ID)
	if err != nil {
		t.Fatalf("back up public CRUD/GC state: %v", err)
	}
	if len(backup.Transactions) != 1 || backup.Transactions[0].ID != stored.ID ||
		backup.Transactions[0].Images != stored.Images ||
		backup.Transactions[0].DeletedAt.Valid != stored.DeletedAt.Valid {
		t.Fatalf("backup silently lost transaction/tombstone/attachment reference: %#v", backup.Transactions)
	}
	_, statErr := os.Stat(fullPath)
	if statErr != nil && !errors.Is(statErr, os.ErrNotExist) {
		t.Fatal(statErr)
	}
	t.Logf("SOURCE root=%s deleted=%t deleted_at=%s attachment_mtime=%s referenced_by_gc=%t gc_run=%t removed=%d file_exists=%t",
		filepath.Dir(f.uploadPath), stored.DeletedAt.Valid, stored.DeletedAt.Time.Format(time.RFC3339Nano),
		info.ModTime().Format(time.RFC3339Nano), referenced, scenario.runGC, removed, statErr == nil)
	t.Logf("BACKUP create_error=nil version=%s transactions=%d images=%s attachments_nil=%t attachments=%d",
		backup.Version, len(backup.Transactions), stored.Images, backup.Attachments == nil, len(backup.Attachments))
	return &attachmentLifecycleSource{fixture: f, transaction: stored, uploadPath: upload.Path, backup: backup}
}

func attachmentLifecycleCreateTarget(t *testing.T) *attachmentLifecycleTarget {
	t.Helper()
	f := attachmentLifecycleFixture(t)
	accountID := createAccountForTest(t, f.repos, f.user.ID, 777)
	target := &attachmentLifecycleTarget{fixture: f}
	if err := f.db.First(&target.account, "id = ?", accountID).Error; err != nil {
		t.Fatal(err)
	}
	if err := f.db.First(&target.user, "id = ?", f.user.ID).Error; err != nil {
		t.Fatal(err)
	}
	relative := filepath.Join(f.userDirectory(), "transactions", "sentinel", "keep.txt")
	writeIntegrityFixture(t, f.uploadPath, relative, []byte("synthetic target sentinel"))
	target.filePath = filepath.Join(f.uploadPath, relative)
	if err := f.db.Callback().Delete().Before("gorm:delete").Register("audit:r5:observe_delete",
		func(_ *gorm.DB) { target.deleteCalls++ }); err != nil {
		t.Fatal(err)
	}
	t.Logf("TARGET root=%s sentinel_id=%s sentinel_balance=%v",
		filepath.Dir(f.uploadPath), target.account.ID, target.account.CurrentBalance)
	return target
}

func attachmentLifecycleAssertTargetUnchanged(t *testing.T, target *attachmentLifecycleTarget) {
	t.Helper()
	var account model.Account
	if err := target.fixture.db.Unscoped().First(&account, "id = ?", target.account.ID).Error; err != nil {
		t.Fatalf("restore failure removed target sentinel: %v", err)
	}
	if !reflect.DeepEqual(account, target.account) {
		t.Errorf("restore failure mutated sentinel account: before=%#v after=%#v", target.account, account)
	}
	var user model.User
	if err := target.fixture.db.First(&user, "id = ?", target.user.ID).Error; err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(user, target.user) {
		t.Error("restore failure mutated target profile")
	}
	for _, check := range []struct {
		model any
		want  int64
	}{{&model.Account{}, 1}, {&model.Transaction{}, 0}, {&model.AccountLog{}, 0}} {
		var count int64
		if err := target.fixture.db.Unscoped().Model(check.model).
			Where("user_id = ?", target.user.ID).Count(&count).Error; err != nil {
			t.Fatal(err)
		}
		if count != check.want {
			t.Errorf("target %T count=%d, want %d", check.model, count, check.want)
		}
	}
	content, err := os.ReadFile(target.filePath)
	if err != nil || string(content) != "synthetic target sentinel" {
		t.Errorf("restore failure changed target attachment: %q, %v", content, err)
	}
	if target.deleteCalls != 0 {
		t.Errorf("invalid backup reached database deletion callbacks: %d", target.deleteCalls)
	}
	assertNoAttachmentRestoreArtifacts(t, target.fixture.uploadPath)
	t.Logf("TARGET_CHECK sentinel_present=true sentinel_balance=%v account_equal=%t profile_equal=%t delete_callbacks=%d attachment_unchanged=%t",
		account.CurrentBalance, reflect.DeepEqual(account, target.account), reflect.DeepEqual(user, target.user),
		target.deleteCalls, string(content) == "synthetic target sentinel")
}

func attachmentLifecycleAssertRoundTrip(t *testing.T, source *attachmentLifecycleSource, target *attachmentLifecycleTarget) {
	t.Helper()
	var restored model.Transaction
	if err := target.fixture.db.Unscoped().First(&restored, "id = ?", source.transaction.ID).Error; err != nil {
		t.Fatalf("read restored transaction: %v", err)
	}
	if restored.Images != source.transaction.Images || restored.DeletedAt.Valid != source.transaction.DeletedAt.Valid ||
		!restored.DeletedAt.Time.Equal(source.transaction.DeletedAt.Time) {
		t.Fatalf("restored attachment reference/tombstone differs: %#v", restored)
	}
	content, err := os.ReadFile(filepath.Join(target.fixture.uploadPath, source.uploadPath))
	if err != nil || !bytes.Equal(content, []byte(attachmentLifecycleReceipt)) {
		t.Fatalf("restored receipt missing/corrupt: %q, %v", content, err)
	}
	var sentinelCount int64
	if err := target.fixture.db.Unscoped().Model(&model.Account{}).
		Where("id = ?", target.account.ID).Count(&sentinelCount).Error; err != nil {
		t.Fatal(err)
	}
	if sentinelCount != 0 || target.deleteCalls == 0 {
		t.Fatal("successful restore did not replace target fixture as expected")
	}
	t.Logf("ROUNDTRIP images_preserved=true tombstone_preserved=true receipt_bytes_equal=true delete_callbacks=%d",
		target.deleteCalls)
}

func TestBackupAttachmentLifecycleControls(t *testing.T) {
	for _, test := range []struct {
		name string
		attachmentLifecycleScenario
	}{
		{"active_attachment", attachmentLifecycleScenario{}},
		{"soft_deleted_without_gc", attachmentLifecycleScenario{deleted: true, aged: true}},
		{"active_old_attachment_after_gc", attachmentLifecycleScenario{aged: true, runGC: true}},
		{"soft_deleted_fresh_attachment_after_gc", attachmentLifecycleScenario{deleted: true, runGC: true}},
	} {
		t.Run(test.name, func(t *testing.T) {
			source := attachmentLifecycleCreateSource(t, test.attachmentLifecycleScenario)
			target := attachmentLifecycleCreateTarget(t)
			if err := target.fixture.service.RestoreBackup(target.user.ID, writeBackupFile(t, source.backup)); err != nil {
				t.Fatalf("control backup must restore: %v", err)
			}
			attachmentLifecycleAssertRoundTrip(t, source, target)
		})
	}
}

func TestSoftDeletedAttachmentSurvivesGCAndBackupRestore(t *testing.T) {
	source := attachmentLifecycleCreateSource(t, attachmentLifecycleScenario{deleted: true, aged: true, runGC: true})
	target := attachmentLifecycleCreateTarget(t)
	err := target.fixture.service.RestoreBackup(target.user.ID, writeBackupFile(t, source.backup))
	if err != nil {
		t.Errorf("INVARIANT: a successful backup of public CRUD/GC state must restore; got %v", err)
		attachmentLifecycleAssertTargetUnchanged(t, target)
		return
	}
	attachmentLifecycleAssertRoundTrip(t, source, target)
}

func TestBackupRejectsMissingHistoricalAttachmentBeforeExport(t *testing.T) {
	source := attachmentLifecycleCreateSource(t, attachmentLifecycleScenario{deleted: true})
	// Model a file already lost before this repair, only in temporary storage.
	if err := os.Remove(filepath.Join(source.fixture.uploadPath, source.uploadPath)); err != nil {
		t.Fatal(err)
	}
	backup, err := source.fixture.service.CreateBackup(source.fixture.user.ID)
	if err == nil || backup != nil {
		t.Fatalf("missing historical file produced a successful backup: backup=%v err=%v", backup != nil, err)
	}
	var stored model.Transaction
	if err := source.fixture.db.Unscoped().First(&stored, "id = ?", source.transaction.ID).Error; err != nil {
		t.Fatal(err)
	}
	if stored.Images != source.transaction.Images || !stored.DeletedAt.Valid {
		t.Fatal("export failure changed historical attachment metadata")
	}
}

func TestSoftDeletedAttachmentCannotBeRemovedDirectly(t *testing.T) {
	source := attachmentLifecycleCreateSource(t, attachmentLifecycleScenario{deleted: true})
	err := source.fixture.service.uploadService.Delete(source.fixture.user.ID, source.uploadPath)
	if !errors.Is(err, ErrUploadReferenced) {
		t.Fatalf("historical attachment deletion = %v, want reference protection", err)
	}
	if _, err := os.Stat(filepath.Join(source.fixture.uploadPath, source.uploadPath)); err != nil {
		t.Fatalf("historical attachment lost: %v", err)
	}
}

func TestRestoreRejectsPreviouslyIncompleteHistoricalBackupWithoutMutation(t *testing.T) {
	source := attachmentLifecycleCreateSource(t, attachmentLifecycleScenario{deleted: true, aged: true})
	// Older exports could declare an empty manifest while retaining this reference.
	source.backup.Attachments = []BackupAttachment{}
	target := attachmentLifecycleCreateTarget(t)
	if err := target.fixture.service.RestoreBackup(target.user.ID, writeBackupFile(t, source.backup)); !errors.Is(err, ErrInvalidBackupFormat) {
		t.Fatalf("incomplete historical backup restore = %v, want invalid backup", err)
	}
	attachmentLifecycleAssertTargetUnchanged(t, target)
}
