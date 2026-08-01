package database

import (
	"bytes"
	"os"
	"strings"
	"testing"
	"time"

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
	assertAPITokenScopesRoundTrip(t, db)
	assertTransactionImportBatchRoundTrip(t, db)
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
	assertAPITokenScopesRoundTrip(t, db)
	assertTransactionImportBatchRoundTrip(t, db)
}

func assertAPITokenScopesRoundTrip(t *testing.T, db *gorm.DB) {
	t.Helper()

	tokenDigest := strings.Repeat(db.Dialector.Name()[:1], 64)
	if err := db.Where("token = ?", tokenDigest).Delete(&model.APIToken{}).Error; err != nil {
		t.Fatalf("clear previous api token: %v", err)
	}
	t.Cleanup(func() {
		if err := db.Where("token = ?", tokenDigest).Delete(&model.APIToken{}).Error; err != nil {
			t.Errorf("clean api token: %v", err)
		}
	})

	wantScopes := `["ledger:read","report:read"]`
	want := model.APIToken{
		UserID:      42,
		Name:        "matrix-scopes",
		Token:       tokenDigest,
		TokenPrefix: "matrix_scope",
		Scopes:      wantScopes,
	}
	if err := db.Create(&want).Error; err != nil {
		t.Fatalf("create api token: %v", err)
	}

	var got model.APIToken
	if err := db.First(&got, "token = ?", tokenDigest).Error; err != nil {
		t.Fatalf("read api token: %v", err)
	}
	if got.Scopes != wantScopes {
		t.Fatalf("api token scopes = %q, want %q", got.Scopes, wantScopes)
	}
}

func assertTransactionImportBatchRoundTrip(t *testing.T, db *gorm.DB) {
	t.Helper()

	id := "matrix-" + db.Dialector.Name()
	if err := db.Where("id = ?", id).Delete(&model.TransactionImportBatch{}).Error; err != nil {
		t.Fatalf("clear previous transaction import batch: %v", err)
	}
	t.Cleanup(func() {
		if err := db.Where("id = ?", id).Delete(&model.TransactionImportBatch{}).Error; err != nil {
			t.Errorf("clean transaction import batch: %v", err)
		}
	})

	now := time.Now().UTC().Truncate(time.Second)
	wantPayload := []byte(`{"version":1,"rows":[{"amount":"12.34"}]}`)
	want := model.TransactionImportBatch{
		ID:            id,
		UserID:        42,
		Filename:      "matrix.csv",
		Format:        "csv",
		FileDigest:    strings.Repeat("a", 64),
		Status:        "validated",
		TotalRows:     2,
		ValidRows:     1,
		InvalidRows:   1,
		DuplicateRows: 0,
		Payload:       wantPayload,
		CreatedAt:     now,
		UpdatedAt:     now,
		ExpiresAt:     now.Add(24 * time.Hour),
	}
	if err := db.Create(&want).Error; err != nil {
		t.Fatalf("create transaction import batch: %v", err)
	}

	var got model.TransactionImportBatch
	if err := db.First(&got, "id = ?", id).Error; err != nil {
		t.Fatalf("read transaction import batch: %v", err)
	}
	if !bytes.Equal(got.Payload, wantPayload) {
		t.Fatalf("transaction import payload = %q, want %q", got.Payload, wantPayload)
	}
	if got.TotalRows != want.TotalRows || got.ValidRows != want.ValidRows || got.InvalidRows != want.InvalidRows {
		t.Fatalf(
			"transaction import summary = (%d, %d, %d), want (%d, %d, %d)",
			got.TotalRows,
			got.ValidRows,
			got.InvalidRows,
			want.TotalRows,
			want.ValidRows,
			want.InvalidRows,
		)
	}
}

func assertMigratedLedgerSchema(t *testing.T, db *gorm.DB) {
	t.Helper()

	migrator := db.Migrator()
	for _, table := range []interface{}{
		&model.User{},
		&model.Account{},
		&model.Transaction{},
		&model.TransactionImportBatch{},
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
