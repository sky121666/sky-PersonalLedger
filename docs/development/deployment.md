# 部署与配置

## 选择发布产物

采用新版发布工作流创建的 Release 应包含两个同名附件：

- docker-compose-vX.Y.Z.yml
- docker-compose-vX.Y.Z.yml.sha256

先校验 SHA-256，再把版本专属 Compose 文件作为部署文件。它已经固定到该次发布的
GHCR digest，不需要设置 LEDGER_IMAGE，也不依赖会移动的 latest。仓库根目录
docker-compose.yml 适合源码检出和本地演练，其默认 digest 只代表仓库记录的部署基线。

例外：v1.0.8 GitHub Release 的 assets 为空；该版本使用仓库根 Compose 记录的
v1.0.8 digest。不要尝试下载并不存在的 v1.0.8 Compose 附件。

## 首次启动

复制示例配置并在本机生成独立随机值；不要把命令输出粘贴到日志、Issue 或文档：

    cp .env.example .env
    chmod 600 .env
    openssl rand -base64 32
    openssl rand -hex 32

base64 命令分别执行一次用于 LEDGER_JWT_SECRET 与
LEDGER_CREDENTIAL_ENCRYPTION_KEY；hex 命令用于 LEDGER_SETUP_TOKEN。把输出只写入
本机 .env，然后启动：

    docker compose up -d
    docker compose ps
    curl -fsS http://127.0.0.1:8080/api/v1/health

首次访问：

    http://localhost:8080/#/setup?setup_token=<LEDGER_SETUP_TOKEN>

宿主机默认数据目录是 ./data，映射到容器内固定的 /data：

    ./data/ledger.db
    ./data/uploads/
    ./data/backups/

不要把宿主机相对路径作为容器环境变量传入。

## 网络与 HTTPS

LEDGER_BIND_ADDRESS 默认是 127.0.0.1，LEDGER_SERVER_PORT 只控制宿主机发布端口；
容器内服务始终监听 8080。推荐让宿主机反向代理终止 TLS，例如 Caddy：

    ledger.example.com {
        reverse_proxy 127.0.0.1:8080
    }

确保域名、80/443 入站和证书签发满足反向代理要求。设置
LEDGER_SERVER_TRUSTED_PROXIES 为实际代理 IP/CIDR 后，后端才会信任转发头；不要填
宽泛网段。

如果确需直接向受控 LAN 暴露，可显式设置 LEDGER_BIND_ADDRESS=0.0.0.0，并用主机
防火墙限制来源。不要把未加密 HTTP 暴露到公网。容器化反向代理应与应用加入专用
Docker 网络并通过服务名访问，不需要把应用端口开放到所有网卡。

Android 正式构建默认禁止明文 HTTP。只有明确面向私有局域网的非商店构建才可使用
-PledgerAllowReleaseCleartext=true；客户端仍会限制公网 HTTP。

## Compose 支持的环境变量

Compose 只透传经过审查的运行 allowlist；.env.example 是可部署合同。

| 分类 | 变量 | 说明 |
| --- | --- | --- |
| 宿主机端口 | LEDGER_BIND_ADDRESS, LEDGER_SERVER_PORT | 默认 127.0.0.1:8080，不改变容器内 8080 |
| 服务 | LEDGER_SERVER_MODE, LEDGER_SERVER_TRUSTED_PROXIES, LEDGER_SERVER_MAX_JSON_BODY_BYTES | Web 路径固定为 /app/web/dist |
| 数据库 | LEDGER_DATABASE_DRIVER, LEDGER_DATABASE_DSN, LEDGER_DATABASE_MAX_OPEN_CONNS, LEDGER_DATABASE_MAX_IDLE_CONNS | SQLite 路径固定为 /data/ledger.db |
| 会话 | LEDGER_JWT_SECRET, LEDGER_JWT_ACCESS_EXPIRE, LEDGER_JWT_REFRESH_EXPIRE | JWT 密钥至少 32 字节 |
| 凭据加密 | LEDGER_CREDENTIAL_ENCRYPTION_KEY, LEDGER_CREDENTIAL_ENCRYPTION_PREVIOUS_KEY | previous 仅用于临时迁移 |
| 初始化 | LEDGER_SETUP_TOKEN | Docker 启动前必填；配置路径固定为 /data/config.yaml |
| 存储 | LEDGER_STORAGE_MAX_FILE_SIZE, LEDGER_STORAGE_RESTORE_MAX_FILE_SIZE, LEDGER_STORAGE_ALLOWED_TYPES | 上传/备份路径固定在 /data |
| Web 安全 | LEDGER_SECURITY_BASE_PATH, LEDGER_SECURITY_ALLOW_PRIVATE_OUTBOUND, LEDGER_CORS_ALLOWED_ORIGINS | release 模式禁止通配 CORS |
| 日志与时区 | LEDGER_LOG_LEVEL, LEDGER_LOG_FORMAT, TZ | 日志不要包含凭据 |
| 限流 | LEDGER_RATE_LIMIT_MAX_REQUESTS, LEDGER_RATE_LIMIT_WINDOW_SECS | release 模式生效 |
| 指标 | LEDGER_OBSERVABILITY_METRICS_ENABLED, LEDGER_OBSERVABILITY_METRICS_TOKEN | 开启时 Token 至少 32 字节 |

docker compose config 会展开环境变量，可能把密钥打印到终端或 CI 日志。自动验证使用
docker compose config --quiet；排障时也不要上传包含展开值的输出。

## 数据库

默认 SQLite。长期部署可在初始化向导或 .env 中选择 PostgreSQL、MySQL 或 MariaDB，
并把真实密码只保存在受限的本机 .env 或 secret manager：

    LEDGER_DATABASE_DRIVER=postgres
    LEDGER_DATABASE_DSN=postgres://ledger:<password>@db:5432/ledger?sslmode=require

    LEDGER_DATABASE_DRIVER=mysql
    LEDGER_DATABASE_DSN=ledger:<password>@tcp(db:3306)/ledger?charset=utf8mb4&parseTime=True&loc=Local

## 凭据加密密钥迁移与轮换

新部署应从首次启动就设置独立的 LEDGER_CREDENTIAL_ENCRYPTION_KEY（至少 32 字节），
让 AI Provider 和通知凭据不再与 JWT 会话签名密钥共用生命周期。

现有部署从 JWT 派生密钥迁移时：

1. 保持当前 LEDGER_JWT_SECRET 不变，新增独立主密钥并启动；
2. 等待启动时对通知与 AI 凭据的事务性重加密完成，核对服务日志和凭据测试结果；
3. 完成备份后再轮换 JWT，重启并验证登录与凭据读取；
4. LEDGER_CREDENTIAL_ENCRYPTION_PREVIOUS_KEY 正常情况下保持空值。

如果必须同时轮换，把新独立主密钥写入 LEDGER_CREDENTIAL_ENCRYPTION_KEY，把旧 JWT
临时写入 LEDGER_CREDENTIAL_ENCRYPTION_PREVIOUS_KEY，再写入新 JWT 并启动。读取候选
按“主密钥、当前 JWT、previous”去重尝试；迁移成功后立即从 .env 删除 previous，
重启并复验。不要长期保留 previous，也不要在确认迁移前丢弃旧密钥。

## 升级与回滚

升级前备份 ./data 和受限的 .env，记录当前镜像 digest。升级时下载新 Release 的
Compose 与 checksum，校验后运行：

    docker compose pull
    docker compose up -d
    docker compose ps

回滚必须同时考虑数据库、备份格式和凭据迁移兼容性；不要只把 latest 改回旧值。发布与
远端保护要求见 [发布治理合同](release-governance.md)。
