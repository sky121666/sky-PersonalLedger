package service

import (
	"database/sql"
	"errors"
	"fmt"

	"gorm.io/gorm"
)

// withConsistentReadSnapshot keeps related queries on one database snapshot.
// PostgreSQL's default READ COMMITTED is not sufficient: each statement could
// otherwise observe a different committed ledger state. MySQL also requests
// REPEATABLE READ explicitly instead of depending on the server default.
// SQLite pins its read snapshot at the first SELECT in the transaction; the
// configured WAL mode lets other connections commit while that snapshot lives.
// Callers must use snapshot for every query and must not perform writes here.
func withConsistentReadSnapshot(db *gorm.DB, fn func(snapshot *gorm.DB) error) error {
	if _, nested := db.Statement.ConnPool.(gorm.TxCommitter); nested {
		// GORM implements nested transactions as savepoints and would silently
		// ignore these isolation options inside a READ COMMITTED transaction.
		return errors.New("consistent read snapshot requires a new transaction")
	}
	options := &sql.TxOptions{ReadOnly: true}
	switch db.Dialector.Name() {
	case "postgres", "mysql":
		options.Isolation = sql.LevelRepeatableRead
	case "sqlite":
		// go-sqlite3 does not implement TxOptions isolation/read-only flags.
		// An explicit read transaction still provides a stable WAL snapshot.
	default:
		return fmt.Errorf("consistent read snapshot unsupported for database %q", db.Dialector.Name())
	}
	return db.Transaction(fn, options)
}
