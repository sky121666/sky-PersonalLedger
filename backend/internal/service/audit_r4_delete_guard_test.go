package service

import (
	"bytes"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"gorm.io/gorm"
)

type auditR4Fixture struct {
	txSvc       *TransactionService
	lendingSvc  *LendingService
	accountSvc  *AccountService
	repos       *repository.Repositories
	userID      uint
	accountID   string
	lendingID   string
	initialID   string
	repaymentID string
}

type auditR4State struct {
	Stage                        string `json:"stage"`
	CashCents                    int64  `json:"cash_cents"`
	PrincipalCents               int64  `json:"principal_cents"`
	LendingCents                 int64  `json:"lending_cents"`
	TotalRepaidCents             int64  `json:"total_repaid_cents"`
	IsSettled                    bool   `json:"is_settled"`
	HasSettledAt                 bool   `json:"has_settled_at"`
	LendingSoftDeleted           bool   `json:"lending_soft_deleted"`
	ActiveLendings               int    `json:"active_lendings"`
	ActiveRecords                int    `json:"active_records"`
	RecordsIncludingDeleted      int64  `json:"records_including_deleted"`
	ActiveTransactions           int    `json:"active_transactions"`
	TransactionsIncludingDeleted int64  `json:"transactions_including_deleted"`
	ReceivableCents              int64  `json:"receivable_cents"`
	PayableCents                 int64  `json:"payable_cents"`
	AccountLogs                  int64  `json:"account_logs"`
}

// Restrict UUID ordering at generation time; never rewrite stored IDs or balances.
// These tests are serial, and the standard random source is restored after each call.
func auditR4UUIDPrefix(prefix byte) func() {
	if prefix == 0 {
		return func() {}
	}
	data := make([]byte, 16*64)
	for i := 0; i < 64; i++ {
		data[16*i] = prefix
		data[16*i+15] = byte(i + 1)
	}
	uuid.SetRand(bytes.NewReader(data))
	return func() { uuid.SetRand(nil) }
}

func newAuditR4Fixture(t *testing.T, lendingType, idOrder string, repaymentTransaction bool) *auditR4Fixture {
	t.Helper()
	txSvc, repos, userID := newTransactionTestService(t)
	sqlDB, err := repos.Transaction.DB().DB()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = sqlDB.Close() })
	var dbs []struct{ Name, File string }
	if err := repos.Transaction.DB().Raw("PRAGMA database_list").Scan(&dbs).Error; err != nil {
		t.Fatal(err)
	}
	// Match testing.T.TempDir's platform fallback when TMPDIR is unset (for example, Linux CI).
	tmpDir, err := filepath.EvalSymlinks(os.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	for _, db := range dbs {
		if db.Name == "main" {
			dbFile, err := filepath.EvalSymlinks(db.File)
			if err != nil {
				t.Fatal(err)
			}
			rel, err := filepath.Rel(tmpDir, dbFile)
			if err != nil || filepath.IsAbs(rel) || rel == ".." || strings.HasPrefix(rel, ".."+string(os.PathSeparator)) {
				t.Fatalf("database escaped isolated TMPDIR: %q", db.File)
			}
			t.Logf("R4_DATABASE %s", db.File)
		}
	}
	f := &auditR4Fixture{
		txSvc: txSvc, lendingSvc: newLendingTestService(repos),
		accountSvc: NewAccountService(repos.Account), repos: repos, userID: userID,
	}
	account, err := f.accountSvc.Create(userID, CreateAccountRequest{
		Name: "R4 synthetic cash", Type: "cash", InitialBalance: 1000,
	})
	if err != nil {
		t.Fatal(err)
	}
	f.accountID = account.ID
	var initialPrefix, repaymentPrefix byte
	switch idOrder {
	case "initial_id_first":
		initialPrefix, repaymentPrefix = 0x10, 0xf0
	case "repayment_id_first":
		initialPrefix, repaymentPrefix = 0xf0, 0x10
	case "natural":
	default:
		t.Fatalf("unknown ID order %q", idOrder)
	}
	var lending *model.Lending
	func() {
		defer auditR4UUIDPrefix(initialPrefix)()
		lending, err = f.lendingSvc.Create(userID, CreateLendingRequest{
			Type: lendingType, ContactName: "R4 synthetic contact", Principal: 100,
			LendDate:  "2026-10-01T10:00:00+08:00",
			AccountID: &f.accountID, CreateTransaction: true,
		})
	}()
	if err != nil {
		t.Fatal(err)
	}
	f.lendingID = lending.ID
	ids := findLendingTransactionIDs(t, repos, userID, lending.ID)
	if len(ids) != 1 {
		t.Fatalf("initial transaction count = %d, want 1", len(ids))
	}
	f.initialID = ids[0]
	cashAfterInitial := int64(90000)
	cashAfterRepayment := int64(94000)
	if lendingType == "borrow_in" {
		cashAfterInitial, cashAfterRepayment = 110000, 106000
	}
	auditR4AssertMoney(t, f.snapshot(t, "after_initial_100"), cashAfterInitial, 10000, 0, 0, 1)
	func() {
		defer auditR4UUIDPrefix(repaymentPrefix)()
		_, err = f.lendingSvc.RecordRepayment(lending.ID, userID, RecordRepaymentRequest{
			Amount: 40, RecordDate: "2026-10-02T10:00:00+08:00",
			AccountID: &f.accountID, CreateTransaction: repaymentTransaction,
		})
	}()
	if err != nil {
		t.Fatal(err)
	}
	record := requireSingleLendingRecord(t, repos, lending.ID)
	if repaymentTransaction && record.TransactionID == nil {
		t.Fatal("repayment has no generated transaction")
	}
	if record.TransactionID != nil {
		f.repaymentID = *record.TransactionID
	}
	if repaymentTransaction && idOrder != "natural" && (f.initialID < f.repaymentID) != (idOrder == "initial_id_first") {
		t.Fatalf("UUID order control failed: initial=%s repayment=%s", f.initialID, f.repaymentID)
	}
	t.Logf("R4_IDS initial=%s repayment=%s id_order=%s", f.initialID, f.repaymentID, idOrder)
	txCount := 2
	if !repaymentTransaction {
		cashAfterRepayment, txCount = cashAfterInitial, 1
	}
	auditR4AssertMoney(t, f.snapshot(t, "after_repayment_40"), cashAfterRepayment, 6000, 4000, 1, txCount)
	if t.Failed() {
		t.Fatal("setup invariants failed")
	}
	return f
}

func (f *auditR4Fixture) snapshot(t *testing.T, stage string) auditR4State {
	t.Helper()
	account, err := f.accountSvc.GetByID(f.accountID, f.userID)
	if err != nil {
		t.Fatal(err)
	}
	var lending model.Lending
	if err := f.repos.Transaction.DB().Unscoped().
		First(&lending, "id = ? AND user_id = ?", f.lendingID, f.userID).Error; err != nil {
		t.Fatal(err)
	}
	records, err := f.repos.Lending.GetRecordsByLendingID(f.lendingID)
	if err != nil {
		t.Fatal(err)
	}
	summary, err := f.lendingSvc.GetSummary(f.userID)
	if err != nil {
		t.Fatal(err)
	}
	s := auditR4State{
		Stage: stage, CashCents: account.CurrentBalance.Cents(),
		PrincipalCents: lending.Principal.Cents(), LendingCents: lending.CurrentBalance.Cents(),
		TotalRepaidCents: lending.TotalRepaid.Cents(), IsSettled: lending.IsSettled,
		HasSettledAt: lending.SettledAt != nil, LendingSoftDeleted: lending.DeletedAt.Valid,
		ActiveLendings:     summary.ActiveLendOut + summary.ActiveBorrowIn,
		ActiveRecords:      len(records),
		ActiveTransactions: len(findLendingTransactionIDs(t, f.repos, f.userID, f.lendingID)),
		ReceivableCents:    summary.TotalReceivable.Cents(), PayableCents: summary.TotalPayable.Cents(),
	}
	// Read-only counts distinguish live residue from expected soft-deleted history.
	if err := f.repos.Transaction.DB().Unscoped().Model(&model.LendingRecord{}).
		Where("lending_id = ? AND user_id = ?", f.lendingID, f.userID).
		Count(&s.RecordsIncludingDeleted).Error; err != nil {
		t.Fatal(err)
	}
	if err := f.repos.Transaction.DB().Unscoped().Model(&model.Transaction{}).
		Where("lending_id = ? AND user_id = ?", f.lendingID, f.userID).
		Count(&s.TransactionsIncludingDeleted).Error; err != nil {
		t.Fatal(err)
	}
	if err := f.repos.Transaction.DB().Model(&model.AccountLog{}).
		Where("account_id = ? AND user_id = ?", f.accountID, f.userID).
		Count(&s.AccountLogs).Error; err != nil {
		t.Fatal(err)
	}
	data, err := json.Marshal(s)
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("R4_STATE %s", data)
	return s
}

func auditR4AssertRejectedUnchanged(t *testing.T, f *auditR4Fixture, action func() error) {
	t.Helper()
	before := f.snapshot(t, "before_rejection")
	err := action()
	after := f.snapshot(t, "after_rejection")
	if !errors.Is(err, ErrLendingInitialHasRepayments) {
		t.Errorf("initial lending deletion with repayments must be rejected with ErrLendingInitialHasRepayments; got %v", err)
	}
	before.Stage, after.Stage = "", ""
	if !reflect.DeepEqual(before, after) {
		t.Errorf("rejected deletion changed financial state: before=%+v after=%+v", before, after)
	}
}

func TestAuditR4InitialDeleteGuardAndSafeReverseOrder(t *testing.T) {
	for _, lendingType := range []string{"lend_out", "borrow_in"} {
		for _, archived := range []bool{false, true} {
			name := lendingType + "/active"
			if archived {
				name = lendingType + "/archived"
			}
			t.Run(name, func(t *testing.T) {
				f := newAuditR4Fixture(t, lendingType, "natural", true)
				if archived {
					if err := f.lendingSvc.Delete(f.lendingID, f.userID); err != nil {
						t.Fatal(err)
					}
				}
				auditR4AssertRejectedUnchanged(t, f, func() error {
					return f.txSvc.Delete(f.initialID, f.userID)
				})
				if t.Failed() {
					return
				}
				if err := f.txSvc.Delete(f.repaymentID, f.userID); err != nil {
					t.Fatalf("safe repayment deletion: %v", err)
				}
				if err := f.txSvc.Delete(f.initialID, f.userID); err != nil {
					t.Fatalf("initial deletion after repayment reversal: %v", err)
				}
				final := f.snapshot(t, "safe_reverse_order")
				auditR4AssertMoney(t, final, 100000, 0, 0, 0, 0)
				if final.LendingSoftDeleted != archived || final.IsSettled || final.HasSettledAt {
					t.Fatalf("deletion must not cancel, settle or resurrect the Lending: %+v", final)
				}
			})
		}
	}
}

func TestAuditR4BatchGuardIsIndependentOfIDAndInputOrder(t *testing.T) {
	for _, lendingType := range []string{"lend_out", "borrow_in"} {
		for _, idOrder := range []string{"initial_id_first", "repayment_id_first"} {
			for _, reverseInput := range []bool{false, true} {
				name := lendingType + "/" + idOrder + "/input_initial_first"
				if reverseInput {
					name = lendingType + "/" + idOrder + "/input_repayment_first"
				}
				t.Run(name, func(t *testing.T) {
					f := newAuditR4Fixture(t, lendingType, idOrder, true)
					ids := []string{f.initialID, f.repaymentID}
					if reverseInput {
						ids[0], ids[1] = ids[1], ids[0]
					}
					ordered := append([]string(nil), ids...)
					sort.Strings(ordered)
					t.Logf("R4_BATCH input=%v sorted=%v", ids, ordered)
					auditR4AssertRejectedUnchanged(t, f, func() error {
						return f.txSvc.DeleteBatch(ids, f.userID)
					})
				})
			}
		}
	}
}

func TestAuditR4GuardRepaymentWithoutCashTransaction(t *testing.T) {
	for _, lendingType := range []string{"lend_out", "borrow_in"} {
		t.Run(lendingType, func(t *testing.T) {
			f := newAuditR4Fixture(t, lendingType, "natural", false)
			auditR4AssertRejectedUnchanged(t, f, func() error {
				return f.txSvc.Delete(f.initialID, f.userID)
			})
			auditR4AssertRejectedUnchanged(t, f, func() error {
				return f.txSvc.DeleteBatch([]string{f.initialID}, f.userID)
			})
		})
	}
}

func TestAuditR4GuardInconsistentHistoricalRepaymentState(t *testing.T) {
	for _, lendingType := range []string{"lend_out", "borrow_in"} {
		for _, state := range []string{"records_missing", "records_soft_deleted", "total_missing"} {
			t.Run(lendingType+"/"+state, func(t *testing.T) {
				f := newAuditR4Fixture(t, lendingType, "natural", true)
				r := f.repos
				backupSvc := NewBackupService(r.Transaction.DB(), r.Account, r.Category, r.Transaction,
					r.Budget, r.Reminder, r.Lending, r.Template, r.Notification, r.Tag, r.User, r.FamilyMember, r.AIReport)
				backup, err := backupSvc.CreateBackup(f.userID)
				if err != nil {
					t.Fatal(err)
				}
				// Import a synthetic legacy snapshot through the public service, never SQL edits.
				switch state {
				case "records_missing":
					backup.LendingRecords = nil
				case "records_soft_deleted":
					backup.LendingRecords[0].DeletedAt = gorm.DeletedAt{Time: time.Now(), Valid: true}
				case "total_missing":
					backup.Lendings[0].TotalRepaid = 0
				}
				if err := backupSvc.RestoreBackup(f.userID, writeBackupFile(t, backup)); err != nil {
					t.Fatalf("restore synthetic legacy fixture: %v", err)
				}
				auditR4AssertRejectedUnchanged(t, f, func() error {
					return f.txSvc.Delete(f.initialID, f.userID)
				})
				auditR4AssertRejectedUnchanged(t, f, func() error {
					return f.txSvc.DeleteBatch([]string{f.initialID, f.repaymentID}, f.userID)
				})
			})
		}
	}
}

func TestAuditR4BatchAtomicityAndSafePaths(t *testing.T) {
	for _, lendingType := range []string{"lend_out", "borrow_in"} {
		t.Run(lendingType, func(t *testing.T) {
			f := newAuditR4Fixture(t, lendingType, "repayment_id_first", true)
			ordinary, err := f.txSvc.Create(f.userID, CreateTransactionRequest{
				Type: "expense", Amount: 7, AccountID: f.accountID, TransactionDate: "2026-10-03",
			})
			if err != nil {
				t.Fatal(err)
			}
			auditR4AssertRejectedUnchanged(t, f, func() error {
				return f.txSvc.DeleteBatch([]string{ordinary.ID, f.repaymentID, f.initialID, f.initialID}, f.userID)
			})
			for _, ids := range [][]string{{f.repaymentID, f.repaymentID}, {f.repaymentID, "missing"}} {
				before := f.snapshot(t, "before_invalid_batch")
				err := f.txSvc.DeleteBatch(ids, f.userID)
				after := f.snapshot(t, "after_invalid_batch")
				if !errors.Is(err, ErrTransactionNotFound) {
					t.Errorf("duplicate/missing IDs must retain existing not-found contract: %v", err)
				}
				before.Stage, after.Stage = "", ""
				if !reflect.DeepEqual(before, after) {
					t.Errorf("invalid batch changed balances, records or audit logs")
				}
			}
			if t.Failed() {
				return
			}
			if err := f.txSvc.DeleteBatch([]string{f.repaymentID, ordinary.ID}, f.userID); err != nil {
				t.Fatalf("safe repayment and ordinary transaction batch: %v", err)
			}
			if err := f.txSvc.DeleteBatch([]string{f.initialID}, f.userID); err != nil {
				t.Fatalf("safe initial-only batch after repayment reversal: %v", err)
			}
			auditR4AssertMoney(t, f.snapshot(t, "safe_batch_path"), 100000, 0, 0, 0, 0)
		})
	}
}

func auditR4AssertMoney(t *testing.T, s auditR4State, cash, balance, repaid int64, records, transactions int) {
	t.Helper()
	if s.CashCents != cash || s.LendingCents != balance || s.TotalRepaidCents != repaid ||
		s.ActiveRecords != records || s.ActiveTransactions != transactions {
		t.Errorf("rollback invariant at %s: cash=%d lending=%d repaid=%d records=%d tx=%d; want cash=%d lending=%d repaid=%d records=%d tx=%d (money in cents)",
			s.Stage, s.CashCents, s.LendingCents, s.TotalRepaidCents, s.ActiveRecords, s.ActiveTransactions,
			cash, balance, repaid, records, transactions)
	}
}
