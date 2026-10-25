package service

import (
	"fmt"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
)

func TestTransactionImportDeletedHistoryRemainsDuplicate(t *testing.T) {
	for _, removal := range []string{"rollback", "delete"} {
		t.Run(removal, func(t *testing.T) {
			fixture := newTransactionImportFixture(t)
			payload := fmt.Sprintf(`[{"type":"expense","amount":25.50,"account_name":%q,"category_name":%q,"transaction_date":"2026-06-15"}]`,
				fixture.account.Name, fixture.expenseCategory.Name)
			preview, err := fixture.service.Preview(fixture.user.ID, "transactions.json", strings.NewReader(payload))
			if err != nil {
				t.Fatalf("preview import: %v", err)
			}
			committed, err := fixture.service.Commit(fixture.user.ID, preview.ID)
			if err != nil || committed.CreatedRows != 1 {
				t.Fatalf("commit import = %#v, err = %v", committed, err)
			}
			assertTransactionImportHasNoMutation(t, fixture, 74.5, 1)
			db := fixture.repos.Transaction.DB()
			var original model.Transaction
			if err := db.Where("user_id = ? AND source = ?", fixture.user.ID, "import").First(&original).Error; err != nil {
				t.Fatalf("load imported transaction: %v", err)
			}
			if original.ImportFingerprint == nil || *original.ImportFingerprint == "" {
				t.Fatal("imported transaction has no fingerprint")
			}
			switch removal {
			case "rollback":
				rolledBack, err := fixture.service.Rollback(fixture.user.ID, preview.ID)
				if err != nil || rolledBack.Status != "rolled_back" || rolledBack.RolledBackRows != 1 {
					t.Fatalf("rollback import = %#v, err = %v", rolledBack, err)
				}
			case "delete":
				if err := fixture.service.transactions.Delete(original.ID, fixture.user.ID); err != nil {
					t.Fatalf("delete imported transaction: %v", err)
				}
			}
			assertTransactionImportHasNoMutation(t, fixture, 100, 0)

			restarted := NewTransactionImportService(fixture.service.transactions)
			repeated, err := restarted.Preview(fixture.user.ID, "transactions.json", strings.NewReader(payload))
			if err != nil {
				t.Fatalf("preview deleted import: %v", err)
			}
			if repeated.ValidRows != 1 || repeated.InvalidRows != 0 || repeated.DuplicateRows != 1 ||
				len(repeated.Rows) != 1 || !repeated.Rows[0].Duplicate {
				t.Errorf("reimport preview = %#v, want one valid duplicate", repeated)
			}
			validated, err := restarted.Validate(fixture.user.ID, repeated.ID)
			if err != nil || validated.DuplicateRows != 1 {
				t.Errorf("validate deleted import = %#v, err = %v, want one duplicate", validated, err)
			}
			repeatedCommit, err := restarted.Commit(fixture.user.ID, repeated.ID)
			if err != nil {
				t.Fatalf("commit deleted import: %v", err)
			}
			if repeatedCommit.Status != "committed" || repeatedCommit.CreatedRows != 0 || repeatedCommit.DuplicateRows != 1 {
				t.Fatalf("reimport commit = %#v, want committed with zero created rows and one duplicate", repeatedCommit)
			}
			assertTransactionImportHasNoMutation(t, fixture, 100, 0)
			var history []model.Transaction
			if err := db.Unscoped().Where("user_id = ? AND source = ?", fixture.user.ID, "import").Find(&history).Error; err != nil {
				t.Fatalf("load imported history: %v", err)
			}
			if len(history) != 1 || history[0].ID != original.ID || !history[0].DeletedAt.Valid ||
				history[0].ImportFingerprint == nil || *history[0].ImportFingerprint != *original.ImportFingerprint {
				t.Fatalf("import history = %#v, want original deleted transaction with retained fingerprint", history)
			}
			if rolledBack, err := restarted.Rollback(fixture.user.ID, repeated.ID); err != nil || rolledBack.RolledBackRows != 0 {
				t.Fatalf("rollback skipped reimport = %#v, err = %v", rolledBack, err)
			}
			assertTransactionImportHasNoMutation(t, fixture, 100, 0)

			otherAccount := &model.Account{
				ID: uuid.NewString(), UserID: fixture.other.ID, Name: fixture.account.Name, Type: "cash",
				InitialBalance: 100, CurrentBalance: 100,
			}
			if err := fixture.repos.Account.Create(otherAccount); err != nil {
				t.Fatalf("create other account: %v", err)
			}
			otherCategory := &model.Category{
				ID: uuid.NewString(), UserID: fixture.other.ID, Name: fixture.expenseCategory.Name, Type: "expense",
			}
			if err := fixture.repos.Category.Create(otherCategory); err != nil {
				t.Fatalf("create other category: %v", err)
			}
			otherPreview, err := restarted.Preview(fixture.other.ID, "transactions.json", strings.NewReader(payload))
			if err != nil || otherPreview.ValidRows != 1 || otherPreview.DuplicateRows != 0 {
				t.Fatalf("other user preview = %#v, err = %v, want one new valid row", otherPreview, err)
			}
			otherCommit, err := restarted.Commit(fixture.other.ID, otherPreview.ID)
			if err != nil || otherCommit.CreatedRows != 1 {
				t.Fatalf("other user commit = %#v, err = %v, want one created row", otherCommit, err)
			}
			assertTransactionImportHasNoMutation(t, fixture, 100, 0)
		})
	}
}

func TestTransactionImportCommitRechecksRolledBackHistory(t *testing.T) {
	fixture := newTransactionImportFixture(t)
	payload := fmt.Sprintf(`[{"type":"expense","amount":10,"account_id":%q,"transaction_date":"2026-06-15"}]`, fixture.account.ID)
	original, err := fixture.service.Preview(fixture.user.ID, "transactions.json", strings.NewReader(payload))
	if err != nil {
		t.Fatalf("preview original import: %v", err)
	}
	pending, err := fixture.service.Preview(fixture.user.ID, "transactions.json", strings.NewReader(payload))
	if err != nil || pending.ValidRows != 1 || pending.DuplicateRows != 0 {
		t.Fatalf("pending preview = %#v, err = %v, want one new valid row", pending, err)
	}
	if committed, err := fixture.service.Commit(fixture.user.ID, original.ID); err != nil || committed.CreatedRows != 1 {
		t.Fatalf("commit original import = %#v, err = %v", committed, err)
	}
	if _, err := fixture.service.Rollback(fixture.user.ID, original.ID); err != nil {
		t.Fatalf("rollback original import: %v", err)
	}
	assertTransactionImportHasNoMutation(t, fixture, 100, 0)

	restarted := NewTransactionImportService(fixture.service.transactions)
	committed, err := restarted.Commit(fixture.user.ID, pending.ID)
	if err != nil {
		t.Fatalf("commit pending import after rollback: %v", err)
	}
	if committed.Status != "committed" || committed.CreatedRows != 0 || committed.DuplicateRows != 1 {
		t.Fatalf("pending commit = %#v, want committed with zero created rows and one duplicate", committed)
	}
	assertTransactionImportHasNoMutation(t, fixture, 100, 0)
}
