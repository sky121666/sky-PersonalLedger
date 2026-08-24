package database

import (
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/sky/personal-ledger/internal/config"
	"github.com/sky/personal-ledger/internal/model"

	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

// These fixtures intentionally model the unversioned schema that existed
// before schema_migrations was introduced. Keep them narrower than the current
// models so this test proves that v1 upgrades old data instead of only creating
// a fresh database.
type legacyUserV0 struct {
	ID           uint   `gorm:"primaryKey"`
	Username     string `gorm:"size:50;uniqueIndex;not null"`
	PasswordHash string `gorm:"size:255;not null"`
}

func (legacyUserV0) TableName() string { return "users" }

type legacyAccountV0 struct {
	ID             string  `gorm:"primaryKey;size:36"`
	UserID         uint    `gorm:"not null;index"`
	Name           string  `gorm:"size:100;not null"`
	Type           string  `gorm:"size:20;not null"`
	InitialBalance float64 `gorm:"type:decimal(15,2);default:0"`
	CurrentBalance float64 `gorm:"type:decimal(15,2);default:0"`
}

func (legacyAccountV0) TableName() string { return "accounts" }

type legacyNotificationSettingV1 struct {
	ID             uint   `gorm:"primaryKey"`
	UserID         uint   `gorm:"uniqueIndex;not null"`
	DingtalkSecret string `gorm:"size:100"`
	SmtpPassword   string `gorm:"size:200"`
	WebhookSecret  string `gorm:"size:100"`
}

func (legacyNotificationSettingV1) TableName() string { return "notification_settings" }

type legacyAPITokenV6 struct {
	ID          uint   `gorm:"primaryKey"`
	UserID      uint   `gorm:"index"`
	Name        string `gorm:"size:100"`
	Token       string `gorm:"size:64;uniqueIndex"`
	TokenPrefix string `gorm:"size:16"`
	Scopes      string `gorm:"type:text;not null;default:''"`
	CreatedAt   time.Time
}

func (legacyAPITokenV6) TableName() string { return "api_tokens" }

type legacyMoneyAccountV7 struct {
	ID             string   `gorm:"primaryKey;size:36"`
	UserID         uint     `gorm:"not null;index"`
	Name           string   `gorm:"size:100;not null"`
	Type           string   `gorm:"size:20;not null"`
	InitialBalance float64  `gorm:"type:decimal(15,3);default:0"`
	CurrentBalance float64  `gorm:"type:decimal(15,3);default:0"`
	CreditLimit    *float64 `gorm:"type:decimal(15,3)"`
	TotalPaid      float64  `gorm:"type:decimal(15,3);default:0"`
}

func (legacyMoneyAccountV7) TableName() string { return "accounts" }

func TestInitKeepsSQLitePathCompatibility(t *testing.T) {
	db, err := Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init sqlite by path: %v", err)
	}

	if !db.Migrator().HasTable(&model.User{}) {
		t.Fatal("users table was not migrated")
	}
}

func TestInitHardensSQLiteFileAndDirectoryPermissions(t *testing.T) {
	directory := filepath.Join(t.TempDir(), "data")
	dbPath := filepath.Join(directory, "ledger.db")
	if _, err := Init(dbPath); err != nil {
		t.Fatalf("init sqlite: %v", err)
	}

	directoryInfo, err := os.Stat(directory)
	if err != nil {
		t.Fatalf("stat data directory: %v", err)
	}
	if got := directoryInfo.Mode().Perm(); got != 0700 {
		t.Fatalf("data directory permissions = %o, want 700", got)
	}
	databaseInfo, err := os.Stat(dbPath)
	if err != nil {
		t.Fatalf("stat sqlite database: %v", err)
	}
	if got := databaseInfo.Mode().Perm(); got != 0600 {
		t.Fatalf("sqlite database permissions = %o, want 600", got)
	}
}

func TestInitHardensSQLiteFileWhenDSNHasQueryParameters(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "ledger-query.db")
	if err := os.WriteFile(dbPath, []byte{}, 0666); err != nil {
		t.Fatalf("seed sqlite file: %v", err)
	}
	if err := os.Chmod(dbPath, 0666); err != nil {
		t.Fatalf("set broad sqlite permissions: %v", err)
	}

	if _, err := Init(dbPath + "?cache=shared"); err != nil {
		t.Fatalf("init sqlite query DSN: %v", err)
	}
	info, err := os.Stat(dbPath)
	if err != nil {
		t.Fatalf("stat sqlite file: %v", err)
	}
	if got := info.Mode().Perm(); got != 0600 {
		t.Fatalf("sqlite database permissions = %o, want 600", got)
	}
}

func TestSQLiteStoragePathSupportsFileURIAndMemoryDSN(t *testing.T) {
	path, err := sqliteStoragePath("file:///tmp/ledger%20data.db?cache=shared")
	if err != nil {
		t.Fatalf("resolve sqlite file URI: %v", err)
	}
	if path != "/tmp/ledger data.db" {
		t.Fatalf("sqlite file URI path = %q, want decoded filesystem path", path)
	}
	for _, dsn := range []string{":memory:", ":memory:?cache=shared", "file::memory:?cache=shared", "file:temporary?mode=memory&cache=shared"} {
		path, err := sqliteStoragePath(dsn)
		if err != nil {
			t.Fatalf("resolve memory DSN %q: %v", dsn, err)
		}
		if path != "" {
			t.Fatalf("memory DSN %q resolved to filesystem path %q", dsn, path)
		}
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

func TestInitWithConfigEnablesSQLiteForeignKeys(t *testing.T) {
	db, err := InitWithConfig(config.DatabaseConfig{
		Driver: "sqlite",
		Path:   filepath.Join(t.TempDir(), "foreign-keys.db"),
	})
	if err != nil {
		t.Fatalf("init sqlite: %v", err)
	}
	var enabled int
	if err := db.Raw("PRAGMA foreign_keys;").Scan(&enabled).Error; err != nil {
		t.Fatalf("read foreign key pragma: %v", err)
	}
	if enabled != 1 {
		t.Fatalf("foreign_keys = %d, want 1", enabled)
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

func TestMoneyMigrationBackfillsRoundedCentsAndKeepsLegacyColumns(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "money-v7.db")
	legacyDB, err := gorm.Open(sqlite.Open(dbPath), &gorm.Config{})
	if err != nil {
		t.Fatalf("open v7 sqlite: %v", err)
	}
	if err := legacyDB.AutoMigrate(&schemaMigration{}, &legacyMoneyAccountV7{}); err != nil {
		t.Fatalf("create v7 money schema: %v", err)
	}
	if err := legacyDB.Create(&schemaMigration{
		Version: 7, Name: "portable_api_token_scopes", AppliedAt: time.Now().UTC(),
	}).Error; err != nil {
		t.Fatalf("record v7 schema: %v", err)
	}
	legacy := legacyMoneyAccountV7{
		ID: "money-account", UserID: 7, Name: "rounding", Type: "cash",
		InitialBalance: 12.345, CurrentBalance: -0.005, CreditLimit: nil, TotalPaid: 0.005,
	}
	if err := legacyDB.Create(&legacy).Error; err != nil {
		t.Fatalf("seed v7 money data: %v", err)
	}
	legacySQLDB, err := legacyDB.DB()
	if err != nil {
		t.Fatalf("get v7 sqlite handle: %v", err)
	}
	if err := legacySQLDB.Close(); err != nil {
		t.Fatalf("close v7 sqlite: %v", err)
	}

	db, err := InitWithConfig(config.DatabaseConfig{Driver: "sqlite", Path: dbPath})
	if err != nil {
		t.Fatalf("upgrade v7 money schema: %v", err)
	}
	var account model.Account
	if err := db.First(&account, "id = ?", legacy.ID).Error; err != nil {
		t.Fatalf("load migrated account: %v", err)
	}
	if account.InitialBalance.Cents() != 1235 || account.CurrentBalance.Cents() != -1 ||
		account.CreditLimit != nil || account.TotalPaid.Cents() != 1 {
		t.Fatalf("migrated cents = initial %d current %d credit %#v paid %d",
			account.InitialBalance.Cents(), account.CurrentBalance.Cents(), account.CreditLimit, account.TotalPaid.Cents())
	}
	for _, column := range []string{"initial_balance", "current_balance", "credit_limit", "total_paid"} {
		if !db.Migrator().HasColumn("accounts", column) {
			t.Fatalf("rollback snapshot column %s was removed", column)
		}
	}
}

func TestInitWithConfigUpgradesUnversionedV0WithoutLosingData(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "legacy-ledger.db")
	legacyDB, err := gorm.Open(sqlite.Open(dbPath), &gorm.Config{})
	if err != nil {
		t.Fatalf("open legacy sqlite: %v", err)
	}
	if err := legacyDB.AutoMigrate(&legacyUserV0{}, &legacyAccountV0{}); err != nil {
		t.Fatalf("create legacy schema: %v", err)
	}
	if err := legacyDB.Create(&legacyUserV0{
		ID:           7,
		Username:     "legacy-user",
		PasswordHash: "legacy-password-hash",
	}).Error; err != nil {
		t.Fatalf("seed legacy user: %v", err)
	}
	if err := legacyDB.Create(&legacyAccountV0{
		ID:             "legacy-account",
		UserID:         7,
		Name:           "旧版现金账户",
		Type:           "cash",
		InitialBalance: 123.45,
		CurrentBalance: 120.34,
	}).Error; err != nil {
		t.Fatalf("seed legacy account: %v", err)
	}
	legacySQLDB, err := legacyDB.DB()
	if err != nil {
		t.Fatalf("get legacy sql db: %v", err)
	}
	if err := legacySQLDB.Close(); err != nil {
		t.Fatalf("close legacy sqlite: %v", err)
	}

	db, err := InitWithConfig(config.DatabaseConfig{
		Driver: "sqlite",
		Path:   dbPath,
	})
	if err != nil {
		t.Fatalf("upgrade legacy sqlite: %v", err)
	}

	var account model.Account
	if err := db.First(&account, "id = ? AND user_id = ?", "legacy-account", 7).Error; err != nil {
		t.Fatalf("read upgraded legacy account: %v", err)
	}
	if account.Name != "旧版现金账户" || account.CurrentBalance != 120.34 {
		t.Fatalf("legacy account changed during migration: %+v", account)
	}
	if !db.Migrator().HasColumn(&model.Account{}, "is_archived") {
		t.Fatal("v1 migration did not add current account columns")
	}
	version, err := latestSchemaVersion(db)
	if err != nil {
		t.Fatalf("read upgraded schema version: %v", err)
	}
	if version != currentSchemaVersion {
		t.Fatalf("upgraded schema version = %d, want %d", version, currentSchemaVersion)
	}
}

func TestInitWithConfigExpandsNotificationCredentialColumns(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "notification-v1.db")
	legacyDB, err := gorm.Open(sqlite.Open(dbPath), &gorm.Config{})
	if err != nil {
		t.Fatalf("open v1 sqlite: %v", err)
	}
	if err := legacyDB.AutoMigrate(&schemaMigration{}, &legacyNotificationSettingV1{}); err != nil {
		t.Fatalf("create v1 notification schema: %v", err)
	}
	if err := legacyDB.Create(&schemaMigration{
		Version:   1,
		Name:      "initial_ledger_schema",
		AppliedAt: time.Now().UTC(),
	}).Error; err != nil {
		t.Fatalf("record v1 schema: %v", err)
	}
	legacySetting := legacyNotificationSettingV1{
		UserID:         7,
		DingtalkSecret: "legacy-dingtalk-secret",
		SmtpPassword:   "legacy-smtp-password",
		WebhookSecret:  "legacy-webhook-secret",
	}
	if err := legacyDB.Create(&legacySetting).Error; err != nil {
		t.Fatalf("seed v1 notification setting: %v", err)
	}
	legacySQLDB, err := legacyDB.DB()
	if err != nil {
		t.Fatalf("get v1 sqlite handle: %v", err)
	}
	if err := legacySQLDB.Close(); err != nil {
		t.Fatalf("close v1 sqlite: %v", err)
	}

	db, err := InitWithConfig(config.DatabaseConfig{Driver: "sqlite", Path: dbPath})
	if err != nil {
		t.Fatalf("upgrade notification schema: %v", err)
	}
	var upgraded model.NotificationSetting
	if err := db.First(&upgraded, "user_id = ?", 7).Error; err != nil {
		t.Fatalf("load upgraded notification setting: %v", err)
	}
	if upgraded.DingtalkSecret != legacySetting.DingtalkSecret ||
		upgraded.SmtpPassword != legacySetting.SmtpPassword ||
		upgraded.WebhookSecret != legacySetting.WebhookSecret {
		t.Fatal("notification credentials changed during schema expansion")
	}

	columnTypes, err := db.Migrator().ColumnTypes(&model.NotificationSetting{})
	if err != nil {
		t.Fatalf("inspect notification credential columns: %v", err)
	}
	credentialColumns := map[string]bool{
		"wecom_webhook":    false,
		"dingtalk_webhook": false,
		"dingtalk_secret":  false,
		"smtp_password":    false,
		"webhook_url":      false,
		"webhook_secret":   false,
	}
	for _, columnType := range columnTypes {
		if _, ok := credentialColumns[columnType.Name()]; !ok {
			continue
		}
		if !strings.EqualFold(columnType.DatabaseTypeName(), "text") {
			t.Fatalf("column %s type = %s, want text", columnType.Name(), columnType.DatabaseTypeName())
		}
		credentialColumns[columnType.Name()] = true
	}
	for column, found := range credentialColumns {
		if !found {
			t.Fatalf("notification credential column %s was not found", column)
		}
	}
}

func TestInitWithConfigMigratesLegacyAPITokenScopesWithoutLosingData(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "api-token-v6.db")
	legacyDB, err := gorm.Open(sqlite.Open(dbPath), &gorm.Config{})
	if err != nil {
		t.Fatalf("open v6 sqlite: %v", err)
	}
	if err := legacyDB.AutoMigrate(&schemaMigration{}, &legacyAPITokenV6{}); err != nil {
		t.Fatalf("create v6 api token schema: %v", err)
	}
	if err := legacyDB.Create(&schemaMigration{
		Version:   6,
		Name:      "transaction_import_batch_summaries",
		AppliedAt: time.Now().UTC(),
	}).Error; err != nil {
		t.Fatalf("record v6 schema: %v", err)
	}
	legacyToken := legacyAPITokenV6{
		UserID:      7,
		Name:        "legacy-scoped-token",
		Token:       strings.Repeat("a", 64),
		TokenPrefix: "sky_ledger_a",
		Scopes:      `["ledger:read","report:read"]`,
		CreatedAt:   time.Now().UTC(),
	}
	if err := legacyDB.Create(&legacyToken).Error; err != nil {
		t.Fatalf("seed v6 api token: %v", err)
	}
	legacySQLDB, err := legacyDB.DB()
	if err != nil {
		t.Fatalf("get v6 sqlite handle: %v", err)
	}
	if err := legacySQLDB.Close(); err != nil {
		t.Fatalf("close v6 sqlite: %v", err)
	}

	db, err := InitWithConfig(config.DatabaseConfig{Driver: "sqlite", Path: dbPath})
	if err != nil {
		t.Fatalf("upgrade api token schema: %v", err)
	}
	var upgraded model.APIToken
	if err := db.First(&upgraded, "id = ?", legacyToken.ID).Error; err != nil {
		t.Fatalf("load upgraded api token: %v", err)
	}
	if upgraded.Scopes != legacyToken.Scopes || upgraded.Token != legacyToken.Token {
		t.Fatal("api token security data changed during portable scope migration")
	}
	version, err := latestSchemaVersion(db)
	if err != nil {
		t.Fatalf("read upgraded schema version: %v", err)
	}
	if version != currentSchemaVersion {
		t.Fatalf("upgraded schema version = %d, want %d", version, currentSchemaVersion)
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
