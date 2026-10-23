package service

import (
	"fmt"
	"testing"
)

func TestDebtDetailsExposeRemainingCreditAndActiveAllocations(t *testing.T) {
	f := newDebtFixture(t)
	payment, err := f.svc.Pay(f.user, DebtPaymentRequest{AccountID: &f.debt, SourceKind: "account",
		SourceAccountID: &f.cash, Amount: 30, UnappliedAmount: 30, IdempotencyKey: "web-payment"})
	if err != nil {
		t.Fatal(err)
	}
	first, err := f.svc.Allocate(f.user, payment.ID, DebtAllocateRequest{
		Allocations: []DebtPaymentPart{{PlanID: f.a, Principal: 10}}, IdempotencyKey: "web-allocation"})
	if err != nil {
		t.Fatal(err)
	}
	detail, err := f.svc.OperationDetails(f.user, payment.ID)
	if err != nil || detail.UnallocatedAmount != 20 || len(detail.ActiveAllocations) != 1 || detail.ActiveAllocations[0].ID != first.ID {
		t.Fatalf("remaining credit and children: %+v %v", detail, err)
	}
	replacement, err := f.svc.Allocate(f.user, payment.ID, DebtAllocateRequest{
		ReplaceOperationID: first.ID, Allocations: []DebtPaymentPart{{PlanID: f.b, Principal: 15}}, IdempotencyKey: "web-replacement"})
	if err != nil {
		t.Fatal(err)
	}
	detail, err = f.svc.OperationDetails(f.user, payment.ID)
	if err != nil || detail.UnallocatedAmount != 15 || len(detail.ActiveAllocations) != 1 || detail.ActiveAllocations[0].ID != replacement.ID {
		t.Fatalf("replacement credit and children: %+v %v", detail, err)
	}
	if _, err := f.svc.Reverse(f.user, payment.ID, DebtReverseRequest{IdempotencyKey: "web-undo"}); err != nil {
		t.Fatal(err)
	}
	detail, err = f.svc.OperationDetails(f.user, payment.ID)
	if err != nil || detail.UnallocatedAmount != 0 || len(detail.ActiveAllocations) != 0 {
		t.Fatalf("reversed payment exposes spendable credit: %+v %v", detail, err)
	}
	if _, err := f.svc.OperationDetails(f.user+100, payment.ID); err != ErrDebtNotFound {
		t.Fatalf("foreign user read payment details: %v", err)
	}
}

func TestDebtDetailsCreditDoesNotDependOnRecentOperationWindow(t *testing.T) {
	f := newDebtFixture(t)
	payment, err := f.svc.Pay(f.user, DebtPaymentRequest{AccountID: &f.debt, SourceKind: "account",
		SourceAccountID: &f.cash, Amount: 20, UnappliedAmount: 20, IdempotencyKey: "old-payment"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.Allocate(f.user, payment.ID, DebtAllocateRequest{
		Allocations: []DebtPaymentPart{{PlanID: f.a, Principal: 5}}, IdempotencyKey: "old-child"}); err != nil {
		t.Fatal(err)
	}
	// Unrelated later operations exceed the list endpoint's 100-record window.
	for i := range 101 {
		if _, err := f.svc.BookInterest(f.user, f.b, DebtInterestRequest{Amount: 0.01, IdempotencyKey: fmt.Sprintf("late-%d", i)}); err != nil {
			t.Fatal(err)
		}
	}
	detail, err := f.svc.OperationDetails(f.user, payment.ID)
	if err != nil || detail.UnallocatedAmount != 15 || len(detail.ActiveAllocations) != 1 {
		t.Fatalf("credit depends on recent operation list: %+v %v", detail, err)
	}
}
