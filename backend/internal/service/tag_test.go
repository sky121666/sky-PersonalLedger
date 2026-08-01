package service

import (
	"testing"
	"time"

	"github.com/sky/personal-ledger/internal/model"
)

func TestTagRenameRewritesOwnedTransactionsAndReconcilesUsageCount(t *testing.T) {
	transactionService, repos, userID := newTransactionTestService(t)
	accountID := createAccountForTest(t, repos, userID, 100)
	tagService := NewTagService(repos.Tag)
	tag, err := tagService.Create(userID, CreateTagRequest{Name: "旧标签", Color: "#111111"})
	if err != nil {
		t.Fatalf("create tag: %v", err)
	}

	created := make([]*model.Transaction, 0, 2)
	for index := 0; index < 2; index++ {
		transaction, err := transactionService.Create(userID, CreateTransactionRequest{
			Type:            "expense",
			Amount:          5,
			AccountID:       accountID,
			TransactionDate: time.Date(2026, time.July, 20+index, 12, 0, 0, 0, time.Local).Format(time.RFC3339),
			Tags:            `["旧标签"]`,
		})
		if err != nil {
			t.Fatalf("create tagged transaction %d: %v", index, err)
		}
		created = append(created, transaction)
	}

	// Simulate a transaction restored by an older version whose tag counter was
	// not maintained, so rename also proves that it reconciles stale history.
	historical := &model.Transaction{
		ID:              "historical-tagged-transaction",
		UserID:          userID,
		AccountID:       accountID,
		Type:            "expense",
		Amount:          1,
		TransactionDate: time.Date(2026, time.July, 22, 12, 0, 0, 0, time.Local),
		Tags:            `["旧标签"]`,
		Source:          "manual",
	}
	if err := repos.Transaction.Create(historical); err != nil {
		t.Fatalf("create historical transaction: %v", err)
	}

	other := &model.User{Username: "other-tag-rename-user", PasswordHash: "hash"}
	if err := repos.User.Create(other); err != nil {
		t.Fatalf("create other user: %v", err)
	}
	otherAccountID := createAccountForTest(t, repos, other.ID, 100)
	otherTransaction := &model.Transaction{
		ID:              "other-user-tagged-transaction",
		UserID:          other.ID,
		AccountID:       otherAccountID,
		Type:            "expense",
		Amount:          1,
		TransactionDate: time.Date(2026, time.July, 22, 12, 0, 0, 0, time.Local),
		Tags:            `["旧标签"]`,
		Source:          "manual",
	}
	if err := repos.Transaction.Create(otherTransaction); err != nil {
		t.Fatalf("create other user transaction: %v", err)
	}

	updated, err := tagService.Update(tag.ID, userID, CreateTagRequest{
		Name:  "新标签",
		Color: "#222222",
		Icon:  "tag",
	})
	if err != nil {
		t.Fatalf("rename tag: %v", err)
	}
	if updated.Name != "新标签" || updated.UsedCount != 3 {
		t.Fatalf("updated tag = %#v, want renamed with reconciled count 3", updated)
	}

	for _, transactionID := range []string{created[0].ID, created[1].ID, historical.ID} {
		transaction, err := repos.Transaction.GetByIDForUser(transactionID, userID)
		if err != nil {
			t.Fatalf("get rewritten transaction %s: %v", transactionID, err)
		}
		if names := transactionTagNames(transaction.Tags); len(names) != 1 || names[0] != "新标签" {
			t.Fatalf("transaction %s tags = %#v, want new tag", transactionID, names)
		}
	}
	otherReloaded, err := repos.Transaction.GetByIDForUser(otherTransaction.ID, other.ID)
	if err != nil {
		t.Fatalf("get other user transaction: %v", err)
	}
	if names := transactionTagNames(otherReloaded.Tags); len(names) != 1 || names[0] != "旧标签" {
		t.Fatalf("other user tags = %#v, want unchanged old tag", names)
	}

	if err := transactionService.Delete(created[0].ID, userID); err != nil {
		t.Fatalf("delete renamed tagged transaction: %v", err)
	}
	reloaded, err := repos.Tag.GetByID(tag.ID)
	if err != nil {
		t.Fatalf("get tag after transaction delete: %v", err)
	}
	if reloaded.UsedCount != 2 {
		t.Fatalf("used_count after delete = %d, want 2", reloaded.UsedCount)
	}
}
