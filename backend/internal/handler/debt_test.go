package handler

import (
	"encoding/json"
	"fmt"
	"net/http"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/authz"
	"github.com/sky/personal-ledger/internal/middleware"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/service"
)

func TestDebtHTTPContractIsScopedStrictAndRetryable(t *testing.T) {
	_, _, repos, owner, other := newCatalogHandlerFixture(t)
	account, err := service.NewAccountService(repos.Account).Create(owner.ID, service.CreateAccountRequest{
		Name: "Synthetic card", Type: "credit", InitialBalance: 100, DebtTrackingMode: model.DebtModeManaged,
	})
	if err != nil {
		t.Fatal(err)
	}
	svc := service.NewDebtService(repos.Account.DB())
	h := NewDebtHandler(svc)
	router := func(userID uint, scopes []string) *gin.Engine {
		r := gin.New()
		r.Use(func(c *gin.Context) {
			c.Set("userID", userID)
			c.Set("authPrincipal", authz.Principal{UserID: userID, CredentialType: authz.CredentialAPIToken, Scopes: scopes})
		}, middleware.EnforceAPITokenScopes())
		h.RegisterRoutes(r.Group("/debt"))
		return r
	}
	r := router(owner.ID, []string{authz.ScopeLedgerRead, authz.ScopeLedgerWrite})
	body := fmt.Sprintf(`{"name":"Plan","scope":"account","account_id":%q,"original_principal":60,"opening_principal":60,"idempotency_key":"open"}`, account.ID)
	created := performCatalogRequest(r, http.MethodPost, "/debt/plans", body)
	assertHandlerStatus(t, created, http.StatusCreated)
	var envelope struct {
		Data model.DebtPlan `json:"data"`
	}
	if err := json.Unmarshal(created.Body.Bytes(), &envelope); err != nil {
		t.Fatal(err)
	}
	id := envelope.Data.ID
	if id == "" {
		t.Fatal("missing plan ID")
	}
	assertHandlerStatus(t, performCatalogRequest(r, http.MethodPost, "/debt/plans", body), http.StatusCreated)
	assertHandlerStatus(t, performCatalogRequest(r, http.MethodPost, "/debt/plans", body[:len(body)-1]+`,"ignored_financial_field":1}`), http.StatusBadRequest)
	assertHandlerStatus(t, performCatalogRequest(r, http.MethodPost, "/debt/plans", body+`{}`), http.StatusBadRequest)
	assertHandlerStatus(t, performCatalogRequest(router(other.ID, []string{authz.ScopeLedgerRead}),
		http.MethodGet, "/debt/plans/"+id, ""), http.StatusNotFound)
	assertHandlerStatus(t, performCatalogRequest(router(owner.ID, []string{authz.ScopeLedgerRead}),
		http.MethodPost, "/debt/plans", body), http.StatusForbidden)
	assertHandlerStatus(t, performCatalogRequest(r, http.MethodGet, "/debt/capabilities", ""), http.StatusOK)
	payment := fmt.Sprintf(`{"account_id":%q,"source_kind":"external","amount":10,"allocations":[{"plan_id":%q,"principal":10}],"idempotency_key":"pay"}`, account.ID, id)
	assertHandlerStatus(t, performCatalogRequest(r, http.MethodPost, "/debt/payments", payment), http.StatusOK)
	assertHandlerStatus(t, performCatalogRequest(r, http.MethodPost, "/debt/payments", payment), http.StatusOK)
	current, _ := repos.Account.GetByID(account.ID)
	if current.CurrentBalance != 90 {
		t.Fatalf("HTTP retry double-paid: %v", current.CurrentBalance)
	}
}

func TestDebtLegacyReminderPaymentCannotBypassManagedAccount(t *testing.T) {
	_, _, repos, owner, _ := newCatalogHandlerFixture(t)
	account, err := service.NewAccountService(repos.Account).Create(owner.ID, service.CreateAccountRequest{
		Name: "Synthetic managed card", Type: "credit", InitialBalance: 100, DebtTrackingMode: model.DebtModeManaged,
	})
	if err != nil {
		t.Fatal(err)
	}
	reminder := model.Reminder{ID: "legacy-binding-fixture", UserID: owner.ID, AccountID: &account.ID,
		PaymentDay: 1, CurrentBalance: &account.CurrentBalance}
	if err := repos.Account.DB().Create(&reminder).Error; err != nil {
		t.Fatal(err)
	}
	h := NewReminderHandler(service.NewReminderService(repos.Reminder, repos.Account, repos.Transaction, repos.Category, nil))
	response := performReminderHandlerRequest(h, owner.ID, http.MethodPost,
		"/reminders/"+reminder.ID+"/payment", `{"amount":10,"idempotency_key":"legacy-write"}`)
	assertHandlerStatus(t, response, http.StatusConflict)
	current, _ := repos.Account.GetByID(account.ID)
	if current.CurrentBalance != 100 {
		t.Fatal("legacy endpoint changed managed balance")
	}
}
