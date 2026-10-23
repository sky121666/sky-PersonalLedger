package service

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/sky/personal-ledger/internal/config"
	"github.com/sky/personal-ledger/internal/model"
)

func debtBackupService(f debtFixture) *BackupService {
	r := f.repos
	return NewBackupService(r.Account.DB(), r.Account, r.Category, r.Transaction, r.Budget, r.Reminder,
		r.Lending, r.Template, r.Notification, r.Tag, r.User, r.FamilyMember, r.AIReport)
}

func TestDebtBackupCrossUserRestorePreservesAllocationAndReversal(t *testing.T) {
	source := newDebtFixture(t)
	payment, err := source.svc.Pay(source.user, DebtPaymentRequest{AccountID: &source.debt, SourceKind: "account",
		SourceAccountID: &source.cash, Amount: 120, UnappliedAmount: 10, IdempotencyKey: "backed-payment",
		Allocations: []DebtPaymentPart{{PlanID: source.a, Principal: 60, CashInterest: 10}, {PlanID: source.b, Principal: 40}}})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := source.svc.Allocate(source.user, payment.ID, DebtAllocateRequest{
		Allocations: []DebtPaymentPart{{PlanID: source.b, Principal: 10}}, IdempotencyKey: "backed-allocation",
	}); err != nil {
		t.Fatal(err)
	}
	backup, err := debtBackupService(source).CreateBackup(source.user)
	if err != nil {
		t.Fatal(err)
	}
	if backup.Version != "2.5" {
		t.Fatalf("new financial evidence exported as legacy version %s", backup.Version)
	}
	raw, err := json.Marshal(backup)
	if err != nil {
		t.Fatal(err)
	}
	var envelope map[string]json.RawMessage
	json.Unmarshal(raw, &envelope)
	for _, key := range []string{"debt_plans", "debt_operations", "debt_allocations"} {
		if len(envelope[key]) == 0 {
			t.Fatalf("missing backup evidence collection %s", key)
		}
	}
	target := newDebtFixture(t)
	user := model.User{Username: "restore-target", PasswordHash: "synthetic"}
	if err := target.repos.User.Create(&user); err != nil {
		t.Fatal(err)
	}
	target.user = user.ID
	for i := 0; i < 2; i++ {
		if err := debtBackupService(target).RestoreBackup(target.user, writeBackupFile(t, backup)); err != nil {
			t.Fatalf("restore %d: %v", i+1, err)
		}
	}
	target.debt, target.cash, target.a, target.b = source.debt, source.cash, source.a, source.b
	debtAssert(t, target, 890, 1880, 540, 250, 100, 0)
	op, err := target.svc.GetOperation(target.user, payment.ID)
	if err != nil || op.UserID != target.user {
		t.Fatalf("operation ownership not remapped: %+v %v", op, err)
	}
	if _, err := target.svc.Reverse(target.user, payment.ID, DebtReverseRequest{IdempotencyKey: "restored-undo"}); err != nil {
		t.Fatal(err)
	}
	debtAssert(t, target, 1000, 2000, 600, 300, 100, 0)
	after, err := debtBackupService(target).CreateBackup(target.user)
	if err != nil {
		t.Fatal(err)
	}
	if err := debtBackupService(target).RestoreBackup(target.user, writeBackupFile(t, after)); err != nil {
		t.Fatalf("reversed history is not restorable: %v", err)
	}
	debtAssert(t, target, 1000, 2000, 600, 300, 100, 0)
}

func TestDebtMalformedBackupNeverClearsTarget(t *testing.T) {
	source := newDebtFixture(t)
	payment, err := source.svc.Pay(source.user, DebtPaymentRequest{AccountID: &source.debt, SourceKind: "account",
		SourceAccountID: &source.cash, Amount: 10, IdempotencyKey: "corruption-base",
		Allocations: []DebtPaymentPart{{PlanID: source.a, Principal: 10}}})
	if err != nil {
		t.Fatal(err)
	}
	original, err := debtBackupService(source).CreateBackup(source.user)
	if err != nil {
		t.Fatal(err)
	}
	raw, _ := json.Marshal(original)
	for _, kind := range []string{"missing-operation", "missing-allocation", "missing-source-log", "duplicate-log",
		"foreign-owner", "balance", "wrong-scope", "lost-idempotency", "uppercase-key", "uppercase-request-hash", "downgrade"} {
		t.Run(kind, func(t *testing.T) {
			var backup FullBackupData
			if err := json.Unmarshal(raw, &backup); err != nil {
				t.Fatal(err)
			}
			switch kind {
			case "missing-operation":
				backup.DebtOperations = nil
			case "missing-allocation":
				backup.DebtAllocations = nil
			case "missing-source-log":
				for i, log := range backup.AccountLogs {
					if log.DebtOperationID != nil && *log.DebtOperationID == payment.ID && log.AccountID == source.cash {
						backup.AccountLogs = append(backup.AccountLogs[:i], backup.AccountLogs[i+1:]...)
						break
					}
				}
			case "duplicate-log":
				backup.AccountLogs = append(backup.AccountLogs, backup.AccountLogs[len(backup.AccountLogs)-1])
			case "foreign-owner":
				backup.DebtPlans[0].UserID = source.user + 500
			case "balance":
				for i := range backup.Accounts {
					if backup.Accounts[i].ID == source.debt {
						backup.Accounts[i].CurrentBalance = 1
					}
				}
			case "wrong-scope":
				backup.DebtPlans[0].AccountID = &source.cash
			case "lost-idempotency":
				for i := range backup.DebtOperations {
					if backup.DebtOperations[i].ID == payment.ID {
						backup.DebtOperations[i].RequestKeyHash = nil
					}
				}
			case "uppercase-key", "uppercase-request-hash":
				for i := range backup.DebtOperations {
					row := &backup.DebtOperations[i]
					if row.ID == payment.ID {
						if kind == "uppercase-key" {
							value := strings.ToUpper(*row.RequestKeyHash)
							row.RequestKeyHash = &value
						} else {
							row.RequestHash = strings.ToUpper(row.RequestHash)
						}
					}
				}
			case "downgrade":
				backup.Version = "2.4"
			}
			target := newDebtFixture(t)
			if err := debtBackupService(target).RestoreBackup(target.user, writeBackupFile(t, &backup)); err == nil {
				t.Fatal("malformed financial backup accepted")
			}
			debtAssert(t, target, 1000, 2000, 600, 300, 100, 0)
		})
	}
}

func TestDebtBackupRejectsAllocationBorrowingAnotherPaymentsCredit(t *testing.T) {
	source := newDebtFixture(t)
	first, err := source.svc.Pay(source.user, DebtPaymentRequest{AccountID: &source.debt, SourceKind: "account",
		SourceAccountID: &source.cash, Amount: 10, UnappliedAmount: 10, IdempotencyKey: "first-credit"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := source.svc.Pay(source.user, DebtPaymentRequest{AccountID: &source.debt, SourceKind: "account",
		SourceAccountID: &source.cash, Amount: 20, UnappliedAmount: 20, IdempotencyKey: "second-credit"}); err != nil {
		t.Fatal(err)
	}
	allocation, err := source.svc.Allocate(source.user, first.ID, DebtAllocateRequest{
		Allocations: []DebtPaymentPart{{PlanID: source.a, Principal: 10}}, IdempotencyKey: "first-split"})
	if err != nil {
		t.Fatal(err)
	}
	backup, err := debtBackupService(source).CreateBackup(source.user)
	if err != nil {
		t.Fatal(err)
	}
	// Keep every aggregate balanced while making the first 10-unit payment
	// consume 20 units. The other payment's credit must not hide this defect.
	for i := range backup.DebtOperations {
		if backup.DebtOperations[i].ID == allocation.ID {
			backup.DebtOperations[i].Amount = 20
		}
	}
	for i := range backup.DebtAllocations {
		if backup.DebtAllocations[i].OperationID == allocation.ID {
			backup.DebtAllocations[i].PrincipalDelta = -20
			backup.DebtAllocations[i].PrincipalPaidDelta = 20
		}
	}
	for i := range backup.DebtPlans {
		if backup.DebtPlans[i].ID == source.a {
			backup.DebtPlans[i].PrincipalBalance = 580
			backup.DebtPlans[i].PrincipalPaid = 20
		}
	}
	for i := range backup.AccountLogs {
		row := &backup.AccountLogs[i]
		if row.DebtOperationID != nil && *row.DebtOperationID == allocation.ID {
			row.UnappliedDelta, row.PrincipalPaidDelta = -20, 20
		}
	}
	for i := range backup.Accounts {
		if backup.Accounts[i].ID == source.debt {
			backup.Accounts[i].UnappliedPayment, backup.Accounts[i].TotalPaid = 10, 20
		}
	}
	target := newDebtFixture(t)
	if err := debtBackupService(target).RestoreBackup(target.user, writeBackupFile(t, backup)); err == nil {
		t.Fatal("one payment consumed another payment's credit")
	}
	debtAssert(t, target, 1000, 2000, 600, 300, 100, 0)
}

func TestDebtReversedReceiptSurvivesGCBackupAndCrossUserRestore(t *testing.T) {
	source := newDebtFixture(t)
	sourceRoot := t.TempDir()
	uploads := NewUploadService(&config.StorageConfig{UploadPath: sourceRoot, MaxFileSize: 1, AllowedTypes: "txt"}, source.repos.Account.DB())
	source.tx.WithUploadService(uploads)
	payment, err := source.svc.Pay(source.user, DebtPaymentRequest{AccountID: &source.debt, SourceKind: "account",
		SourceAccountID: &source.cash, Amount: 10, IdempotencyKey: "receipt-pay",
		Allocations: []DebtPaymentPart{{PlanID: source.a, Principal: 10}}})
	if err != nil {
		t.Fatal(err)
	}
	details, err := source.svc.OperationDetails(source.user, payment.ID)
	if err != nil || len(details.Transactions) != 1 {
		t.Fatalf("payment details: %+v %v", details, err)
	}
	txID := details.Transactions[0].ID
	file, err := uploads.Upload(source.user, "transactions", txID, newUploadFileHeader(t, "receipt.txt", "synthetic multi-plan receipt\n"))
	if err != nil {
		t.Fatal(err)
	}
	images, _ := json.Marshal([]string{file.Path})
	imageValue := string(images)
	if _, err := source.tx.UpdateAttachments(txID, source.user, UpdateTransactionAttachmentsRequest{Images: &imageValue}); err != nil {
		t.Fatal(err)
	}
	reversal, err := source.svc.Reverse(source.user, payment.ID, DebtReverseRequest{IdempotencyKey: "receipt-undo"})
	if err != nil {
		t.Fatal(err)
	}
	old := time.Now().Add(-72 * time.Hour)
	if err := os.Chtimes(filepath.Join(sourceRoot, filepath.FromSlash(file.Path)), old, old); err != nil {
		t.Fatal(err)
	}
	if removed, err := uploads.CollectOrphanedFiles(source.user, time.Now().Add(-24*time.Hour)); err != nil || len(removed) != 0 {
		t.Fatalf("GC removed a reversed receipt: %v %v", removed, err)
	}
	backup, err := debtBackupService(source).WithUploadService(uploads).CreateBackup(source.user)
	if err != nil {
		t.Fatal(err)
	}
	target := newDebtFixture(t)
	user := model.User{Username: "receipt-restore-target", PasswordHash: "synthetic"}
	if err := target.repos.User.Create(&user); err != nil {
		t.Fatal(err)
	}
	target.user = user.ID
	targetRoot := t.TempDir()
	targetUploads := NewUploadService(&config.StorageConfig{UploadPath: targetRoot, MaxFileSize: 1}, target.repos.Account.DB())
	if err := debtBackupService(target).WithUploadService(targetUploads).RestoreBackup(target.user, writeBackupFile(t, backup)); err != nil {
		t.Fatal(err)
	}
	target.debt, target.cash, target.a, target.b = source.debt, source.cash, source.a, source.b
	debtAssert(t, target, 1000, 2000, 600, 300, 100, 0)
	var restored model.Transaction
	if err := target.repos.Account.DB().Unscoped().First(&restored, "id = ?", txID).Error; err != nil {
		t.Fatal(err)
	}
	if !restored.DeletedAt.Valid {
		t.Fatal("reversed transaction was resurrected")
	}
	var references []string
	if err := json.Unmarshal([]byte(restored.Images), &references); err != nil || len(references) != 1 {
		t.Fatalf("receipt references not restored: %s %v", restored.Images, err)
	}
	wantPrefix := fmt.Sprintf("%d/", target.user)
	if len(references[0]) < len(wantPrefix) || references[0][:len(wantPrefix)] != wantPrefix {
		t.Fatal("receipt owner was not remapped")
	}
	content, err := os.ReadFile(filepath.Join(targetRoot, filepath.FromSlash(references[0])))
	if err != nil || string(content) != "synthetic multi-plan receipt\n" {
		t.Fatalf("receipt bytes: %q %v", content, err)
	}
	replayed, err := target.svc.Reverse(target.user, payment.ID, DebtReverseRequest{IdempotencyKey: "receipt-undo"})
	if err != nil || replayed.ID != reversal.ID {
		t.Fatalf("restore lost reversal idempotency: %+v %v", replayed, err)
	}
	debtAssert(t, target, 1000, 2000, 600, 300, 100, 0)
}
