package handler

import (
	"errors"
	"fmt"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	mysqldriver "github.com/go-sql-driver/mysql"
	"github.com/sky/personal-ledger/internal/config"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/service"
	"github.com/sky/personal-ledger/pkg/response"
	"gopkg.in/yaml.v3"
)

type SetupHandler struct {
	auth     *service.AuthService
	database config.DatabaseConfig
	setup    config.SetupConfig
}

func NewSetupHandler(auth *service.AuthService, dbConfig config.DatabaseConfig, setupConfig config.SetupConfig) *SetupHandler {
	return &SetupHandler{
		auth:     auth,
		database: dbConfig,
		setup:    setupConfig,
	}
}

func (h *SetupHandler) Status(c *gin.Context) {
	initialized, err := h.auth.IsInitialized()
	if err != nil {
		response.InternalError(c, "failed to check setup status")
		return
	}

	response.Success(c, gin.H{
		"initialized": initialized,
		"database":    setupDatabaseSummary(h.database),
	})
}

type TestDatabaseRequest struct {
	Driver       string `json:"driver"`
	Path         string `json:"path"`
	DSN          string `json:"dsn"`
	Host         string `json:"host"`
	Port         int    `json:"port"`
	Database     string `json:"database"`
	Username     string `json:"username"`
	Password     string `json:"password"`
	SSLMode      string `json:"ssl_mode"`
	Timezone     string `json:"timezone"`
	MaxOpenConns *int   `json:"max_open_conns"`
	MaxIdleConns *int   `json:"max_idle_conns"`
}

func (h *SetupHandler) TestDatabase(c *gin.Context) {
	initialized, err := h.auth.IsInitialized()
	if err != nil {
		response.InternalError(c, "failed to check setup status")
		return
	}
	if initialized {
		response.Forbidden(c, "setup is disabled after initialization")
		return
	}

	var req TestDatabaseRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request: "+err.Error())
		return
	}

	dbConfig, err := mergeDatabaseConfig(h.database, req)
	if err != nil {
		response.BadRequest(c, "invalid database config: "+err.Error())
		return
	}

	if err := database.TestConnection(dbConfig); err != nil {
		response.BadRequest(c, "database test failed: "+err.Error())
		return
	}

	response.Success(c, gin.H{"ok": true})
}

func (h *SetupHandler) Apply(c *gin.Context) {
	initialized, err := h.auth.IsInitialized()
	if err != nil {
		response.InternalError(c, "failed to check setup status")
		return
	}
	if initialized {
		response.Forbidden(c, "setup is disabled after initialization")
		return
	}

	var req TestDatabaseRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request: "+err.Error())
		return
	}

	dbConfig, err := mergeDatabaseConfig(h.database, req)
	if err != nil {
		response.BadRequest(c, "invalid database config: "+err.Error())
		return
	}
	if err := database.TestConnection(dbConfig); err != nil {
		response.BadRequest(c, "database test failed: "+err.Error())
		return
	}

	if err := writeSetupDatabaseConfig(h.setup.ConfigPath, dbConfig); err != nil {
		internalServerError(c, err, "failed to write setup config")
		return
	}

	response.Success(c, gin.H{
		"restart_required": true,
		"config_path":      h.setup.ConfigPath,
		"database":         setupDatabaseSummary(dbConfig),
	})
}

func mergeDatabaseConfig(base config.DatabaseConfig, req TestDatabaseRequest) (config.DatabaseConfig, error) {
	dbConfig := base
	if strings.TrimSpace(req.Driver) != "" {
		dbConfig.Driver = setupDriverName(req.Driver)
	} else {
		dbConfig.Driver = setupDriverName(dbConfig.Driver)
	}
	if req.MaxOpenConns != nil {
		if *req.MaxOpenConns < 0 {
			return dbConfig, errors.New("max open connections must be greater than or equal to 0")
		}
		dbConfig.MaxOpenConns = *req.MaxOpenConns
	}
	if req.MaxIdleConns != nil {
		if *req.MaxIdleConns < 0 {
			return dbConfig, errors.New("max idle connections must be greater than or equal to 0")
		}
		dbConfig.MaxIdleConns = *req.MaxIdleConns
	}

	if setupUsesSQLite(dbConfig.Driver) {
		if strings.TrimSpace(req.Path) != "" {
			dbConfig.Path = req.Path
		}
		dbConfig.DSN = ""
	} else {
		if strings.TrimSpace(req.DSN) != "" {
			dbConfig.DSN = req.DSN
		} else if hasStructuredDatabaseInput(req) || strings.TrimSpace(dbConfig.DSN) == "" {
			dsn, err := buildStructuredDatabaseDSN(dbConfig.Driver, req)
			if err != nil {
				return dbConfig, err
			}
			dbConfig.DSN = dsn
		}
		dbConfig.Path = ""
	}
	return dbConfig, nil
}

func hasStructuredDatabaseInput(req TestDatabaseRequest) bool {
	return strings.TrimSpace(req.Host) != "" ||
		req.Port > 0 ||
		strings.TrimSpace(req.Database) != "" ||
		strings.TrimSpace(req.Username) != "" ||
		req.Password != "" ||
		strings.TrimSpace(req.SSLMode) != "" ||
		strings.TrimSpace(req.Timezone) != ""
}

func buildStructuredDatabaseDSN(driver string, req TestDatabaseRequest) (string, error) {
	driver = setupDriverName(driver)
	host := strings.TrimSpace(req.Host)
	if host == "" {
		host = "127.0.0.1"
	}
	port := req.Port
	if port <= 0 {
		port = defaultDatabasePort(driver)
	}
	if port <= 0 {
		return "", fmt.Errorf("unsupported database driver %q", driver)
	}

	databaseName := strings.TrimSpace(req.Database)
	if databaseName == "" {
		return "", errors.New("database name is required")
	}
	username := strings.TrimSpace(req.Username)
	if username == "" {
		return "", errors.New("database username is required")
	}

	switch driver {
	case "mysql", "mariadb":
		timezone := strings.TrimSpace(req.Timezone)
		if timezone == "" {
			timezone = "Local"
		}
		loc, err := time.LoadLocation(timezone)
		if err != nil {
			return "", fmt.Errorf("invalid mysql timezone %q", timezone)
		}

		mysqlConfig := mysqldriver.NewConfig()
		mysqlConfig.User = username
		mysqlConfig.Passwd = req.Password
		mysqlConfig.Net = "tcp"
		mysqlConfig.Addr = net.JoinHostPort(host, strconv.Itoa(port))
		mysqlConfig.DBName = databaseName
		mysqlConfig.ParseTime = true
		mysqlConfig.Loc = loc
		mysqlConfig.Params = map[string]string{"charset": "utf8mb4"}
		return mysqlConfig.FormatDSN(), nil
	case "postgres", "postgresql":
		sslMode := strings.TrimSpace(req.SSLMode)
		if sslMode == "" {
			sslMode = "disable"
		}
		timezone, err := config.ResolveDatabaseTimeZone(req.Timezone)
		if err != nil {
			return "", fmt.Errorf("invalid postgres timezone %q", req.Timezone)
		}
		postgresURL := url.URL{
			Scheme: "postgres",
			User:   url.UserPassword(username, req.Password),
			Host:   net.JoinHostPort(host, strconv.Itoa(port)),
			Path:   databaseName,
		}
		query := postgresURL.Query()
		query.Set("sslmode", sslMode)
		query.Set("TimeZone", timezone)
		postgresURL.RawQuery = encodePostgresSetupURLQuery(query)
		return postgresURL.String(), nil
	default:
		return "", fmt.Errorf("unsupported database driver %q", driver)
	}
}

func encodePostgresSetupURLQuery(query url.Values) string {
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

func defaultDatabasePort(driver string) int {
	switch setupDriverName(driver) {
	case "mysql", "mariadb":
		return 3306
	case "postgres", "postgresql":
		return 5432
	default:
		return 0
	}
}

func setupDatabaseSummary(dbConfig config.DatabaseConfig) gin.H {
	path := ""
	if setupUsesSQLite(dbConfig.Driver) {
		path = dbConfig.Path
	}
	return gin.H{
		"driver":         setupDriverName(dbConfig.Driver),
		"path":           path,
		"dsn_configured": strings.TrimSpace(dbConfig.DSN) != "",
		"max_open_conns": dbConfig.MaxOpenConns,
		"max_idle_conns": dbConfig.MaxIdleConns,
	}
}

func setupUsesSQLite(driver string) bool {
	return strings.HasPrefix(setupDriverName(driver), "sqlite")
}

func writeSetupDatabaseConfig(configPath string, dbConfig config.DatabaseConfig) error {
	configPath = strings.TrimSpace(configPath)
	if configPath == "" {
		return errors.New("setup config path is required")
	}

	if err := os.MkdirAll(filepath.Dir(configPath), 0700); err != nil {
		return err
	}

	configData := map[string]any{}
	if raw, err := os.ReadFile(configPath); err == nil && len(strings.TrimSpace(string(raw))) > 0 {
		if err := yaml.Unmarshal(raw, &configData); err != nil {
			return err
		}
	} else if err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}

	configData["database"] = dbConfig
	data, err := yaml.Marshal(configData)
	if err != nil {
		return err
	}

	return os.WriteFile(configPath, data, 0600)
}

func setupDriverName(driver string) string {
	value := strings.ToLower(strings.TrimSpace(driver))
	switch value {
	case "", "sqlite", "sqlite3":
		return "sqlite"
	case "postgres", "postgresql":
		return "postgres"
	case "mysql", "mariadb":
		return "mysql"
	default:
		return value
	}
}
