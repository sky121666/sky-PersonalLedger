package handler

import (
	"bytes"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/service"
	"gorm.io/gorm"
)

func TestReminderPaymentRetryHTTPContract(t *testing.T) {
	_, _, repos, owner, other := newCatalogHandlerFixture(t)
	svc := service.NewReminderService(repos.Reminder, repos.Account, repos.Transaction, repos.Category, nil)
	h := NewReminderHandler(svc)
	r, err := svc.Create(owner.ID, service.CreateReminderRequest{Name: "test", PaymentDay: 1})
	if err != nil {
		t.Fatal(err)
	}
	path := "/reminders/" + r.ID + "/payment"
	for i := 0; i < 2; i++ {
		assertHandlerStatus(t, performReminderHandlerRequest(h, owner.ID, http.MethodPost, path, `{"amount":10,"idempotency_key":"one"}`), http.StatusOK)
	}
	assertHandlerStatus(t, performReminderHandlerRequest(h, owner.ID, http.MethodPost, path, `{"amount":20,"idempotency_key":"one"}`), http.StatusConflict)
	assertHandlerStatus(t, performReminderHandlerRequest(h, other.ID, http.MethodPost, path, `{"amount":10,"idempotency_key":"one"}`), http.StatusNotFound)
	assertHandlerStatus(t, performReminderHandlerRequest(h, owner.ID, http.MethodPost, path, `{"amount":10,"idempotency_key":"`+strings.Repeat("a", 129)+`"}`), http.StatusBadRequest)
}

func TestReminderCommittedPaymentReadFailureReturnsRetryableServerError(t *testing.T) {
	_, _, repos, owner, _ := newCatalogHandlerFixture(t)
	svc := service.NewReminderService(repos.Reminder, repos.Account, repos.Transaction, repos.Category, nil)
	h := NewReminderHandler(svc)
	r, err := svc.Create(owner.ID, service.CreateReminderRequest{Name: "test", PaymentDay: 1})
	if err != nil {
		t.Fatal(err)
	}
	db := repos.Account.DB()
	const name = "test:fail-after-payment-commit"
	if err := db.Callback().Query().Before("gorm:query").Register(name, func(tx *gorm.DB) {
		_, inTx := tx.Statement.ConnPool.(gorm.TxCommitter)
		if tx.Statement.Schema != nil && tx.Statement.Schema.Table == "reminders" && !inTx {
			tx.AddError(errors.New("forced committed read failure"))
		}
	}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = db.Callback().Query().Remove(name) })
	path := "/reminders/" + r.ID + "/payment"
	body := `{"amount":10,"idempotency_key":"commit-read"}`
	w := performReminderHandlerRequest(h, owner.ID, http.MethodPost, path, body)
	assertHandlerStatus(t, w, http.StatusInternalServerError)
	if err := db.Callback().Query().Remove(name); err != nil {
		t.Fatal(err)
	}
	assertHandlerStatus(t, performReminderHandlerRequest(h, owner.ID, http.MethodPost, path, body), http.StatusOK)
	current, err := svc.GetByID(r.ID, owner.ID)
	if err != nil || current.TotalPaid != 10 {
		t.Fatalf("retry after committed read failure duplicated payment: %+v, %v", current, err)
	}
}

func TestLendingPaymentRetryHTTPContract(t *testing.T) {
	h, repos, userID := newLendingHandlerForTest(t)
	lending := &model.Lending{ID: uuid.NewString(), UserID: userID, Type: "borrow_in", ContactName: "test", Principal: 100, CurrentBalance: 100}
	if err := repos.Lending.Create(lending); err != nil {
		t.Fatal(err)
	}
	router := gin.New()
	router.POST("/lendings/:id/repayment", catalogUserHandler(userID)(h.RecordRepayment))
	perform := func(body string) *httptest.ResponseRecorder {
		r := httptest.NewRequest(http.MethodPost, "/lendings/"+lending.ID+"/repayment", bytes.NewBufferString(body))
		r.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		router.ServeHTTP(w, r)
		return w
	}
	for i := 0; i < 2; i++ {
		assertHandlerStatus(t, perform(`{"amount":100,"record_date":"2026-04-30","idempotency_key":"one"}`), http.StatusOK)
	}
	assertHandlerStatus(t, perform(`{"amount":90,"record_date":"2026-04-30","idempotency_key":"one"}`), http.StatusConflict)
}

func TestAccountDeleteReferencedHTTPAdvisesArchive(t *testing.T) {
	h, repos, userID := newAccountHandlerForTest(t)
	a := &model.Account{ID: uuid.NewString(), UserID: userID, Name: "test", Type: "cash", IsArchived: true}
	if err := repos.Account.Create(a); err != nil {
		t.Fatal(err)
	}
	if err := repos.Account.DB().Create(&model.AccountLog{ID: uuid.NewString(), UserID: userID, AccountID: a.ID, Type: "adjustment"}).Error; err != nil {
		t.Fatal(err)
	}
	w := performAccountCRUDRequest(h, userID, http.MethodDelete, "/accounts/"+a.ID, "")
	assertHandlerStatus(t, w, http.StatusConflict)
	if !strings.Contains(w.Body.String(), "归档") {
		t.Fatalf("response lacks archive guidance: %s", w.Body.String())
	}
}
