package database

import (
	"net/url"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/sky/personal-ledger/internal/config"
	"github.com/sky/personal-ledger/internal/model"

	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
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

func TestInitWithConfigRecordsSchemaVersion(t *testing.T) {
	db, err := InitWithConfig(config.DatabaseConfig{
		Driver: "sqlite",
		Path:   filepath.Join(t.TempDir(), "ledger.db"),
	})
	if err != nil {
		t.Fatalf("init sqlite: %v", err)
	}

	version, err := latestSchemaVersion(db)
	if err != nil {
		t.Fatalf("read schema version: %v", err)
	}
	if version != currentSchemaVersion {
		t.Fatalf("schema version = %d, want %d", version, currentSchemaVersion)
	}

	var migration schemaMigration
	if err := db.First(&migration, "version = ?", currentSchemaVersion).Error; err != nil {
		t.Fatalf("read current migration record: %v", err)
	}
	if migration.Name == "" {
		t.Fatal("schema migration name should be recorded")
	}
}

func TestApplySchemaMigrationsRunsOnlyPendingVersions(t *testing.T) {
	db, err := gorm.Open(sqlite.Open(filepath.Join(t.TempDir(), "ledger.db")), &gorm.Config{})
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	if err := db.AutoMigrate(&schemaMigration{}); err != nil {
		t.Fatalf("migrate schema migrations: %v", err)
	}
	if err := db.Create(&schemaMigration{
		Version:   1,
		Name:      "already_applied",
		AppliedAt: time.Now().UTC(),
	}).Error; err != nil {
		t.Fatalf("seed schema migration: %v", err)
	}

	originalMigrations := schemaMigrations
	originalVersion := currentSchemaVersion
	defer func() {
		schemaMigrations = originalMigrations
		currentSchemaVersion = originalVersion
	}()

	applied := 0
	schemaMigrations = []versionedMigration{
		{
			Version: 1,
			Name:    "already_applied",
			Apply: func(tx *gorm.DB) error {
				t.Fatal("already applied migration should not run")
				return nil
			},
		},
		{
			Version: 2,
			Name:    "add_system_settings",
			Apply: func(tx *gorm.DB) error {
				applied++
				return tx.AutoMigrate(&model.SystemSetting{})
			},
		},
	}
	currentSchemaVersion = latestKnownSchemaVersion()

	if err := applySchemaMigrations(db); err != nil {
		t.Fatalf("apply schema migrations: %v", err)
	}
	if applied != 1 {
		t.Fatalf("pending migration applied %d times, want 1", applied)
	}
	if !db.Migrator().HasTable(&model.SystemSetting{}) {
		t.Fatal("pending migration did not create system settings table")
	}
	version, err := latestSchemaVersion(db)
	if err != nil {
		t.Fatalf("read schema version: %v", err)
	}
	if version != 2 {
		t.Fatalf("schema version = %d, want 2", version)
	}

	if err := applySchemaMigrations(db); err != nil {
		t.Fatalf("reapply schema migrations: %v", err)
	}
	if applied != 1 {
		t.Fatalf("pending migration reapplied, count = %d", applied)
	}
}

func TestInitWithConfigRejectsNewerSchemaVersion(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "ledger.db")
	seedDB, err := gorm.Open(sqlite.Open(dbPath), &gorm.Config{})
	if err != nil {
		t.Fatalf("open seed sqlite: %v", err)
	}
	if err := seedDB.AutoMigrate(&schemaMigration{}); err != nil {
		t.Fatalf("migrate seed schema versions: %v", err)
	}
	if err := seedDB.Create(&schemaMigration{
		Version:   currentSchemaVersion + 1,
		AppliedAt: time.Now().UTC(),
	}).Error; err != nil {
		t.Fatalf("seed future schema version: %v", err)
	}

	_, err = InitWithConfig(config.DatabaseConfig{
		Driver: "sqlite",
		Path:   dbPath,
	})
	if err == nil {
		t.Fatal("expected newer schema version error")
	}
	if !strings.Contains(err.Error(), "newer than this application supports") {
		t.Fatalf("error = %q, want newer schema version error", err.Error())
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
