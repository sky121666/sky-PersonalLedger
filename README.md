# Personal Ledger

🏠 简洁、安全的个人记账系统，支持私有部署

## ✨ 特性

- 🔐 **安全私密** - 数据存储在你自己的服务器，完全掌控
- 📱 **多端支持** - Web 网页版 + Android/macOS/Windows 客户端
- 🐳 **一键部署** - Docker/1Panel 快速部署，开箱即用
- 💾 **轻量存储** - SQLite 单文件数据库，易于备份迁移
- 🚀 **高性能** - Go 后端 + Vue3 前端，响应迅速
- 🛡️ **安全防护** - JWT 认证 + 限流保护 + 自定义入口

## 🚀 快速开始

### 方式一：Docker Compose (推荐)

```bash
# 1. 下载配置文件
wget https://raw.githubusercontent.com/sky121666/sky-PersonalLedger/main/docker-compose.yml

# 2. 修改 JWT 密钥 (必须!)
nano docker-compose.yml
# 将 LEDGER_JWT_SECRET 改为随机字符串，如: $(openssl rand -base64 32)

# 3. 启动服务
docker-compose up -d

# 4. 查看状态
docker-compose ps
docker-compose logs -f
```

✅ **访问地址**: `http://localhost:8080`

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
  -e LEDGER_JWT_ACCESS_EXPIRE=15 \
  -e LEDGER_JWT_REFRESH_EXPIRE=43200 \
  -e LEDGER_STORAGE_MAX_FILE_SIZE=10 \
  -e LEDGER_SERVER_MODE=debug \
  -e LEDGER_LOG_LEVEL=info \
  -e TZ=Asia/Shanghai \
  ghcr.io/sky121666/sky-personalledger:latest

# 可选的安全配置
# -e LEDGER_SECURITY_BASE_PATH=/my-secret-path \
# -e LEDGER_SECURITY_API_TOKEN=sk-your-api-token \
```

## 📱 客户端下载

从 [Releases](https://github.com/sky121666/sky-PersonalLedger/releases) 下载对应平台的客户端：

| 平台 | 文件名 | 说明 |
|------|--------|------|
| 🤖 Android | `personal-ledger-xxx-android.apk` | 直接安装 APK |
| 🍎 macOS | `personal-ledger-xxx-macos.zip` | 解压后运行，首次需在安全设置中允许 |
| 🪟 Windows | `personal-ledger-xxx-windows.zip` | 解压后运行，需安装 [WebView2](https://developer.microsoft.com/en-us/microsoft-edge/webview2/) |

## ⚙️ 配置说明

### 核心环境变量

| 变量 | 说明 | 默认值 | 重要性 |
|------|------|--------|--------|
| **LEDGER_JWT_SECRET** | JWT 密钥 (至少32位随机字符串) | - | ⚠️ 必须修改 |
| LEDGER_SECURITY_BASE_PATH | 自定义入口路径 (如 `/my-ledger`) | 空 | 🔒 安全推荐 |
| LEDGER_SECURITY_API_TOKEN | API Token (移动端验证) | 空 | 📱 移动端必需 |

### 功能配置

| 变量 | 说明 | 默认值 |
|------|------|--------|
| LEDGER_JWT_ACCESS_EXPIRE | 登录状态刷新间隔 (分钟) | 15 |
| LEDGER_JWT_REFRESH_EXPIRE | 重新登录间隔 (分钟) | 43200 (30天) |
| LEDGER_STORAGE_MAX_FILE_SIZE | 最大上传文件 (MB) | 10 |
| LEDGER_SERVER_MODE | 服务器模式 (debug=禁用限流, release=启用限流) | release |
| LEDGER_RATE_LIMIT_MAX_REQUESTS | 每分钟最大请求数 (仅 release 模式) | 1000 |
| LEDGER_RATE_LIMIT_WINDOW_SECS | 限流时间窗口 (秒，仅 release 模式) | 60 |
| LEDGER_LOG_LEVEL | 日志级别 (debug/info/warn/error) | info |
| TZ | 时区 | Asia/Shanghai |

### docker-compose.yml 完整配置

```yaml
version: '3.8'

services:
  personal-ledger:
    image: ghcr.io/sky121666/sky-personalledger:latest
    container_name: personal-ledger
    restart: unless-stopped
    ports:
      - "8080:8080"
    volumes:
      - ./data:/data
    environment:
      # ========== 必须修改 ==========
      # 生成随机密钥: openssl rand -base64 32
      - LEDGER_JWT_SECRET=please-change-this-to-a-random-secret-key
      
      # ========== 安全配置 (可选) ==========
      # 自定义入口路径，隐藏真实访问地址
      # - LEDGER_SECURITY_BASE_PATH=/my-secret-path
      # 移动端 API 验证 Token
      # - LEDGER_SECURITY_API_TOKEN=sk-your-api-token
      
      # ========== 登录配置 ==========
      - LEDGER_JWT_ACCESS_EXPIRE=15      # 15分钟后自动刷新登录状态
      - LEDGER_JWT_REFRESH_EXPIRE=43200  # 30天后需要重新登录
      
      # ========== 存储配置 ==========
      - LEDGER_STORAGE_MAX_FILE_SIZE=10  # 最大上传文件 10MB
      
      # ========== 限流配置 ==========
      # 开发模式禁用限流，生产环境可改为 release 并设置限流参数
      - LEDGER_SERVER_MODE=debug        # debug=禁用限流, release=启用限流
      # - LEDGER_RATE_LIMIT_MAX_REQUESTS=2000  # 每分钟最多请求数 (仅 release 模式)
      # - LEDGER_RATE_LIMIT_WINDOW_SECS=60     # 限流时间窗口 (仅 release 模式)
      
      # ========== 其他配置 ==========
      - LEDGER_LOG_LEVEL=info           # 日志级别
      - TZ=Asia/Shanghai                # 时区设置

# 数据持久化目录说明:
# ./data/ledger.db    - SQLite 数据库文件
# ./data/uploads/     - 用户上传的文件
# ./data/backups/     - 自动备份文件
```

### 常用管理命令

```bash
# 启动服务
docker-compose up -d

# 停止服务
docker-compose down

# 查看日志
docker-compose logs -f

# 重启服务
docker-compose restart

# 更新到最新版本
docker-compose pull && docker-compose up -d

# 备份数据
cp -r ./data ./data-backup-$(date +%Y%m%d)
```

## 📂 数据目录结构

```
./data/
├── ledger.db      # SQLite 数据库文件
├── uploads/       # 用户上传的文件
└── backups/       # 系统自动备份
```

## 🛠️ 技术栈

- **后端**: Go + Gin + GORM + SQLite
- **前端**: Vue 3 + TypeScript + Tailwind CSS  
- **客户端**: Flutter (WebView)
- **部署**: Docker + GitHub Actions

## 🔧 本地开发

```bash
# 后端开发
cd backend
go mod tidy          # 首次运行需要整理依赖
go run ./cmd/server  # 启动后端服务

# 前端开发
cd web
npm install
npm run dev

# 移动端开发
cd mobile
flutter pub get      # 获取依赖
flutter run
```

## 📄 License

MIT License 