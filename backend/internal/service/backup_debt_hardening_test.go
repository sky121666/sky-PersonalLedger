package service

import (
	"testing"
	"time"

	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

func TestDebtBackupHardeningBackupMustRejectReversalMarkerOnPaymentAllocation(t *testing.T) {
	f := newDebtFixture(t)
	first, err := f.svc.Pay(f.user, DebtPaymentRequest{
		AccountID: &f.debt, SourceKind: "account", SourceAccountID: &f.cash,
		Amount: 10, Allocations: []DebtPaymentPart{{PlanID: f.a, Principal: 10}}, IdempotencyKey: "marker-first",
	})
	if err != nil {
		t.Fatal(err)
	}
	second, err := f.svc.Pay(f.user, DebtPaymentRequest{
		AccountID: &f.debt, SourceKind: "account", SourceAccountID: &f.cash,
		Amount: 20, Allocations: []DebtPaymentPart{{PlanID: f.a, Principal: 20}}, IdempotencyKey: "marker-second",
	})
	if err != nil {
		t.Fatal(err)
	}
	backup, err := debtBackupService(f).CreateBackup(f.user)
	if err != nil {
		t.Fatal(err)
	}
	firstPart := ""
	for _, part := range backup.DebtAllocations {
		if part.OperationID == first.ID {
			firstPart = part.ID
		}
	}
	if firstPart == "" {
		t.Fatal("missing first payment allocation")
	}
	for i := range backup.DebtAllocations {
		if backup.DebtAllocations[i].OperationID == second.ID {
			backup.DebtAllocations[i].ReversalOf = &firstPart
		}
	}
	target := newDebtFixture(t)
	if err := debtBackupService(target).RestoreBackup(target.user, writeBackupFile(t, backup)); err == nil {
		_, reverseErr := target.svc.Reverse(target.user, first.ID, DebtReverseRequest{IdempotencyKey: "marker-undo"})
		account, _ := target.repos.Account.GetByID(f.debt)
		cash, _ := target.repos.Account.GetByID(f.cash)
		t.Fatalf("invalid reversal marker restored; reverse_error=%v debt=%v cash=%v",
			reverseErr, account.CurrentBalance, cash.CurrentBalance)
	}
	debtAssert(t, target, 1000, 2000, 600, 300, 100, 0)
}

func TestDebtBackupHardeningBackupMustRejectLivePaymentUsingDeletedSource(t *testing.T) {
	f := newDebtFixture(t)
	payment, err := f.svc.Pay(f.user, DebtPaymentRequest{
		AccountID: &f.debt, SourceKind: "account", SourceAccountID: &f.cash,
		Amount: 10, Allocations: []DebtPaymentPart{{PlanID: f.a, Principal: 10}}, IdempotencyKey: "deleted-source",
	})
	if err != nil {
		t.Fatal(err)
	}
	backup, err := debtBackupService(f).CreateBackup(f.user)
	if err != nil {
		t.Fatal(err)
	}
	for i := range backup.Accounts {
		if backup.Accounts[i].ID == f.cash {
			backup.Accounts[i].DeletedAt = gorm.DeletedAt{Time: time.Now(), Valid: true}
		}
	}
	target := newDebtFixture(t)
	if err := debtBackupService(target).RestoreBackup(target.user, writeBackupFile(t, backup)); err == nil {
		_, reverseErr := target.svc.Reverse(target.user, payment.ID, DebtReverseRequest{IdempotencyKey: "undo-deleted-source"})
		var source model.Account
		if err := target.repos.Account.DB().Unscoped().First(&source, "id = ?", f.cash).Error; err != nil {
			t.Fatal(err)
		}
		t.Fatalf("live payment with deleted source restored; reverse_error=%v source_deleted=%t source_balance=%v",
			reverseErr, source.DeletedAt.Valid, source.CurrentBalance)
	}
	debtAssert(t, target, 1000, 2000, 600, 300, 100, 0)
}

func TestDebtBackupHardeningRejectsDeletedAccountWithLivePlans(t *testing.T) {
	f := newDebtFixture(t)
	backup, err := debtBackupService(f).CreateBackup(f.user)
	if err != nil {
		t.Fatal(err)
	}
	for i := range backup.Accounts {
		if backup.Accounts[i].ID == f.debt {
			backup.Accounts[i].DeletedAt = gorm.DeletedAt{Time: time.Now(), Valid: true}
		}
	}
	target := newDebtFixture(t)
	if err := debtBackupService(target).RestoreBackup(target.user, writeBackupFile(t, backup)); err == nil {
		t.Fatal("live plans restored against a deleted managed account")
	}
	debtAssert(t, target, 1000, 2000, 600, 300, 100, 0)
}

func TestDebtBackupHardeningRetainsHistoricalDeletedSource(t *testing.T) {
	f := newDebtFixture(t)
	payment, err := f.svc.Pay(f.user, DebtPaymentRequest{AccountID: &f.debt, SourceKind: "account",
		SourceAccountID: &f.cash, Amount: 10, IdempotencyKey: "historical-payment",
		Allocations: []DebtPaymentPart{{PlanID: f.a, Principal: 10}}})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.Reverse(f.user, payment.ID, DebtReverseRequest{IdempotencyKey: "historical-undo"}); err != nil {
		t.Fatal(err)
	}
	backup, err := debtBackupService(f).CreateBackup(f.user)
	if err != nil {
		t.Fatal(err)
	}
	for i := range backup.Accounts {
		if backup.Accounts[i].ID == f.cash {
			backup.Accounts[i].DeletedAt = gorm.DeletedAt{Time: time.Now(), Valid: true}
		}
	}
	target := newDebtFixture(t)
	if err := debtBackupService(target).RestoreBackup(target.user, writeBackupFile(t, backup)); err != nil {
		t.Fatalf("pure historical source tombstone rejected: %v", err)
	}
	var account model.Account
	if err := target.repos.Account.DB().Unscoped().First(&account, "id = ?", f.cash).Error; err != nil ||
		!account.DeletedAt.Valid || account.CurrentBalance != 2000 {
		t.Fatalf("historical source did not survive restore: %+v %v", account, err)
	}
	if err := target.svc.CheckAccount(target.user, f.debt); err != nil {
		t.Fatal(err)
	}
	if _, err := debtBackupService(target).CreateBackup(target.user); err != nil {
		t.Fatalf("restored history cannot be re-exported: %v", err)
	}
}
