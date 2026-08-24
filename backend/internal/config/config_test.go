package config

import (
	"os"
	"testing"

	"github.com/spf13/viper"
)

func resetViperForTest(t *testing.T) {
	t.Helper()
	viper.Reset()
	t.Cleanup(viper.Reset)
}

func chdirForTest(t *testing.T, dir string) {
	t.Helper()
	previous, err := os.Getwd()
	if err != nil {
		t.Fatalf("get cwd: %v", err)
	}
	if err := os.Chdir(dir); err != nil {
		t.Fatalf("chdir: %v", err)
	}
	t.Cleanup(func() {
		if err := os.Chdir(previous); err != nil {
			t.Fatalf("restore cwd: %v", err)
		}
	})
}

func TestLoadDatabaseCompatibilityDefaults(t *testing.T) {
	resetViperForTest(t)
	chdirForTest(t, t.TempDir())

	cfg, err := Load()
	if err != nil {
		t.Fatalf("load config: %v", err)
	}

	if cfg.Database.Driver != "sqlite" {
		t.Fatalf("database driver = %q, want sqlite", cfg.Database.Driver)
	}
	if cfg.Database.Path != "./data/ledger.db" {
		t.Fatalf("database path = %q, want ./data/ledger.db", cfg.Database.Path)
	}
	if cfg.Database.DSN != "" {
		t.Fatalf("database dsn = %q, want empty", cfg.Database.DSN)
	}
	if cfg.Setup.ConfigPath != "./data/config.yaml" {
		t.Fatalf("setup config path = %q, want ./data/config.yaml", cfg.Setup.ConfigPath)
	}
	if cfg.RateLimit.MaxRequests != 1000 {
		t.Fatalf("rate limit max requests = %d, want 1000", cfg.RateLimit.MaxRequests)
	}
	if cfg.RateLimit.WindowSecs != 60 {
		t.Fatalf("rate limit window secs = %d, want 60", cfg.RateLimit.WindowSecs)
	}
	if cfg.Security.AllowPrivateOutbound {
		t.Fatal("private outbound networks must be disabled by default")
	}
	if cfg.Server.TrustedProxies != "" {
		t.Fatalf("trusted proxies = %q, want empty secure default", cfg.Server.TrustedProxies)
	}
	if cfg.Server.MaxJSONBodyBytes != 1<<20 {
		t.Fatalf("max JSON body bytes = %d, want 1 MiB", cfg.Server.MaxJSONBodyBytes)
	}
	if cfg.Credentials.EncryptionKey != "" || cfg.Credentials.EncryptionPreviousKey != "" {
		t.Fatalf("credential encryption keys must be empty by default: %#v", cfg.Credentials)
	}
	if cfg.Storage.RestoreMaxFileSize != 64 {
		t.Fatalf("restore max file size = %d, want 64MB", cfg.Storage.RestoreMaxFileSize)
	}
	if cfg.Observability.MetricsEnabled || cfg.Observability.MetricsToken != "" {
		t.Fatalf("metrics must be disabled without a token by default: %#v", cfg.Observability)
	}
}

func TestLoadDatabaseCompatibilityConfigFromEnv(t *testing.T) {
	resetViperForTest(t)
	chdirForTest(t, t.TempDir())
	t.Setenv("LEDGER_DATABASE_DRIVER", "postgres")
	t.Setenv("LEDGER_DATABASE_PATH", "")
	t.Setenv("LEDGER_DATABASE_DSN", "host=db user=ledger dbname=ledger sslmode=disable")
	t.Setenv("LEDGER_DATABASE_MAX_OPEN_CONNS", "17")
	t.Setenv("LEDGER_DATABASE_MAX_IDLE_CONNS", "9")
	t.Setenv("LEDGER_SETUP_CONFIG_PATH", "/data/config.yaml")
	t.Setenv("LEDGER_RATE_LIMIT_MAX_REQUESTS", "321")
	t.Setenv("LEDGER_RATE_LIMIT_WINDOW_SECS", "45")
	t.Setenv("LEDGER_SECURITY_ALLOW_PRIVATE_OUTBOUND", "true")
	t.Setenv("LEDGER_SERVER_TRUSTED_PROXIES", "10.0.0.10,10.0.0.0/24")
	t.Setenv("LEDGER_SERVER_MAX_JSON_BODY_BYTES", "2097152")
	t.Setenv("LEDGER_CREDENTIAL_ENCRYPTION_KEY", "new-credential-encryption-key-with-32-characters")
	t.Setenv("LEDGER_CREDENTIAL_ENCRYPTION_PREVIOUS_KEY", "old-credential-encryption-key-with-32-characters")
	t.Setenv("LEDGER_STORAGE_RESTORE_MAX_FILE_SIZE", "96")
	t.Setenv("LEDGER_OBSERVABILITY_METRICS_ENABLED", "true")
	t.Setenv("LEDGER_OBSERVABILITY_METRICS_TOKEN", "metrics-token-with-at-least-32-characters")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("load config: %v", err)
	}

	if cfg.Database.Driver != "postgres" {
		t.Fatalf("database driver = %q, want postgres", cfg.Database.Driver)
	}
	if cfg.Database.DSN != "host=db user=ledger dbname=ledger sslmode=disable" {
		t.Fatalf("database dsn = %q, want env dsn", cfg.Database.DSN)
	}
	if cfg.Database.MaxOpenConns != 17 {
		t.Fatalf("max open conns = %d, want 17", cfg.Database.MaxOpenConns)
	}
	if cfg.Database.MaxIdleConns != 9 {
		t.Fatalf("max idle conns = %d, want 9", cfg.Database.MaxIdleConns)
	}
	if cfg.Setup.ConfigPath != "/data/config.yaml" {
		t.Fatalf("setup config path = %q, want /data/config.yaml", cfg.Setup.ConfigPath)
	}
	if cfg.RateLimit.MaxRequests != 321 {
		t.Fatalf("rate limit max requests = %d, want 321", cfg.RateLimit.MaxRequests)
	}
	if cfg.RateLimit.WindowSecs != 45 {
		t.Fatalf("rate limit window secs = %d, want 45", cfg.RateLimit.WindowSecs)
	}
	if !cfg.Security.AllowPrivateOutbound {
		t.Fatal("private outbound network opt-in was not loaded from env")
	}
	if cfg.Server.TrustedProxies != "10.0.0.10,10.0.0.0/24" {
		t.Fatalf("trusted proxies = %q, want env value", cfg.Server.TrustedProxies)
	}
	if cfg.Server.MaxJSONBodyBytes != 2<<20 {
		t.Fatalf("max JSON body bytes = %d, want 2 MiB", cfg.Server.MaxJSONBodyBytes)
	}
	if cfg.Credentials.EncryptionKey != "new-credential-encryption-key-with-32-characters" {
		t.Fatal("credential encryption key was not loaded from env")
	}
	if cfg.Credentials.EncryptionPreviousKey != "old-credential-encryption-key-with-32-characters" {
		t.Fatal("previous credential encryption key was not loaded from env")
	}
	if cfg.Storage.RestoreMaxFileSize != 96 {
		t.Fatalf("restore max file size = %d, want 96MB", cfg.Storage.RestoreMaxFileSize)
	}
	if !cfg.Observability.MetricsEnabled || cfg.Observability.MetricsToken != "metrics-token-with-at-least-32-characters" {
		t.Fatalf("metrics env config = %#v", cfg.Observability)
	}
}

func TestResolveDatabaseTimeZoneRejectsInvalidValue(t *testing.T) {
	_, err := ResolveDatabaseTimeZone("not/a-real-zone")
	if err == nil {
		t.Fatal("expected invalid timezone error")
	}
}

func TestResolveDatabaseTimeZoneAcceptsExplicitIANAValue(t *testing.T) {
	timezone, err := ResolveDatabaseTimeZone("Asia/Shanghai")
	if err != nil {
		t.Fatalf("resolve timezone: %v", err)
	}
	if timezone != "Asia/Shanghai" {
		t.Fatalf("timezone = %q, want Asia/Shanghai", timezone)
	}
}
