package handler

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"
)

func TestTransactionCreationRetryHTTPContract(t *testing.T) {
	h, repos, user := newTransactionHandlerForTest(t)
	account := createTransactionHandlerAccount(t, repos, user)
	body := `{"type":"expense","amount":10,"account_id":"` + account + `","transaction_date":"2026-10-19","idempotency_key":"manual-http"}`
	first := performTransactionCreateRequest(h, user, body)
	assertHandlerStatus(t, first, http.StatusCreated)
	var response struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(first.Body.Bytes(), &response); err != nil {
		t.Fatal(err)
	}
	second := performTransactionCreateRequest(h, user, body)
	assertHandlerStatus(t, second, http.StatusCreated)
	if !strings.Contains(second.Body.String(), response.Data.ID) {
		t.Fatalf("retry returned a different transaction: %s", second.Body.String())
	}
	conflict := performTransactionCreateRequest(h, user, strings.Replace(body, `"amount":10`, `"amount":20`, 1))
	assertHandlerStatus(t, conflict, http.StatusConflict)
	if !strings.Contains(conflict.Body.String(), `"code":40903`) {
		t.Fatalf("wrong payload conflict contract: %s", conflict.Body.String())
	}
	assertHandlerStatus(t, performTransactionCreateRequest(h, user, strings.Replace(body, "manual-http", strings.Repeat("x", 129), 1)), http.StatusBadRequest)
	assertHandlerStatus(t, performTransactionDeleteRequest(h, user, response.Data.ID), http.StatusOK)
	deleted := performTransactionCreateRequest(h, user, body)
	assertHandlerStatus(t, deleted, http.StatusConflict)
	if !strings.Contains(deleted.Body.String(), `"code":40913`) {
		t.Fatalf("wrong deleted retry contract: %s", deleted.Body.String())
	}
}
