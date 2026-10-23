package handler

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"reflect"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"github.com/sky/personal-ledger/internal/service"
	"gorm.io/gorm"
)

type debtHistoryFixture struct {
	svc                                   *service.DebtService
	repos                                 *repository.Repositories
	owner, other                          uint
	account, plan, standalone             string
	accountOpen, planOpen, standaloneOpen string
}

func newDebtHistoryFixture(t *testing.T) debtHistoryFixture {
	t.Helper()
	_, _, repos, owner, other := newCatalogHandlerFixture(t)
	db, err := repos.Account.DB().DB()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = db.Close() })
	account, err := service.NewAccountService(repos.Account).Create(owner.ID, service.CreateAccountRequest{
		Name: "History card", Type: "credit", InitialBalance: 1000, DebtTrackingMode: model.DebtModeManaged,
	})
	if err != nil {
		t.Fatal(err)
	}
	f := debtHistoryFixture{svc: service.NewDebtService(repos.Account.DB()), repos: repos,
		owner: owner.ID, other: other.ID, account: account.ID}
	plan, err := f.svc.CreatePlan(f.owner, service.CreateDebtPlanRequest{
		Name: "Account history", Scope: "account", AccountID: &f.account,
		OriginalPrincipal: 500, OpeningPrincipal: 500, IdempotencyKey: "history-account-plan",
	})
	if err != nil {
		t.Fatal(err)
	}
	f.plan = plan.ID
	standalone, err := f.svc.CreatePlan(f.owner, service.CreateDebtPlanRequest{
		Name: "Standalone history", Scope: "standalone",
		OriginalPrincipal: 400, OpeningPrincipal: 400, IdempotencyKey: "history-standalone-plan",
	})
	if err != nil {
		t.Fatal(err)
	}
	f.standalone = standalone.ID
	rows, err := f.svc.ListOperations(f.owner, "")
	if err != nil {
		t.Fatal(err)
	}
	for _, op := range rows {
		if op.StandalonePlanID != nil {
			f.standaloneOpen = op.ID
		} else if op.Kind == "plan_open" {
			f.planOpen = op.ID
		} else if op.Kind == "account_open" {
			f.accountOpen = op.ID
		}
	}
	return f
}

func (f debtHistoryFixture) request(userID uint, target string) *httptest.ResponseRecorder {
	router := gin.New()
	router.Use(func(c *gin.Context) { c.Set("userID", userID) })
	NewDebtHandler(f.svc).RegisterRoutes(router.Group("/debt"))
	return performCatalogRequest(router, http.MethodGet, target, "")
}

func (f debtHistoryFixture) history(t *testing.T, query url.Values) []model.DebtOperation {
	t.Helper()
	res := f.request(f.owner, "/debt/operations?"+query.Encode())
	if res.Code != http.StatusOK {
		t.Fatalf("history status=%d body=%s", res.Code, res.Body.String())
	}
	var body struct {
		Data json.RawMessage `json:"data"`
	}
	if err := json.Unmarshal(res.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(string(body.Data), "[") {
		t.Fatalf("history must remain an array, including empty pages: %s", body.Data)
	}
	var rows []model.DebtOperation
	if err := json.Unmarshal(body.Data, &rows); err != nil {
		t.Fatal(err)
	}
	return rows
}

func debtHistoryIDs(rows []model.DebtOperation) []string {
	ids := make([]string, 0, len(rows))
	for _, op := range rows {
		ids = append(ids, op.ID)
	}
	sort.Strings(ids)
	return ids
}

func TestDebtWebHistoryOldStandalonePaymentSurvivesAccountTraffic(t *testing.T) {
	f := newDebtHistoryFixture(t)
	payment, err := f.svc.Pay(f.owner, service.DebtPaymentRequest{
		StandalonePlanID: &f.standalone, SourceKind: "external", Amount: 40,
		Allocations: []service.DebtPaymentPart{{PlanID: f.standalone, Principal: 40}}, IdempotencyKey: "old-external",
	})
	if err != nil {
		t.Fatal(err)
	}
	for i := range 101 {
		if _, err := f.svc.BookInterest(f.owner, f.plan, service.DebtInterestRequest{
			Amount: 0.01, IdempotencyKey: fmt.Sprintf("new-account-interest-%d", i),
		}); err != nil {
			t.Fatal(err)
		}
	}
	defaultRows := f.history(t, nil)
	if len(defaultRows) != 100 {
		t.Fatalf("default history count=%d want 100", len(defaultRows))
	}
	for _, query := range []url.Values{
		{"plan_id": {f.standalone}},
		{"standalone_only": {"true"}},
		{"plan_id": {f.standalone}, "standalone_only": {"true"}},
	} {
		got := debtHistoryIDs(f.history(t, query))
		want := []string{f.standaloneOpen, payment.ID}
		sort.Strings(want)
		if !reflect.DeepEqual(got, want) {
			t.Errorf("old standalone payment unreachable for %v: got %v want %v", query, got, want)
		}
	}
}

func TestDebtWebHistoryCursorPagesHaveNoGapsOrDuplicatesAtEqualTime(t *testing.T) {
	f := newDebtHistoryFixture(t)
	expected := []string{f.standaloneOpen}
	for i := range 205 {
		op, err := f.svc.BookInterest(f.owner, f.standalone, service.DebtInterestRequest{
			Amount: 0.01, IdempotencyKey: fmt.Sprintf("paged-interest-%d", i),
		})
		if err != nil {
			t.Fatal(err)
		}
		expected = append(expected, op.ID)
	}
	stamp := time.Date(2026, 10, 18, 1, 2, 3, 0, time.UTC)
	if err := f.repos.Account.DB().Model(&model.DebtOperation{}).
		Where("user_id = ? AND standalone_plan_id = ?", f.owner, f.standalone).
		Update("created_at", stamp).Error; err != nil {
		t.Fatal(err)
	}
	sort.Sort(sort.Reverse(sort.StringSlice(expected)))
	query := url.Values{"plan_id": {f.standalone}, "standalone_only": {"true"}}
	var got []string
	seen := make(map[string]bool)
	for page := range 4 {
		rows := f.history(t, query)
		wantSize := []int{100, 100, 6, 0}[page]
		if len(rows) != wantSize {
			t.Fatalf("page %d count=%d want %d", page, len(rows), wantSize)
		}
		for _, op := range rows {
			if seen[op.ID] {
				t.Fatalf("cursor repeated operation %s on page %d", op.ID, page)
			}
			seen[op.ID] = true
			got = append(got, op.ID)
		}
		if len(rows) > 0 {
			query.Set("before", rows[len(rows)-1].ID)
		}
	}
	if !reflect.DeepEqual(got, expected) {
		t.Fatalf("same-time pages omit operations or violate descending ID order: got=%d want=%d", len(got), len(expected))
	}
}

func TestDebtWebHistoryAccountPlanIncludesOpenPaymentInterestAndReversals(t *testing.T) {
	f := newDebtHistoryFixture(t)
	sibling, err := f.svc.CreatePlan(f.owner, service.CreateDebtPlanRequest{
		Name: "Sibling", Scope: "account", AccountID: &f.account, OriginalPrincipal: 100,
		OpeningPrincipal: 100, IdempotencyKey: "history-sibling",
	})
	if err != nil {
		t.Fatal(err)
	}
	payment, err := f.svc.Pay(f.owner, service.DebtPaymentRequest{
		AccountID: &f.account, SourceKind: "external", Amount: 50, IdempotencyKey: "account-payment",
		Allocations: []service.DebtPaymentPart{{PlanID: f.plan, Principal: 30}, {PlanID: sibling.ID, Principal: 20}},
	})
	if err != nil {
		t.Fatal(err)
	}
	interest, err := f.svc.BookInterest(f.owner, f.plan, service.DebtInterestRequest{Amount: 5, IdempotencyKey: "account-interest"})
	if err != nil {
		t.Fatal(err)
	}
	undoInterest, err := f.svc.Reverse(f.owner, interest.ID, service.DebtReverseRequest{IdempotencyKey: "undo-history-interest"})
	if err != nil {
		t.Fatal(err)
	}
	undoPayment, err := f.svc.Reverse(f.owner, payment.ID, service.DebtReverseRequest{IdempotencyKey: "undo-history-payment"})
	if err != nil {
		t.Fatal(err)
	}
	want := []string{f.planOpen, payment.ID, interest.ID, undoInterest.ID, undoPayment.ID}
	sort.Strings(want)
	for _, query := range []url.Values{
		{"plan_id": {f.plan}},
		{"plan_id": {f.plan}, "account_id": {f.account}},
	} {
		got := debtHistoryIDs(f.history(t, query))
		if !reflect.DeepEqual(got, want) {
			t.Errorf("account plan history=%v want=%v", got, want)
		}
	}
	if rows := f.history(t, url.Values{"plan_id": {f.plan}, "standalone_only": {"true"}}); len(rows) != 0 {
		t.Errorf("standalone filter leaked account operations: %d", len(rows))
	}
}

func TestDebtWebHistoryRejectsForeignPlanAndOutOfScopeCursors(t *testing.T) {
	f := newDebtHistoryFixture(t)
	foreign, err := f.svc.CreatePlan(f.other, service.CreateDebtPlanRequest{
		Name: "Other user", Scope: "standalone", OriginalPrincipal: 10, OpeningPrincipal: 10, IdempotencyKey: "other-plan",
	})
	if err != nil {
		t.Fatal(err)
	}
	foreignRows, err := f.svc.ListOperations(f.other, "")
	if err != nil || len(foreignRows) != 1 {
		t.Fatalf("foreign fixture: %v %v", foreignRows, err)
	}
	for _, test := range []struct {
		name  string
		user  uint
		query url.Values
	}{
		{"missing-cursor", f.owner, url.Values{"before": {uuid.NewString()}}},
		{"foreign-cursor", f.owner, url.Values{"before": {foreignRows[0].ID}}},
		{"foreign-plan", f.owner, url.Values{"plan_id": {foreign.ID}}},
		{"missing-plan", f.owner, url.Values{"plan_id": {uuid.NewString()}}},
		{"foreign-user-plan", f.other, url.Values{"plan_id": {f.standalone}}},
		{"foreign-user-cursor", f.other, url.Values{"before": {f.standaloneOpen}}},
		{"other-plan-cursor", f.owner, url.Values{"plan_id": {f.plan}, "before": {f.standaloneOpen}}},
		{"other-account-cursor", f.owner, url.Values{"account_id": {f.account}, "before": {f.standaloneOpen}}},
		{"non-standalone-cursor", f.owner, url.Values{"standalone_only": {"true"}, "before": {f.planOpen}}},
		{"combined-scope", f.owner, url.Values{"account_id": {f.account}, "plan_id": {f.plan}, "before": {f.standaloneOpen}}},
	} {
		t.Run(test.name, func(t *testing.T) {
			res := f.request(test.user, "/debt/operations?"+test.query.Encode())
			if res.Code != http.StatusNotFound {
				t.Errorf("out-of-scope history status=%d body=%s; want 404", res.Code, res.Body.String())
			}
		})
	}
}

func TestDebtWebHistoryCapabilityAndInvalidBoolean(t *testing.T) {
	f := newDebtHistoryFixture(t)
	res := f.request(f.owner, "/debt/capabilities")
	var body struct {
		Data struct {
			OperationHistory bool `json:"operation_history"`
		} `json:"data"`
	}
	if err := json.Unmarshal(res.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if res.Code != http.StatusOK || !body.Data.OperationHistory {
		t.Errorf("operation_history capability missing: %s", res.Body.String())
	}
	res = f.request(f.owner, "/debt/operations?standalone_only=invalid")
	if res.Code != http.StatusBadRequest {
		t.Errorf("invalid standalone filter status=%d want 400", res.Code)
	}
}

func TestDebtWebHistoryUsesOneSnapshotForPlanCursorAndPage(t *testing.T) {
	f := newDebtHistoryFixture(t)
	cursor, err := f.svc.BookInterest(f.owner, f.standalone, service.DebtInterestRequest{Amount: 1, IdempotencyKey: "snapshot-cursor"})
	if err != nil {
		t.Fatal(err)
	}
	db := f.repos.Account.DB()
	if err := db.Model(&model.DebtOperation{}).Where("id = ?", f.standaloneOpen).
		Update("created_at", time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)).Error; err != nil {
		t.Fatal(err)
	}
	if err := db.Model(&model.DebtOperation{}).Where("id = ?", cursor.ID).
		Update("created_at", time.Date(2021, 1, 1, 0, 0, 0, 0, time.UTC)).Error; err != nil {
		t.Fatal(err)
	}
	pool, err := db.DB()
	if err != nil {
		t.Fatal(err)
	}
	pool.SetMaxOpenConns(2)
	pool.SetMaxIdleConns(2)
	wrote := false
	var writeErr error
	const name = "test:history-wal-write-after-plan-read"
	if err := db.Callback().Query().After("gorm:query").Register(name, func(query *gorm.DB) {
		if query.Statement.Table != "debt_plans" || wrote {
			return
		}
		wrote = true
		// A different WAL connection moves the cursor before the opening operation.
		writeErr = db.Model(&model.DebtOperation{}).Where("id = ?", cursor.ID).
			Update("created_at", time.Date(2019, 1, 1, 0, 0, 0, 0, time.UTC)).Error
	}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = db.Callback().Query().Remove(name) })
	rows := f.history(t, url.Values{"plan_id": {f.standalone}, "before": {cursor.ID}})
	if !wrote || writeErr != nil {
		t.Fatalf("concurrent WAL fixture did not commit: wrote=%v err=%v", wrote, writeErr)
	}
	if len(rows) != 1 || rows[0].ID != f.standaloneOpen {
		t.Fatalf("history mixed plan/cursor/page snapshots: %+v", rows)
	}
}
