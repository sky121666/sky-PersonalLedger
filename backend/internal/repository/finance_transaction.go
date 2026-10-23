package repository

import (
	"sync"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

var sqliteFinanceWriteMu sync.Mutex

// FinanceWriteTransaction serializes SQLite financial/reference writers in the
// supported single-write-instance deployment. Server databases use row locks.
func FinanceWriteTransaction(db *gorm.DB, fn func(*gorm.DB) error) error {
	if db.Dialector.Name() == "sqlite" {
		sqliteFinanceWriteMu.Lock()
		defer sqliteFinanceWriteMu.Unlock()
	}
	return db.Transaction(fn)
}

func FinanceQueryForUpdate(db *gorm.DB) *gorm.DB {
	switch db.Dialector.Name() {
	case "postgres", "mysql":
		return db.Clauses(clause.Locking{Strength: "UPDATE"})
	default:
		return db
	}
}
