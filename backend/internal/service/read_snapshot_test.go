package service

import (
	"context"
	"database/sql"
	"testing"

	"gorm.io/gorm"
)

type snapshotTestDialector struct {
	gorm.Dialector
	name string
}

func (d snapshotTestDialector) Name() string { return d.name }

type snapshotTestPool struct {
	gorm.ConnPool
	beginner gorm.TxBeginner
	options  *sql.TxOptions
}

func (p *snapshotTestPool) BeginTx(ctx context.Context, options *sql.TxOptions) (gorm.ConnPool, error) {
	copy := *options
	p.options = &copy
	return p.beginner.BeginTx(ctx, options)
}

// This checks the database/sql contract we request, not a simulated claim of
// PostgreSQL/MySQL integration coverage. Actual WAL snapshot behavior is covered
// by TestCreateBackupUsesOneSnapshotAcrossConcurrentLedgerWrites.
func TestConsistentReadSnapshotRequestsExplicitIsolation(t *testing.T) {
	_, repos, _ := newTransactionTestService(t)
	for _, driver := range []string{"sqlite", "postgres", "mysql"} {
		t.Run(driver, func(t *testing.T) {
			db := repos.User.DB().Session(&gorm.Session{NewDB: true, Context: context.Background()})
			db.Dialector = snapshotTestDialector{Dialector: db.Dialector, name: driver}
			pool := &snapshotTestPool{ConnPool: db.Statement.ConnPool, beginner: db.Statement.ConnPool.(gorm.TxBeginner)}
			db.Statement.ConnPool = pool
			if err := withConsistentReadSnapshot(db, func(*gorm.DB) error { return nil }); err != nil {
				t.Fatal(err)
			}
			if pool.options == nil || !pool.options.ReadOnly {
				t.Fatal("snapshot did not request a read-only transaction")
			}
			if driver != "sqlite" && pool.options.Isolation != sql.LevelRepeatableRead {
				t.Fatalf("isolation=%v, want repeatable read", pool.options.Isolation)
			}
		})
	}
}

func TestConsistentReadSnapshotRejectsNestedTransaction(t *testing.T) {
	_, repos, _ := newTransactionTestService(t)
	if err := repos.User.DB().Transaction(func(txdb *gorm.DB) error {
		called := false
		err := withConsistentReadSnapshot(txdb, func(*gorm.DB) error { called = true; return nil })
		if err == nil || called {
			t.Fatal("nested savepoint silently accepted without new snapshot isolation")
		}
		return nil
	}); err != nil {
		t.Fatal(err)
	}
}
