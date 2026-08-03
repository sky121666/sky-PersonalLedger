package handler

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/service"
)

func TestBudgetHandlerCRUDValidationAndOwnership(t *testing.T) {
	_, _, repos, owner, other := newCatalogHandlerFixture(t)
	handler := NewBudgetHandler(service.NewBudgetService(repos.Budget, repos.Transaction, repos.FamilyMember, repos.Category))
	category := &model.Category{ID: uuid.NewString(), UserID: owner.ID, Name: "Food", Type: "expense"}
	if err := repos.Category.Create(category); err != nil {
		t.Fatalf("create category: %v", err)
	}

	assertHandlerStatus(t, performBudgetHandlerRequest(handler, owner.ID, http.MethodGet, "/budgets?month=2026-13", ""), http.StatusBadRequest)
	assertHandlerStatus(t, performBudgetHandlerRequest(handler, owner.ID, http.MethodPut, "/budgets/total", `{}`), http.StatusBadRequest)
	total := performBudgetHandlerRequest(handler, owner.ID, http.MethodPut, "/budgets/total", `{"amount":1000,"alert_threshold":80}`)
	assertHandlerStatus(t, total, http.StatusOK)
	var totalEnvelope struct {
		Data model.Budget `json:"data"`
	}
	if err := json.Unmarshal(total.Body.Bytes(), &totalEnvelope); err != nil || totalEnvelope.Data.ID == "" {
		t.Fatalf("decode total budget: data=%#v err=%v", totalEnvelope.Data, err)
	}
	assertHandlerStatus(t, performBudgetHandlerRequest(handler, owner.ID, http.MethodPut, "/budgets/total", `{"amount":1200,"alert_threshold":75}`), http.StatusOK)

	assertHandlerStatus(t, performBudgetHandlerRequest(handler, owner.ID, http.MethodPost, "/budgets/category", `{`), http.StatusBadRequest)
	assertHandlerStatus(t, performBudgetHandlerRequest(handler, owner.ID, http.MethodPost, "/budgets/category", `{"category_id":"missing","amount":100}`), http.StatusNotFound)
	categoryBudget := performBudgetHandlerRequest(handler, owner.ID, http.MethodPost, "/budgets/category", `{"category_id":"`+category.ID+`","amount":300,"alert_threshold":70}`)
	assertHandlerStatus(t, categoryBudget, http.StatusCreated)
	var categoryEnvelope struct {
		Data model.Budget `json:"data"`
	}
	if err := json.Unmarshal(categoryBudget.Body.Bytes(), &categoryEnvelope); err != nil || categoryEnvelope.Data.ID == "" {
		t.Fatalf("decode category budget: data=%#v err=%v", categoryEnvelope.Data, err)
	}
	assertHandlerStatus(t, performBudgetHandlerRequest(handler, owner.ID, http.MethodPost, "/budgets/category", `{"category_id":"`+category.ID+`","amount":350}`), http.StatusCreated)
	assertHandlerStatus(t, performBudgetHandlerRequest(handler, owner.ID, http.MethodGet, "/budgets?month=2026-08", ""), http.StatusOK)
	assertHandlerStatus(t, performBudgetHandlerRequest(handler, owner.ID, http.MethodGet, "/budgets/summary", ""), http.StatusOK)
	assertHandlerStatus(t, performBudgetHandlerRequest(handler, other.ID, http.MethodDelete, "/budgets/"+categoryEnvelope.Data.ID, ""), http.StatusNotFound)
	assertHandlerStatus(t, performBudgetHandlerRequest(handler, owner.ID, http.MethodDelete, "/budgets/"+categoryEnvelope.Data.ID, ""), http.StatusOK)
	assertHandlerStatus(t, performBudgetHandlerRequest(handler, owner.ID, http.MethodDelete, "/budgets/missing", ""), http.StatusNotFound)
}

func performBudgetHandlerRequest(handler *BudgetHandler, userID uint, method, target, body string) *httptest.ResponseRecorder {
	router := gin.New()
	withUser := catalogUserHandler(userID)
	router.GET("/budgets", withUser(handler.List))
	router.GET("/budgets/summary", withUser(handler.GetSummary))
	router.PUT("/budgets/total", withUser(handler.SetTotal))
	router.POST("/budgets/category", withUser(handler.SetCategory))
	router.DELETE("/budgets/:id", withUser(handler.Delete))
	request := httptest.NewRequest(method, target, bytes.NewBufferString(body))
	if body != "" {
		request.Header.Set("Content-Type", "application/json")
	}
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	return response
}
