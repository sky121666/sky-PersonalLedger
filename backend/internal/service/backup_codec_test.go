package service

import (
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

func TestBackupRoundTripPreservesDeletedTransactions(t *testing.T) {
	f := newBackupIntegrityFixture(t)
	account := model.Account{ID: uuid.NewString(), UserID: f.user.ID, Name: "Cash", Type: "cash", InitialBalance: 100, CurrentBalance: 100}
	if err := f.db.Create(&account).Error; err != nil {
		t.Fatal(err)
	}
	svc := NewTransactionService(f.repos.Transaction, f.repos.Account, f.repos.Reminder, f.repos.Lending, f.repos.FamilyMember, NewAccountLogService(f.repos.AccountLog, f.repos.Account))
	tx, err := svc.Create(f.user.ID, CreateTransactionRequest{Type: "expense", Amount: 25, AccountID: account.ID, TransactionDate: "2026-10-06", Remark: "deleted expense"})
	if err != nil {
		t.Fatal(err)
	}
	if err := svc.Delete(tx.ID, f.user.ID); err != nil {
		t.Fatal(err)
	}
	assertDeletedExpenseLedger(t, f, account.ID)
	var deleted model.Transaction
	if err := f.db.Unscoped().First(&deleted, "id = ?", tx.ID).Error; err != nil {
		t.Fatal(err)
	}
	backup, err := f.service.CreateBackup(f.user.ID)
	if err != nil {
		t.Fatal(err)
	}
	if err := f.service.RestoreBackup(f.user.ID, writeBackupFile(t, backup)); err != nil {
		t.Fatal(err)
	}
	assertDeletedExpenseLedger(t, f, account.ID)
	var restored model.Transaction
	if err := f.db.Unscoped().First(&restored, "id = ?", tx.ID).Error; err != nil {
		t.Fatal(err)
	}
	if !restored.DeletedAt.Valid || !restored.DeletedAt.Time.Equal(deleted.DeletedAt.Time) {
		t.Fatalf("transaction tombstone = %#v, want %#v", restored.DeletedAt, deleted.DeletedAt)
	}
	var logs []model.AccountLog
	if err := f.db.Where("transaction_id = ?", tx.ID).Find(&logs).Error; err != nil {
		t.Fatal(err)
	}
	if len(logs) != 2 {
		t.Fatalf("transaction history logs = %d, want original expense and rollback", len(logs))
	}
}

func assertDeletedExpenseLedger(t *testing.T, f *backupIntegrityFixture, accountID string) {
	t.Helper()
	var count int64
	if err := f.db.Model(&model.Transaction{}).Where("user_id = ?", f.user.ID).Count(&count).Error; err != nil {
		t.Fatal(err)
	}
	var account model.Account
	if err := f.db.First(&account, "id = ?", accountID).Error; err != nil {
		t.Fatal(err)
	}
	sum, err := f.repos.Transaction.SumByDateRange(f.user.ID, time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC), time.Date(2026, 11, 1, 0, 0, 0, 0, time.UTC))
	if err != nil {
		t.Fatal(err)
	}
	if count != 0 || account.CurrentBalance != 100 || sum.Expense != 0 {
		t.Fatalf("ledger active tx/balance/expense = %d/%v/%v, want 0/100/0", count, account.CurrentBalance, sum.Expense)
	}
}

func TestRestoreBackupRejectsPartialEnvelopeWithoutMutation(t *testing.T) {
	for _, version := range []string{"2.1", "2.2", "2.3", "2.4"} {
		t.Run(version, func(t *testing.T) {
			f := newBackupIntegrityFixture(t)
			account := model.Account{ID: uuid.NewString(), UserID: f.user.ID, Name: "Current Cash", Type: "cash", CurrentBalance: 100}
			if err := f.db.Create(&account).Error; err != nil {
				t.Fatal(err)
			}
			fields := map[string]any{"version": version, "user_profile": map[string]string{"nickname": "partial"}}
			if version != "2.1" {
				fields["attachments"] = []any{}
			}
			payload, err := json.Marshal(fields)
			if err != nil {
				t.Fatal(err)
			}
			err = f.service.RestoreBackup(f.user.ID, writeRawBackupFile(t, payload))
			if !errors.Is(err, ErrInvalidBackupFormat) {
				t.Errorf("partial envelope error = %v, want ErrInvalidBackupFormat", err)
			}
			var current model.Account
			if err := f.db.First(&current, "id = ?", account.ID).Error; err != nil {
				t.Fatalf("partial envelope removed current account: %v", err)
			}
			if current.CurrentBalance != 100 {
				t.Fatalf("current balance = %v, want 100", current.CurrentBalance)
			}
			var user model.User
			if err := f.db.First(&user, f.user.ID).Error; err != nil {
				t.Fatal(err)
			}
			if user.Nickname == "partial" {
				t.Fatal("partial envelope mutated user profile")
			}
		})
	}
}

func TestBackupRoundTripPreservesEveryLedgerTombstoneAndReferences(t *testing.T) {
	f := newBackupIntegrityFixture(t)
	deleted := gorm.DeletedAt{Time: time.Date(2026, 10, 5, 11, 12, 13, 123456000, time.UTC), Valid: true}
	accountID, categoryID, memberID, reminderID, lendingID, txID := uuid.NewString(), uuid.NewString(), uuid.NewString(), uuid.NewString(), uuid.NewString(), uuid.NewString()
	rows := []any{
		&model.Account{ID: accountID, UserID: f.user.ID, Name: "Archived Cash", Type: "cash", IsArchived: true, DeletedAt: deleted},
		&model.Category{ID: categoryID, UserID: f.user.ID, Name: "Food", Type: "expense", DeletedAt: deleted},
		&model.FamilyMember{ID: memberID, UserID: f.user.ID, Name: "Historical Member", DeletedAt: deleted},
		&model.Reminder{ID: reminderID, UserID: f.user.ID, AccountID: &accountID, PaymentDay: 1, PaidOffAt: &deleted.Time, DeletedAt: deleted},
		&model.Lending{ID: lendingID, UserID: f.user.ID, Type: "lend", ContactName: "Historical Contact", Principal: 25, LendDate: deleted.Time, AccountID: &accountID, IsSettled: true, SettledAt: &deleted.Time, DeletedAt: deleted},
		&model.Transaction{ID: txID, UserID: f.user.ID, AccountID: accountID, CategoryID: &categoryID, MemberID: &memberID, PaidByMemberID: &memberID, ReminderID: &reminderID, LendingID: &lendingID, Type: "expense", Amount: 25, TransactionDate: deleted.Time, DeletedAt: deleted},
		&model.Budget{ID: uuid.NewString(), UserID: f.user.ID, CategoryID: &categoryID, MemberID: &memberID, Amount: 100, DeletedAt: deleted},
		&model.LendingRecord{ID: uuid.NewString(), UserID: f.user.ID, LendingID: lendingID, AccountID: &accountID, TransactionID: &txID, Type: "repay", Amount: 25, RecordDate: deleted.Time, DeletedAt: deleted},
		&model.QuickTemplate{ID: uuid.NewString(), UserID: f.user.ID, Name: "Historical", Type: "expense", AccountID: accountID, CategoryID: &categoryID, DeletedAt: deleted},
		&model.Tag{ID: uuid.NewString(), UserID: f.user.ID, Name: "Historical tag", DeletedAt: deleted},
		&model.AIReport{ID: uuid.NewString(), UserID: f.user.ID, ReportType: "monthly", PeriodStart: deleted.Time, PeriodEnd: deleted.Time, Status: "completed", ContentJSON: `{"summary":"historic"}`, ProviderRevision: "internal-excluded", DeletedAt: deleted},
	}
	for _, row := range rows {
		if err := f.db.Create(row).Error; err != nil {
			t.Fatal(err)
		}
	}
	backup, err := f.service.CreateBackup(f.user.ID)
	if err != nil {
		t.Fatal(err)
	}
	backup.Transactions[0].Account = &model.Account{Name: "association-excluded"}
	fingerprint := "fingerprint-excluded"
	backup.Transactions[0].ImportFingerprint = &fingerprint
	data, err := json.Marshal(backup)
	if err != nil {
		t.Fatal(err)
	}
	for _, excluded := range []string{"internal-excluded", "provider_revision", "association-excluded", "fingerprint-excluded", "import_fingerprint"} {
		if strings.Contains(string(data), excluded) {
			t.Fatalf("backup leaked internal or association data: %s", excluded)
		}
	}
	if err := f.service.RestoreBackup(f.user.ID, writeRawBackupFile(t, data)); err != nil {
		t.Fatal(err)
	}
	for _, row := range rows {
		var active, total int64
		if err := f.db.Model(row).Where("user_id = ?", f.user.ID).Count(&active).Error; err != nil {
			t.Fatal(err)
		}
		if err := f.db.Unscoped().Model(row).Where("user_id = ? AND deleted_at = ?", f.user.ID, deleted.Time).Count(&total).Error; err != nil {
			t.Fatal(err)
		}
		if active != 0 || total != 1 {
			t.Errorf("%T active/deleted = %d/%d, want 0/1", row, active, total)
		}
	}
	var tx model.Transaction
	if err := f.db.Unscoped().First(&tx, "id = ?", txID).Error; err != nil {
		t.Fatal(err)
	}
	if tx.AccountID != accountID || tx.CategoryID == nil || *tx.CategoryID != categoryID || tx.MemberID == nil || *tx.MemberID != memberID || tx.LendingID == nil || *tx.LendingID != lendingID {
		t.Fatalf("historical references lost: %#v", tx)
	}
	var account model.Account
	if err := f.db.Unscoped().First(&account, "id = ?", accountID).Error; err != nil {
		t.Fatal(err)
	}
	if !account.IsArchived {
		t.Fatal("archived account became unarchived")
	}
	var lending model.Lending
	if err := f.db.Unscoped().First(&lending, "id = ?", lendingID).Error; err != nil {
		t.Fatal(err)
	}
	if !lending.IsSettled || lending.SettledAt == nil || !lending.SettledAt.Equal(deleted.Time) {
		t.Fatal("settled lending state lost")
	}
}

// This is the oldest 2.1 envelope's actual field set: family members, AI reports,
// logs and attachments did not exist yet. Null and [] are explicit empty sets.
const legacy21EmptyLedger = `{"version":"2.1","accounts":[],"categories":null,"transactions":[],"budgets":null,"reminders":[],"lendings":null,"lending_records":[],"templates":null,"tags":[]}`

func TestRestoreLegacy21OriginalFieldsPreserveArchivedAccount(t *testing.T) {
	f := newBackupIntegrityFixture(t)
	// Literal original envelope, independent of FullBackupData's current codec.
	payload := []byte(`{"version":"2.1","accounts":[{"id":"legacy-account","name":"Archived Cash","type":"cash","initial_balance":100,"current_balance":100,"is_archived":true}],"categories":null,"transactions":[],"budgets":null,"reminders":[],"lendings":null,"lending_records":[],"templates":null,"tags":[]}`)
	if err := f.service.RestoreBackup(f.user.ID, writeRawBackupFile(t, payload)); err != nil {
		t.Fatalf("original 2.1 account rejected: %v", err)
	}
	var account model.Account
	if err := f.db.First(&account, "id = ? AND user_id = ?", "legacy-account", f.user.ID).Error; err != nil {
		t.Fatal(err)
	}
	if !account.IsArchived || account.CurrentBalance != 100 || account.DeletedAt.Valid {
		t.Fatalf("legacy account changed or invented tombstone: %#v", account)
	}
}

func TestRestoreLegacy21OriginalCollectionsAndExplicitEmptyLedger(t *testing.T) {
	f := newBackupIntegrityFixture(t)
	account := model.Account{ID: uuid.NewString(), UserID: f.user.ID, Name: "Current Cash", Type: "cash"}
	if err := f.db.Create(&account).Error; err != nil {
		t.Fatal(err)
	}
	if err := f.service.RestoreBackup(f.user.ID, writeRawBackupFile(t, []byte(legacy21EmptyLedger))); err != nil {
		t.Fatalf("valid original 2.1 explicit empty ledger rejected: %v", err)
	}
	var count int64
	if err := f.db.Model(&model.Account{}).Where("user_id = ?", f.user.ID).Count(&count).Error; err != nil {
		t.Fatal(err)
	}
	if count != 0 {
		t.Fatalf("explicit empty ledger left %d accounts", count)
	}
}

func TestBackupEnvelopeRequiresEachOriginalCollection(t *testing.T) {
	for _, version := range []string{"2.1", "2.2", "2.3", "2.4"} {
		required := []string{"accounts", "categories", "transactions", "budgets", "reminders", "lendings", "lending_records", "templates", "tags"}
		if version != "2.1" {
			required = append(required, "family_members", "ai_reports", "account_logs", "notification_logs")
		}
		for _, missing := range required {
			t.Run(version+"/"+missing, func(t *testing.T) {
				fields := map[string]any{"version": version, "user_profile": map[string]any{"nickname": "partial"}}
				for _, field := range required {
					fields[field] = []any{}
				}
				if version != "2.1" {
					fields["attachments"] = []any{}
				}
				delete(fields, missing)
				data, err := json.Marshal(fields)
				if err != nil {
					t.Fatal(err)
				}
				if _, err := preflightBackupJSON(data); !errors.Is(err, ErrInvalidBackupFormat) {
					t.Fatalf("missing %s accepted in %s: %v", missing, version, err)
				}
			})
		}
	}
}

func TestBackup24RejectsMissingTransactionTombstoneBeforeMutation(t *testing.T) {
	f := newBackupIntegrityFixture(t)
	account := model.Account{ID: uuid.NewString(), UserID: f.user.ID, Name: "Current", Type: "cash", CurrentBalance: 100}
	if err := f.db.Create(&account).Error; err != nil {
		t.Fatal(err)
	}
	fields := map[string]any{"version": "2.4", "attachments": nil}
	for _, key := range []string{"accounts", "categories", "transactions", "budgets", "reminders", "lendings", "lending_records", "templates", "tags", "family_members", "ai_reports", "account_logs", "notification_logs"} {
		fields[key] = []any{}
	}
	fields["accounts"] = []any{map[string]any{"id": account.ID, "name": "Current", "type": "cash", "current_balance": 100, "deleted_at": nil}}
	fields["transactions"] = []any{map[string]any{"id": uuid.NewString(), "account_id": account.ID, "type": "expense", "amount": 25, "transaction_date": "2026-10-06T00:00:00Z"}}
	data, err := json.Marshal(fields)
	if err != nil {
		t.Fatal(err)
	}
	if err := f.service.RestoreBackup(f.user.ID, writeRawBackupFile(t, data)); !errors.Is(err, ErrInvalidBackupFormat) {
		t.Fatalf("missing 2.4 tombstone accepted: %v", err)
	}
	var current model.Account
	if err := f.db.First(&current, "id = ?", account.ID).Error; err != nil {
		t.Fatal(err)
	}
	if current.CurrentBalance != 100 {
		t.Fatalf("failed restore changed balance: %v", current.CurrentBalance)
	}
}

func TestBackup24RequiresTombstoneInEverySoftDeletedCollection(t *testing.T) {
	collections := []string{"accounts", "categories", "transactions", "budgets", "reminders", "lendings", "lending_records", "templates", "tags", "family_members", "ai_reports"}
	for _, collection := range collections {
		t.Run(collection, func(t *testing.T) {
			// The envelope is complete; only the record's deletion state is absent.
			fields := map[string]any{"version": "2.4", "attachments": nil, "account_logs": nil, "notification_logs": nil}
			for _, key := range collections {
				fields[key] = []any{}
			}
			fields[collection] = []any{map[string]any{"id": "incomplete-record"}}
			data, err := json.Marshal(fields)
			if err != nil {
				t.Fatal(err)
			}
			if _, err := preflightBackupJSON(data); err != nil {
				t.Fatalf("complete envelope failed before codec: %v", err)
			}
			var decoded FullBackupData
			if err := json.Unmarshal(data, &decoded); !errors.Is(err, ErrInvalidBackupFormat) {
				t.Fatalf("missing %s deletion state accepted: %v", collection, err)
			}
		})
	}
}

func TestBackupRoundTripPreservesDisabledLedgerObjects(t *testing.T) {
	f := newBackupIntegrityFixture(t)
	budget := model.Budget{ID: uuid.NewString(), UserID: f.user.ID, Amount: 100}
	reminder := model.Reminder{ID: uuid.NewString(), UserID: f.user.ID, PaymentDay: 1}
	member := model.FamilyMember{ID: uuid.NewString(), UserID: f.user.ID, Name: "Disabled member"}
	for _, row := range []any{&budget, &reminder, &member} {
		if err := f.db.Create(row).Error; err != nil {
			t.Fatal(err)
		}
	}
	if err := f.db.Model(&budget).Update("is_active", false).Error; err != nil {
		t.Fatal(err)
	}
	if err := f.db.Model(&reminder).Updates(map[string]any{"is_enabled": false, "advance_days": 0}).Error; err != nil {
		t.Fatal(err)
	}
	if err := f.db.Model(&member).Update("is_enabled", false).Error; err != nil {
		t.Fatal(err)
	}
	backup, err := f.service.CreateBackup(f.user.ID)
	if err != nil {
		t.Fatal(err)
	}
	if err := f.service.RestoreBackup(f.user.ID, writeBackupFile(t, backup)); err != nil {
		t.Fatal(err)
	}
	var restoredBudget model.Budget
	var restoredReminder model.Reminder
	var restoredMember model.FamilyMember
	if err := f.db.First(&restoredBudget, "id = ?", budget.ID).Error; err != nil {
		t.Fatal(err)
	}
	if err := f.db.First(&restoredReminder, "id = ?", reminder.ID).Error; err != nil {
		t.Fatal(err)
	}
	if err := f.db.First(&restoredMember, "id = ?", member.ID).Error; err != nil {
		t.Fatal(err)
	}
	if restoredBudget.IsActive || restoredReminder.IsEnabled || restoredMember.IsEnabled {
		t.Fatalf("disabled objects reenabled budget/reminder/member = %v/%v/%v", restoredBudget.IsActive, restoredReminder.IsEnabled, restoredMember.IsEnabled)
	}
	if restoredReminder.AdvanceDays != 0 {
		t.Fatalf("same-day reminder advance days = %d, want 0", restoredReminder.AdvanceDays)
	}
}
