package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/config"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"github.com/sky/personal-ledger/internal/service"
	"github.com/sky/personal-ledger/pkg/jwt"
	"gopkg.in/yaml.v3"
)

func TestSetupStatusReportsDatabaseMode(t *testing.T) {
	handler, _ := newSetupTestHandler(t, config.DatabaseConfig{
		Driver:       "postgres",
		DSN:          "postgres://ledger:password@db:5432/ledger?sslmode=disable",
		MaxOpenConns: 10,
		MaxIdleConns: 5,
	})

	response := performSetupRequest(handler, http.MethodGet, "/setup/status", nil)

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
	data := decodeSetupResponse(t, response.Body.Bytes())
	databaseInfo := data["database"].(map[string]any)
	if data["initialized"] != false {
		t.Fatalf("initialized = %#v, want false", data["initialized"])
	}
	if databaseInfo["driver"] != "postgres" {
		t.Fatalf("database driver = %#v, want postgres", databaseInfo["driver"])
	}
	if databaseInfo["dsn_configured"] != true {
		t.Fatalf("dsn_configured = %#v, want true", databaseInfo["dsn_configured"])
	}
	if _, ok := databaseInfo["dsn"]; ok {
		t.Fatal("setup status leaked database dsn")
	}
}

func TestSetupTestDatabaseAcceptsSQLiteBeforeInitialization(t *testing.T) {
	handler, _ := newSetupTestHandler(t, config.DatabaseConfig{Driver: "sqlite", Path: filepath.Join(t.TempDir(), "current.db")})
	payload := map[string]any{
		"driver": "sqlite",
		"path":   filepath.Join(t.TempDir(), "candidate.db"),
	}

	response := performSetupRequest(handler, http.MethodPost, "/setup/test-database", payload)

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
	data := decodeSetupResponse(t, response.Body.Bytes())
	if data["ok"] != true {
		t.Fatalf("ok = %#v, want true", data["ok"])
	}
}

func TestSetupTestDatabaseDisabledAfterInitialization(t *testing.T) {
	handler, repos := newSetupTestHandler(t, config.DatabaseConfig{Driver: "sqlite", Path: filepath.Join(t.TempDir(), "current.db")})
	if err := repos.User.Create(&model.User{Username: "admin", PasswordHash: "hash"}); err != nil {
		t.Fatalf("create user: %v", err)
	}
	payload := map[string]any{
		"driver": "sqlite",
		"path":   filepath.Join(t.TempDir(), "candidate.db"),
	}

	response := performSetupRequest(handler, http.MethodPost, "/setup/test-database", payload)

	if response.Code != http.StatusForbidden {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
}

func TestSetupTestDatabaseDoesNotExposeConnectionDetails(t *testing.T) {
	handler, _ := newSetupTestHandler(t, config.DatabaseConfig{Driver: "sqlite", Path: filepath.Join(t.TempDir(), "current.db")})
	payload := map[string]any{
		"driver":   "mysql",
		"host":     "127.0.0.1",
		"port":     1,
		"database": "ledger",
		"username": "ledger_user",
		"password": "setup-secret-password",
	}

	response := performSetupRequest(handler, http.MethodPost, "/setup/test-database", payload)

	if response.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400; body = %s", response.Code, response.Body.String())
	}
	assertSetupResponseDoesNotExpose(t, response.Body.String(), []string{
		"127.0.0.1",
		"setup-secret-password",
		"ledger_user",
		"dial",
		"connect",
	})
	if !strings.Contains(response.Body.String(), "database test failed") {
		t.Fatalf("body = %s, want generic database test failure", response.Body.String())
	}
}

func TestSetupTestDatabaseMalformedJSONDoesNotExposeParserDetails(t *testing.T) {
	handler, _ := newSetupTestHandler(t, config.DatabaseConfig{Driver: "sqlite", Path: filepath.Join(t.TempDir(), "current.db")})

	response := performSetupRawRequest(handler, http.MethodPost, "/setup/test-database", `{"driver":`)

	if response.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400; body = %s", response.Code, response.Body.String())
	}
	body := strings.ToLower(response.Body.String())
	if !strings.Contains(body, "invalid request") {
		t.Fatalf("body = %s, want invalid request", response.Body.String())
	}
	for _, forbidden := range []string{"unexpected", "eof", "json", "driver"} {
		if strings.Contains(body, forbidden) {
			t.Fatalf("response exposed parser detail %q: %s", forbidden, response.Body.String())
		}
	}
}

func TestSetupApplyWritesLocalConfigBeforeInitialization(t *testing.T) {
	configPath := filepath.Join(t.TempDir(), "config.yaml")
	databasePath := filepath.Join(t.TempDir(), "applied.db")
	handler, _ := newSetupTestHandlerWithConfig(t,
		config.DatabaseConfig{Driver: "sqlite", Path: filepath.Join(t.TempDir(), "current.db")},
		config.SetupConfig{ConfigPath: configPath},
	)
	payload := map[string]any{
		"driver":         "sqlite",
		"path":           databasePath,
		"max_open_conns": 3,
		"max_idle_conns": 2,
	}

	response := performSetupRequest(handler, http.MethodPost, "/setup/apply", payload)

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
	data := decodeSetupResponse(t, response.Body.Bytes())
	if data["restart_required"] != true {
		t.Fatalf("restart_required = %#v, want true", data["restart_required"])
	}
	databaseInfo := data["database"].(map[string]any)
	if databaseInfo["driver"] != "sqlite" {
		t.Fatalf("response database driver = %#v, want sqlite", databaseInfo["driver"])
	}
	if _, ok := databaseInfo["dsn"]; ok {
		t.Fatal("apply response leaked database dsn")
	}

	rawConfig, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatalf("read applied config: %v", err)
	}
	var saved struct {
		Database config.DatabaseConfig `yaml:"database"`
	}
	if err := yaml.Unmarshal(rawConfig, &saved); err != nil {
		t.Fatalf("parse applied config: %v", err)
	}
	if saved.Database.Driver != "sqlite" {
		t.Fatalf("saved driver = %q, want sqlite", saved.Database.Driver)
	}
	if saved.Database.Path != databasePath {
		t.Fatalf("saved path = %q, want %q", saved.Database.Path, databasePath)
	}
	if saved.Database.MaxOpenConns != 3 {
		t.Fatalf("saved max open conns = %d, want 3", saved.Database.MaxOpenConns)
	}
	if saved.Database.MaxIdleConns != 2 {
		t.Fatalf("saved max idle conns = %d, want 2", saved.Database.MaxIdleConns)
	}
}

func TestSetupApplyDoesNotExposeConnectionDetails(t *testing.T) {
	handler, _ := newSetupTestHandlerWithConfig(t,
		config.DatabaseConfig{Driver: "sqlite", Path: filepath.Join(t.TempDir(), "current.db")},
		config.SetupConfig{ConfigPath: filepath.Join(t.TempDir(), "config.yaml")},
	)
	payload := map[string]any{
		"driver":   "mysql",
		"host":     "127.0.0.1",
		"port":     1,
		"database": "ledger",
		"username": "ledger_user",
		"password": "setup-secret-password",
	}

	response := performSetupRequest(handler, http.MethodPost, "/setup/apply", payload)

	if response.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400; body = %s", response.Code, response.Body.String())
	}
	assertSetupResponseDoesNotExpose(t, response.Body.String(), []string{
		"127.0.0.1",
		"setup-secret-password",
		"ledger_user",
		"dial",
		"connect",
	})
	if !strings.Contains(response.Body.String(), "database test failed") {
		t.Fatalf("body = %s, want generic database test failure", response.Body.String())
	}
}

func TestSetupApplyMalformedJSONDoesNotExposeParserDetails(t *testing.T) {
	handler, _ := newSetupTestHandlerWithConfig(t,
		config.DatabaseConfig{Driver: "sqlite", Path: filepath.Join(t.TempDir(), "current.db")},
		config.SetupConfig{ConfigPath: filepath.Join(t.TempDir(), "config.yaml")},
	)

	response := performSetupRawRequest(handler, http.MethodPost, "/setup/apply", `{"driver":`)

	if response.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400; body = %s", response.Code, response.Body.String())
	}
	body := strings.ToLower(response.Body.String())
	if !strings.Contains(body, "invalid request") {
		t.Fatalf("body = %s, want invalid request", response.Body.String())
	}
	for _, forbidden := range []string{"unexpected", "eof", "json", "driver"} {
		if strings.Contains(body, forbidden) {
			t.Fatalf("response exposed parser detail %q: %s", forbidden, response.Body.String())
		}
	}
}

func TestSetupApplyPreservesExistingLocalConfigSections(t *testing.T) {
	configPath := filepath.Join(t.TempDir(), "config.yaml")
	if err := os.WriteFile(configPath, []byte(`
server:
  port: "19090"
jwt:
  access_expire: 30
database:
  driver: sqlite
  path: ./old.db
`), 0600); err != nil {
		t.Fatalf("write existing config: %v", err)
	}

	databasePath := filepath.Join(t.TempDir(), "applied.db")
	handler, _ := newSetupTestHandlerWithConfig(t,
		config.DatabaseConfig{Driver: "sqlite", Path: filepath.Join(t.TempDir(), "current.db")},
		config.SetupConfig{ConfigPath: configPath},
	)
	payload := map[string]any{
		"driver": "sqlite",
		"path":   databasePath,
	}

	response := performSetupRequest(handler, http.MethodPost, "/setup/apply", payload)

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
	rawConfig, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatalf("read applied config: %v", err)
	}
	var saved struct {
		Server struct {
			Port string `yaml:"port"`
		} `yaml:"server"`
		JWT struct {
			AccessExpire int `yaml:"access_expire"`
		} `yaml:"jwt"`
		Database config.DatabaseConfig `yaml:"database"`
	}
	if err := yaml.Unmarshal(rawConfig, &saved); err != nil {
		t.Fatalf("parse applied config: %v", err)
	}
	if saved.Server.Port != "19090" {
		t.Fatalf("server port = %q, want preserved 19090", saved.Server.Port)
	}
	if saved.JWT.AccessExpire != 30 {
		t.Fatalf("jwt access expire = %d, want preserved 30", saved.JWT.AccessExpire)
	}
	if saved.Database.Path != databasePath {
		t.Fatalf("database path = %q, want %q", saved.Database.Path, databasePath)
	}
}

func TestMergeDatabaseConfigClearsUnusedSQLitePathForServerDriver(t *testing.T) {
	dbConfig, err := mergeDatabaseConfig(
		config.DatabaseConfig{
			Driver: "sqlite",
			Path:   "./data/ledger.db",
		},
		TestDatabaseRequest{
			Driver:       "mysql",
			DSN:          "ledger:secret@tcp(127.0.0.1:3306)/ledger?charset=utf8mb4&parseTime=True&loc=Local",
			MaxOpenConns: setupIntPtr(2),
			MaxIdleConns: setupIntPtr(1),
		},
	)
	if err != nil {
		t.Fatalf("merge database config: %v", err)
	}

	if dbConfig.Driver != "mysql" {
		t.Fatalf("driver = %q, want mysql", dbConfig.Driver)
	}
	if dbConfig.Path != "" {
		t.Fatalf("path = %q, want empty for server database driver", dbConfig.Path)
	}
	if dbConfig.DSN == "" {
		t.Fatal("dsn was cleared for server database driver")
	}
}

func TestMergeDatabaseConfigAllowsClearingConnectionPoolDefaults(t *testing.T) {
	dbConfig, err := mergeDatabaseConfig(
		config.DatabaseConfig{
			Driver:       "sqlite",
			Path:         "./data/ledger.db",
			MaxOpenConns: 12,
			MaxIdleConns: 6,
		},
		TestDatabaseRequest{
			Driver:       "sqlite",
			Path:         "./data/ledger.db",
			MaxOpenConns: setupIntPtr(0),
			MaxIdleConns: setupIntPtr(0),
		},
	)
	if err != nil {
		t.Fatalf("merge database config: %v", err)
	}

	if dbConfig.MaxOpenConns != 0 {
		t.Fatalf("max open conns = %d, want 0", dbConfig.MaxOpenConns)
	}
	if dbConfig.MaxIdleConns != 0 {
		t.Fatalf("max idle conns = %d, want 0", dbConfig.MaxIdleConns)
	}
}

func TestMergeDatabaseConfigRejectsNegativeConnectionPoolValues(t *testing.T) {
	_, err := mergeDatabaseConfig(
		config.DatabaseConfig{Driver: "sqlite", Path: "./data/ledger.db"},
		TestDatabaseRequest{
			Driver:       "sqlite",
			Path:         "./data/ledger.db",
			MaxOpenConns: setupIntPtr(-1),
		},
	)
	if err == nil {
		t.Fatal("expected negative max open connections error")
	}
	if !strings.Contains(err.Error(), "max open connections") {
		t.Fatalf("error = %q, want max open connections validation", err.Error())
	}
}

func TestMergeDatabaseConfigBuildsMySQLDSNFromStructuredFields(t *testing.T) {
	dbConfig, err := mergeDatabaseConfig(
		config.DatabaseConfig{Driver: "sqlite", Path: "./data/ledger.db"},
		TestDatabaseRequest{
			Driver:   "mysql",
			Host:     "127.0.0.1",
			Port:     3307,
			Database: "ledger_test",
			Username: "ledger",
			Password: "secret",
		},
	)
	if err != nil {
		t.Fatalf("merge database config: %v", err)
	}

	if dbConfig.Path != "" {
		t.Fatalf("path = %q, want empty", dbConfig.Path)
	}
	for _, want := range []string{"ledger:secret@tcp(127.0.0.1:3307)/ledger_test", "charset=utf8mb4", "parseTime=true", "loc=Local"} {
		if !strings.Contains(dbConfig.DSN, want) {
			t.Fatalf("dsn = %q, want to contain %q", dbConfig.DSN, want)
		}
	}
}

func TestMergeDatabaseConfigBuildsPostgresDSNFromStructuredFields(t *testing.T) {
	dbConfig, err := mergeDatabaseConfig(
		config.DatabaseConfig{Driver: "sqlite", Path: "./data/ledger.db"},
		TestDatabaseRequest{
			Driver:   "postgres",
			Host:     "db",
			Port:     5432,
			Database: "ledger_test",
			Username: "ledger",
			Password: "secret",
			SSLMode:  "disable",
			Timezone: "Asia/Shanghai",
		},
	)
	if err != nil {
		t.Fatalf("merge database config: %v", err)
	}

	if dbConfig.Path != "" {
		t.Fatalf("path = %q, want empty", dbConfig.Path)
	}
	if !strings.HasPrefix(dbConfig.DSN, "postgres://ledger:secret@db:5432/ledger_test?") {
		t.Fatalf("dsn = %q, want postgres url", dbConfig.DSN)
	}
	if !strings.Contains(dbConfig.DSN, "sslmode=disable") {
		t.Fatalf("dsn = %q, want sslmode disabled", dbConfig.DSN)
	}
	postgresURL, err := url.Parse(dbConfig.DSN)
	if err != nil {
		t.Fatalf("parse postgres dsn: %v", err)
	}
	if got := postgresURL.Query().Get("TimeZone"); got != "Asia/Shanghai" {
		t.Fatalf("TimeZone = %q, want Asia/Shanghai", got)
	}
	if !strings.Contains(dbConfig.DSN, "TimeZone=Asia/Shanghai") {
		t.Fatalf("dsn = %q, want raw postgres TimeZone query value", dbConfig.DSN)
	}
}

func TestMergeDatabaseConfigRequiresStructuredServerFields(t *testing.T) {
	_, err := mergeDatabaseConfig(
		config.DatabaseConfig{Driver: "sqlite", Path: "./data/ledger.db"},
		TestDatabaseRequest{Driver: "mysql", Host: "127.0.0.1"},
	)
	if err == nil {
		t.Fatal("expected missing structured database fields error")
	}
	if !strings.Contains(err.Error(), "database name is required") {
		t.Fatalf("error = %q, want database name requirement", err.Error())
	}
}

func TestSetupApplyDisabledAfterInitialization(t *testing.T) {
	handler, repos := newSetupTestHandlerWithConfig(t,
		config.DatabaseConfig{Driver: "sqlite", Path: filepath.Join(t.TempDir(), "current.db")},
		config.SetupConfig{ConfigPath: filepath.Join(t.TempDir(), "config.yaml")},
	)
	if err := repos.User.Create(&model.User{Username: "admin", PasswordHash: "hash"}); err != nil {
		t.Fatalf("create user: %v", err)
	}
	payload := map[string]any{
		"driver": "sqlite",
		"path":   filepath.Join(t.TempDir(), "candidate.db"),
	}

	response := performSetupRequest(handler, http.MethodPost, "/setup/apply", payload)

	if response.Code != http.StatusForbidden {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
}

func TestSetupApplyDoesNotExposeConfigWriteError(t *testing.T) {
	configPath := t.TempDir()
	handler, _ := newSetupTestHandlerWithConfig(t,
		config.DatabaseConfig{Driver: "sqlite", Path: filepath.Join(t.TempDir(), "current.db")},
		config.SetupConfig{ConfigPath: configPath},
	)
	payload := map[string]any{
		"driver": "sqlite",
		"path":   filepath.Join(t.TempDir(), "candidate.db"),
	}

	response := performSetupRequest(handler, http.MethodPost, "/setup/apply", payload)

	if response.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500; body = %s", response.Code, response.Body.String())
	}
	body := response.Body.String()
	if !strings.Contains(body, "failed to write setup config") {
		t.Fatalf("body = %s, want generic setup config error", body)
	}
	if strings.Contains(body, configPath) || strings.Contains(strings.ToLower(body), "is a directory") {
		t.Fatalf("response exposed config write detail: %s", body)
	}
}

func newSetupTestHandler(t *testing.T, dbConfig config.DatabaseConfig) (*SetupHandler, *repository.Repositories) {
	return newSetupTestHandlerWithConfig(t, dbConfig, config.SetupConfig{
		ConfigPath: filepath.Join(t.TempDir(), "config.yaml"),
	})
}

func newSetupTestHandlerWithConfig(t *testing.T, dbConfig config.DatabaseConfig, setupConfig config.SetupConfig) (*SetupHandler, *repository.Repositories) {
	t.Helper()
	gin.SetMode(gin.TestMode)

	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	authService := service.NewAuthService(
		repos.User,
		repos.RefreshToken,
		repos.Category,
		repos.Account,
		jwt.NewManager("test-secret-that-is-long-enough-for-tests", 15, 60),
	)
	return NewSetupHandler(authService, dbConfig, setupConfig), repos
}

func performSetupRequest(handler *SetupHandler, method string, path string, payload any) *httptest.ResponseRecorder {
	var body string
	if payload == nil {
		body = ""
	} else {
		data, _ := json.Marshal(payload)
		body = string(data)
	}
	return performSetupRawRequest(handler, method, path, body)
}

func performSetupRawRequest(handler *SetupHandler, method string, path string, payload string) *httptest.ResponseRecorder {
	router := gin.New()
	router.GET("/setup/status", handler.Status)
	router.POST("/setup/test-database", handler.TestDatabase)
	router.POST("/setup/apply", handler.Apply)

	request := httptest.NewRequest(method, path, strings.NewReader(payload))
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	return response
}

func decodeSetupResponse(t *testing.T, data []byte) map[string]any {
	t.Helper()
	var response struct {
		Code int            `json:"code"`
		Data map[string]any `json:"data"`
	}
	if err := json.Unmarshal(data, &response); err != nil {
		t.Fatalf("decode response: %v; body=%s", err, string(data))
	}
	return response.Data
}

func assertSetupResponseDoesNotExpose(t *testing.T, body string, forbidden []string) {
	t.Helper()

	lowerBody := strings.ToLower(body)
	for _, value := range forbidden {
		if strings.Contains(lowerBody, strings.ToLower(value)) {
			t.Fatalf("setup response exposed %q: %s", value, body)
		}
	}
}

func setupIntPtr(value int) *int {
	return &value
}
