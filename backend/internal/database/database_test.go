package database

import (
	"net/url"
	"path/filepath"
	"strings"
	"testing"

	"github.com/sky/personal-ledger/internal/config"
	"github.com/sky/personal-ledger/internal/model"
)

func TestInitKeepsSQLitePathCompatibility(t *testing.T) {
	db, err := Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init sqlite by path: %v", err)
	}

	if !db.Migrator().HasTable(&model.User{}) {
		t.Fatal("users table was not migrated")
	}
}

func TestInitWithConfigSupportsSQLiteAlias(t *testing.T) {
	db, err := InitWithConfig(config.DatabaseConfig{
		Driver: "sqlite3",
		Path:   filepath.Join(t.TempDir(), "ledger.db"),
	})
	if err != nil {
		t.Fatalf("init sqlite alias: %v", err)
	}

	if !db.Migrator().HasTable(&model.Account{}) {
		t.Fatal("accounts table was not migrated")
	}
}

func TestInitWithConfigRejectsUnsupportedDriver(t *testing.T) {
	_, err := InitWithConfig(config.DatabaseConfig{Driver: "oracle"})
	if err == nil {
		t.Fatal("expected unsupported driver error")
	}
	if !strings.Contains(err.Error(), "unsupported database driver") {
		t.Fatalf("error = %q, want unsupported driver", err.Error())
	}
}

func TestInitWithConfigRequiresDSNForServerDrivers(t *testing.T) {
	for _, driver := range []string{"postgres", "postgresql", "mysql", "mariadb"} {
		t.Run(driver, func(t *testing.T) {
			_, err := InitWithConfig(config.DatabaseConfig{Driver: driver})
			if err == nil {
				t.Fatal("expected missing dsn error")
			}
			if !strings.Contains(err.Error(), "database dsn is required") {
				t.Fatalf("error = %q, want missing dsn", err.Error())
			}
		})
	}
}

func TestNormalizePostgresDSNAddsLocalTimeZoneToURL(t *testing.T) {
	dsn, err := normalizePostgresDSN("postgres://ledger:secret@db:5432/ledger?sslmode=disable")
	if err != nil {
		t.Fatalf("normalize postgres dsn: %v", err)
	}
	postgresURL, err := url.Parse(dsn)
	if err != nil {
		t.Fatalf("parse postgres dsn: %v", err)
	}
	timezone := postgresURL.Query().Get("TimeZone")
	if timezone == "" || strings.EqualFold(timezone, "Local") {
		t.Fatalf("TimeZone = %q, want explicit database timezone", timezone)
	}
	if !strings.Contains(dsn, "TimeZone="+timezone) {
		t.Fatalf("dsn = %q, want raw TimeZone query value", dsn)
	}
}

func TestNormalizePostgresDSNReplacesLocalTimeZoneInURL(t *testing.T) {
	dsn, err := normalizePostgresDSN("postgres://ledger:secret@db:5432/ledger?sslmode=disable&TimeZone=Local")
	if err != nil {
		t.Fatalf("normalize postgres dsn: %v", err)
	}
	postgresURL, err := url.Parse(dsn)
	if err != nil {
		t.Fatalf("parse postgres dsn: %v", err)
	}
	timezone := postgresURL.Query().Get("TimeZone")
	if timezone == "" || strings.EqualFold(timezone, "Local") {
		t.Fatalf("TimeZone = %q, want explicit database timezone", timezone)
	}
}

func TestNormalizePostgresDSNPreservesExplicitTimeZone(t *testing.T) {
	dsn, err := normalizePostgresDSN("postgres://ledger:secret@db:5432/ledger?sslmode=disable&TimeZone=UTC")
	if err != nil {
		t.Fatalf("normalize postgres dsn: %v", err)
	}
	postgresURL, err := url.Parse(dsn)
	if err != nil {
		t.Fatalf("parse postgres dsn: %v", err)
	}
	if got := postgresURL.Query().Get("TimeZone"); got != "UTC" {
		t.Fatalf("TimeZone = %q, want UTC", got)
	}
}

func TestNormalizePostgresKeywordDSNAddsTimeZone(t *testing.T) {
	dsn, err := normalizePostgresDSN("host=db user=ledger dbname=ledger sslmode=disable")
	if err != nil {
		t.Fatalf("normalize postgres dsn: %v", err)
	}
	if !strings.Contains(dsn, "TimeZone=") {
		t.Fatalf("dsn = %q, want TimeZone keyword", dsn)
	}
	if strings.Contains(dsn, "TimeZone=Local") {
		t.Fatalf("dsn = %q, should not use invalid Local timezone", dsn)
	}
}
