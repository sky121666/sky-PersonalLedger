package database

import (
	"path/filepath"
	"strings"
	"testing"

	"gorm.io/gorm"
)

func TestOperationalQueryIndexesExistAndDriveSQLitePlans(t *testing.T) {
	db, err := Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init database: %v", err)
	}
	for _, index := range []struct {
		table string
		name  string
	}{
		{"accounts", "idx_accounts_user_archived_sort"},
		{"categories", "idx_categories_user_type_sort"},
		{"transactions", "idx_transactions_user_date"},
		{"transactions", "idx_transactions_user_type_date"},
		{"budgets", "idx_budgets_user_scope"},
		{"reminders", "idx_reminders_user_account"},
		{"account_logs", "idx_account_logs_user_account_created"},
	} {
		if !db.Migrator().HasIndex(index.table, index.name) {
			t.Errorf("missing operational index %s on %s", index.name, index.table)
		}
	}

	assertSQLiteQueryUsesIndex(t, db,
		"EXPLAIN QUERY PLAN SELECT * FROM transactions WHERE user_id = ? AND transaction_date >= ? AND transaction_date <= ? ORDER BY transaction_date DESC LIMIT 50",
		"idx_transactions_user_date", 1, "2026-01-01", "2026-12-31")
	assertSQLiteQueryUsesIndex(t, db,
		"EXPLAIN QUERY PLAN SELECT category_id, SUM(amount_cents) FROM transactions WHERE user_id = ? AND type = ? AND transaction_date >= ? AND transaction_date <= ? GROUP BY category_id",
		"idx_transactions_user_type_date", 1, "expense", "2026-01-01", "2026-12-31")
}

func assertSQLiteQueryUsesIndex(t *testing.T, db *gorm.DB, query, expectedIndex string, args ...interface{}) {
	t.Helper()
	var rows []struct {
		Detail string `gorm:"column:detail"`
	}
	if err := db.Raw(query, args...).Scan(&rows).Error; err != nil {
		t.Fatalf("explain query plan: %v", err)
	}
	var details []string
	for _, row := range rows {
		details = append(details, row.Detail)
		if strings.Contains(row.Detail, expectedIndex) {
			return
		}
	}
	t.Fatalf("query plan did not use %s: %s", expectedIndex, strings.Join(details, " | "))
}
