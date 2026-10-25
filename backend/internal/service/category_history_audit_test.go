package service

import (
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

func TestDeletedCategoryRetainsHistoricalNamesInStatisticsAndTransactions(t *testing.T) {
	stats, _, repos, userID := newStatisticsTestService(t)
	category := model.Category{ID: uuid.NewString(), UserID: userID, Type: "expense", Name: "旧餐饮", Icon: "food", Color: "#abcdef"}
	if err := repos.Category.Create(&category); err != nil {
		t.Fatal(err)
	}
	accountID := createAccountForTest(t, repos, userID, 100)
	transaction := model.Transaction{ID: uuid.NewString(), UserID: userID, Type: "expense", Amount: 25, AccountID: accountID, CategoryID: &category.ID, TransactionDate: time.Date(2026, 1, 2, 12, 0, 0, 0, time.Local)}
	if err := repos.Transaction.Create(&transaction); err != nil {
		t.Fatal(err)
	}
	if err := repos.Category.Delete(category.ID); err != nil {
		t.Fatal(err)
	}
	t.Run("month statistics", func(t *testing.T) {
		result, err := stats.GetCategoryStats(userID, "2026-01", "expense")
		if err != nil {
			t.Fatal(err)
		}
		if len(result.Items) != 1 || result.Items[0].CategoryName != "旧餐饮" {
			t.Fatalf("history category = %+v", result.Items)
		}
	})
	t.Run("transaction list and details", func(t *testing.T) {
		rows, _, err := repos.Transaction.List(repository.TransactionFilter{UserID: userID, Page: 1, PageSize: 20})
		if err != nil {
			t.Fatal(err)
		}
		if len(rows) != 1 || rows[0].Category == nil || rows[0].Category.Name != "旧餐饮" {
			t.Fatalf("list category missing: %+v", rows)
		}
		detail, err := repos.Transaction.GetByIDForUser(transaction.ID, userID)
		if err != nil {
			t.Fatal(err)
		}
		if detail.Category == nil || detail.Category.Name != "旧餐饮" {
			t.Fatalf("detail category missing: %+v", detail)
		}
	})
	t.Run("not selectable for new records", func(t *testing.T) {
		rows, err := repos.Category.GetByUserID(userID, "expense")
		if err != nil {
			t.Fatal(err)
		}
		for _, row := range rows {
			if row.ID == category.ID {
				t.Fatal("deleted category selectable")
			}
		}
	})
}
