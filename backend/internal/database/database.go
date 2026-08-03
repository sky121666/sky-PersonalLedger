package database

import (
	"errors"
	"fmt"
	"io"
	"log"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/sky/personal-ledger/internal/config"
	"github.com/sky/personal-ledger/internal/model"

	"gorm.io/driver/mysql"
	"gorm.io/driver/postgres"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
	"gorm.io/gorm/logger"
)

var schemaMigrations = []versionedMigration{
	{
		Version: 1,
		Name:    "initial_ledger_schema",
		Apply: func(tx *gorm.DB) error {
			return tx.AutoMigrate(
				&model.User{},
				&model.Account{},
				&model.Category{},
				&model.Transaction{},
				&model.Budget{},
				&model.Reminder{},
				&model.RefreshToken{},
				&model.QuickTemplate{},
				&model.NotificationSetting{},
				&model.Lending{},
				&model.LendingRecord{},
				&model.NotificationLog{},
				&model.SystemSetting{},
				&model.AccountLog{},
				&model.Tag{},
				&model.RecurringTransaction{},
				&model.APIToken{},
				&model.FamilyMember{},
				&model.AIProvider{},
				&model.AIReport{},
			)
		},
	},
	{
		Version: 2,
		Name:    "expand_notification_secret_columns",
		Apply: func(tx *gorm.DB) error {
			// AES-GCM adds a nonce and authentication tag before base64 encoding,
			// so the legacy varchar limits are not large enough for every valid
			// SMTP password or webhook secret.
			return tx.AutoMigrate(&model.NotificationSetting{})
		},
	},
	{
		Version: 3,
		Name:    "api_token_scopes_and_revocation",
		Apply: func(tx *gorm.DB) error {
			return tx.AutoMigrate(&model.APIToken{})
		},
	},
	{
		Version: 4,
		Name:    "transaction_import_fingerprint",
		Apply: func(tx *gorm.DB) error {
			return tx.AutoMigrate(&model.Transaction{})
		},
	},
	{
		Version: 5,
		Name:    "persistent_transaction_import_batches",
		Apply: func(tx *gorm.DB) error {
			return tx.AutoMigrate(&model.TransactionImportBatch{})
		},
	},
	{
		Version: 6,
		Name:    "transaction_import_batch_summaries",
		Apply: func(tx *gorm.DB) error {
			return tx.AutoMigrate(&model.TransactionImportBatch{})
		},
	},
	{
		Version: 7,
		Name:    "portable_api_token_scopes",
		Apply: func(tx *gorm.DB) error {
			// MySQL does not allow a default value on TEXT columns. API token
			// scopes have a small bounded vocabulary, so varchar(512) keeps the
			// legacy empty-string default while remaining portable.
			return tx.AutoMigrate(&model.APIToken{})
		},
	},
	{
		Version: 8,
		Name:    "integer_minor_units",
		Apply:   migrateMoneyColumnsToMinorUnits,
	},
}

type moneyColumnMigration struct {
	Table  string
	Legacy string
	Cents  string
}

var moneyColumnMigrations = []moneyColumnMigration{
	{Table: "accounts", Legacy: "initial_balance", Cents: "initial_balance_cents"},
	{Table: "accounts", Legacy: "current_balance", Cents: "current_balance_cents"},
	{Table: "accounts", Legacy: "credit_limit", Cents: "credit_limit_cents"},
	{Table: "accounts", Legacy: "total_paid", Cents: "total_paid_cents"},
	{Table: "transactions", Legacy: "amount", Cents: "amount_cents"},
	{Table: "transactions", Legacy: "principal_amount", Cents: "principal_amount_cents"},
	{Table: "transactions", Legacy: "interest_amount", Cents: "interest_amount_cents"},
	{Table: "budgets", Legacy: "amount", Cents: "amount_cents"},
	{Table: "reminders", Legacy: "amount", Cents: "amount_cents"},
	{Table: "reminders", Legacy: "principal", Cents: "principal_cents"},
	{Table: "reminders", Legacy: "current_balance", Cents: "current_balance_cents"},
	{Table: "reminders", Legacy: "total_interest", Cents: "total_interest_cents"},
	{Table: "reminders", Legacy: "total_paid", Cents: "total_paid_cents"},
	{Table: "reminders", Legacy: "interest_paid", Cents: "interest_paid_cents"},
	{Table: "quick_templates", Legacy: "amount", Cents: "amount_cents"},
	{Table: "lendings", Legacy: "principal", Cents: "principal_cents"},
	{Table: "lendings", Legacy: "current_balance", Cents: "current_balance_cents"},
	{Table: "lendings", Legacy: "total_repaid", Cents: "total_repaid_cents"},
	{Table: "lending_records", Legacy: "amount", Cents: "amount_cents"},
	{Table: "account_logs", Legacy: "amount", Cents: "amount_cents"},
	{Table: "account_logs", Legacy: "balance_before", Cents: "balance_before_cents"},
	{Table: "account_logs", Legacy: "balance_after", Cents: "balance_after_cents"},
	{Table: "recurring_transactions", Legacy: "amount", Cents: "amount_cents"},
}

func migrateMoneyColumnsToMinorUnits(tx *gorm.DB) error {
	if err := tx.AutoMigrate(
		&model.Account{},
		&model.Transaction{},
		&model.Budget{},
		&model.Reminder{},
		&model.QuickTemplate{},
		&model.Lending{},
		&model.LendingRecord{},
		&model.AccountLog{},
		&model.RecurringTransaction{},
	); err != nil {
		return err
	}

	for _, column := range moneyColumnMigrations {
		if !tx.Migrator().HasColumn(column.Table, column.Legacy) ||
			!tx.Migrator().HasColumn(column.Table, column.Cents) {
			continue
		}
		expression, err := roundedMinorUnitExpression(tx.Dialector.Name(), column.Legacy)
		if err != nil {
			return err
		}
		query := fmt.Sprintf(
			"UPDATE %s SET %s = %s WHERE %s IS NOT NULL",
			column.Table, column.Cents, expression, column.Legacy,
		)
		if err := tx.Exec(query).Error; err != nil {
			return fmt.Errorf("backfill %s.%s: %w", column.Table, column.Cents, err)
		}
	}
	return nil
}

func roundedMinorUnitExpression(driver, legacyColumn string) (string, error) {
	switch normalizeDriver(driver) {
	case "sqlite":
		return fmt.Sprintf("CAST(ROUND(%s * 100) AS INTEGER)", legacyColumn), nil
	case "postgres":
		return fmt.Sprintf("CAST(ROUND(%s * 100) AS BIGINT)", legacyColumn), nil
	case "mysql":
		return fmt.Sprintf("CAST(ROUND(%s * 100) AS SIGNED)", legacyColumn), nil
	default:
		return "", fmt.Errorf("unsupported database driver %q for money migration", driver)
	}
}

var currentSchemaVersion = latestKnownSchemaVersion()

type versionedMigration struct {
	Version int
	Name    string
	Apply   func(tx *gorm.DB) error
}

type schemaMigration struct {
	Version   int       `gorm:"primaryKey"`
	Name      string    `gorm:"size:100;not null;default:''"`
	AppliedAt time.Time `gorm:"not null"`
}

func Init(dbPath string) (*gorm.DB, error) {
	return InitWithConfig(config.DatabaseConfig{
		Driver: "sqlite",
		Path:   dbPath,
	})
}

func InitWithConfig(cfg config.DatabaseConfig, logConfigs ...config.LogConfig) (*gorm.DB, error) {
	driver := normalizeDriver(cfg.Driver)

	dialector, isSQLite, err := openDialector(driver, cfg)
	if err != nil {
		return nil, err
	}

	logConfig := config.LogConfig{Level: "warn"}
	if len(logConfigs) > 0 {
		logConfig = logConfigs[0]
	}
	db, err := gorm.Open(dialector, &gorm.Config{Logger: newGORMLogger(os.Stdout, logConfig)})
	if err != nil {
		return nil, err
	}

	if err := configureConnectionPool(db, cfg); err != nil {
		return nil, err
	}

	if isSQLite {
		var foreignKeys int
		if err := db.Raw("PRAGMA foreign_keys;").Scan(&foreignKeys).Error; err != nil {
			return nil, fmt.Errorf("read sqlite foreign key mode: %w", err)
		}
		if foreignKeys != 1 {
			return nil, errors.New("sqlite foreign key enforcement is disabled")
		}
		if err := db.Exec("PRAGMA journal_mode=WAL;").Error; err != nil {
			return nil, fmt.Errorf("enable sqlite wal mode: %w", err)
		}
	}

	if err := guardSchemaVersion(db); err != nil {
		return nil, err
	}

	if err := applySchemaMigrations(db); err != nil {
		return nil, err
	}

	return db, nil
}

func newGORMLogger(writer io.Writer, cfg config.LogConfig) logger.Interface {
	level := logger.Warn
	switch strings.ToLower(strings.TrimSpace(cfg.Level)) {
	case "debug", "trace":
		level = logger.Info
	case "error":
		level = logger.Error
	case "silent", "off", "none":
		level = logger.Silent
	case "info", "warn", "warning", "":
		level = logger.Warn
	}

	return logger.New(log.New(writer, "", log.LstdFlags), logger.Config{
		SlowThreshold:             time.Second,
		LogLevel:                  level,
		IgnoreRecordNotFoundError: true,
		ParameterizedQueries:      true,
		Colorful:                  false,
	})
}

func TestConnection(cfg config.DatabaseConfig) error {
	driver := normalizeDriver(cfg.Driver)

	dialector, _, err := openDialector(driver, cfg)
	if err != nil {
		return err
	}

	db, err := gorm.Open(dialector, &gorm.Config{
		Logger: logger.Default.LogMode(logger.Silent),
	})
	if err != nil {
		return err
	}

	sqlDB, err := db.DB()
	if err != nil {
		return err
	}
	defer sqlDB.Close()

	if cfg.MaxOpenConns > 0 {
		sqlDB.SetMaxOpenConns(cfg.MaxOpenConns)
	}
	if cfg.MaxIdleConns > 0 {
		sqlDB.SetMaxIdleConns(cfg.MaxIdleConns)
	}

	return sqlDB.Ping()
}

func normalizeDriver(driver string) string {
	switch strings.ToLower(strings.TrimSpace(driver)) {
	case "", "sqlite", "sqlite3":
		return "sqlite"
	case "postgres", "postgresql":
		return "postgres"
	case "mysql", "mariadb":
		return "mysql"
	default:
		return strings.ToLower(strings.TrimSpace(driver))
	}
}

func openDialector(driver string, cfg config.DatabaseConfig) (gorm.Dialector, bool, error) {
	switch driver {
	case "sqlite":
		dbPath := strings.TrimSpace(cfg.Path)
		if dbPath == "" {
			return nil, false, errors.New("database path is required for sqlite")
		}
		if err := os.MkdirAll(filepath.Dir(dbPath), 0755); err != nil {
			return nil, false, err
		}
		separator := "?"
		if strings.Contains(dbPath, "?") {
			separator = "&"
		}
		return sqlite.Open(dbPath + separator + "_foreign_keys=on&_busy_timeout=5000"), true, nil
	case "postgres":
		dsn := strings.TrimSpace(cfg.DSN)
		if dsn == "" {
			return nil, false, errors.New("database dsn is required for postgres")
		}
		dsn, err := normalizePostgresDSN(dsn)
		if err != nil {
			return nil, false, err
		}
		return postgres.Open(dsn), false, nil
	case "mysql":
		dsn := strings.TrimSpace(cfg.DSN)
		if dsn == "" {
			return nil, false, errors.New("database dsn is required for mysql")
		}
		return mysql.Open(dsn), false, nil
	default:
		return nil, false, fmt.Errorf("unsupported database driver %q", driver)
	}
}

func normalizePostgresDSN(dsn string) (string, error) {
	timezone, err := config.ResolveDatabaseTimeZone("")
	if err != nil {
		return "", fmt.Errorf("resolve postgres timezone: %w", err)
	}
	if normalized, ok := normalizePostgresURLDSN(dsn, timezone); ok {
		return normalized, nil
	}
	return normalizePostgresKeywordDSN(dsn, timezone), nil
}

func normalizePostgresURLDSN(dsn string, timezone string) (string, bool) {
	postgresURL, err := url.Parse(dsn)
	if err != nil || postgresURL.Scheme == "" {
		return dsn, false
	}

	query := postgresURL.Query()
	hasTimeZone := false
	for key, values := range query {
		if !strings.EqualFold(key, "timezone") {
			continue
		}
		hasTimeZone = true
		value := ""
		if len(values) > 0 {
			value = strings.TrimSpace(values[0])
		}
		if value == "" || strings.EqualFold(value, "local") {
			query.Del(key)
			query.Set("TimeZone", timezone)
		}
	}
	if !hasTimeZone {
		query.Set("TimeZone", timezone)
	}
	postgresURL.RawQuery = encodePostgresURLQuery(query)
	return postgresURL.String(), true
}

func encodePostgresURLQuery(query url.Values) string {
	rawQuery := query.Encode()
	for key, values := range query {
		if !strings.EqualFold(key, "timezone") {
			continue
		}
		for _, value := range values {
			if value == "" {
				continue
			}
			encodedPair := url.QueryEscape(key) + "=" + url.QueryEscape(value)
			rawPair := url.QueryEscape(key) + "=" + value
			rawQuery = strings.ReplaceAll(rawQuery, encodedPair, rawPair)
		}
	}
	return rawQuery
}

func normalizePostgresKeywordDSN(dsn string, timezone string) string {
	fields := strings.Fields(dsn)
	for index, field := range fields {
		key, value, ok := strings.Cut(field, "=")
		if !ok || !strings.EqualFold(strings.TrimSpace(key), "timezone") {
			continue
		}
		trimmedValue := strings.Trim(strings.TrimSpace(value), `'"`)
		if trimmedValue == "" || strings.EqualFold(trimmedValue, "local") {
			fields[index] = "TimeZone=" + quotePostgresKeywordValue(timezone)
			return strings.Join(fields, " ")
		}
		return dsn
	}
	return strings.TrimSpace(dsn) + " TimeZone=" + quotePostgresKeywordValue(timezone)
}

func quotePostgresKeywordValue(value string) string {
	if !strings.ContainsAny(value, " \t\n\r'\\") {
		return value
	}
	escaped := strings.ReplaceAll(value, `\`, `\\`)
	escaped = strings.ReplaceAll(escaped, `'`, `\'`)
	return "'" + escaped + "'"
}

func configureConnectionPool(db *gorm.DB, cfg config.DatabaseConfig) error {
	if cfg.MaxOpenConns <= 0 && cfg.MaxIdleConns <= 0 {
		return nil
	}

	sqlDB, err := db.DB()
	if err != nil {
		return err
	}
	if cfg.MaxOpenConns > 0 {
		sqlDB.SetMaxOpenConns(cfg.MaxOpenConns)
	}
	if cfg.MaxIdleConns > 0 {
		sqlDB.SetMaxIdleConns(cfg.MaxIdleConns)
	}
	return nil
}

func guardSchemaVersion(db *gorm.DB) error {
	if err := db.AutoMigrate(&schemaMigration{}); err != nil {
		return err
	}

	version, err := latestSchemaVersion(db)
	if err != nil {
		return err
	}
	if version > currentSchemaVersion {
		return fmt.Errorf("database schema version %d is newer than this application supports (%d)", version, currentSchemaVersion)
	}
	return nil
}

func applySchemaMigrations(db *gorm.DB) error {
	appliedVersion, err := latestSchemaVersion(db)
	if err != nil {
		return err
	}

	for _, migration := range schemaMigrations {
		if migration.Version <= appliedVersion {
			continue
		}
		migration := migration
		if err := db.Transaction(func(tx *gorm.DB) error {
			if err := migration.Apply(tx); err != nil {
				return fmt.Errorf("apply schema migration %d %s: %w", migration.Version, migration.Name, err)
			}
			return recordSchemaMigration(tx, migration)
		}); err != nil {
			return err
		}
	}
	return nil
}

func latestSchemaVersion(db *gorm.DB) (int, error) {
	var version int
	err := db.Model(&schemaMigration{}).
		Select("COALESCE(MAX(version), 0)").
		Scan(&version).Error
	return version, err
}

func CurrentSchemaVersion() int {
	return currentSchemaVersion
}

func LatestSchemaVersion(db *gorm.DB) (int, error) {
	return latestSchemaVersion(db)
}

func recordSchemaMigration(db *gorm.DB, migration versionedMigration) error {
	return db.Clauses(clause.OnConflict{DoNothing: true}).Create(&schemaMigration{
		Version:   migration.Version,
		Name:      migration.Name,
		AppliedAt: time.Now().UTC(),
	}).Error
}

func latestKnownSchemaVersion() int {
	version := 0
	for _, migration := range schemaMigrations {
		if migration.Version > version {
			version = migration.Version
		}
	}
	return version
}
