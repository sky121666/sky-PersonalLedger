package service

import (
	"fmt"
	"testing"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
)

func TestDebtInterestReusesCategoryWithoutChangingHistory(t *testing.T) {
	f := newDebtFixture(t)
	existing := model.Category{ID: uuid.NewString(), UserID: f.user, Type: "expense", Name: "利息",
		Color: "#007AFF", Icon: "wallet"}
	if err := f.repos.Account.DB().Create(&existing).Error; err != nil {
		t.Fatal(err)
	}
	for i := range 3 {
		if _, err := f.svc.BookInterest(f.user, f.a, DebtInterestRequest{
			Amount: 10, IdempotencyKey: fmt.Sprintf("category-interest-%d", i),
		}); err != nil {
			t.Fatal(err)
		}
	}
	var categories []model.Category
	if err := f.repos.Account.DB().Where("user_id = ? AND type = ? AND name = ?", f.user, "expense", "利息").
		Find(&categories).Error; err != nil {
		t.Fatal(err)
	}
	if len(categories) != 1 || categories[0].ID != existing.ID || categories[0].Color != "#007AFF" {
		t.Fatalf("interest created or changed categories: %+v", categories)
	}
	var rows []model.Transaction
	if err := f.repos.Account.DB().Where("user_id = ? AND source = ?", f.user, "debt_interest").Find(&rows).Error; err != nil {
		t.Fatal(err)
	}
	if len(rows) != 3 {
		t.Fatalf("interest projection count = %d, want 3", len(rows))
	}
	for _, row := range rows {
		if row.CategoryID == nil || *row.CategoryID != existing.ID || row.Amount != 10 {
			t.Fatalf("interest projection changed: %+v", row)
		}
	}
	debtAssert(t, f, 1030, 2000, 600, 300, 100, 0)
}

func TestDebtInterestCreatesOnlyOneCategoryForNewHistory(t *testing.T) {
	f := newDebtFixture(t)
	for i := range 3 {
		if _, err := f.svc.BookInterest(f.user, f.a, DebtInterestRequest{
			Amount: 1, IdempotencyKey: fmt.Sprintf("new-category-%d", i),
		}); err != nil {
			t.Fatal(err)
		}
	}
	var count int64
	if err := f.repos.Account.DB().Model(&model.Category{}).
		Where("user_id = ? AND type = ? AND name = ?", f.user, "expense", "利息").Count(&count).Error; err != nil {
		t.Fatal(err)
	}
	if count != 1 {
		t.Fatalf("three interest postings created %d categories, want 1", count)
	}
}

func TestDebtInterestRetainsDuplicateHistoricalCategoriesAndTransactions(t *testing.T) {
	f := newDebtFixture(t)
	ids := []string{uuid.NewString(), uuid.NewString()}
	oldRows := make([]model.Transaction, 0, 2)
	for i, id := range ids {
		category := model.Category{ID: id, UserID: f.user, Type: "expense", Name: "利息"}
		if err := f.repos.Account.DB().Create(&category).Error; err != nil {
			t.Fatal(err)
		}
		req := keyedTransactionRequest(t, f.cash, "")
		req.CategoryID = &ids[i]
		req.Amount = 10
		row, err := f.tx.Create(f.user, req)
		if err != nil {
			t.Fatal(err)
		}
		oldRows = append(oldRows, *row)
	}
	if _, err := f.svc.BookInterest(f.user, f.a, DebtInterestRequest{Amount: 10, IdempotencyKey: "existing-duplicates"}); err != nil {
		t.Fatal(err)
	}
	var count int64
	if err := f.repos.Account.DB().Model(&model.Category{}).
		Where("user_id = ? AND name = ?", f.user, "利息").Count(&count).Error; err != nil || count != 2 {
		t.Fatalf("historical category count = %d, want 2: %v", count, err)
	}
	for i, before := range oldRows {
		after, err := f.tx.GetByID(before.ID, f.user)
		if err != nil || after.CategoryID == nil || *after.CategoryID != ids[i] || after.Amount != 10 {
			t.Fatalf("historical transaction was rebound or recalculated: %+v %v", after, err)
		}
	}
	var current model.Transaction
	if err := f.repos.Account.DB().Where("user_id = ? AND source = ?", f.user, "debt_interest").First(&current).Error; err != nil {
		t.Fatal(err)
	}
	if current.CategoryID == nil || (*current.CategoryID != ids[0] && *current.CategoryID != ids[1]) {
		t.Fatalf("new interest did not reuse an existing category: %+v", current)
	}
	debtAssert(t, f, 1010, 1980, 600, 300, 100, 0)
}
