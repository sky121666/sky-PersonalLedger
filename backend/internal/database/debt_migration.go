package database

import (
	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

func migrateManagedDebt(tx *gorm.DB) error {
	// Old logs have no debt-operation effects. Supply SQL zero defaults while
	// adding their columns; model-level defaults would make GORM mutate
	// unaddressable value inserts that were valid before this migration.
	for _, column := range []string{
		"unplanned_debt_delta_cents", "unapplied_delta_cents",
		"principal_paid_delta_cents", "unclassified_delta_cents",
	} {
		if tx.Migrator().HasTable(&model.AccountLog{}) && !tx.Migrator().HasColumn(&model.AccountLog{}, column) {
			if err := tx.Exec("ALTER TABLE account_logs ADD COLUMN " + column + " BIGINT NOT NULL DEFAULT 0").Error; err != nil {
				return err
			}
		}
	}
	return tx.AutoMigrate(&model.Account{}, &model.Transaction{}, &model.AccountLog{},
		&model.DebtPlan{}, &model.DebtOperation{}, &model.DebtAllocation{})
}
