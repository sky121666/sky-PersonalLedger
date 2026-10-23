package service

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"reflect"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/config"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/money"
)

func debtAIService(f debtFixture) *AIReportService {
	return NewAIReportService(f.repos.AIReport, f.repos.AIProvider, f.repos.Transaction,
		f.repos.Category, f.repos.FamilyMember, NewOpenAICompatibleClient(nil, true)).
		WithBudgetRepository(f.repos.Budget).WithAccountRepository(f.repos.Account)
}

func debtAIFinancialState(t *testing.T, f debtFixture) string {
	t.Helper()
	state := map[string][]map[string]any{}
	for _, table := range []string{"accounts", "transactions", "account_logs", "debt_plans", "debt_operations", "debt_allocations"} {
		var rows []map[string]any
		if err := f.repos.Account.DB().Table(table).Where("user_id = ?", f.user).Order("id").Find(&rows).Error; err != nil {
			t.Fatal(err)
		}
		state[table] = rows
	}
	data, err := json.Marshal(state)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func testAIDebtAccountChanges(t *testing.T, fixture func(*testing.T) debtFixture) {
	start := time.Date(2025, 1, 1, 0, 0, 0, 0, time.Local)
	end := start.AddDate(0, 1, 0).Add(-time.Second)
	for _, tc := range []struct {
		name                       string
		principal, booked, cash    money.Amount
		unplanned, pending, second money.Amount
		internal                   bool
		wantDebt, wantSource       money.Amount
	}{
		{name: "external-principal", principal: 100, wantDebt: -100},
		{name: "external-booked-interest", booked: 20, wantDebt: -20},
		{name: "external-mixed", principal: 100, booked: 20, wantDebt: -120},
		{name: "external-cent", principal: 0.01, wantDebt: -0.01},
		{name: "external-two-plans", principal: 40, second: 60, wantDebt: -100},
		{name: "external-unplanned", unplanned: 40, wantDebt: -40},
		{name: "external-pending-then-allocate", pending: 40, wantDebt: -40},
		{name: "internal-principal", principal: 100, internal: true, wantDebt: -100, wantSource: -100},
		{name: "internal-cash-interest", cash: 20, internal: true, wantSource: -20},
		{name: "internal-mixed", principal: 100, cash: 20, internal: true, wantDebt: -100, wantSource: -120},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := fixture(t)
			if tc.booked > 0 {
				if _, err := f.svc.BookInterest(f.user, f.a, DebtInterestRequest{Amount: tc.booked,
					OccurredAt: start.Add(-time.Hour).Format(time.RFC3339), IdempotencyKey: "book-before-period"}); err != nil {
					t.Fatal(err)
				}
			}
			req := DebtPaymentRequest{AccountID: &f.debt, SourceKind: "external", IdempotencyKey: "ai-payment",
				OccurredAt: start.Format(time.RFC3339), UnplannedAmount: tc.unplanned, UnappliedAmount: tc.pending,
				Amount: tc.principal.Add(tc.booked).Add(tc.cash).Add(tc.unplanned).Add(tc.pending).Add(tc.second)}
			if tc.principal.Add(tc.booked).Add(tc.cash) > 0 {
				req.Allocations = []DebtPaymentPart{{PlanID: f.a, Principal: tc.principal, BookedInterest: tc.booked, CashInterest: tc.cash}}
			}
			if tc.second > 0 {
				req.Allocations = append(req.Allocations, DebtPaymentPart{PlanID: f.b, Principal: tc.second})
			}
			if tc.internal {
				req.SourceKind, req.SourceAccountID = "account", &f.cash
			}
			payment, err := f.svc.Pay(f.user, req)
			if err != nil {
				t.Fatal(err)
			}
			replay, err := f.svc.Pay(f.user, req)
			if err != nil || replay.ID != payment.ID {
				t.Fatalf("payment replay changed identity: %v", err)
			}
			if tc.pending > 0 {
				if _, err := f.svc.Allocate(f.user, payment.ID, DebtAllocateRequest{
					Allocations: []DebtPaymentPart{{PlanID: f.a, Principal: 25}}, IdempotencyKey: "later-allocation"}); err != nil {
					t.Fatal(err)
				}
			}
			check := func(from, to time.Time, wantDebt, wantSource, wantExpense money.Amount) {
				t.Helper()
				before := debtAIFinancialState(t, f)
				raw, err := debtAIService(f).buildSnapshotJSON(f.user, from, to, false)
				if err != nil {
					t.Fatal(err)
				}
				var snapshot aiReportSnapshot
				if err := json.Unmarshal([]byte(raw), &snapshot); err != nil {
					t.Fatal(err)
				}
				got, want := map[string]int64{}, map[string]int64{}
				for _, change := range snapshot.AccountChanges {
					got[change.AccountName] = change.BalanceDelta.Cents()
				}
				if wantDebt != 0 {
					want["Synthetic managed card"] = wantDebt.Cents()
				}
				if wantSource != 0 {
					want["Wallet cash"] = wantSource.Cents()
				}
				if !reflect.DeepEqual(got, want) {
					t.Errorf("account changes cents=%v, want %v", got, want)
				}
				if snapshot.IncomeTotal != 0 || snapshot.ExpenseTotal != wantExpense || snapshot.NetCashflow != wantExpense.Negate() {
					t.Errorf("cash-flow facts income=%v expense=%v net=%v", snapshot.IncomeTotal, snapshot.ExpenseTotal, snapshot.NetCashflow)
				}
				if after := debtAIFinancialState(t, f); after != before {
					t.Fatal("snapshot query wrote financial data")
				}
			}
			check(start, end, tc.wantDebt, tc.wantSource, tc.cash)
			check(start.Add(time.Second), end, 0, 0, 0)
			check(start.Add(-time.Second), start, tc.wantDebt, tc.wantSource, tc.cash)
			if sums, err := f.repos.Transaction.SumBalanceDeltaByAccount(f.user+1000000, start, end); err != nil || len(sums) != 0 {
				t.Fatalf("cross-user data: %v %v", sums, err)
			}
			if _, err := f.svc.Reverse(f.user, payment.ID, DebtReverseRequest{IdempotencyKey: "ai-reverse"}); err != nil {
				t.Fatal(err)
			}
			check(start, end, 0, 0, 0)
			check(end.Add(time.Second), end.AddDate(0, 1, 0), 0, 0, 0)
			if err := f.svc.CheckAccount(f.user, f.debt); err != nil {
				t.Fatal(err)
			}
		})
	}
}

func TestAIDebtAccountChanges(t *testing.T) {
	testAIDebtAccountChanges(t, newDebtFixture)
	testAIDebtProjectionGuards(t, newDebtFixture)
}

func testAIDebtProjectionGuards(t *testing.T, fixture func(*testing.T) debtFixture) {
	for _, name := range []string{"active-projection", "deleted-projection", "out-of-period-projection",
		"archived-account", "wrong-effect-role", "wrong-operation-owner", "wrong-log-owner", "wrong-account", "internal-source"} {
		t.Run(name, func(t *testing.T) {
			f := fixture(t)
			db := f.repos.Account.DB()
			at := time.Date(2025, 1, 10, 12, 0, 0, 0, time.Local)
			op, err := f.svc.Pay(f.user, DebtPaymentRequest{AccountID: &f.debt, SourceKind: "external", Amount: 100,
				OccurredAt: at.Format(time.RFC3339), IdempotencyKey: "projection-guard",
				Allocations: []DebtPaymentPart{{PlanID: f.a, Principal: 100}}})
			if err != nil {
				t.Fatal(err)
			}
			want := money.Amount(0)
			switch name {
			case "active-projection", "deleted-projection", "out-of-period-projection":
				// Deliberately model a projected operation to guard against double counting
				// and against resurrecting a soft-deleted projection through its log.
				row := model.Transaction{ID: uuid.NewString(), UserID: f.user, AccountID: f.cash, ToAccountID: &f.debt,
					Type: "transfer", Amount: 100, TransactionDate: at, DebtOperationID: &op.ID}
				if name == "out-of-period-projection" {
					row.TransactionDate = at.AddDate(0, -1, 0)
				}
				if err := db.Create(&row).Error; err != nil {
					t.Fatal(err)
				}
				if name == "deleted-projection" {
					err = db.Delete(&row).Error
				} else if name == "active-projection" {
					want = -100
				}
			case "archived-account":
				err = db.Model(&model.Account{}).Where("id = ?", f.debt).Update("is_archived", true).Error
				want = -100
			case "wrong-effect-role":
				err = db.Model(&model.AccountLog{}).Where("debt_operation_id = ?", op.ID).Update("debt_effect_role", "source").Error
			case "wrong-operation-owner", "wrong-log-owner":
				other := newDebtServerFixture(t, db)
				if name == "wrong-operation-owner" {
					err = db.Model(&model.DebtOperation{}).Where("id = ?", op.ID).Update("user_id", other.user).Error
				} else {
					err = db.Model(&model.AccountLog{}).Where("debt_operation_id = ?", op.ID).Update("user_id", other.user).Error
				}
			case "wrong-account":
				err = db.Model(&model.AccountLog{}).Where("debt_operation_id = ?", op.ID).Update("account_id", f.cash).Error
			case "internal-source":
				err = db.Model(&model.DebtOperation{}).Where("id = ?", op.ID).Update("source_account_id", f.cash).Error
			}
			if err != nil {
				t.Fatal(err)
			}
			before := debtAIFinancialState(t, f)
			rows, err := f.repos.Transaction.SumBalanceDeltaByAccount(f.user, at.Add(-time.Hour), at.Add(time.Hour))
			if err != nil {
				t.Fatal(err)
			}
			var got money.Amount
			for _, row := range rows {
				if row.AccountID == f.debt {
					got = row.BalanceDelta
				}
			}
			if got != want {
				t.Fatalf("debt delta=%v, want %v", got, want)
			}
			if debtAIFinancialState(t, f) != before {
				t.Fatal("aggregate query wrote financial data")
			}
		})
	}
}

func TestAIDebtAccountChangesServerIntegration(t *testing.T) {
	for _, driver := range []string{"postgres", "mysql"} {
		t.Run(driver, func(t *testing.T) {
			dsn := strings.TrimSpace(os.Getenv("LEDGER_TEST_" + strings.ToUpper(driver) + "_DSN"))
			if dsn == "" {
				t.Skip("isolated database DSN not supplied")
			}
			db, err := database.InitWithConfig(config.DatabaseConfig{Driver: driver, DSN: dsn})
			if err != nil {
				t.Fatal(err)
			}
			sqlDB, err := db.DB()
			if err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { _ = sqlDB.Close() })
			testAIDebtAccountChanges(t, func(t *testing.T) debtFixture { return newDebtServerFixture(t, db) })
			testAIDebtProjectionGuards(t, func(t *testing.T) debtFixture { return newDebtServerFixture(t, db) })
		})
	}
}

func TestAIExternalDebtSnapshotInvalidatesCacheWithoutRewritingHistory(t *testing.T) {
	f := newDebtFixture(t)
	var calls atomic.Int32
	var fail atomic.Bool
	payloads := make(chan string, 4)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		var payload struct {
			Messages []struct {
				Content string `json:"content"`
			} `json:"messages"`
		}
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil || len(payload.Messages) < 2 {
			http.Error(w, "invalid request", http.StatusBadRequest)
			return
		}
		payloads <- payload.Messages[1].Content
		if fail.Load() {
			http.Error(w, "synthetic outage", http.StatusBadGateway)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"{\"summary\":\"Synthetic debt analysis\"}"}}]}`))
	}))
	defer server.Close()
	providerSvc := NewAIProviderService(f.repos.AIProvider, NewOpenAICompatibleClient(nil, true)).WithPrivateOutboundNetworks(true)
	provider, err := providerSvc.Create(f.user, SaveAIProviderRequest{Name: "Synthetic AI", ProviderType: aiProviderTypeOpenAICompatible,
		BaseURL: server.URL, APIKey: "synthetic-test-key", Model: "synthetic-model", Enabled: true})
	if err != nil {
		t.Fatal(err)
	}
	ai := debtAIService(f)
	req := GenerateAIReportRequest{ReportType: "monthly", ProviderID: provider.ID, PeriodStart: "2025-01-01", PeriodEnd: "2025-01-31"}
	first, err := ai.Generate(f.user, req)
	if err != nil {
		t.Fatal(err)
	}
	<-payloads
	history, err := f.repos.AIReport.GetByID(first.ID)
	if err != nil {
		t.Fatal(err)
	}
	beforeReport, err := json.Marshal(history)
	if err != nil {
		t.Fatal(err)
	}
	pay := func(key string) string {
		t.Helper()
		payment, err := f.svc.Pay(f.user, DebtPaymentRequest{AccountID: &f.debt, SourceKind: "external", Amount: 100,
			Allocations: []DebtPaymentPart{{PlanID: f.a, Principal: 100}}, OccurredAt: "2025-01-10T12:00:00Z", IdempotencyKey: key})
		if err != nil {
			t.Fatal(err)
		}
		return payment.ID
	}
	firstPayment := pay("first-payment")
	before := debtAIFinancialState(t, f)
	second, err := ai.Generate(f.user, req)
	if err != nil {
		t.Fatal(err)
	}
	if second.ID == first.ID || calls.Load() != 2 {
		t.Fatalf("changed facts reused old report; calls=%d", calls.Load())
	}
	var snapshot aiReportSnapshot
	if err := json.Unmarshal([]byte(second.SnapshotJSON), &snapshot); err != nil {
		t.Fatal(err)
	}
	if len(snapshot.AccountChanges) != 1 || snapshot.AccountChanges[0].BalanceDelta != -100 || snapshot.AccountChanges[0].AccountName != "账户1" {
		t.Fatalf("missing or unmasked debt facts: %+v", snapshot.AccountChanges)
	}
	message := <-payloads
	if !strings.Contains(message, second.SnapshotJSON) || strings.Contains(message, "Synthetic managed card") {
		t.Fatal("model input differs from stored facts or leaks account name")
	}
	reused, err := ai.Generate(f.user, req)
	if err != nil || reused.ID != second.ID || calls.Load() != 2 {
		t.Fatalf("unchanged facts not reused: %v", err)
	}
	if debtAIFinancialState(t, f) != before {
		t.Fatal("report generation wrote financial data")
	}
	secondPayment := pay("second-payment")
	fail.Store(true)
	before = debtAIFinancialState(t, f)
	if _, err := ai.Generate(f.user, req); err == nil {
		t.Fatal("outage reported success")
	}
	if calls.Load() != 3 {
		t.Fatalf("unexpected automatic retry: %d", calls.Load())
	}
	if debtAIFinancialState(t, f) != before {
		t.Fatal("failed generation wrote financial data")
	}
	fail.Store(false)
	for i, operation := range []string{secondPayment, firstPayment} {
		if _, err := f.svc.Reverse(f.user, operation, DebtReverseRequest{IdempotencyKey: "undo-" + operation}); err != nil {
			t.Fatal(err)
		}
		before = debtAIFinancialState(t, f)
		reused, err := ai.Generate(f.user, req)
		if err != nil {
			t.Fatal(err)
		}
		if i == 0 && (reused.ID != second.ID || calls.Load() != 3) {
			t.Fatal("matching latest snapshot after reversal was not reused")
		}
		// The cache considers the latest completed report, not every historical
		// report. A second reversal must not reuse its now-stale payment facts.
		if i == 1 && (reused.ID == second.ID || reused.SnapshotJSON != first.SnapshotJSON || calls.Load() != 4) {
			t.Fatal("fully reversed payment facts stayed in the generated report")
		}
		if debtAIFinancialState(t, f) != before {
			t.Fatal("generation after reversal wrote financial data")
		}
	}
	still, err := f.repos.AIReport.GetByID(first.ID)
	if err != nil {
		t.Fatal(err)
	}
	afterReport, err := json.Marshal(still)
	if err != nil || string(afterReport) != string(beforeReport) {
		t.Fatal("old report rewritten")
	}
	still, err = f.repos.AIReport.GetByID(second.ID)
	if err != nil || still.Status != "completed" || still.ContentJSON != second.ContentJSON {
		t.Fatal("last success lost after failure")
	}
}
