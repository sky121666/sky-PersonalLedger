package service

import (
	"errors"
	"testing"

	"github.com/sky/personal-ledger/internal/model"
)

func TestDebtExternalCashInterestIsRejectedWithoutFinancialWrites(t *testing.T) {
	for _, mixed := range []bool{false, true} {
		name := "interest-only"
		if mixed {
			name = "principal-and-interest"
		}
		t.Run(name, func(t *testing.T) {
			f := newDebtFixture(t)
			part := DebtPaymentPart{PlanID: f.a, CashInterest: 20}
			req := DebtPaymentRequest{AccountID: &f.debt, SourceKind: "external", Amount: 20,
				IdempotencyKey: "external-cash-interest"}
			if mixed {
				part.Principal, req.Amount = 10, 30
			}
			req.Allocations = []DebtPaymentPart{part}
			if _, err := f.svc.Pay(f.user, req); !errors.Is(err, ErrInvalidDebtRequest) {
				t.Fatalf("unrepresentable external expense accepted: %v", err)
			}
			debtAssert(t, f, 1000, 2000, 600, 300, 100, 0)
			plan, err := f.svc.GetPlan(f.user, f.a)
			if err != nil || plan.InterestPaid != 0 {
				t.Fatalf("rejected payment changed interest: %+v %v", plan, err)
			}
			var count int64
			if err := f.repos.Account.DB().Model(&model.DebtOperation{}).
				Where("user_id = ? AND kind = ?", f.user, "payment").Count(&count).Error; err != nil || count != 0 {
				t.Fatalf("rejected payment retained an operation: %d %v", count, err)
			}
		})
	}
}

func TestDebtExternalBookedInterestUsesBookingExpenseOnly(t *testing.T) {
	f := newDebtFixture(t)
	if _, err := f.svc.BookInterest(f.user, f.a, DebtInterestRequest{Amount: 20, IdempotencyKey: "booking"}); err != nil {
		t.Fatal(err)
	}
	payment, err := f.svc.Pay(f.user, DebtPaymentRequest{AccountID: &f.debt, SourceKind: "external",
		Amount: 30, IdempotencyKey: "external-booked",
		Allocations: []DebtPaymentPart{{PlanID: f.a, Principal: 10, BookedInterest: 20}}})
	if err != nil {
		t.Fatal(err)
	}
	debtAssert(t, f, 990, 2000, 590, 300, 100, 0)
	if _, err := f.svc.Reverse(f.user, payment.ID, DebtReverseRequest{IdempotencyKey: "undo-external"}); err != nil {
		t.Fatal(err)
	}
	debtAssert(t, f, 1020, 2000, 600, 300, 100, 0)
	var expenses int64
	if err := f.repos.Account.DB().Model(&model.Transaction{}).
		Where("user_id = ? AND source = ?", f.user, "debt_interest").Count(&expenses).Error; err != nil || expenses != 1 {
		t.Fatalf("booked interest expense counted incorrectly: %d %v", expenses, err)
	}
}

func TestDebtPlanCancellationRefusesUnexplainedPaidAmounts(t *testing.T) {
	f := newDebtFixture(t)
	plan, err := f.svc.CreatePlan(f.user, CreateDebtPlanRequest{Name: "Independent", Scope: "standalone",
		OriginalPrincipal: 100, OpeningPrincipal: 100, IdempotencyKey: "independent"})
	if err != nil {
		t.Fatal(err)
	}
	var opening model.DebtAllocation
	db := f.repos.Account.DB()
	if err := db.First(&opening, "plan_id = ?", plan.ID).Error; err != nil {
		t.Fatal(err)
	}
	// Missing provenance must lead to protection, never a cancelled plan with
	// paid amounts left behind.
	if err := db.Model(&model.DebtPlan{}).Where("id = ?", plan.ID).
		Update("interest_paid_cents", 100).Error; err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.Reverse(f.user, opening.OperationID, DebtReverseRequest{IdempotencyKey: "cancel"}); !errors.Is(err, ErrDebtDependency) {
		t.Fatalf("inconsistent plan cancellation was not rejected: %v", err)
	}
	after, err := f.svc.GetPlan(f.user, plan.ID)
	if err != nil || after.Status != "active" || after.PrincipalBalance != 100 || after.InterestPaid != 1 {
		t.Fatalf("failed cancellation changed plan: %+v %v", after, err)
	}
}
