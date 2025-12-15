package config

import (
	"github.com/spf13/viper"
)

type Config struct {
	Server   ServerConfig
	Database DatabaseConfig
	JWT      JWTConfig
	Log      LogConfig
	Storage  StorageConfig
}

type StorageConfig struct {
	UploadPath   string `mapstructure:"upload_path"`
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

	viper.SetDefault("server.port", "8080")
	viper.SetDefault("server.mode", "debug")
	viper.SetDefault("server.web_path", "./web/dist")
	viper.SetDefault("database.path", "./data/ledger.db")
	viper.SetDefault("jwt.access_expire", 15)
	viper.SetDefault("jwt.refresh_expire", 43200)
	viper.SetDefault("log.level", "info")
	viper.SetDefault("log.format", "json")
	viper.SetDefault("storage.upload_path", "./data/uploads")
	viper.SetDefault("storage.max_file_size", 10) // 10MB
	viper.SetDefault("storage.allowed_types", "jpg,jpeg,png,gif,webp,pdf,doc,docx,xls,xlsx,txt")
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
