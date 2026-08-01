package handler

import (
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/sky/personal-ledger/internal/model"
)

func TestParseTransactionExportDateUsesLocalTimezone(t *testing.T) {
	previousLocal := time.Local
	local := time.FixedZone("UTC+08", 8*60*60)
	time.Local = local
	t.Cleanup(func() {
		time.Local = previousLocal
	})

	got, err := parseTransactionExportDate("2026-05-31")
	if err != nil {
		t.Fatalf("parse export date: %v", err)
	}
	want := time.Date(2026, time.May, 31, 0, 0, 0, 0, local)
	if got == nil || !got.Equal(want) || got.Location() != local {
		t.Fatalf("parsed date = %v, want %v in local timezone", got, want)
	}
}

func TestTransactionExportEndDateIncludesEntireLocalDay(t *testing.T) {
	previousLocal := time.Local
	local := time.FixedZone("UTC+08", 8*60*60)
	time.Local = local
	t.Cleanup(func() {
		time.Local = previousLocal
	})

	handler, repos, userID := newTransactionHandlerForTest(t)
	accountID := createTransactionHandlerAccount(t, repos, userID)
	transactions := []model.Transaction{
		{
			ID:              "export-local-day-start",
			UserID:          userID,
			AccountID:       accountID,
			Type:            "expense",
			Amount:          10,
			TransactionDate: time.Date(2026, time.May, 31, 0, 0, 0, 0, local),
		},
		{
			ID:              "export-local-day-end",
			UserID:          userID,
			AccountID:       accountID,
			Type:            "expense",
			Amount:          20,
			TransactionDate: time.Date(2026, time.May, 31, 23, 59, 59, 500_000_000, local),
		},
		{
			ID:              "export-next-local-day",
			UserID:          userID,
			AccountID:       accountID,
			Type:            "expense",
			Amount:          30,
			TransactionDate: time.Date(2026, time.June, 1, 0, 0, 0, 0, local),
		},
	}
	for index := range transactions {
		if err := repos.Transaction.Create(&transactions[index]); err != nil {
			t.Fatalf("create transaction %s: %v", transactions[index].ID, err)
		}
	}

	response := performTransactionExportRequest(
		handler,
		userID,
		"/transactions/export?format=json&start_date=2026-05-31&end_date=2026-05-31",
	)
	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", response.Code, response.Body.String())
	}

	var payload struct {
		Data []model.Transaction `json:"data"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	gotIDs := make(map[string]bool, len(payload.Data))
	for _, tx := range payload.Data {
		gotIDs[tx.ID] = true
	}
	if !gotIDs["export-local-day-start"] || !gotIDs["export-local-day-end"] {
		t.Fatalf("exported transaction IDs = %v, want both transactions on local end date", gotIDs)
	}
	if gotIDs["export-next-local-day"] {
		t.Fatalf("exported transaction IDs = %v, should exclude next local day", gotIDs)
	}
}
