package handler

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/service"
)

func TestReminderHandlerLifecyclePaymentAndOwnership(t *testing.T) {
	_, _, repos, owner, other := newCatalogHandlerFixture(t)
	handler := NewReminderHandler(service.NewReminderService(repos.Reminder, repos.Account, repos.Transaction, repos.Category, nil))

	assertHandlerStatus(t, performReminderHandlerRequest(handler, owner.ID, http.MethodPost, "/reminders", `{}`), http.StatusBadRequest)
	assertHandlerStatus(t, performReminderHandlerRequest(handler, owner.ID, http.MethodPost, "/reminders", `{"name":"Bad date","payment_day":10,"start_date":"bad"}`), http.StatusUnprocessableEntity)
	assertHandlerStatus(t, performReminderHandlerRequest(handler, owner.ID, http.MethodPost, "/reminders", `{"name":"Missing account","payment_day":10,"account_id":"missing"}`), http.StatusNotFound)
	created := performReminderHandlerRequest(handler, owner.ID, http.MethodPost, "/reminders", `{"name":"Loan","payment_day":15,"principal":500,"current_balance":500}`)
	assertHandlerStatus(t, created, http.StatusCreated)
	var envelope struct {
		Data model.Reminder `json:"data"`
	}
	if err := json.Unmarshal(created.Body.Bytes(), &envelope); err != nil || envelope.Data.ID == "" {
		t.Fatalf("decode reminder response: data=%#v err=%v", envelope.Data, err)
	}
	reminderID := envelope.Data.ID

	assertHandlerStatus(t, performReminderHandlerRequest(handler, owner.ID, http.MethodGet, "/reminders", ""), http.StatusOK)
	assertHandlerStatus(t, performReminderHandlerRequest(handler, owner.ID, http.MethodGet, "/reminders/"+reminderID, ""), http.StatusOK)
	assertHandlerStatus(t, performReminderHandlerRequest(handler, other.ID, http.MethodGet, "/reminders/"+reminderID, ""), http.StatusNotFound)
	assertHandlerStatus(t, performReminderHandlerRequest(handler, owner.ID, http.MethodPut, "/reminders/"+reminderID, `{`), http.StatusBadRequest)
	assertHandlerStatus(t, performReminderHandlerRequest(handler, owner.ID, http.MethodPut, "/reminders/"+reminderID, `{"payment_day":32}`), http.StatusUnprocessableEntity)
	updated := performReminderHandlerRequest(handler, owner.ID, http.MethodPut, "/reminders/"+reminderID, `{"name":"Updated loan","advance_days":5}`)
	assertHandlerStatus(t, updated, http.StatusOK)
	assertHandlerStatus(t, performReminderHandlerRequest(handler, owner.ID, http.MethodPut, "/reminders/missing", `{"name":"Missing"}`), http.StatusNotFound)

	assertHandlerStatus(t, performReminderHandlerRequest(handler, owner.ID, http.MethodPost, "/reminders/"+reminderID+"/toggle", ""), http.StatusOK)
	assertHandlerStatus(t, performReminderHandlerRequest(handler, owner.ID, http.MethodPost, "/reminders/missing/toggle", ""), http.StatusNotFound)
	assertHandlerStatus(t, performReminderHandlerRequest(handler, owner.ID, http.MethodPost, "/reminders/"+reminderID+"/payment", `{}`), http.StatusBadRequest)
	assertHandlerStatus(t, performReminderHandlerRequest(handler, owner.ID, http.MethodPost, "/reminders/"+reminderID+"/payment", `{"amount":600}`), http.StatusBadRequest)
	assertHandlerStatus(t, performReminderHandlerRequest(handler, owner.ID, http.MethodPost, "/reminders/"+reminderID+"/payment", `{"amount":100}`), http.StatusOK)
	assertHandlerStatus(t, performReminderHandlerRequest(handler, owner.ID, http.MethodPost, "/reminders/missing/payment", `{"amount":100}`), http.StatusNotFound)
	assertHandlerStatus(t, performReminderHandlerRequest(handler, owner.ID, http.MethodGet, "/reminders/debt-summary", ""), http.StatusOK)

	assertHandlerStatus(t, performReminderHandlerRequest(handler, other.ID, http.MethodDelete, "/reminders/"+reminderID, ""), http.StatusNotFound)
	assertHandlerStatus(t, performReminderHandlerRequest(handler, owner.ID, http.MethodDelete, "/reminders/"+reminderID, ""), http.StatusOK)
	assertHandlerStatus(t, performReminderHandlerRequest(handler, owner.ID, http.MethodDelete, "/reminders/"+reminderID, ""), http.StatusNotFound)
}

func performReminderHandlerRequest(handler *ReminderHandler, userID uint, method, target, body string) *httptest.ResponseRecorder {
	router := gin.New()
	withUser := catalogUserHandler(userID)
	router.GET("/reminders", withUser(handler.List))
	router.POST("/reminders", withUser(handler.Create))
	router.GET("/reminders/debt-summary", withUser(handler.GetDebtSummary))
	router.GET("/reminders/:id", withUser(handler.GetByID))
	router.PUT("/reminders/:id", withUser(handler.Update))
	router.DELETE("/reminders/:id", withUser(handler.Delete))
	router.POST("/reminders/:id/toggle", withUser(handler.Toggle))
	router.POST("/reminders/:id/payment", withUser(handler.RecordPayment))
	request := httptest.NewRequest(method, target, bytes.NewBufferString(body))
	if body != "" {
		request.Header.Set("Content-Type", "application/json")
	}
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	return response
}
