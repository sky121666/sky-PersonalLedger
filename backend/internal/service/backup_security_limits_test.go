package service

import (
	"encoding/json"
	"errors"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
)

func TestRestoreRejectsDenseCollectionBeforeMutation(t *testing.T) {
	fixture := newBackupIntegrityFixture(t)
	original := &model.Account{ID: uuid.NewString(), UserID: fixture.user.ID, Name: "Current Cash", Type: "cash"}
	if err := fixture.db.Create(original).Error; err != nil {
		t.Fatalf("seed current account: %v", err)
	}

	var payload strings.Builder
	payload.WriteString(`{"version":"2.1","accounts":[`)
	appendDenseBackupObjects(&payload, backupCollectionRecordLimits["accounts"]+1)
	payload.WriteString(`]}`)

	err := fixture.service.RestoreBackup(fixture.user.ID, writeRawBackupFile(t, []byte(payload.String())))
	if !errors.Is(err, ErrBackupRecordLimitExceeded) || !errors.Is(err, ErrInvalidBackupFormat) {
		t.Fatalf("restore error = %v, want identifiable record-limit and invalid-format errors", err)
	}
	var current model.Account
	if err := fixture.db.First(&current, "id = ? AND user_id = ?", original.ID, fixture.user.ID).Error; err != nil {
		t.Fatalf("current data changed after dense backup rejection: %v", err)
	}
}

func TestBackupJSONPreflightRejectsTotalRecordAmplification(t *testing.T) {
	var payload strings.Builder
	payload.WriteString(`{"version":"2.1","transactions":[`)
	appendDenseBackupObjects(&payload, maxBackupTotalRecordCount)
	payload.WriteString(`],"accounts":[{}]}`)

	_, err := preflightBackupJSON([]byte(payload.String()))
	if !errors.Is(err, ErrBackupRecordLimitExceeded) || !errors.Is(err, ErrInvalidBackupFormat) {
		t.Fatalf("preflight error = %v, want identifiable total record-limit error", err)
	}
}

func TestCreateBackupRejectsDatabaseStateBeyondRestoreRecordLimit(t *testing.T) {
	fixture := newBackupIntegrityFixture(t)
	accounts := make([]model.Account, backupCollectionRecordLimits["accounts"]+1)
	for index := range accounts {
		accounts[index] = model.Account{
			ID:     uuid.NewString(),
			UserID: fixture.user.ID,
			Name:   "Dense account",
			Type:   "cash",
		}
	}
	if err := fixture.db.CreateInBatches(&accounts, 500).Error; err != nil {
		t.Fatalf("seed dense accounts: %v", err)
	}

	_, err := fixture.service.CreateBackup(fixture.user.ID)
	if !errors.Is(err, ErrBackupRecordLimitExceeded) || !errors.Is(err, ErrInvalidBackupFormat) {
		t.Fatalf("create backup error = %v, want identifiable record-limit error", err)
	}
}

func TestBackupJSONPreflightRejectsCaseInsensitiveFieldAliases(t *testing.T) {
	tests := []string{
		`{"version":"2.1","Accounts":[{}]}`,
		`{"version":"2.1","accountſ":[{}]}`,
		`{"version":"2.1","LendingRecords":[{}]}`,
		`{"version":"2.1","accounts":[{}],"Attachments":[]}`,
	}
	for _, payload := range tests {
		if _, err := preflightBackupJSON([]byte(payload)); !errors.Is(err, ErrInvalidBackupFormat) {
			t.Fatalf("preflight error = %v, want ErrInvalidBackupFormat for %s", err, payload)
		}
	}
}

func TestRestoreEnforcesBackupVersionAttachmentSemanticsWithoutMutation(t *testing.T) {
	fixture := newBackupIntegrityFixture(t)
	original := &model.Account{ID: uuid.NewString(), UserID: fixture.user.ID, Name: "Current Cash", Type: "cash"}
	if err := fixture.db.Create(original).Error; err != nil {
		t.Fatalf("seed current account: %v", err)
	}

	tests := []struct {
		name    string
		payload string
	}{
		{name: "2.2 missing attachments", payload: `{"version":"2.2","accounts":[{}]}`},
		{name: "2.2 null attachments", payload: `{"version":"2.2","accounts":[{}],"attachments":null}`},
		{name: "2.3 missing attachments", payload: `{"version":"2.3","accounts":[{}]}`},
		{name: "2.3 notification credential", payload: `{"version":"2.3","accounts":[{}],"notification_settings":{"dingtalk_webhook":"https://example.test/?access_token=secret"},"attachments":null}`},
		{name: "2.1 attachment array", payload: `{"version":"2.1","accounts":[{}],"attachments":[]}`},
		{name: "unknown version", payload: `{"version":"9.9","accounts":[{}],"attachments":[]}`},
		{name: "missing version", payload: `{"accounts":[{}]}`},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := fixture.service.RestoreBackup(fixture.user.ID, writeRawBackupFile(t, []byte(tt.payload)))
			if !errors.Is(err, ErrInvalidBackupFormat) {
				t.Fatalf("restore error = %v, want ErrInvalidBackupFormat", err)
			}
			var current model.Account
			if err := fixture.db.First(&current, "id = ? AND user_id = ?", original.ID, fixture.user.ID).Error; err != nil {
				t.Fatalf("current data changed after rejected version semantics: %v", err)
			}
		})
	}
}

func TestCreateBackupWithoutUploadServiceUsesVersion23NullAttachmentSemantics(t *testing.T) {
	fixture := newBackupIntegrityFixture(t)
	withoutUploads := NewBackupService(
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
	)

	backup, err := withoutUploads.CreateBackup(fixture.user.ID)
	if err != nil {
		t.Fatalf("create backup without upload service: %v", err)
	}
	if backup.Version != "2.3" || backup.Attachments != nil {
		t.Fatalf("backup version/attachments = %q/%#v, want 2.3 with null attachment semantics", backup.Version, backup.Attachments)
	}
	data, err := json.Marshal(backup)
	if err != nil {
		t.Fatalf("marshal backup: %v", err)
	}
	if _, err := preflightBackupJSON(data); err != nil {
		t.Fatalf("created 2.3 backup does not pass restore preflight: %v", err)
	}
}

func TestBackupVersion23AcceptsExplicitAttachmentSemantics(t *testing.T) {
	for _, payload := range []string{
		`{"version":"2.3","accounts":[{}],"attachments":null}`,
		`{"version":"2.3","accounts":[{}],"attachments":[]}`,
	} {
		if _, err := preflightBackupJSON([]byte(payload)); err != nil {
			t.Fatalf("valid 2.3 attachment semantics rejected for %s: %v", payload, err)
		}
	}
}

func TestNormalizeBackupInfersOwnerFromAllInternalUploadReferences(t *testing.T) {
	backup := &FullBackupData{
		UserProfile:  &UserProfileBackup{Avatar: "/uploads/77/avatars/profile/avatar.png"},
		Transactions: []model.Transaction{{ID: "tx", Images: `["77/transactions/tx/receipt.png"]`}},
		Reminders:    []model.Reminder{{ID: "reminder", Evidence: `77/reminders/reminder/evidence.png`}},
		Lendings: []*model.Lending{{
			ID: "lending", Evidence: `["77/lendings/lending/evidence.png"]`,
		}},
		LendingRecords: []*model.LendingRecord{{
			LendingID: "lending", Evidence: `77/lendings/lending_repay_record/evidence.png`,
		}},
		FamilyMembers: []model.FamilyMember{{Avatar: "/uploads/77/family/member/avatar.png"}},
	}

	if err := normalizeBackupForRestore(backup, 9); err != nil {
		t.Fatalf("normalize backup: %v", err)
	}
	if backup.SourceUserID != 77 {
		t.Fatalf("inferred source user = %d, want 77", backup.SourceUserID)
	}
	wants := map[string]string{
		"profile":        "/uploads/9/avatars/profile/avatar.png",
		"transaction":    `["9/transactions/tx/receipt.png"]`,
		"reminder":       `["9/reminders/reminder/evidence.png"]`,
		"lending":        `["9/lendings/lending/evidence.png"]`,
		"lending record": `["9/lendings/lending_repay_record/evidence.png"]`,
		"family member":  "/uploads/9/family/member/avatar.png",
	}
	got := map[string]string{
		"profile":        backup.UserProfile.Avatar,
		"transaction":    backup.Transactions[0].Images,
		"reminder":       backup.Reminders[0].Evidence,
		"lending":        backup.Lendings[0].Evidence,
		"lending record": backup.LendingRecords[0].Evidence,
		"family member":  backup.FamilyMembers[0].Avatar,
	}
	for field, want := range wants {
		if got[field] != want {
			t.Errorf("%s reference = %q, want %q", field, got[field], want)
		}
	}
}

func TestRestoreRejectsMixedInferredUploadOwnersWithoutMutation(t *testing.T) {
	fixture := newBackupIntegrityFixture(t)
	original := &model.Account{ID: uuid.NewString(), UserID: fixture.user.ID, Name: "Current Cash", Type: "cash"}
	if err := fixture.db.Create(original).Error; err != nil {
		t.Fatalf("seed current account: %v", err)
	}
	backup := &FullBackupData{
		Version:     "2.2",
		UserProfile: &UserProfileBackup{Avatar: "/uploads/77/avatars/profile/avatar.png"},
		Accounts: []model.Account{{
			ID:   uuid.NewString(),
			Name: "Replacement",
			Type: "cash",
		}},
		FamilyMembers: []model.FamilyMember{{
			ID:     uuid.NewString(),
			Name:   "Mixed Owner",
			Avatar: "/uploads/88/family/member/avatar.png",
		}},
		Attachments: []BackupAttachment{},
	}

	err := fixture.service.RestoreBackup(fixture.user.ID, writeBackupFile(t, backup))
	if !errors.Is(err, ErrInvalidBackupFormat) {
		t.Fatalf("restore error = %v, want ErrInvalidBackupFormat", err)
	}
	var current model.Account
	if err := fixture.db.First(&current, "id = ? AND user_id = ?", original.ID, fixture.user.ID).Error; err != nil {
		t.Fatalf("current data changed after mixed-owner rejection: %v", err)
	}
}

func TestNormalizeBackupRejectsUnsafeSuffixInEveryInternalReferenceField(t *testing.T) {
	tests := []struct {
		name   string
		backup *FullBackupData
	}{
		{name: "profile avatar", backup: &FullBackupData{UserProfile: &UserProfileBackup{Avatar: "/uploads/77/../secret.png"}}},
		{name: "transaction images", backup: &FullBackupData{Transactions: []model.Transaction{{Images: `["77/transactions//secret.png"]`}}}},
		{name: "heterogeneous transaction images", backup: &FullBackupData{Transactions: []model.Transaction{{Images: `["77/transactions/one.png",0,"88/transactions/two.png"]`}}}},
		{name: "JSON scalar transaction images", backup: &FullBackupData{Transactions: []model.Transaction{{Images: `"77/transactions/one.png"`}}}},
		{name: "reminder evidence", backup: &FullBackupData{Reminders: []model.Reminder{{Evidence: `77/reminders/./secret.png`}}}},
		{name: "lending evidence", backup: &FullBackupData{Lendings: []*model.Lending{{Evidence: `77\lendings\secret.png`}}}},
		{name: "lending record evidence", backup: &FullBackupData{LendingRecords: []*model.LendingRecord{{Evidence: `77/C:/secret.png`}}}},
		{name: "family avatar", backup: &FullBackupData{FamilyMembers: []model.FamilyMember{{Avatar: "/uploads/77/family/../secret.png"}}}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := normalizeBackupForRestore(tt.backup, 9)
			if !errors.Is(err, ErrInvalidBackupFormat) {
				t.Fatalf("normalize error = %v, want ErrInvalidBackupFormat", err)
			}
		})
	}
}

func appendDenseBackupObjects(builder *strings.Builder, count int) {
	for index := 0; index < count; index++ {
		if index > 0 {
			builder.WriteByte(',')
		}
		builder.WriteString(`{}`)
	}
}
