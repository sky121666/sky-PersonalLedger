package config

import (
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/spf13/viper"
)

// Config 应用配置
type Config struct {
	Server    ServerConfig
	Database  DatabaseConfig
	JWT       JWTConfig
	Log       LogConfig
	Storage   StorageConfig
	Security  SecurityConfig
	CORS      CORSConfig
	RateLimit RateLimitConfig `mapstructure:"rate_limit"`
	Setup     SetupConfig
}

// RateLimitConfig 限速配置
type RateLimitConfig struct {
	MaxRequests int `mapstructure:"max_requests"` // 每个时间窗口最大请求数
	WindowSecs  int `mapstructure:"window_secs"`  // 时间窗口(秒)
}

// SecurityConfig 安全配置
type SecurityConfig struct {
	BasePath string `mapstructure:"base_path"`
	APIToken string `mapstructure:"api_token"`
}

// CORSConfig 跨域配置
type CORSConfig struct {
	AllowedOrigins string `mapstructure:"allowed_origins"`
}

// StorageConfig 存储配置
type StorageConfig struct {
	UploadPath   string `mapstructure:"upload_path"`
	BackupPath   string `mapstructure:"backup_path"`
	MaxFileSize  int64  `mapstructure:"max_file_size"` // 最大文件大小(MB)
	AllowedTypes string `mapstructure:"allowed_types"`
}

// ServerConfig 服务器配置
type ServerConfig struct {
	Port    string
	Mode    string
	WebPath string `mapstructure:"web_path"` // 前端文件路径
}

// DatabaseConfig 数据库配置
type DatabaseConfig struct {
	Driver       string `mapstructure:"driver" yaml:"driver"`
	Path         string `mapstructure:"path" yaml:"path"`
	DSN          string `mapstructure:"dsn" yaml:"dsn"`
	MaxOpenConns int    `mapstructure:"max_open_conns" yaml:"max_open_conns"`
	MaxIdleConns int    `mapstructure:"max_idle_conns" yaml:"max_idle_conns"`
}

// SetupConfig 首次安装配置
type SetupConfig struct {
	ConfigPath string `mapstructure:"config_path" yaml:"config_path"`
}

// JWTConfig JWT配置
type JWTConfig struct {
	Secret        string
	AccessExpire  int `mapstructure:"access_expire"`
	RefreshExpire int `mapstructure:"refresh_expire"`
}

// LogConfig 日志配置
type LogConfig struct {
	Level  string
	Format string
}

func Load() (*Config, error) {
	viper.SetConfigName("config")
	viper.SetConfigType("yaml")
	viper.AddConfigPath(".")
	viper.AddConfigPath("./backend")
	viper.AddConfigPath("./data")
	viper.AddConfigPath("/data")

	// 启用环境变量支持
	viper.AutomaticEnv()
	viper.SetEnvPrefix("LEDGER")
	viper.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))

	// 绑定环境变量到配置键
	viper.BindEnv("server.port", "LEDGER_SERVER_PORT")
	viper.BindEnv("server.mode", "LEDGER_SERVER_MODE")
	viper.BindEnv("server.web_path", "LEDGER_SERVER_WEB_PATH")
	viper.BindEnv("database.driver", "LEDGER_DATABASE_DRIVER")
	viper.BindEnv("database.path", "LEDGER_DATABASE_PATH")
	viper.BindEnv("database.dsn", "LEDGER_DATABASE_DSN")
	viper.BindEnv("database.max_open_conns", "LEDGER_DATABASE_MAX_OPEN_CONNS")
	viper.BindEnv("database.max_idle_conns", "LEDGER_DATABASE_MAX_IDLE_CONNS")
	viper.BindEnv("jwt.secret", "LEDGER_JWT_SECRET")
	viper.BindEnv("jwt.access_expire", "LEDGER_JWT_ACCESS_EXPIRE")
	viper.BindEnv("jwt.refresh_expire", "LEDGER_JWT_REFRESH_EXPIRE")
	viper.BindEnv("log.level", "LEDGER_LOG_LEVEL")
	viper.BindEnv("log.format", "LEDGER_LOG_FORMAT")
	viper.BindEnv("storage.upload_path", "LEDGER_STORAGE_UPLOAD_PATH")
	viper.BindEnv("storage.backup_path", "LEDGER_STORAGE_BACKUP_PATH")
	viper.BindEnv("storage.max_file_size", "LEDGER_STORAGE_MAX_FILE_SIZE")
	viper.BindEnv("storage.allowed_types", "LEDGER_STORAGE_ALLOWED_TYPES")
	viper.BindEnv("security.base_path", "LEDGER_SECURITY_BASE_PATH")
	viper.BindEnv("security.api_token", "LEDGER_SECURITY_API_TOKEN")
	viper.BindEnv("cors.allowed_origins", "LEDGER_CORS_ALLOWED_ORIGINS")
	viper.BindEnv("rate_limit.max_requests", "LEDGER_RATE_LIMIT_MAX_REQUESTS")
	viper.BindEnv("rate_limit.window_secs", "LEDGER_RATE_LIMIT_WINDOW_SECS")
	viper.BindEnv("setup.config_path", "LEDGER_SETUP_CONFIG_PATH")

	// 设置默认值
	viper.SetDefault("server.port", "8080")
	viper.SetDefault("server.mode", "debug")
	viper.SetDefault("server.web_path", "./web/dist")
	viper.SetDefault("database.driver", "sqlite")
	viper.SetDefault("database.path", "./data/ledger.db")
	viper.SetDefault("database.dsn", "")
	viper.SetDefault("database.max_open_conns", 0)
	viper.SetDefault("database.max_idle_conns", 0)
	viper.SetDefault("jwt.access_expire", 15)
	viper.SetDefault("jwt.refresh_expire", 43200)
	viper.SetDefault("log.level", "info")
	viper.SetDefault("log.format", "json")
	viper.SetDefault("storage.upload_path", "./data/uploads")
	viper.SetDefault("storage.backup_path", "./data/backups")
	viper.SetDefault("storage.max_file_size", 10) // 10MB
	viper.SetDefault("storage.allowed_types", "jpg,jpeg,png,gif,webp,pdf,doc,docx,xls,xlsx,txt")
	viper.SetDefault("cors.allowed_origins", "")      // 默认仅允许同站/无 Origin 请求
	viper.SetDefault("rate_limit.max_requests", 1000) // 每窗口1000次请求
	viper.SetDefault("rate_limit.window_secs", 60)    // 60秒窗口
	viper.SetDefault("setup.config_path", "./data/config.yaml")

	// 尝试读取配置文件(可选)
	if err := viper.ReadInConfig(); err != nil {
		if _, ok := err.(viper.ConfigFileNotFoundError); !ok {
			return nil, err
		}
	}

	var cfg Config
	if err := viper.Unmarshal(&cfg); err != nil {
		return nil, err
	}

	return &cfg, nil
}

func ResolveDatabaseTimeZone(value string) (string, error) {
	timezone := strings.TrimSpace(value)
	if timezone == "" || strings.EqualFold(timezone, "local") {
		timezone = localTimeZoneName()
	}
	if timezone == "" {
		timezone = "UTC"
	}

	if _, err := time.LoadLocation(timezone); err != nil {
		return "", err
	}
	return timezone, nil
}

func localTimeZoneName() string {
	if timezone := strings.TrimPrefix(strings.TrimSpace(os.Getenv("TZ")), ":"); timezone != "" && !strings.EqualFold(timezone, "local") {
		return timezone
	}
	if timezone := time.Local.String(); timezone != "" && !strings.EqualFold(timezone, "local") {
		return timezone
	}
	if timezone := localTimeZoneFromSymlink("/etc/localtime"); timezone != "" {
		return timezone
	}
	return "UTC"
}

func localTimeZoneFromSymlink(path string) string {
	target, err := filepath.EvalSymlinks(path)
	if err != nil {
		return ""
	}
	normalized := filepath.ToSlash(target)
	for _, marker := range []string{"/zoneinfo/", "/share/zoneinfo/"} {
		if index := strings.LastIndex(normalized, marker); index >= 0 {
			return normalized[index+len(marker):]
		}
	}
	return ""
}
