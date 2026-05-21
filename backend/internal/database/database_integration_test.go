package database

import (
	"os"
	"strings"
	"testing"

	"github.com/sky/personal-ledger/internal/config"
	"github.com/sky/personal-ledger/internal/model"

	"gorm.io/gorm"
)

func TestInitWithConfigPostgresIntegration(t *testing.T) {
	dsn := strings.TrimSpace(os.Getenv("LEDGER_TEST_POSTGRES_DSN"))
	if dsn == "" {
		t.Skip("set LEDGER_TEST_POSTGRES_DSN to run PostgreSQL integration test")
	}

	db, err := InitWithConfig(config.DatabaseConfig{
		Driver:       "postgres",
		DSN:          dsn,
		MaxOpenConns: 2,
		MaxIdleConns: 1,
	})
	if err != nil {
		t.Fatalf("init postgres: %v", err)
	}

	assertMigratedLedgerSchema(t, db)
	assertCurrentSchemaVersion(t, db)
}

func TestInitWithConfigMySQLIntegration(t *testing.T) {
	dsn := strings.TrimSpace(os.Getenv("LEDGER_TEST_MYSQL_DSN"))
	if dsn == "" {
		t.Skip("set LEDGER_TEST_MYSQL_DSN to run MySQL integration test")
	}

	db, err := InitWithConfig(config.DatabaseConfig{
		Driver:       "mysql",
		DSN:          dsn,
		MaxOpenConns: 2,
		MaxIdleConns: 1,
	})
	if err != nil {
		t.Fatalf("init mysql: %v", err)
	}

	assertMigratedLedgerSchema(t, db)
	assertCurrentSchemaVersion(t, db)
}

func assertMigratedLedgerSchema(t *testing.T, db *gorm.DB) {
	t.Helper()

	migrator := db.Migrator()
	for _, table := range []interface{}{
		&model.User{},
		&model.Account{},
		&model.Transaction{},
		&model.SystemSetting{},
		&schemaMigration{},
	} {
		if !migrator.HasTable(table) {
			t.Fatalf("expected migrated table for %T", table)
		}
	}
}

func assertCurrentSchemaVersion(t *testing.T, db *gorm.DB) {
	t.Helper()

	version, err := latestSchemaVersion(db)
	if err != nil {
		t.Fatalf("read schema version: %v", err)
	}
	if version != currentSchemaVersion {
		t.Fatalf("schema version = %d, want %d", version, currentSchemaVersion)
	}
}
