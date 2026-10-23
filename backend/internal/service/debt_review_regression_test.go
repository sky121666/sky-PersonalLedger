package service

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

func TestDebtReviewStandaloneDowngradeMustNotDiscardEvidence(t *testing.T) {
	_, repos, user := newTransactionTestService(t)
	f := debtFixture{svc: NewDebtService(repos.Account.DB()), repos: repos, user: user}
	plan, err := f.svc.CreatePlan(user, CreateDebtPlanRequest{
		Name: "Standalone synthetic debt", Scope: "standalone",
		OriginalPrincipal: 100, OpeningPrincipal: 100, IdempotencyKey: "standalone",
	})
	if err != nil {
		t.Fatal(err)
	}
	backup, err := debtBackupService(f).CreateBackup(user)
	if err != nil {
		t.Fatal(err)
	}
	raw, err := json.Marshal(backup)
	if err != nil {
		t.Fatal(err)
	}
	var envelope map[string]json.RawMessage
	if err := json.Unmarshal(raw, &envelope); err != nil {
		t.Fatal(err)
	}
	envelope["version"] = json.RawMessage(`"2.4"`)
	raw, err = json.Marshal(envelope)
	if err != nil {
		t.Fatal(err)
	}
	err = debtBackupService(f).RestoreBackup(user, writeRawBackupFile(t, raw))
	if err == nil {
		var plans, operations, allocations int64
		db := repos.Account.DB()
		db.Model(&model.DebtPlan{}).Count(&plans)
		db.Model(&model.DebtOperation{}).Count(&operations)
		db.Model(&model.DebtAllocation{}).Count(&allocations)
		t.Fatalf("downgraded backup accepted; original_plan=%s remaining plans/operations/allocations=%d/%d/%d",
			plan.ID, plans, operations, allocations)
	}
}

func TestDebtReviewBackupMustRejectAllocationExceedingParentPayment(t *testing.T) {
	f := newDebtFixture(t)
	direct, err := f.svc.Pay(f.user, DebtPaymentRequest{
		AccountID: &f.debt, SourceKind: "account", SourceAccountID: &f.cash,
		Amount: 10, Allocations: []DebtPaymentPart{{PlanID: f.a, Principal: 10}}, IdempotencyKey: "direct",
	})
	if err != nil {
		t.Fatal(err)
	}
	pending, err := f.svc.Pay(f.user, DebtPaymentRequest{
		AccountID: &f.debt, SourceKind: "account", SourceAccountID: &f.cash,
		Amount: 10, UnappliedAmount: 10, IdempotencyKey: "pending",
	})
	if err != nil {
		t.Fatal(err)
	}
	child, err := f.svc.Allocate(f.user, pending.ID, DebtAllocateRequest{
		Allocations: []DebtPaymentPart{{PlanID: f.a, Principal: 10}}, IdempotencyKey: "child",
	})
	if err != nil {
		t.Fatal(err)
	}
	backup, err := debtBackupService(f).CreateBackup(f.user)
	if err != nil {
		t.Fatal(err)
	}
	for i := range backup.DebtOperations {
		if backup.DebtOperations[i].ID == child.ID {
			backup.DebtOperations[i].PaymentID = &direct.ID
		}
	}
	target := newDebtFixture(t)
	if err := debtBackupService(target).RestoreBackup(target.user, writeBackupFile(t, backup)); err == nil {
		actual, err := target.svc.OperationDetails(target.user, child.ID)
		if err != nil {
			t.Fatal(err)
		}
		t.Fatalf("malformed backup restored: child_amount=%v parent_unapplied=%v restored_parent=%s",
			actual.Operation.Amount, direct.UnappliedAmount, *actual.Operation.PaymentID)
	}
}

func TestDebtReviewManagedImportMustRetainBatchRollback(t *testing.T) {
	f := newDebtFixture(t)
	importer := NewTransactionImportService(f.tx)
	raw := fmt.Sprintf(`{"transactions":[{"type":"transfer","account_id":%q,"to_account_id":%q,"amount":10,"transaction_date":"2026-10-18"}]}`,
		f.cash, f.debt)
	preview, err := importer.Preview(f.user, "synthetic.json", strings.NewReader(raw))
	if err != nil {
		t.Fatal(err)
	}
	if preview.InvalidRows != 0 {
		t.Fatalf("invalid preview: %+v", preview)
	}
	if _, err := importer.Commit(f.user, preview.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := importer.Rollback(f.user, preview.ID); err != nil {
		account, _ := f.repos.Account.GetByID(f.debt)
		cash, _ := f.repos.Account.GetByID(f.cash)
		t.Fatalf("managed import committed but rollback rejected: %v; debt=%v cash=%v pending=%v",
			err, account.CurrentBalance, cash.CurrentBalance, account.UnappliedPayment)
	}
	debtAssert(t, f, 1000, 2000, 600, 300, 100, 0)
}

func TestDebtMixedImportRollbackReversesAllocationsAndIsAtomic(t *testing.T) {
	f := newDebtFixture(t)
	importer := NewTransactionImportService(f.tx)
	raw := fmt.Sprintf(`{"transactions":[
		{"type":"transfer","account_id":%q,"to_account_id":%q,"amount":10,"transaction_date":"2026-10-18"},
		{"type":"expense","account_id":%q,"amount":7,"transaction_date":"2026-10-18"}]}`,
		f.cash, f.debt, f.cash)
	preview, err := importer.Preview(f.user, "synthetic.json", strings.NewReader(raw))
	if err != nil || preview.InvalidRows != 0 {
		t.Fatalf("preview: %+v %v", preview, err)
	}
	if _, err := importer.Commit(f.user, preview.ID); err != nil {
		t.Fatal(err)
	}
	db := f.repos.Account.DB()
	var imported model.Transaction
	if err := db.First(&imported, "user_id = ? AND source = ? AND type = ?", f.user, "import", "transfer").Error; err != nil {
		t.Fatal(err)
	}
	if imported.DebtOperationID == nil {
		t.Fatal("imported payment has no operation")
	}
	if _, err := f.svc.Allocate(f.user, *imported.DebtOperationID, DebtAllocateRequest{
		Allocations: []DebtPaymentPart{{PlanID: f.a, Principal: 10}}, IdempotencyKey: "allocate-import"}); err != nil {
		t.Fatal(err)
	}
	debtAssert(t, f, 990, 1983, 590, 300, 100, 0)
	injected := errors.New("synthetic rollback log failure")
	const callback = "debt_test:rollback_log_failure"
	if err := db.Callback().Create().Before("gorm:create").Register(callback, func(tx *gorm.DB) {
		if log, ok := tx.Statement.Dest.(*model.AccountLog); ok && log.DebtEffectRole == "reversal" && log.AccountID == f.cash {
			tx.AddError(injected)
		}
	}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Callback().Create().Remove(callback) })
	if _, err := importer.Rollback(f.user, preview.ID); !errors.Is(err, injected) {
		t.Fatalf("rollback did not report injected failure: %v", err)
	}
	debtAssert(t, f, 990, 1983, 590, 300, 100, 0)
	state, err := importer.Get(f.user, preview.ID)
	if err != nil || state.Status != "committed" {
		t.Fatalf("failed rollback changed batch state: %+v %v", state, err)
	}
	var active int64
	if err := db.Model(&model.Transaction{}).Where("user_id = ? AND source = ?", f.user, "import").Count(&active).Error; err != nil || active != 2 {
		t.Fatalf("failed rollback deleted part of batch: %d %v", active, err)
	}
	if err := db.Callback().Create().Remove(callback); err != nil {
		t.Fatal(err)
	}
	if _, err := importer.Rollback(f.user, preview.ID); err != nil {
		t.Fatal(err)
	}
	debtAssert(t, f, 1000, 2000, 600, 300, 100, 0)
	if _, err := debtBackupService(f).CreateBackup(f.user); err != nil {
		t.Fatalf("rolled-back import cannot be backed up: %v", err)
	}
}

func TestDebtReviewBackupMustRejectManagedTransactionWithoutOperation(t *testing.T) {
	f := newDebtFixture(t)
	backup, err := debtBackupService(f).CreateBackup(f.user)
	if err != nil {
		t.Fatal(err)
	}
	backup.Transactions = append(backup.Transactions, model.Transaction{
		ID: "synthetic-orphan-transaction", UserID: f.user, AccountID: f.debt,
		Type: "expense", Amount: 25, TransactionDate: time.Now(), Source: "manual",
	})
	target := newDebtFixture(t)
	if err := debtBackupService(target).RestoreBackup(target.user, writeBackupFile(t, backup)); err == nil {
		err := target.tx.Delete("synthetic-orphan-transaction", target.user)
		t.Fatalf("orphan expense restored without balance/evidence; deletion error=%v", err)
	}
}

func TestDebtReviewStaleParentReadMustNotAllocateReversedPayment(t *testing.T) {
	f := newDebtFixture(t)
	parent, err := f.svc.Pay(f.user, DebtPaymentRequest{
		AccountID: &f.debt, SourceKind: "account", SourceAccountID: &f.cash,
		Amount: 10, UnappliedAmount: 10, IdempotencyKey: "reversed-parent",
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.Pay(f.user, DebtPaymentRequest{
		AccountID: &f.debt, SourceKind: "account", SourceAccountID: &f.cash,
		Amount: 20, UnappliedAmount: 20, IdempotencyKey: "unrelated-pending",
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.Reverse(f.user, parent.ID, DebtReverseRequest{IdempotencyKey: "reverse-parent"}); err != nil {
		t.Fatal(err)
	}
	db := f.repos.Account.DB()
	injected := false
	// Simulate the parent image read before another transaction obtained the
	// account lock and committed reversal. All financial state is real SQLite.
	if err := db.Callback().Query().After("gorm:query").Register("review:stale_parent", func(tx *gorm.DB) {
		if row, ok := tx.Statement.Dest.(*model.DebtOperation); ok && row.ID == parent.ID && !injected {
			row.ReversedBy = nil
			injected = true
		}
	}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Callback().Query().Remove("review:stale_parent") })
	child, err := f.svc.Allocate(f.user, parent.ID, DebtAllocateRequest{
		Allocations: []DebtPaymentPart{{PlanID: f.a, Principal: 10}}, IdempotencyKey: "stale-allocation",
	})
	if !injected {
		t.Fatal("stale-read injection did not run")
	}
	if err == nil {
		actual, _ := f.svc.GetOperation(f.user, parent.ID)
		account, _ := f.repos.Account.GetByID(f.debt)
		_, backupErr := debtBackupService(f).CreateBackup(f.user)
		t.Fatalf("allocation committed against reversed parent; child=%s parent_reversed=%t pending=%v check=%v backup_error=%v",
			child.ID, actual.ReversedBy != nil, account.UnappliedPayment, f.svc.CheckAccount(f.user, f.debt), backupErr)
	}
}
