package service

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"testing"

	"github.com/sky/personal-ledger/internal/config"
	"github.com/sky/personal-ledger/internal/model"
)

func TestNormalizeAttachmentEvidenceEnforcesOwnerCategoryAndReference(t *testing.T) {
	const userID uint = 7
	tests := []struct {
		name      string
		value     string
		category  string
		allowRef  func(string) bool
		want      string
		wantError bool
	}{
		{
			name:     "canonical reminder scope",
			value:    `["/uploads/7/reminders/reminder-id/proof.png"]`,
			category: "reminders",
			allowRef: exactAttachmentRef("reminder-id"),
			want:     `["7/reminders/reminder-id/proof.png"]`,
		},
		{name: "foreign owner", value: `["8/reminders/reminder-id/proof.png"]`, category: "reminders", allowRef: exactAttachmentRef("reminder-id"), wantError: true},
		{name: "wrong category", value: `["7/lendings/reminder-id/proof.png"]`, category: "reminders", allowRef: exactAttachmentRef("reminder-id"), wantError: true},
		{name: "wrong entity", value: `["7/reminders/other/proof.png"]`, category: "reminders", allowRef: exactAttachmentRef("reminder-id"), wantError: true},
		{
			name:     "lending repayment prefix",
			value:    `["7/lendings/lending-id_repay_client-token/proof.png"]`,
			category: "lendings",
			allowRef: lendingRepaymentAttachmentRef("lending-id"),
			want:     `["7/lendings/lending-id_repay_client-token/proof.png"]`,
		},
		{name: "wrong lending repayment prefix", value: `["7/lendings/other_repay_client-token/proof.png"]`, category: "lendings", allowRef: lendingRepaymentAttachmentRef("lending-id"), wantError: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := normalizeAttachmentEvidence(tt.value, userID, tt.category, tt.allowRef)
			if tt.wantError {
				if !errors.Is(err, ErrInvalidAttachmentEvidence) {
					t.Fatalf("normalize error = %v, want ErrInvalidAttachmentEvidence", err)
				}
				return
			}
			if err != nil || got != tt.want {
				t.Fatalf("normalize = %q, err=%v, want %q", got, err, tt.want)
			}
		})
	}
}

func TestReminderEvidenceCreateAndFileExistenceBoundary(t *testing.T) {
	_, repos, userID := newTransactionTestService(t)
	uploadRoot := t.TempDir()
	uploadService := NewUploadService(&config.StorageConfig{UploadPath: uploadRoot}, repos.User.DB())
	svc := NewReminderService(
		repos.Reminder,
		repos.Account,
		repos.Transaction,
		repos.Category,
		NewAccountLogService(repos.AccountLog, repos.Account),
	).WithUploadService(uploadService)

	owner := strconv.FormatUint(uint64(userID), 10)
	if _, err := svc.Create(userID, CreateReminderRequest{
		Name: "unsafe create", PaymentDay: 1,
		Evidence: `[` + fmt.Sprintf("%q", owner+"/reminders/client-id/proof.png") + `]`,
	}); !errors.Is(err, ErrCreateAttachmentEvidence) {
		t.Fatalf("create evidence error = %v, want ErrCreateAttachmentEvidence", err)
	}
	reminder, err := svc.Create(userID, CreateReminderRequest{Name: "safe create", PaymentDay: 1, Evidence: "[]"})
	if err != nil {
		t.Fatalf("create reminder with empty evidence: %v", err)
	}
	storedPath := owner + "/reminders/" + reminder.ID + "/proof.png"
	request := decodeReminderEvidencePatch(t, storedPath)
	if _, err := svc.Patch(reminder.ID, userID, request); !errors.Is(err, ErrAttachmentFileUnavailable) {
		t.Fatalf("missing reminder evidence error = %v, want ErrAttachmentFileUnavailable", err)
	}
	writeEvidenceFixture(t, uploadRoot, storedPath)
	updated, err := svc.Patch(reminder.ID, userID, request)
	if err != nil {
		t.Fatalf("patch existing reminder evidence: %v", err)
	}
	if updated.Evidence != `[`+fmt.Sprintf("%q", storedPath)+`]` {
		t.Fatalf("stored reminder evidence = %q", updated.Evidence)
	}
}

func TestLendingEvidenceAndRepaymentReferenceBoundary(t *testing.T) {
	_, repos, userID := newTransactionTestService(t)
	uploadRoot := t.TempDir()
	uploadService := NewUploadService(&config.StorageConfig{UploadPath: uploadRoot}, repos.User.DB())
	svc := newLendingTestService(repos).WithUploadService(uploadService)
	owner := strconv.FormatUint(uint64(userID), 10)

	if _, err := svc.Create(userID, CreateLendingRequest{
		Type: "lend_out", ContactName: "unsafe", Principal: 100, LendDate: "2026-08-24T10:00:00Z",
		Evidence: `[` + fmt.Sprintf("%q", owner+"/lendings/client-id/proof.png") + `]`,
	}); !errors.Is(err, ErrCreateAttachmentEvidence) {
		t.Fatalf("create lending evidence error = %v, want ErrCreateAttachmentEvidence", err)
	}
	lending, err := svc.Create(userID, CreateLendingRequest{
		Type: "lend_out", ContactName: "safe", Principal: 100, LendDate: "2026-08-24T10:00:00Z", Evidence: "[]",
	})
	if err != nil {
		t.Fatalf("create lending with empty evidence: %v", err)
	}
	lendingPath := owner + "/lendings/" + lending.ID + "/proof.png"
	patch := decodeLendingEvidencePatch(t, lendingPath)
	if _, err := svc.Patch(lending.ID, userID, patch); !errors.Is(err, ErrAttachmentFileUnavailable) {
		t.Fatalf("missing lending evidence error = %v, want ErrAttachmentFileUnavailable", err)
	}
	writeEvidenceFixture(t, uploadRoot, lendingPath)
	if _, err := svc.Patch(lending.ID, userID, patch); err != nil {
		t.Fatalf("patch existing lending evidence: %v", err)
	}

	repaymentRef := lending.ID + "_repay_client-token"
	repaymentPath := owner + "/lendings/" + repaymentRef + "/repayment.png"
	request := RecordRepaymentRequest{
		Amount: 10, RecordDate: "2026-08-24T12:00:00Z",
		Evidence: `[` + fmt.Sprintf("%q", repaymentPath) + `]`,
	}
	if _, err := svc.RecordRepayment(lending.ID, userID, request); !errors.Is(err, ErrAttachmentFileUnavailable) {
		t.Fatalf("missing repayment evidence error = %v, want ErrAttachmentFileUnavailable", err)
	}
	writeEvidenceFixture(t, uploadRoot, repaymentPath)
	if _, err := svc.RecordRepayment(lending.ID, userID, request); err != nil {
		t.Fatalf("record repayment with bound evidence: %v", err)
	}
	var record model.LendingRecord
	if err := repos.User.DB().Where("user_id = ? AND lending_id = ?", userID, lending.ID).First(&record).Error; err != nil {
		t.Fatalf("load repayment record: %v", err)
	}
	if record.Evidence != `[`+fmt.Sprintf("%q", repaymentPath)+`]` {
		t.Fatalf("stored repayment evidence = %q", record.Evidence)
	}
}

func TestTransactionAttachmentPersistenceRejectsMissingFile(t *testing.T) {
	svc, repos, userID := newTransactionTestService(t)
	uploadRoot := t.TempDir()
	svc.WithUploadService(NewUploadService(&config.StorageConfig{UploadPath: uploadRoot}, repos.User.DB()))
	accountID := createAccountForTest(t, repos, userID, 100)
	transaction, err := svc.Create(userID, CreateTransactionRequest{
		Type: "expense", Amount: 10, AccountID: accountID, TransactionDate: "2026-08-24T10:00:00Z",
	})
	if err != nil {
		t.Fatalf("create transaction: %v", err)
	}
	storedPath := strconv.FormatUint(uint64(userID), 10) + "/transactions/" + transaction.ID + "/receipt.png"
	images := `[` + fmt.Sprintf("%q", storedPath) + `]`
	if _, err := svc.UpdateAttachments(transaction.ID, userID, UpdateTransactionAttachmentsRequest{Images: &images}); !errors.Is(err, ErrAttachmentFileUnavailable) {
		t.Fatalf("missing transaction attachment error = %v, want ErrAttachmentFileUnavailable", err)
	}
	writeEvidenceFixture(t, uploadRoot, storedPath)
	updated, err := svc.UpdateAttachments(transaction.ID, userID, UpdateTransactionAttachmentsRequest{Images: &images})
	if err != nil {
		t.Fatalf("persist existing transaction attachment: %v", err)
	}
	if updated.Images != images {
		t.Fatalf("stored transaction images = %q, want %q", updated.Images, images)
	}
}

func decodeReminderEvidencePatch(t *testing.T, storedPath string) PatchReminderRequest {
	t.Helper()
	var request PatchReminderRequest
	data := `{"evidence":` + fmt.Sprintf("%q", `[`+fmt.Sprintf("%q", storedPath)+`]`) + `}`
	if err := json.Unmarshal([]byte(data), &request); err != nil {
		t.Fatalf("decode reminder patch: %v", err)
	}
	return request
}

func decodeLendingEvidencePatch(t *testing.T, storedPath string) PatchLendingRequest {
	t.Helper()
	var request PatchLendingRequest
	data := `{"evidence":` + fmt.Sprintf("%q", `[`+fmt.Sprintf("%q", storedPath)+`]`) + `}`
	if err := json.Unmarshal([]byte(data), &request); err != nil {
		t.Fatalf("decode lending patch: %v", err)
	}
	return request
}

func writeEvidenceFixture(t *testing.T, uploadRoot, storedPath string) {
	t.Helper()
	fullPath := filepath.Join(uploadRoot, filepath.FromSlash(storedPath))
	if err := os.MkdirAll(filepath.Dir(fullPath), 0700); err != nil {
		t.Fatalf("create evidence directory: %v", err)
	}
	if err := os.WriteFile(fullPath, []byte("evidence"), 0600); err != nil {
		t.Fatalf("write evidence file: %v", err)
	}
}
