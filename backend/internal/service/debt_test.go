package service

import (
	"errors"
	"sync"
	"testing"

	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/money"
	"github.com/sky/personal-ledger/internal/repository"
	"gorm.io/gorm"
)

type debtFixture struct {
	svc   *DebtService
	tx    *TransactionService
	repos *repository.Repositories
	user  uint
	debt  string
	cash  string
	a, b  string
}

func newDebtFixture(t *testing.T) debtFixture {
	t.Helper()
	tx, repos, user := newTransactionTestService(t)
	account, err := NewAccountService(repos.Account).Create(user, CreateAccountRequest{
		Name: "Synthetic managed card", Type: "credit", InitialBalance: 1000, DebtTrackingMode: model.DebtModeManaged,
	})
	if err != nil {
		t.Fatal(err)
	}
	f := debtFixture{svc: NewDebtService(repos.Account.DB()), tx: tx, repos: repos, user: user, debt: account.ID,
		cash: createAccountForTest(t, repos, user, 2000)}
	for i, amount := range []money.Amount{600, 300} {
		plan, err := f.svc.CreatePlan(user, CreateDebtPlanRequest{
			Name: "Synthetic plan", Scope: "account", AccountID: &f.debt, OriginalPrincipal: amount,
			OpeningPrincipal: amount, IdempotencyKey: []string{"open-A", "open-B"}[i],
		})
		if err != nil {
			t.Fatal(err)
		}
		if i == 0 {
			f.a = plan.ID
		} else {
			f.b = plan.ID
		}
	}
	debtAssert(t, f, 1000, 2000, 600, 300, 100, 0)
	return f
}

func debtAssert(t *testing.T, f debtFixture, debt, cash, a, b, other, pending money.Amount) {
	t.Helper()
	account, err := f.repos.Account.GetByID(f.debt)
	if err != nil {
		t.Fatal(err)
	}
	source, err := f.repos.Account.GetByID(f.cash)
	if err != nil {
		t.Fatal(err)
	}
	pa, err := f.svc.GetPlan(f.user, f.a)
	if err != nil {
		t.Fatal(err)
	}
	pb, err := f.svc.GetPlan(f.user, f.b)
	if err != nil {
		t.Fatal(err)
	}
	for _, x := range []struct {
		name      string
		got, want money.Amount
	}{
		{"debt", account.CurrentBalance, debt}, {"cash", source.CurrentBalance, cash},
		{"A", pa.PrincipalBalance, a}, {"B", pb.PrincipalBalance, b},
		{"unplanned", account.UnplannedDebt, other}, {"unapplied", account.UnappliedPayment, pending},
	} {
		if x.got.Cents() != x.want.Cents() {
			t.Errorf("%s = %v, want %v", x.name, x.got, x.want)
		}
	}
	if err := f.svc.CheckAccount(f.user, f.debt); err != nil {
		t.Fatalf("account does not reconcile: %v", err)
	}
}

func TestDebtPaymentAllocationReallocationAndExactReversal(t *testing.T) {
	f := newDebtFixture(t)
	req := DebtPaymentRequest{AccountID: &f.debt, SourceKind: "account", SourceAccountID: &f.cash,
		Amount: 120, UnappliedAmount: 10, IdempotencyKey: "payment",
		Allocations: []DebtPaymentPart{{PlanID: f.a, Principal: 60, CashInterest: 10}, {PlanID: f.b, Principal: 40}}}
	payment, err := f.svc.Pay(f.user, req)
	if err != nil {
		t.Fatal(err)
	}
	debtAssert(t, f, 890, 1880, 540, 260, 100, 10)
	replay, err := f.svc.Pay(f.user, req)
	if err != nil || replay.ID != payment.ID {
		t.Fatalf("payment replay = %v, %v", replay, err)
	}
	debtAssert(t, f, 890, 1880, 540, 260, 100, 10)
	allocation, err := f.svc.Allocate(f.user, payment.ID, DebtAllocateRequest{
		Allocations: []DebtPaymentPart{{PlanID: f.b, Principal: 10}}, IdempotencyKey: "allocate",
	})
	if err != nil {
		t.Fatal(err)
	}
	debtAssert(t, f, 890, 1880, 540, 250, 100, 0)
	if _, err := f.svc.Allocate(f.user, payment.ID, DebtAllocateRequest{
		ReplaceOperationID: allocation.ID, Allocations: []DebtPaymentPart{{PlanID: f.a, Principal: 10}}, IdempotencyKey: "reallocate",
	}); err != nil {
		t.Fatal(err)
	}
	debtAssert(t, f, 890, 1880, 530, 260, 100, 0)
	if _, err := f.tx.Create(f.user, CreateTransactionRequest{
		Type: "expense", AccountID: f.cash, Amount: 7, TransactionDate: "2026-10-18",
	}); err != nil {
		t.Fatal(err)
	}
	reversal, err := f.svc.Reverse(f.user, payment.ID, DebtReverseRequest{IdempotencyKey: "reverse"})
	if err != nil {
		t.Fatal(err)
	}
	debtAssert(t, f, 1000, 1993, 600, 300, 100, 0)
	replayed, err := f.svc.Reverse(f.user, payment.ID, DebtReverseRequest{IdempotencyKey: "reverse"})
	if err != nil || replayed.ID != reversal.ID {
		t.Fatalf("reverse replay = %v %v", replayed, err)
	}
	plan, _ := f.svc.GetPlan(f.user, f.a)
	if plan.InterestPaid != 0 {
		t.Fatalf("interest not reversed: %v", plan.InterestPaid)
	}
}

func TestDebtInterestModesAreNotChargedTwice(t *testing.T) {
	for _, booked := range []bool{false, true} {
		t.Run(map[bool]string{false: "cash-only", true: "already-booked"}[booked], func(t *testing.T) {
			f := newDebtFixture(t)
			part := DebtPaymentPart{PlanID: f.a, CashInterest: 20}
			if booked {
				if _, err := f.svc.BookInterest(f.user, f.a, DebtInterestRequest{Amount: 20, IdempotencyKey: "interest"}); err != nil {
					t.Fatal(err)
				}
				part.CashInterest, part.BookedInterest = 0, 20
			}
			op, err := f.svc.Pay(f.user, DebtPaymentRequest{AccountID: &f.debt, SourceKind: "account", SourceAccountID: &f.cash,
				Amount: 20, Allocations: []DebtPaymentPart{part}, IdempotencyKey: "interest-payment"})
			if err != nil {
				t.Fatal(err)
			}
			debtAssert(t, f, 1000, 1980, 600, 300, 100, 0)
			var expense money.Amount
			if err := f.repos.Account.DB().Model(&model.Transaction{}).
				Select("COALESCE(SUM(amount_cents),0)").Where("user_id = ? AND source = ?", f.user, "debt_interest").Scan(&expense).Error; err != nil {
				t.Fatal(err)
			}
			if expense != 20 {
				t.Fatalf("interest expense = %v, want exactly 20", expense)
			}
			if _, err := f.svc.Reverse(f.user, op.ID, DebtReverseRequest{IdempotencyKey: "undo-interest"}); err != nil {
				t.Fatal(err)
			}
			want := money.Amount(1000)
			if booked {
				want = 1020
			}
			debtAssert(t, f, want, 2000, 600, 300, 100, 0)
		})
	}
}

func TestDebtPaymentFailurePreservesAllState(t *testing.T) {
	for _, kind := range []string{"sum", "overpayment", "foreign-plan", "same-account", "missing-source", "legacy-target"} {
		t.Run(kind, func(t *testing.T) {
			f := newDebtFixture(t)
			req := DebtPaymentRequest{AccountID: &f.debt, SourceKind: "account", SourceAccountID: &f.cash, Amount: 10,
				Allocations: []DebtPaymentPart{{PlanID: f.a, Principal: 10}}, IdempotencyKey: "invalid"}
			switch kind {
			case "sum":
				req.Amount = 11
			case "overpayment":
				req.Amount, req.Allocations[0].Principal = 601, 601
			case "foreign-plan":
				req.Allocations[0].PlanID = "someone-elses-plan"
			case "same-account":
				req.SourceAccountID = &f.debt
			case "missing-source":
				req.SourceAccountID = nil
			case "legacy-target":
				legacy := createTypedAccountForTest(t, f.repos, f.user, "credit", 1000)
				req.AccountID = &legacy
			}
			var before int64
			f.repos.Account.DB().Model(&model.DebtOperation{}).Count(&before)
			if _, err := f.svc.Pay(f.user, req); err == nil {
				t.Fatal("unsafe payment succeeded")
			}
			var after int64
			f.repos.Account.DB().Model(&model.DebtOperation{}).Count(&after)
			if after != before {
				t.Fatalf("failed payment left operation: %d -> %d", before, after)
			}
			debtAssert(t, f, 1000, 2000, 600, 300, 100, 0)
		})
	}
}

func TestDebtPaymentRejectsDifferentPayloadForSameKey(t *testing.T) {
	f := newDebtFixture(t)
	req := DebtPaymentRequest{AccountID: &f.debt, SourceKind: "account", SourceAccountID: &f.cash, Amount: 10,
		Allocations: []DebtPaymentPart{{PlanID: f.a, Principal: 10}}, IdempotencyKey: "same-key"}
	if _, err := f.svc.Pay(f.user, req); err != nil {
		t.Fatal(err)
	}
	req.Amount, req.Allocations[0].Principal = 20, 20
	if _, err := f.svc.Pay(f.user, req); !errors.Is(err, ErrIdempotencyConflict) {
		t.Fatalf("changed retry = %v", err)
	}
	debtAssert(t, f, 990, 1990, 590, 300, 100, 0)
}

func TestDebtOrdinaryTransferCanBeAllocatedWithoutSecondDebit(t *testing.T) {
	f := newDebtFixture(t)
	transfer, err := f.tx.Create(f.user, CreateTransactionRequest{Type: "transfer", AccountID: f.cash,
		ToAccountID: &f.debt, Amount: 80, TransactionDate: "2026-10-18"})
	if err != nil {
		t.Fatal(err)
	}
	if transfer.DebtOperationID == nil {
		t.Fatal("transfer has no immutable repayment identity")
	}
	debtAssert(t, f, 920, 1920, 600, 300, 100, 80)
	if _, err := f.svc.Allocate(f.user, *transfer.DebtOperationID, DebtAllocateRequest{IdempotencyKey: "split-transfer",
		Allocations: []DebtPaymentPart{{PlanID: f.a, Principal: 20}, {PlanID: f.b, Principal: 30}}, UnplannedAmount: 30}); err != nil {
		t.Fatal(err)
	}
	debtAssert(t, f, 920, 1920, 580, 270, 70, 0)
	if err := f.tx.Delete(transfer.ID, f.user); !errors.Is(err, ErrManagedTransactionImmutable) {
		t.Fatalf("ordinary delete bypassed operation: %v", err)
	}
	if _, err := f.svc.Reverse(f.user, *transfer.DebtOperationID, DebtReverseRequest{IdempotencyKey: "undo-transfer"}); err != nil {
		t.Fatal(err)
	}
	debtAssert(t, f, 1000, 2000, 600, 300, 100, 0)
}

func TestDebtReversalRejectsMissingAccountEffectAtomically(t *testing.T) {
	f := newDebtFixture(t)
	payment, err := f.svc.Pay(f.user, DebtPaymentRequest{AccountID: &f.debt, SourceKind: "account", SourceAccountID: &f.cash,
		Amount: 10, Allocations: []DebtPaymentPart{{PlanID: f.a, Principal: 10}}, IdempotencyKey: "missing-proof"})
	if err != nil {
		t.Fatal(err)
	}
	if err := f.repos.Account.DB().Where("debt_operation_id = ? AND account_id = ?", payment.ID, f.cash).
		Delete(&model.AccountLog{}).Error; err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.Reverse(f.user, payment.ID, DebtReverseRequest{IdempotencyKey: "unsafe-undo"}); err == nil {
		t.Fatal("partial financial evidence accepted")
	}
	debtAssert(t, f, 990, 1990, 590, 300, 100, 0)
}

func TestDebtPlanListAndStandalonePayment(t *testing.T) {
	f := newDebtFixture(t)
	plans, err := f.svc.ListPlans(f.user, f.debt)
	if err != nil || len(plans) != 2 {
		t.Fatalf("plan list = %d, %v", len(plans), err)
	}
	standalone, err := f.svc.CreatePlan(f.user, CreateDebtPlanRequest{Name: "Independent", Scope: "standalone",
		OriginalPrincipal: 40, OpeningPrincipal: 40, IdempotencyKey: "independent"})
	if err != nil {
		t.Fatal(err)
	}
	payment, err := f.svc.Pay(f.user, DebtPaymentRequest{StandalonePlanID: &standalone.ID, SourceKind: "account",
		SourceAccountID: &f.cash, Amount: 12, IdempotencyKey: "independent-pay",
		Allocations: []DebtPaymentPart{{PlanID: standalone.ID, Principal: 10, CashInterest: 2}}})
	if err != nil {
		t.Fatal(err)
	}
	after, _ := f.svc.GetPlan(f.user, standalone.ID)
	if after.PrincipalBalance != 30 || after.InterestPaid != 2 {
		t.Fatalf("independent payment = %+v", after)
	}
	if _, err := f.svc.Reverse(f.user, payment.ID, DebtReverseRequest{IdempotencyKey: "independent-undo"}); err != nil {
		t.Fatal(err)
	}
	after, _ = f.svc.GetPlan(f.user, standalone.ID)
	if after.PrincipalBalance != 40 || after.InterestPaid != 0 {
		t.Fatalf("independent reversal = %+v", after)
	}
	debtAssert(t, f, 1000, 2000, 600, 300, 100, 0)
}

func TestDebtConcurrentRetryOnlyDebitsOnce(t *testing.T) {
	f := newDebtFixture(t)
	req := DebtPaymentRequest{AccountID: &f.debt, SourceKind: "account", SourceAccountID: &f.cash, Amount: 10,
		Allocations: []DebtPaymentPart{{PlanID: f.a, Principal: 10}}, IdempotencyKey: "concurrent"}
	var wg sync.WaitGroup
	results := make(chan string, 6)
	for i := 0; i < 6; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			op, err := f.svc.Pay(f.user, req)
			if err != nil {
				t.Error(err)
				return
			}
			results <- op.ID
		}()
	}
	wg.Wait()
	close(results)
	id := ""
	for actual := range results {
		if id != "" && actual != id {
			t.Fatal("concurrent retry created multiple payments")
		}
		id = actual
	}
	debtAssert(t, f, 990, 1990, 590, 300, 100, 0)
}

func TestDebtUnclassifiedCreditPreservesCashFactAndBlocksAllocation(t *testing.T) {
	f := newDebtFixture(t)
	refund, err := f.tx.Create(f.user, CreateTransactionRequest{Type: "income", AccountID: f.debt,
		Amount: 5, TransactionDate: "2026-10-18"})
	if err != nil {
		t.Fatal(err)
	}
	account, _ := f.repos.Account.GetByID(f.debt)
	if account.CurrentBalance != 995 || account.DebtUnclassified != -5 || account.UnplannedDebt != 100 {
		t.Fatalf("unclassified credit was silently assigned or dropped: %+v", account)
	}
	if _, err := f.svc.Pay(f.user, DebtPaymentRequest{AccountID: &f.debt, SourceKind: "account",
		SourceAccountID: &f.cash, Amount: 1, UnappliedAmount: 1, IdempotencyKey: "review-block"}); !errors.Is(err, ErrDebtReconciliation) {
		t.Fatalf("unclassified account accepted a new payment: %v", err)
	}
	if refund.DebtOperationID == nil {
		t.Fatal("missing correction evidence")
	}
	if _, err := f.svc.Reverse(f.user, *refund.DebtOperationID, DebtReverseRequest{IdempotencyKey: "undo-credit"}); err != nil {
		t.Fatal(err)
	}
	debtAssert(t, f, 1000, 2000, 600, 300, 100, 0)
}

func TestDebtLogWriteFailureRollsBackPlansCashAndProjections(t *testing.T) {
	f := newDebtFixture(t)
	db := f.repos.Account.DB()
	const callback = "test:debt-log-failure"
	if err := db.Callback().Create().Before("gorm:create").Register(callback, func(tx *gorm.DB) {
		if tx.Statement.Schema != nil && tx.Statement.Schema.Table == "account_logs" {
			tx.AddError(errors.New("synthetic log storage failure"))
		}
	}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = db.Callback().Create().Remove(callback) })
	var before int64
	db.Model(&model.DebtOperation{}).Count(&before)
	if _, err := f.svc.Pay(f.user, DebtPaymentRequest{AccountID: &f.debt, SourceKind: "account", SourceAccountID: &f.cash,
		Amount: 20, IdempotencyKey: "fail-on-log", Allocations: []DebtPaymentPart{{PlanID: f.a, Principal: 10, CashInterest: 10}}}); err == nil {
		t.Fatal("payment succeeded without durable effect evidence")
	}
	debtAssert(t, f, 1000, 2000, 600, 300, 100, 0)
	var after, projections int64
	db.Model(&model.DebtOperation{}).Count(&after)
	db.Model(&model.Transaction{}).Where("source IN ?", []string{"debt_payment", "debt_interest"}).Count(&projections)
	if after != before || projections != 0 {
		t.Fatalf("failed payment left records: ops %d -> %d, projections=%d", before, after, projections)
	}
}

func TestDebtTransferOverpaymentAndAllocationRetainCredit(t *testing.T) {
	f := newDebtFixture(t)
	row, err := f.tx.Create(f.user, CreateTransactionRequest{Type: "transfer", AccountID: f.cash,
		ToAccountID: &f.debt, Amount: 1200, TransactionDate: "2026-10-18"})
	if err != nil || row.DebtOperationID == nil {
		t.Fatalf("overpayment transfer: %+v, %v", row, err)
	}
	debtAssert(t, f, -200, 800, 600, 300, 100, 1200)
	if _, err := f.svc.Allocate(f.user, *row.DebtOperationID, DebtAllocateRequest{IdempotencyKey: "credit-allocation",
		Allocations: []DebtPaymentPart{{PlanID: f.a, Principal: 600}, {PlanID: f.b, Principal: 300}}, UnplannedAmount: 100}); err != nil {
		t.Fatal(err)
	}
	debtAssert(t, f, -200, 800, 0, 0, 0, 200)
	if _, err := f.svc.Pay(f.user, DebtPaymentRequest{AccountID: &f.debt, SourceKind: "external",
		Amount: 1, UnappliedAmount: 1, IdempotencyKey: "reject-more-credit"}); err == nil {
		t.Fatal("dedicated payment silently allowed an excess debt reduction")
	}
	if _, err := f.svc.Reverse(f.user, *row.DebtOperationID, DebtReverseRequest{IdempotencyKey: "undo-credit-transfer"}); err != nil {
		t.Fatal(err)
	}
	debtAssert(t, f, 1000, 2000, 600, 300, 100, 0)
}

func TestDebtConcurrentAllocationAndReversalDoNotLeavePartialState(t *testing.T) {
	f := newDebtFixture(t)
	op, err := f.svc.Pay(f.user, DebtPaymentRequest{AccountID: &f.debt, SourceKind: "account", SourceAccountID: &f.cash,
		Amount: 80, UnappliedAmount: 80, IdempotencyKey: "race-payment"})
	if err != nil {
		t.Fatal(err)
	}
	var wg sync.WaitGroup
	wg.Add(2)
	go func() {
		defer wg.Done()
		_, err := f.svc.Allocate(f.user, op.ID, DebtAllocateRequest{IdempotencyKey: "race-allocation",
			Allocations: []DebtPaymentPart{{PlanID: f.a, Principal: 80}}})
		if err != nil && !errors.Is(err, ErrDebtDependency) {
			t.Error(err)
		}
	}()
	go func() {
		defer wg.Done()
		if _, err := f.svc.Reverse(f.user, op.ID, DebtReverseRequest{IdempotencyKey: "race-reverse"}); err != nil {
			t.Error(err)
		}
	}()
	wg.Wait()
	debtAssert(t, f, 1000, 2000, 600, 300, 100, 0)
}
