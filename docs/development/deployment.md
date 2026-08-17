# 部署与配置

## Docker Compose

复制示例配置并设置 JWT 密钥和初始化令牌：

    cp .env.example .env
    openssl rand -base64 32
    openssl rand -hex 32
    docker compose up -d

健康检查：

    curl -fsS http://127.0.0.1:8080/api/v1/health

首次访问：

    http://localhost:8080/#/setup?setup_token=<LEDGER_SETUP_TOKEN>

默认数据目录：

    ./data/ledger.db
    ./data/uploads/
    ./data/backups/

## 数据库

默认 SQLite。长期部署可以在初始化向导或配置中切换到 PostgreSQL、MySQL 或 MariaDB。

    LEDGER_DATABASE_DRIVER=postgres
    LEDGER_DATABASE_DSN=postgres://ledger:password@db:5432/ledger?sslmode=disable&TimeZone=Asia/Shanghai

    LEDGER_DATABASE_DRIVER=mysql
    LEDGER_DATABASE_DSN=ledger:password@tcp(db:3306)/ledger?charset=utf8mb4&parseTime=True&loc=Local

## 常用配置

- LEDGER_SERVER_MODE：生产使用 release，本地联调可用 debug；
- LEDGER_SECURITY_BASE_PATH：可选的自定义入口路径；
- LEDGER_CORS_ALLOWED_ORIGINS：前后端分离时填写具体来源；
- LEDGER_STORAGE_MAX_FILE_SIZE：上传文件大小上限；
- LEDGER_STORAGE_RESTORE_MAX_FILE_SIZE：恢复文件大小上限；
- LEDGER_OBSERVABILITY_METRICS_ENABLED：是否启用受保护指标。

完整变量见 .env.example、config.example.yaml 和 docker-compose.yml。

