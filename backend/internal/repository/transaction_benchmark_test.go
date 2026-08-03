package repository

import (
	"fmt"
	"path/filepath"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/money"
)

func BenchmarkTransactionRepositoryListRecentPage(b *testing.B) {
	repository, userID, start, end := newTransactionBenchmarkFixture(b, 5000)
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		transactions, total, err := repository.List(TransactionFilter{
			UserID: userID, StartDate: &start, EndDate: &end, Page: 1, PageSize: 50,
		})
		if err != nil || len(transactions) != 50 || total != 5000 {
			b.Fatalf("list result length=%d total=%d err=%v", len(transactions), total, err)
		}
	}
}

func BenchmarkTransactionRepositoryMonthlySummary(b *testing.B) {
	repository, userID, start, end := newTransactionBenchmarkFixture(b, 5000)
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		summary, err := repository.SumByDateRange(userID, start, end)
		if err != nil || summary.Count != 5000 {
			b.Fatalf("summary count=%d err=%v", summary.Count, err)
		}
	}
}

func newTransactionBenchmarkFixture(b *testing.B, count int) (*TransactionRepository, uint, time.Time, time.Time) {
	b.Helper()
	db, err := database.Init(filepath.Join(b.TempDir(), "ledger.db"))
	if err != nil {
		b.Fatalf("init benchmark database: %v", err)
	}
	repos := NewRepositories(db)
	user := &model.User{Username: "benchmark-" + uuid.NewString(), PasswordHash: "hash"}
	if err := repos.User.Create(user); err != nil {
		b.Fatalf("create benchmark user: %v", err)
	}
	account := &model.Account{ID: uuid.NewString(), UserID: user.ID, Name: "Wallet", Type: "cash"}
	if err := repos.Account.Create(account); err != nil {
		b.Fatalf("create benchmark account: %v", err)
	}
	start := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	end := time.Date(2026, 12, 31, 23, 59, 59, 0, time.UTC)
	for offset := 0; offset < count; offset += 500 {
		batchSize := min(500, count-offset)
		batch := make([]model.Transaction, batchSize)
		for index := range batch {
			sequence := offset + index
			transactionType := "expense"
			if sequence%5 == 0 {
				transactionType = "income"
			}
			batch[index] = model.Transaction{
				ID: fmt.Sprintf("benchmark-%06d", sequence), UserID: user.ID, AccountID: account.ID,
				Type: transactionType, Amount: 100 + money.Amount(sequence%1000),
				TransactionDate: start.Add(time.Duration(sequence%365) * 24 * time.Hour), Source: "manual",
			}
		}
		if err := repos.Transaction.DB().Create(&batch).Error; err != nil {
			b.Fatalf("create benchmark transaction batch: %v", err)
		}
	}
	return repos.Transaction, user.ID, start, end
}
