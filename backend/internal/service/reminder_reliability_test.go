package service

import (
	"errors"
	"fmt"
	"reflect"
	"testing"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/money"
	"github.com/sky/personal-ledger/internal/repository"
)

func TestReminderUndoPreservesPrincipalAndSplitCompatibility(t *testing.T) {
	for _, tc := range []struct {
		name                        string
		amount, principal, interest money.Amount
		legacy                      bool
	}{
		{"interest_only", 20, 0, 20, false},
		{"one_cent_interest", 0.01, 0, 0.01, false},
		{"principal_only", 20, 20, 0, false},
		{"mixed", 120, 100, 20, false},
		{"legacy_missing_principal", 120, 100, 20, false},
		{"legacy_missing_interest", 120, 100, 20, false},
		{"paid_off", 520, 500, 20, false},
		{"legacy_unsplit", 100, 100, 0, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			txSvc, repos, userID := newTransactionTestService(t)
			svc, _ := repaymentServices(repos)
			debt := createTypedAccountForTest(t, repos, userID, "loan", 500)
			cash := createAccountForTest(t, repos, userID, 1000)
			r, err := svc.Create(userID, CreateReminderRequest{Name: "Synthetic loan", AccountID: &debt, PaymentDay: 15})
			if err != nil {
				t.Fatal(err)
			}
			if _, err := svc.RecordPayment(r.ID, userID, RecordPaymentRequest{Amount: tc.amount, PrincipalAmount: tc.principal, InterestAmount: tc.interest, AccountID: &cash}); err != nil {
				t.Fatal(err)
			}
			id := findReminderTransactionID(t, repos, userID, r.ID)
			if tc.legacy {
				if err := repos.Transaction.DB().Model(&model.Transaction{}).Where("id = ?", id).
					Updates(map[string]any{"principal_amount_cents": 0, "interest_amount_cents": 0}).Error; err != nil {
					t.Fatal(err)
				}
			}
			column := ""
			if tc.name == "legacy_missing_principal" {
				column = "principal_amount_cents"
			} else if tc.name == "legacy_missing_interest" {
				column = "interest_amount_cents"
			}
			if column != "" {
				if err := repos.Transaction.DB().Model(&model.Transaction{}).Where("id = ?", id).Update(column, 0).Error; err != nil {
					t.Fatal(err)
				}
			}
			if err := txSvc.Delete(id, userID); err != nil {
				t.Fatal(err)
			}
			assertReliabilityAccount(t, repos, debt, 500, 0)
			assertReliabilityAccount(t, repos, cash, 1000, 0)
			after, err := svc.GetByID(r.ID, userID)
			if err != nil {
				t.Fatal(err)
			}
			if after.CurrentBalance == nil || after.CurrentBalance.Cents() != 50000 || after.TotalPaid != 0 || after.InterestPaid != 0 || after.PaidOffAt != nil {
				t.Fatalf("undo did not restore reminder: %+v", after)
			}
		})
	}
}

func TestReminderBindingChangeRejectsOutstandingPaymentHistory(t *testing.T) {
	for _, mode := range []string{"patch_rebind", "update_rebind", "patch_unlink", "update_unlink", "payment_without_transaction", "interest_only", "link_independent"} {
		t.Run(mode, func(t *testing.T) {
			txSvc, repos, userID := newTransactionTestService(t)
			svc, _ := repaymentServices(repos)
			debt := createTypedAccountForTest(t, repos, userID, "loan", 500)
			other := createTypedAccountForTest(t, repos, userID, "loan", 300)
			cash := createAccountForTest(t, repos, userID, 1000)
			balance := money.Amount(500)
			create := CreateReminderRequest{Name: "Synthetic loan", AccountID: &debt, CurrentBalance: &balance, PaymentDay: 15}
			if mode == "link_independent" {
				create.AccountID = nil
			}
			r, err := svc.Create(userID, create)
			if err != nil {
				t.Fatal(err)
			}
			pay := RecordPaymentRequest{Amount: 100, AccountID: &cash}
			if mode == "payment_without_transaction" {
				pay.AccountID = nil
			}
			if mode == "interest_only" {
				pay.InterestAmount = 100
			}
			if _, err := svc.RecordPayment(r.ID, userID, pay); err != nil {
				t.Fatal(err)
			}
			switch mode {
			case "update_rebind":
				_, err = svc.Update(r.ID, userID, CreateReminderRequest{Name: r.Name, AccountID: &other, PaymentDay: 15})
			case "update_unlink":
				_, err = svc.Update(r.ID, userID, CreateReminderRequest{Name: r.Name, PaymentDay: 15})
			case "patch_unlink":
				_, err = svc.Patch(r.ID, userID, PatchReminderRequest{AccountID: Optional[string]{Set: true, Null: true}})
			default:
				_, err = svc.Patch(r.ID, userID, PatchReminderRequest{AccountID: Optional[string]{Set: true, Value: other}})
			}
			if err == nil {
				t.Fatal("changed repayment target while outstanding payment history exists")
			}
			after, err := svc.GetByID(r.ID, userID)
			if err != nil {
				t.Fatal(err)
			}
			if mode == "link_independent" {
				if after.AccountID != nil {
					t.Fatal("independent reminder became linked")
				}
			} else if after.AccountID == nil || *after.AccountID != debt {
				t.Fatal("rejected binding change mutated reminder")
			}
			if _, err := svc.Patch(r.ID, userID, PatchReminderRequest{Name: Optional[string]{Set: true, Value: "Renamed"}}); err != nil {
				t.Fatalf("safe metadata edit rejected: %v", err)
			}
			if pay.AccountID != nil && mode != "link_independent" {
				if err := txSvc.Delete(findReminderTransactionID(t, repos, userID, r.ID), userID); err != nil {
					t.Fatalf("valid undo rejected: %v", err)
				}
				assertReliabilityAccount(t, repos, debt, 500, 0)
				assertReliabilityAccount(t, repos, other, 300, 0)
				assertReliabilityAccount(t, repos, cash, 1000, 0)
			}
		})
	}
}

func TestReminderUndoRejectsUnverifiableHistoricalEffectsAtomically(t *testing.T) {
	for _, mode := range []string{"rebound", "unlinked", "unlinked_missing_log", "missing_log", "duplicate_log", "clamped_effect", "missing_reminder", "inconsistent_split"} {
		t.Run(mode, func(t *testing.T) {
			txSvc, repos, userID := newTransactionTestService(t)
			svc, _ := repaymentServices(repos)
			db := repos.Transaction.DB()
			debt := createTypedAccountForTest(t, repos, userID, "loan", 500)
			other := createTypedAccountForTest(t, repos, userID, "loan", 300)
			cash := createAccountForTest(t, repos, userID, 1000)
			r, err := svc.Create(userID, CreateReminderRequest{Name: "Historical fixture", AccountID: &debt, PaymentDay: 15})
			if err != nil {
				t.Fatal(err)
			}
			if _, err := svc.RecordPayment(r.ID, userID, RecordPaymentRequest{Amount: 100, AccountID: &cash}); err != nil {
				t.Fatal(err)
			}
			id := findReminderTransactionID(t, repos, userID, r.ID)
			switch mode {
			case "rebound":
				err = db.Model(&model.Reminder{}).Where("id = ?", r.ID).Update("account_id", other).Error
			case "unlinked", "unlinked_missing_log":
				err = db.Model(&model.Reminder{}).Where("id = ?", r.ID).Update("account_id", nil).Error
				if err == nil && mode == "unlinked_missing_log" {
					err = db.Where("transaction_id = ? AND type = ?", id, "adjustment").Delete(&model.AccountLog{}).Error
				}
			case "missing_log":
				err = db.Where("transaction_id = ? AND type = ?", id, "adjustment").Delete(&model.AccountLog{}).Error
			case "duplicate_log":
				log := requireAccountLog(t, repos, userID, id, debt, "adjustment")
				log.ID = uuid.NewString()
				err = db.Create(log).Error
			case "clamped_effect":
				err = db.Model(&model.AccountLog{}).Where("transaction_id = ? AND type = ?", id, "adjustment").
					Update("balance_after_cents", 45000).Error
			case "missing_reminder":
				err = db.Unscoped().Delete(&model.Reminder{}, "id = ?", r.ID).Error
			case "inconsistent_split":
				err = db.Model(&model.Transaction{}).Where("id = ?", id).Update("interest_amount_cents", 1000).Error
			}
			if err != nil {
				t.Fatal(err)
			}
			var reminderBefore model.Reminder
			if mode != "missing_reminder" {
				if err := db.Unscoped().First(&reminderBefore, "id = ?", r.ID).Error; err != nil {
					t.Fatal(err)
				}
			}
			var logsBefore int64
			if err := db.Model(&model.AccountLog{}).Count(&logsBefore).Error; err != nil {
				t.Fatal(err)
			}
			if err := txSvc.Delete(id, userID); !errors.Is(err, ErrReminderRollbackUnverified) {
				t.Fatalf("ambiguous historical undo = %v, want review conflict", err)
			}
			assertReliabilityAccount(t, repos, debt, 400, 100)
			assertReliabilityAccount(t, repos, other, 300, 0)
			assertReliabilityAccount(t, repos, cash, 900, 0)
			var count, logsAfter int64
			if err := db.Model(&model.Transaction{}).Where("id = ?", id).Count(&count).Error; err != nil || count != 1 {
				t.Fatalf("transaction lost after rejected undo: count=%d err=%v", count, err)
			}
			if err := db.Model(&model.AccountLog{}).Count(&logsAfter).Error; err != nil || logsAfter != logsBefore {
				t.Fatalf("logs changed after rejected undo: before=%d after=%d err=%v", logsBefore, logsAfter, err)
			}
			if mode != "missing_reminder" {
				var reminderAfter model.Reminder
				if err := db.Unscoped().First(&reminderAfter, "id = ?", r.ID).Error; err != nil {
					t.Fatal(err)
				}
				if !reflect.DeepEqual(reminderBefore, reminderAfter) {
					t.Fatal("rejected undo changed reminder balances, totals or metadata")
				}
			}
		})
	}
}

func TestReminderMetadataEditsDoNotReconcileDivergentBalances(t *testing.T) {
	for _, mode := range []string{"patch", "update"} {
		t.Run(mode, func(t *testing.T) {
			txSvc, repos, userID := newTransactionTestService(t)
			svc, _ := repaymentServices(repos)
			debt := createTypedAccountForTest(t, repos, userID, "loan", 500)
			cash := createAccountForTest(t, repos, userID, 1000)
			r, err := svc.Create(userID, CreateReminderRequest{Name: "Synthetic loan", AccountID: &debt, PaymentDay: 15})
			if err != nil {
				t.Fatal(err)
			}
			if _, err := txSvc.Create(userID, CreateTransactionRequest{Type: "transfer", Amount: 100, AccountID: cash, ToAccountID: &debt, TransactionDate: "2026-10-18"}); err != nil {
				t.Fatal(err)
			}
			var after *model.Reminder
			if mode == "patch" {
				after, err = svc.Patch(r.ID, userID, PatchReminderRequest{Name: Optional[string]{Set: true, Value: "Renamed"}})
			} else {
				after, err = svc.Update(r.ID, userID, CreateReminderRequest{Name: "Renamed", AccountID: &debt, PaymentDay: 15})
			}
			if err != nil {
				t.Fatal(err)
			}
			if after.CurrentBalance == nil || *after.CurrentBalance != 500 {
				t.Fatalf("metadata edit silently reconciled historical balance: %v", after.CurrentBalance)
			}
			if _, err := svc.RecordPayment(r.ID, userID, RecordPaymentRequest{Amount: 100, AccountID: &cash}); !errors.Is(err, ErrReminderBalanceConflict) {
				t.Fatalf("payment after metadata edit = %v, want balance conflict", err)
			}
		})
	}
}

func TestIndependentPrincipalUndoRequiresHistoricalTargetReview(t *testing.T) {
	txSvc, repos, userID := newTransactionTestService(t)
	svc, _ := repaymentServices(repos)
	cash := createAccountForTest(t, repos, userID, 1000)
	balance := money.Amount(500)
	r, err := svc.Create(userID, CreateReminderRequest{Name: "Independent", PaymentDay: 15, CurrentBalance: &balance})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := svc.RecordPayment(r.ID, userID, RecordPaymentRequest{Amount: 100, AccountID: &cash}); err != nil {
		t.Fatal(err)
	}
	if err := txSvc.Delete(findReminderTransactionID(t, repos, userID, r.ID), userID); !errors.Is(err, ErrReminderRollbackUnverified) {
		t.Fatalf("unverifiable target undo = %v, want explicit review conflict", err)
	}
	assertReliabilityAccount(t, repos, cash, 900, 0)
}

func TestReminderBindingGuardChecksActiveTransactionsAndAllowsCompletedUndo(t *testing.T) {
	for _, zeroTotals := range []bool{false, true} {
		t.Run(fmt.Sprint(zeroTotals), func(t *testing.T) {
			txSvc, repos, userID := newTransactionTestService(t)
			svc, _ := repaymentServices(repos)
			debt := createTypedAccountForTest(t, repos, userID, "loan", 500)
			other := createTypedAccountForTest(t, repos, userID, "loan", 300)
			cash := createAccountForTest(t, repos, userID, 1000)
			r, err := svc.Create(userID, CreateReminderRequest{Name: "Synthetic loan", AccountID: &debt, PaymentDay: 15})
			if err != nil {
				t.Fatal(err)
			}
			if _, err := svc.RecordPayment(r.ID, userID, RecordPaymentRequest{Amount: 100, AccountID: &cash}); err != nil {
				t.Fatal(err)
			}
			change := PatchReminderRequest{AccountID: Optional[string]{Set: true, Value: other}}
			if zeroTotals {
				if err := repos.Transaction.DB().Model(&model.Reminder{}).Where("id = ?", r.ID).Update("total_paid_cents", 0).Error; err != nil {
					t.Fatal(err)
				}
				if _, err := svc.Patch(r.ID, userID, change); !errors.Is(err, ErrReminderPaymentHistory) {
					t.Fatalf("active repayment guard = %v", err)
				}
			} else {
				if err := txSvc.Delete(findReminderTransactionID(t, repos, userID, r.ID), userID); err != nil {
					t.Fatal(err)
				}
				after, err := svc.Patch(r.ID, userID, change)
				if err != nil || after.AccountID == nil || *after.AccountID != other {
					t.Fatalf("fully reversed payments blocked binding change: %+v, %v", after, err)
				}
			}
		})
	}
}

func TestReminderPaymentRejectsDivergentBalancesWithoutRewritingHistory(t *testing.T) {
	for _, amount := range []money.Amount{100, 500} {
		t.Run(fmt.Sprintf("%.2f", amount.Float64()), func(t *testing.T) {
			txSvc, repos, userID := newTransactionTestService(t)
			svc, _ := repaymentServices(repos)
			debt := createTypedAccountForTest(t, repos, userID, "loan", 500)
			cash := createAccountForTest(t, repos, userID, 1000)
			r, err := svc.Create(userID, CreateReminderRequest{Name: "Synthetic loan", AccountID: &debt, PaymentDay: 15})
			if err != nil {
				t.Fatal(err)
			}
			transfer, err := txSvc.Create(userID, CreateTransactionRequest{Type: "transfer", Amount: 100, AccountID: cash, ToAccountID: &debt, TransactionDate: "2026-10-18T10:00:00+08:00"})
			if err != nil {
				t.Fatal(err)
			}
			if _, err := svc.RecordPayment(r.ID, userID, RecordPaymentRequest{Amount: amount, AccountID: &cash, IdempotencyKey: "divergent"}); err == nil {
				t.Fatal("payment accepted against divergent account/reminder balances")
			}
			assertReliabilityAccount(t, repos, debt, 400, 0)
			assertReliabilityAccount(t, repos, cash, 900, 0)
			after, err := svc.GetByID(r.ID, userID)
			if err != nil || after.CurrentBalance == nil || *after.CurrentBalance != 500 || after.TotalPaid != 0 {
				t.Fatalf("rejection rewrote reminder: %+v, %v", after, err)
			}
			if err := txSvc.Delete(transfer.ID, userID); err != nil {
				t.Fatal(err)
			}
			if _, err := svc.RecordPayment(r.ID, userID, RecordPaymentRequest{Amount: amount, AccountID: &cash, IdempotencyKey: "divergent"}); err != nil {
				t.Fatalf("failed request consumed idempotency key: %v", err)
			}
			if err := txSvc.Delete(findReminderTransactionID(t, repos, userID, r.ID), userID); err != nil {
				t.Fatal(err)
			}
			assertReliabilityAccount(t, repos, debt, 500, 0)
			assertReliabilityAccount(t, repos, cash, 1000, 0)
		})
	}
}

func assertReliabilityAccount(t *testing.T, repos *repository.Repositories, id string, balance, paid money.Amount) {
	t.Helper()
	account, err := repos.Account.GetByID(id)
	if err != nil {
		t.Fatal(err)
	}
	assertFloatEqual(t, "balance", account.CurrentBalance, balance)
	assertFloatEqual(t, "total paid", account.TotalPaid, paid)
}
