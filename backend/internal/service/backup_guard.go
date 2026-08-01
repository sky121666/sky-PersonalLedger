package service

import (
	"errors"
	"fmt"
	"sort"

	"gorm.io/gorm"
)

// rejectCrossUserBackupReferences prevents a restored row from pointing at a
// globally identified row owned by another user. Dangling legacy references
// remain accepted because older releases allowed deleting referenced labels;
// a missing row cannot expose another user's data.
func (s *BackupService) rejectCrossUserBackupReferences(targetUserID uint, backup *FullBackupData) error {
	if s == nil || s.db == nil || backup == nil {
		return ErrInvalidBackupFormat
	}

	accountIDs := newBackupReferenceSet()
	categoryIDs := newBackupReferenceSet()
	memberIDs := newBackupReferenceSet()
	reminderIDs := newBackupReferenceSet()
	lendingIDs := newBackupReferenceSet()
	transactionIDs := newBackupReferenceSet()

	for i := range backup.Accounts {
		accountIDs.include(backup.Accounts[i].ID)
	}
	for i := range backup.Categories {
		categoryIDs.include(backup.Categories[i].ID)
	}
	for i := range backup.FamilyMembers {
		memberIDs.include(backup.FamilyMembers[i].ID)
	}
	for i := range backup.Reminders {
		reminderIDs.include(backup.Reminders[i].ID)
		accountIDs.reference(optionalBackupReference(backup.Reminders[i].AccountID))
	}
	for _, lending := range backup.Lendings {
		if lending == nil {
			return invalidBackupOwnership(errors.New("backup contains a null lending"))
		}
		lendingIDs.include(lending.ID)
		accountIDs.reference(optionalBackupReference(lending.AccountID))
	}
	for i := range backup.Transactions {
		transaction := &backup.Transactions[i]
		transactionIDs.include(transaction.ID)
		accountIDs.reference(transaction.AccountID)
		accountIDs.reference(optionalBackupReference(transaction.ToAccountID))
		categoryIDs.reference(optionalBackupReference(transaction.CategoryID))
		memberIDs.reference(optionalBackupReference(transaction.MemberID))
		memberIDs.reference(optionalBackupReference(transaction.PaidByMemberID))
		reminderIDs.reference(optionalBackupReference(transaction.ReminderID))
		lendingIDs.reference(optionalBackupReference(transaction.LendingID))
	}
	for i := range backup.Budgets {
		categoryIDs.reference(optionalBackupReference(backup.Budgets[i].CategoryID))
		memberIDs.reference(optionalBackupReference(backup.Budgets[i].MemberID))
	}
	for i := range backup.Templates {
		accountIDs.reference(backup.Templates[i].AccountID)
		categoryIDs.reference(optionalBackupReference(backup.Templates[i].CategoryID))
	}
	for _, record := range backup.LendingRecords {
		if record == nil {
			return invalidBackupOwnership(errors.New("backup contains a null lending record"))
		}
		lendingIDs.reference(record.LendingID)
		accountIDs.reference(optionalBackupReference(record.AccountID))
		transactionIDs.reference(optionalBackupReference(record.TransactionID))
	}
	for i := range backup.AccountLogs {
		entry := &backup.AccountLogs[i]
		accountIDs.reference(entry.AccountID)
		transactionIDs.reference(optionalBackupReference(entry.TransactionID))
		reminderIDs.reference(optionalBackupReference(entry.ReminderID))
		lendingIDs.reference(optionalBackupReference(entry.LendingID))
	}

	checks := []struct {
		table string
		set   *backupReferenceSet
	}{
		{table: "accounts", set: accountIDs},
		{table: "categories", set: categoryIDs},
		{table: "family_members", set: memberIDs},
		{table: "reminders", set: reminderIDs},
		{table: "lendings", set: lendingIDs},
		{table: "transactions", set: transactionIDs},
	}
	for _, check := range checks {
		external := check.set.external()
		if err := rejectOtherOwnerReferences(s.db, check.table, targetUserID, external); err != nil {
			return err
		}
		if len(external) > 0 {
			return invalidBackupOwnership(fmt.Errorf("backup omits referenced %s row %q", check.table, external[0]))
		}
	}
	return nil
}

type backupReferenceSet struct {
	included   map[string]struct{}
	referenced map[string]struct{}
}

func newBackupReferenceSet() *backupReferenceSet {
	return &backupReferenceSet{included: map[string]struct{}{}, referenced: map[string]struct{}{}}
}

func (s *backupReferenceSet) include(id string) {
	if id != "" {
		s.included[id] = struct{}{}
	}
}

func (s *backupReferenceSet) reference(id string) {
	if id != "" {
		s.referenced[id] = struct{}{}
	}
}

func (s *backupReferenceSet) external() []string {
	values := make([]string, 0, len(s.referenced))
	for id := range s.referenced {
		if _, included := s.included[id]; !included {
			values = append(values, id)
		}
	}
	sort.Strings(values)
	return values
}

func optionalBackupReference(value *string) string {
	if value == nil {
		return ""
	}
	return *value
}

func rejectOtherOwnerReferences(db *gorm.DB, table string, targetUserID uint, ids []string) error {
	const queryChunkSize = 400
	type ownedRow struct {
		ID     string
		UserID uint
	}
	for start := 0; start < len(ids); start += queryChunkSize {
		end := start + queryChunkSize
		if end > len(ids) {
			end = len(ids)
		}
		var rows []ownedRow
		if err := db.Unscoped().Table(table).
			Select("id", "user_id").
			Where("id IN ?", ids[start:end]).
			Scan(&rows).Error; err != nil {
			return fmt.Errorf("validate backup references: %w", err)
		}
		for _, row := range rows {
			if row.UserID != targetUserID {
				return invalidBackupOwnership(fmt.Errorf("backup references another user's %s row", table))
			}
		}
	}
	return nil
}
