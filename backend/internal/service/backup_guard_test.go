package service

import (
	"errors"
	"testing"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
)

func TestRestoreRejectsReferenceToAnotherUsersExistingRow(t *testing.T) {
	fixture := newBackupIntegrityFixture(t)
	original := &model.Account{
		ID:     uuid.NewString(),
		UserID: fixture.user.ID,
		Name:   "Current Cash",
		Type:   "cash",
	}
	if err := fixture.db.Create(original).Error; err != nil {
		t.Fatalf("seed target account: %v", err)
	}
	otherUser := &model.User{Username: "backup-reference-other-" + uuid.NewString(), PasswordHash: "hash"}
	if err := fixture.db.Create(otherUser).Error; err != nil {
		t.Fatalf("seed other user: %v", err)
	}
	otherAccount := &model.Account{
		ID:     uuid.NewString(),
		UserID: otherUser.ID,
		Name:   "Other User Account",
		Type:   "cash",
	}
	if err := fixture.db.Create(otherAccount).Error; err != nil {
		t.Fatalf("seed other account: %v", err)
	}

	const sourceUserID uint = 77
	backup := &FullBackupData{
		Version:      "2.2",
		SourceUserID: sourceUserID,
		Accounts: []model.Account{{
			ID:     uuid.NewString(),
			UserID: sourceUserID,
			Name:   "Imported Cash",
			Type:   "cash",
		}},
		Transactions: []model.Transaction{{
			ID:        uuid.NewString(),
			UserID:    sourceUserID,
			AccountID: otherAccount.ID,
			Type:      "expense",
			Amount:    1,
		}},
		Attachments: []BackupAttachment{},
	}

	err := fixture.service.RestoreBackup(fixture.user.ID, writeBackupFile(t, backup))
	if !errors.Is(err, ErrInvalidBackupFormat) {
		t.Fatalf("restore error = %v, want ErrInvalidBackupFormat", err)
	}
	var restored model.Account
	if err := fixture.db.First(&restored, "id = ? AND user_id = ?", original.ID, fixture.user.ID).Error; err != nil {
		t.Fatalf("target data changed after rejected restore: %v", err)
	}
}

func TestRestoreRejectsDanglingReferenceBeforeReplacingCurrentData(t *testing.T) {
	fixture := newBackupIntegrityFixture(t)
	original := &model.Account{
		ID: uuid.NewString(), UserID: fixture.user.ID, Name: "Current Cash", Type: "cash",
	}
	if err := fixture.db.Create(original).Error; err != nil {
		t.Fatalf("seed target account: %v", err)
	}
	const sourceUserID uint = 77
	backup := &FullBackupData{
		Version:      "2.2",
		SourceUserID: sourceUserID,
		Transactions: []model.Transaction{{
			ID: uuid.NewString(), UserID: sourceUserID, AccountID: "missing-account",
			Type: "expense", Amount: 1,
		}},
		Attachments: []BackupAttachment{},
	}
	if err := fixture.service.RestoreBackup(fixture.user.ID, writeBackupFile(t, backup)); !errors.Is(err, ErrInvalidBackupFormat) {
		t.Fatalf("restore error = %v, want ErrInvalidBackupFormat", err)
	}
	var count int64
	if err := fixture.db.Model(&model.Account{}).
		Where("id = ? AND user_id = ?", original.ID, fixture.user.ID).Count(&count).Error; err != nil {
		t.Fatalf("count current account: %v", err)
	}
	if count != 1 {
		t.Fatalf("current data changed after rejected restore")
	}
}

func TestRestoreOmitsNestedLendingAssociations(t *testing.T) {
	fixture := newBackupIntegrityFixture(t)
	const sourceUserID uint = 77
	accountID := uuid.NewString()
	nestedAccountID := uuid.NewString()
	lendingID := uuid.NewString()
	backup := &FullBackupData{
		Version:      "2.2",
		SourceUserID: sourceUserID,
		Accounts: []model.Account{{
			ID:     accountID,
			UserID: sourceUserID,
			Name:   "Imported Cash",
			Type:   "cash",
		}},
		Lendings: []*model.Lending{{
			ID:             lendingID,
			UserID:         sourceUserID,
			Type:           "lend_out",
			ContactName:    "Contact",
			Principal:      10,
			CurrentBalance: 10,
			AccountID:      &accountID,
			Account: &model.Account{
				ID:     nestedAccountID,
				UserID: 999,
				Name:   "Injected Association",
				Type:   "cash",
			},
		}},
		Attachments: []BackupAttachment{},
	}

	if err := fixture.service.RestoreBackup(fixture.user.ID, writeBackupFile(t, backup)); err != nil {
		t.Fatalf("restore backup: %v", err)
	}
	var nestedCount int64
	if err := fixture.db.Unscoped().Model(&model.Account{}).Where("id = ?", nestedAccountID).Count(&nestedCount).Error; err != nil {
		t.Fatalf("count nested association: %v", err)
	}
	if nestedCount != 0 {
		t.Fatalf("nested association created %d account rows, want 0", nestedCount)
	}
	var lending model.Lending
	if err := fixture.db.First(&lending, "id = ? AND user_id = ?", lendingID, fixture.user.ID).Error; err != nil {
		t.Fatalf("restored lending missing: %v", err)
	}
}
