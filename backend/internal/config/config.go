package config

import (
	"strings"

	"github.com/spf13/viper"
)

type Config struct {
	Server   ServerConfig
	Database DatabaseConfig
	JWT      JWTConfig
	Log      LogConfig
	Storage  StorageConfig
	Security SecurityConfig
	CORS     CORSConfig
}

type SecurityConfig struct {
	BasePath string `mapstructure:"base_path"`
	APIToken string `mapstructure:"api_token"`
}

type CORSConfig struct {
	AllowedOrigins string `mapstructure:"allowed_origins"`
}

type StorageConfig struct {
	UploadPath   string `mapstructure:"upload_path"`
	BackupPath   string `mapstructure:"backup_path"`
	MaxFileSize  int64  `mapstructure:"max_file_size"` // MB
	AllowedTypes string `mapstructure:"allowed_types"`
}

type ServerConfig struct {
	Port    string
	Mode    string
	WebPath string `mapstructure:"web_path"` // Path to frontend dist folder
}

type DatabaseConfig struct {
	Path string
}

type JWTConfig struct {
	Secret        string
	AccessExpire  int `mapstructure:"access_expire"`
	RefreshExpire int `mapstructure:"refresh_expire"`
}

type LogConfig struct {
	Level  string
	Format string
}

func Load() (*Config, error) {
	viper.SetConfigName("config")
	viper.SetConfigType("yaml")
	viper.AddConfigPath(".")
	viper.AddConfigPath("./backend")

	// Enable environment variable support
	viper.AutomaticEnv()
	viper.SetEnvPrefix("LEDGER")
	viper.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))

	// Bind environment variables to config keys
	viper.BindEnv("server.port", "LEDGER_SERVER_PORT")
	viper.BindEnv("server.mode", "LEDGER_SERVER_MODE")
	viper.BindEnv("server.web_path", "LEDGER_SERVER_WEB_PATH")
	viper.BindEnv("database.path", "LEDGER_DATABASE_PATH")
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

	// Set defaults
	viper.SetDefault("server.port", "8080")
	viper.SetDefault("server.mode", "debug")
	viper.SetDefault("server.web_path", "./web/dist")
	viper.SetDefault("database.path", "./data/ledger.db")
	viper.SetDefault("jwt.access_expire", 15)
	viper.SetDefault("jwt.refresh_expire", 43200)
	viper.SetDefault("log.level", "info")
	viper.SetDefault("log.format", "json")
	viper.SetDefault("storage.upload_path", "./data/uploads")
	viper.SetDefault("storage.backup_path", "./data/backups")
	viper.SetDefault("storage.max_file_size", 10) // 10MB
	viper.SetDefault("storage.allowed_types", "jpg,jpeg,png,gif,webp,pdf,doc,docx,xls,xlsx,txt")
	viper.SetDefault("cors.allowed_origins", "*") // Default to all, should be configured in production

	// Try to read config file (optional)
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
