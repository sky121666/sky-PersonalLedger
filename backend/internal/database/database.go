package database

import (
	"errors"
	"fmt"
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

const currentSchemaVersion = 1

type schemaMigration struct {
	Version   int       `gorm:"primaryKey"`
	AppliedAt time.Time `gorm:"not null"`
}

func Init(dbPath string) (*gorm.DB, error) {
	return InitWithConfig(config.DatabaseConfig{
		Driver: "sqlite",
		Path:   dbPath,
	})
}

func InitWithConfig(cfg config.DatabaseConfig) (*gorm.DB, error) {
	driver := normalizeDriver(cfg.Driver)

	dialector, isSQLite, err := openDialector(driver, cfg)
	if err != nil {
		return nil, err
	}

	db, err := gorm.Open(dialector, &gorm.Config{
		Logger: logger.Default.LogMode(logger.Info),
	})
	if err != nil {
		return nil, err
	}

	if err := configureConnectionPool(db, cfg); err != nil {
		return nil, err
	}

	if isSQLite {
		if err := db.Exec("PRAGMA journal_mode=WAL;").Error; err != nil {
			return nil, fmt.Errorf("enable sqlite wal mode: %w", err)
		}
	}

	if err := guardSchemaVersion(db); err != nil {
		return nil, err
	}

	if err := db.AutoMigrate(
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
	); err != nil {
		return nil, err
	}

	if err := recordSchemaVersion(db); err != nil {
		return nil, err
	}

	return db, nil
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
		return sqlite.Open(dbPath), true, nil
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

func latestSchemaVersion(db *gorm.DB) (int, error) {
	var version int
	err := db.Model(&schemaMigration{}).
		Select("COALESCE(MAX(version), 0)").
		Scan(&version).Error
	return version, err
}

func recordSchemaVersion(db *gorm.DB) error {
	version, err := latestSchemaVersion(db)
	if err != nil {
		return err
	}
	if version >= currentSchemaVersion {
		return nil
	}

	return db.Clauses(clause.OnConflict{DoNothing: true}).Create(&schemaMigration{
		Version:   currentSchemaVersion,
		AppliedAt: time.Now().UTC(),
	}).Error
}
