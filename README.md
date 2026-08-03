# Personal Ledger

🏠 简洁、安全的个人记账系统，支持私有部署

## 📸 应用截图

> 💡 **多端适配** - Web 响应式界面 + 原生 Flutter 客户端，移动端主流程不再依赖 WebView

<details>
<summary><b>🖥️ 桌面端界面</b> (点击展开)</summary>
<br/>
<img width="100%" alt="Personal Ledger 桌面端界面" src="https://github.com/user-attachments/assets/1ddb77fa-e564-494b-9cb0-bfaf8a0bfdc3" />
</details>

<details open>
<summary><b>📱 手机端界面</b> (响应式布局)</summary>
<br/>
<p align="center">
  <img width="24%" alt="登录" src="https://github.com/user-attachments/assets/52ea4a37-a2a0-4e7c-96b5-8f5b0598eeb9" />
  <img width="24%" alt="首页" src="https://github.com/user-attachments/assets/2f5377a6-89ff-4c05-a48a-c52d0ed327e9" />
  <img width="24%" alt="记账" src="https://github.com/user-attachments/assets/51b57139-f909-4efe-8ff5-5575ad7a5102" />
  <img width="24%" alt="账户" src="https://github.com/user-attachments/assets/36709b85-711c-4dc3-a8fa-5f0cd3ac565e" />
</p>
<p align="center">
  <img width="24%" alt="统计" src="https://github.com/user-attachments/assets/b042d21c-5fbd-4997-897b-33290287b869" />
  <img width="24%" alt="设置" src="https://github.com/user-attachments/assets/df338827-6c6f-49b4-ab0c-893d23a7376a" />
  <img width="24%" alt="借贷" src="https://github.com/user-attachments/assets/3a839b8e-47bc-4b33-9928-c7e354dfeb1e" />
  <img width="24%" alt="导出" src="https://github.com/user-attachments/assets/5a9ed06c-9b73-48c7-b175-3c961d6805f3" />
</p>
<p align="center">
  <img width="24%" alt="标签" src="https://github.com/user-attachments/assets/1a2004b2-1b30-4c08-99cb-32ef58fb26eb" />
  <img width="24%" alt="更多" src="https://github.com/user-attachments/assets/717a0a03-77c5-414a-b39d-47883612c196" />
</p>
</details>

## ✨ 特性

- 🔐 **安全私密** - 数据存储在你自己的服务器，完全掌控
- 📱 **多端支持** - Web 网页版 + Android/macOS/Windows 客户端
- 🐳 **一键部署** - Docker/1Panel 快速部署，开箱即用
- 💾 **灵活存储** - 默认 SQLite 单文件，也可配置 PostgreSQL/MySQL/MariaDB
- 🚀 **高性能** - Go 后端 + Vue3 前端，响应迅速
- 🛡️ **安全防护** - JWT 认证 + 限流保护 + 自定义入口

## 🚀 快速开始

### 方式一：Docker Compose (推荐)

```bash
# 1. 下载配置文件
curl -fsSLO https://raw.githubusercontent.com/sky121666/sky-PersonalLedger/main/docker-compose.yml

# 2. 生成 JWT 密钥和一次性安装令牌 (必须)
printf 'LEDGER_JWT_SECRET=%s\nLEDGER_SETUP_TOKEN=%s\n' \
  "$(openssl rand -base64 32)" "$(openssl rand -hex 32)" > .env

# 3. 启动服务
docker compose up -d

# 4. 查看状态
docker compose ps
docker compose logs -f
```

✅ **访问地址**: `http://localhost:8080/#/setup?setup_token=<.env 中的 LEDGER_SETUP_TOKEN>`

初始化页会把安装令牌仅保存在当前浏览器会话中，并立即从地址栏移除。初始化完成后，服务端会拒绝再次执行安装接口。

### 方式二：1Panel 面板部署

使用 1Panel 面板的用户，可以通过可视化界面轻松部署：

📖 **[1Panel 详细安装教程](https://5ee.net/docs/sky-PersonalLedger/1panel_install)**

### 方式三：Docker 命令部署

```bash
# 拉取镜像
docker pull ghcr.io/sky121666/sky-personalledger:latest

# 启动服务 (完整配置)
docker run -d \
  --name personal-ledger \
  --restart unless-stopped \
  -p 8080:8080 \
  -v ./data:/data \
  -e LEDGER_JWT_SECRET=$(openssl rand -base64 32) \
  -e LEDGER_SETUP_TOKEN=$(openssl rand -hex 32) \
  -e LEDGER_JWT_ACCESS_EXPIRE=15 \
  -e LEDGER_JWT_REFRESH_EXPIRE=43200 \
  -e LEDGER_STORAGE_MAX_FILE_SIZE=10 \
  -e LEDGER_SERVER_MODE=release \
  -e LEDGER_LOG_LEVEL=info \
  -e TZ=Asia/Shanghai \
  ghcr.io/sky121666/sky-personalledger:latest

# 可选的安全配置
# -e LEDGER_SECURITY_BASE_PATH=/my-secret-path \
```

## 📱 客户端下载

> 📦 **客户端说明**: 当前客户端已切换为原生 Flutter 应用，通过 API Client 直连服务端；旧 WebView 兜底入口已移除。Android 已完成当前原生范围验证，macOS/Windows 需要按目标平台单独回归。

从 [Releases](https://github.com/sky121666/sky-PersonalLedger/releases) 下载对应平台的客户端：

| 平台 | 文件名 | 说明 | 测试状态 |
|------|--------|------|----------|
| 🤖 Android | `personal-ledger-xxx-android.apk` | 原生 Flutter 客户端，正式包必须使用 release keystore 签名 | ✅ Android 模拟器 smoke 通过 |
| 🍎 macOS | 暂不随当前 Release 发布 | 原生 Flutter 客户端，首次需在安全设置中允许 | ⏳ 待平台回归 |
| 🪟 Windows | 暂不随当前 Release 发布 | 原生 Flutter 客户端 | ⏳ 待平台回归 |

### Android 正式签名

正式 Android APK 不允许使用 debug key 签名。发布前需要在 `mobile/android/key.properties` 配置 release keystore，或在 GitHub Actions 中配置同名 secrets：

```properties
storeFile=app/upload-keystore.jks
storePassword=<keystore-password>
keyAlias=upload
keyPassword=<key-password>
```

GitHub Actions 需要配置：

- `ANDROID_KEYSTORE_BASE64`: release keystore 文件的 base64 内容
- `ANDROID_KEYSTORE_PASSWORD`: keystore 密码
- `ANDROID_KEY_ALIAS`: key alias
- `ANDROID_KEY_PASSWORD`: key 密码

未配置这些签名信息时，`flutter build apk --release` 会直接失败，避免生成 debug-signed release APK。

## ⚙️ 配置说明

### 核心环境变量

| 变量 | 说明 | 默认值 | 重要性 |
|------|------|--------|--------|
| **LEDGER_JWT_SECRET** | JWT 密钥 (至少32位随机字符串) | - | ⚠️ 必须修改 |
| **LEDGER_SETUP_TOKEN** | 首次远程安装令牌（至少32位） | 空，仅允许 loopback 初始化 | ⚠️ Docker 必须设置 |
| LEDGER_SECURITY_BASE_PATH | 自定义入口路径 (如 `/my-ledger`) | 空 | 🔒 安全推荐 |
| LEDGER_SECURITY_ALLOW_PRIVATE_OUTBOUND | 允许 AI、Webhook、SMTP 访问回环/私网；仅本地网关场景由部署者显式开启 | false | 🔒 默认保持关闭 |
| LEDGER_SERVER_TRUSTED_PROXIES | 可信反向代理 IP/CIDR，多个值用逗号分隔；留空忽略转发来源头 | 空 | 🔒 仅代理部署填写 |
| LEDGER_OBSERVABILITY_METRICS_ENABLED | 启用受保护的 Prometheus `/metrics` 指标 | false | 可选 |
| LEDGER_OBSERVABILITY_METRICS_TOKEN | 指标抓取 Bearer Token，启用指标时至少 32 位 | 空 | 🔒 启用时必填 |

移动端和自动化客户端使用登录后的“设备授权”页面生成访问令牌。令牌通过 `Authorization: Bearer` 发送，并由服务端按最小权限 scope 校验；不存在全局环境变量形式的万能移动端令牌。

### 运行指标

指标默认关闭。需要接入 Prometheus 时，在 `.env` 中生成独立令牌并启用：

```bash
LEDGER_OBSERVABILITY_METRICS_ENABLED=true
LEDGER_OBSERVABILITY_METRICS_TOKEN=$(openssl rand -hex 32)
```

抓取请求必须携带 `Authorization: Bearer <token>`。指标只包含路由模板、HTTP 方法、状态码、耗时、Go 运行时和数据库连接池状态，不记录 URL 参数、用户标识、令牌或账务内容。

### 数据库配置

默认使用 SQLite，适合单人私有部署和低维护场景。长期服务器部署或多设备高频访问时，可以改用 PostgreSQL；MySQL/MariaDB 也可通过 GORM driver 连接。

未初始化时 Web 会先进入 `/setup`，不会直接显示登录页。初始化页会显示当前数据库类型并支持连接测试；SQLite 可直接使用默认路径，PostgreSQL/MySQL 可填写主机、端口、库名、用户名和密码，系统会生成连接串并保存到本地配置。数据库切换应在设置访问密码前完成，保存新配置后重启服务，再回到 `/setup` 继续设置访问密码。高级用户仍可使用 DSN 模式。

| 变量 | 说明 | 默认值 |
|------|------|--------|
| LEDGER_DATABASE_DRIVER | 数据库类型：`sqlite` / `postgres` / `postgresql` / `mysql` / `mariadb` | sqlite |
| LEDGER_DATABASE_PATH | SQLite 数据库文件路径 | ./data/ledger.db |
| LEDGER_DATABASE_DSN | PostgreSQL/MySQL/MariaDB 连接串 | 空 |
| LEDGER_DATABASE_MAX_OPEN_CONNS | 最大打开连接数，0 表示驱动默认 | 0 |
| LEDGER_DATABASE_MAX_IDLE_CONNS | 最大空闲连接数，0 表示驱动默认 | 0 |
| LEDGER_SETUP_CONFIG_PATH | 初始化向导保存数据库配置的 YAML 路径，Docker 建议 `/data/config.yaml` | ./data/config.yaml |

PostgreSQL 示例：

```bash
LEDGER_DATABASE_DRIVER=postgres
LEDGER_DATABASE_DSN='postgres://ledger:password@db:5432/ledger?sslmode=disable&TimeZone=Asia/Shanghai'
```

MySQL/MariaDB 示例：

```bash
LEDGER_DATABASE_DRIVER=mysql
LEDGER_DATABASE_DSN='ledger:password@tcp(db:3306)/ledger?charset=utf8mb4&parseTime=True&loc=Local'
```

### 功能配置

| 变量 | 说明 | 默认值 |
|------|------|--------|
| LEDGER_JWT_ACCESS_EXPIRE | 登录状态刷新间隔 (分钟) | 15 |
| LEDGER_JWT_REFRESH_EXPIRE | 重新登录间隔 (分钟) | 43200 (30天) |
| LEDGER_STORAGE_MAX_FILE_SIZE | 最大上传文件 (MB) | 10 |
| LEDGER_STORAGE_RESTORE_MAX_FILE_SIZE | 最大 JSON 备份恢复文件 (MB) | 64 |
| LEDGER_SERVER_MODE | 服务器模式 (debug=禁用限流, release=启用限流) | release |
| LEDGER_CORS_ALLOWED_ORIGINS | 跨域白名单，留空仅允许同站 Host/无 Origin；前后端分离时填具体域名；release 禁止 `*` | 空 |
| LEDGER_RATE_LIMIT_MAX_REQUESTS | 每分钟最大请求数 (仅 release 模式) | 1000 |
| LEDGER_RATE_LIMIT_WINDOW_SECS | 限流时间窗口 (秒，仅 release 模式) | 60 |
| LEDGER_LOG_LEVEL | 日志级别 (debug/info/warn/error) | info |
| TZ | 时区 | Asia/Shanghai |

### docker-compose.yml 完整配置

```yaml
services:
  personal-ledger:
    image: ${LEDGER_IMAGE:-ghcr.io/sky121666/sky-personalledger:latest}
    container_name: personal-ledger
    restart: unless-stopped
    ports:
      - "8080:8080"
    volumes:
      - ./data:/data
    environment:
      # ========== 必须修改 ==========
      # 在 .env 中设置: LEDGER_JWT_SECRET=$(openssl rand -base64 32)
      - LEDGER_JWT_SECRET=${LEDGER_JWT_SECRET:?Set LEDGER_JWT_SECRET in .env before starting}
      - LEDGER_SETUP_TOKEN=${LEDGER_SETUP_TOKEN:?Set LEDGER_SETUP_TOKEN in .env before starting}
      
      # ========== 安全配置 (可选) ==========
      # 自定义入口路径，隐藏真实访问地址
      # - LEDGER_SECURITY_BASE_PATH=/my-secret-path
      # 默认禁止用户配置的出站地址访问容器回环/私网；连接本地 AI/SMTP 时由部署者审慎开启
      - LEDGER_SECURITY_ALLOW_PRIVATE_OUTBOUND=false
      # 反向代理部署时填写代理 IP/CIDR；不使用代理则保持为空
      - LEDGER_SERVER_TRUSTED_PROXIES=
      # 默认关闭；启用后必须同时配置至少 32 位随机抓取令牌
      - LEDGER_OBSERVABILITY_METRICS_ENABLED=false
      - LEDGER_OBSERVABILITY_METRICS_TOKEN=
      # 跨域白名单；同域部署保持为空，前后端分离时设置具体域名
      # - LEDGER_CORS_ALLOWED_ORIGINS=https://ledger.example.com
      
      # ========== 登录配置 ==========
      - LEDGER_JWT_ACCESS_EXPIRE=15      # 15分钟后自动刷新登录状态
      - LEDGER_JWT_REFRESH_EXPIRE=43200  # 30天后需要重新登录
      
      # ========== 存储配置 ==========
      - LEDGER_STORAGE_MAX_FILE_SIZE=10  # 最大上传文件 10MB
      - LEDGER_STORAGE_RESTORE_MAX_FILE_SIZE=64 # 最大备份恢复文件 64MB

      # ========== 数据库配置 ==========
      - LEDGER_DATABASE_DRIVER=sqlite
      - LEDGER_DATABASE_PATH=/data/ledger.db
      - LEDGER_SETUP_CONFIG_PATH=/data/config.yaml
      # PostgreSQL 示例:
      # - LEDGER_DATABASE_DRIVER=postgres
      # - LEDGER_DATABASE_DSN=postgres://ledger:password@db:5432/ledger?sslmode=disable&TimeZone=Asia/Shanghai
      
      # ========== 限流配置 ==========
      # 正式部署默认启用限流；仅本地开发时改为 debug
      - LEDGER_SERVER_MODE=release      # debug=禁用限流, release=启用限流
      # - LEDGER_RATE_LIMIT_MAX_REQUESTS=2000  # 每分钟最多请求数 (仅 release 模式)
      # - LEDGER_RATE_LIMIT_WINDOW_SECS=60     # 限流时间窗口 (仅 release 模式)
      
      # ========== 其他配置 ==========
      - LEDGER_LOG_LEVEL=info           # 日志级别
      - TZ=Asia/Shanghai                # 时区设置

# 数据持久化目录说明:
# ./data/ledger.db    - SQLite 数据库文件（默认）
# ./data/uploads/     - 用户上传的文件
# ./data/backups/     - 自动备份文件
```

### 常用管理命令

```bash
# 启动服务
docker compose up -d

# 停止服务
docker compose down

# 查看日志
docker compose logs -f

# 重启服务
docker compose restart

# 更新到最新版本
docker compose pull && docker compose up -d

# 备份数据
cp -r ./data ./data-backup-$(date +%Y%m%d)
```

## 📂 数据目录结构

```
./data/
├── ledger.db      # SQLite 数据库文件（默认）
├── uploads/       # 用户上传的文件
└── backups/       # 系统自动备份
```

## 🛠️ 技术栈

- **后端**: Go + Gin + GORM + SQLite/PostgreSQL/MySQL
- **前端**: Vue 3 + TypeScript + Tailwind CSS  
- **客户端**: Flutter 原生客户端
- **部署**: Docker + GitHub Actions

## 🔧 本地开发

基础 `docker-compose.yml` 始终使用生产安全的 `release` 模式。仅本地联调需要关闭全局限流时，显式叠加 debug override：

```bash
docker compose -f docker-compose.yml -f docker-compose.debug.yml up -d
```

停止该本地调试环境时使用相同的文件组合：

```bash
docker compose -f docker-compose.yml -f docker-compose.debug.yml down
```

不要将 `docker-compose.debug.yml` 用于生产部署。

```bash
# 后端开发
cd backend
go mod tidy          # 首次运行需要整理依赖
go run ./cmd/server  # 启动后端服务

# 前端开发
cd web
pnpm install
pnpm run dev

# 移动端开发
cd mobile
flutter pub get      # 获取依赖
flutter run
```

### Public repository safety

Before committing to the public repository, run:

```bash
./scripts/check-public-git-safety.sh
git diff --check
```

The safety check rejects tracked local config, databases, signing keys, build caches, app packages, and high-confidence secret patterns.

### Mobile runtime smoke

For the real backend E2E path, run from the repository root:

```bash
./scripts/verify-mobile-e2e.sh
```

Android and iOS simulator variants are documented in [docs/mobile-real-backend-e2e.md](docs/mobile-real-backend-e2e.md).

For a quick mocked UI smoke, run:

```bash
cd mobile
flutter test -d flutter-tester integration_test/app_smoke_test.dart
flutter run
```

Manual smoke checklist:

- save server URL
- log in
- open home
- open accounts
- create a quick expense transaction

## 📄 License

MIT License
