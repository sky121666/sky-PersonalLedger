package service

import (
	"fmt"
	"sort"
	"testing"
	"time"

	"github.com/sky/personal-ledger/internal/model"
)

func TestDebtWebHistoryLegacySignatureKeepsLatest100AndStableIDs(t *testing.T) {
	f := newDebtFixture(t)
	initial, err := f.svc.ListOperations(f.user, f.debt)
	if err != nil {
		t.Fatal(err)
	}
	var expected []string
	for _, op := range initial {
		expected = append(expected, op.ID)
	}
	for i := range 103 {
		op, err := f.svc.BookInterest(f.user, f.a, DebtInterestRequest{
			Amount: 0.01, IdempotencyKey: fmt.Sprintf("history-legacy-%d", i),
		})
		if err != nil {
			t.Fatal(err)
		}
		expected = append(expected, op.ID)
	}
	// Only fixture ordering metadata is fixed; financial effects use public services.
	stamp := time.Date(2026, 10, 18, 1, 2, 3, 0, time.UTC)
	if err := f.repos.Account.DB().Model(&model.DebtOperation{}).
		Where("user_id = ?", f.user).Update("created_at", stamp).Error; err != nil {
		t.Fatal(err)
	}
	sort.Sort(sort.Reverse(sort.StringSlice(expected)))
	for _, accountID := range []string{"", f.debt} {
		rows, err := f.svc.ListOperations(f.user, accountID)
		if err != nil || len(rows) != 100 {
			t.Fatalf("legacy latest-100 contract: count=%d err=%v", len(rows), err)
		}
		for i, op := range rows {
			if op.ID != expected[i] {
				t.Fatalf("same-timestamp ordering at %d: got %s want %s", i, op.ID, expected[i])
			}
		}
	}
}
