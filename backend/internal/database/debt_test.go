package database

import (
	"fmt"
	"path/filepath"
	"testing"

	"github.com/sky/personal-ledger/internal/model"
)

func TestDebtMigrationAddsZeroEffectColumnsToPopulatedLegacyLogs(t *testing.T) {
	db, err := Init(filepath.Join(t.TempDir(), "upgrade.db"))
	if err != nil {
		t.Fatal(err)
	}
	account := model.Account{ID: "existing-account", UserID: 1, Name: "Legacy", Type: "cash", CurrentBalance: 123.45}
	if err := db.Create(&account).Error; err != nil {
		t.Fatal(err)
	}
	for _, column := range []string{"debt_tracking_mode", "unplanned_debt_cents", "unapplied_payment_cents", "debt_unclassified_cents"} {
		if err := db.Exec("ALTER TABLE accounts DROP COLUMN " + column).Error; err != nil {
			t.Fatal(err)
		}
	}
	columns := []string{"unplanned_debt_delta_cents", "unapplied_delta_cents", "principal_paid_delta_cents", "unclassified_delta_cents"}
	for _, column := range columns {
		if err := db.Exec("ALTER TABLE account_logs DROP COLUMN " + column).Error; err != nil {
			t.Fatal(err)
		}
	}
	if err := db.Exec(`INSERT INTO account_logs (id,user_id,account_id,type,amount_cents,balance_before_cents,balance_after_cents,created_at)
		VALUES ('legacy-log',1,'existing-account','adjustment',12345,0,12345,'2026-10-01 00:00:00')`).Error; err != nil {
		t.Fatal(err)
	}
	if err := schemaMigrations[len(schemaMigrations)-1].Apply(db); err != nil {
		t.Fatal(err)
	}
	for _, column := range columns {
		var value int64
		if err := db.Raw(fmt.Sprintf("SELECT %s FROM account_logs WHERE id = ?", column), "legacy-log").Scan(&value).Error; err != nil || value != 0 {
			t.Fatalf("legacy effect %s = %d, %v", column, value, err)
		}
	}
	var amount int64
	db.Raw("SELECT amount_cents FROM account_logs WHERE id = 'legacy-log'").Scan(&amount)
	if amount != 12345 {
		t.Fatal("legacy amount was recalculated")
	}
	var legacy struct {
		Mode    string
		Balance int64
	}
	if err := db.Raw("SELECT debt_tracking_mode AS mode,current_balance_cents AS balance FROM accounts WHERE id = ?", account.ID).Scan(&legacy).Error; err != nil {
		t.Fatal(err)
	}
	if legacy.Mode != "legacy" || legacy.Balance != 12345 {
		t.Fatalf("existing account was converted: %+v", legacy)
	}
}

func TestDebtSchemaSupportsPlansWithoutConvertingLegacyAccounts(t *testing.T) {
	path := filepath.Join(t.TempDir(), "isolated.db")
	db, err := Init(path)
	if err != nil {
		t.Fatal(err)
	}
	for _, table := range []string{"debt_plans", "debt_operations", "debt_allocations"} {
		if !db.Migrator().HasTable(table) {
			t.Errorf("missing financial persistence table %s", table)
		}
	}
	if !db.Migrator().HasColumn(&model.Account{}, "debt_tracking_mode") {
		t.Fatal("accounts do not distinguish legacy from managed debt")
	}
	account := model.Account{ID: "legacy-account", UserID: 1, Name: "Synthetic legacy", Type: "credit", CurrentBalance: 123.45}
	if err := db.Create(&account).Error; err != nil {
		t.Fatal(err)
	}
	var row struct {
		CurrentBalance int64
		Mode           string
		Unplanned      int64
		Pending        int64
	}
	if err := db.Raw("SELECT current_balance_cents AS current_balance, debt_tracking_mode AS mode, unplanned_debt_cents AS unplanned, unapplied_payment_cents AS pending FROM accounts WHERE id = ?", account.ID).Scan(&row).Error; err != nil {
		t.Fatal(err)
	}
	if row.CurrentBalance != 12345 || row.Mode != "legacy" || row.Unplanned != 0 || row.Pending != 0 {
		t.Fatalf("legacy data was converted or recomputed: %+v", row)
	}
	sqlDB, _ := db.DB()
	if err := sqlDB.Close(); err != nil {
		t.Fatal(err)
	}
	reopened, err := Init(path)
	if err != nil {
		t.Fatal(err)
	}
	var count int64
	if err := reopened.Table("debt_operations").Count(&count).Error; err != nil || count != 0 {
		t.Fatalf("migration invented history: count=%d err=%v", count, err)
	}
}
