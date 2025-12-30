# Personal Ledger

简洁、安全的个人记账系统，支持私有部署。

## 特性

- 🔐 **安全私密** - 数据存储在你自己的服务器
- 📱 **多端支持** - Web / Android / macOS / Windows
- 🐳 **Docker 部署** - 一键启动，开箱即用
- 💾 **SQLite 存储** - 单文件数据库，易于备份

## 快速开始

### Docker 部署 (推荐)

```bash
# 拉取镜像
docker pull ghcr.io/sky121666/sky-personalledger:latest

# 启动服务
docker run -d \
  --name personal-ledger \
  -p 8080:8080 \
  -v ./data:/data \
  -e LEDGER_JWT_SECRET=$(openssl rand -base64 32) \
  ghcr.io/sky121666/sky-personalledger:latest
```

或使用 docker-compose:

```bash
wget https://raw.githubusercontent.com/sky121666/sky-PersonalLedger/main/docker-compose.yml
# 编辑 docker-compose.yml 修改 LEDGER_JWT_SECRET
docker-compose up -d
```

访问 `http://localhost:8080` 开始使用。

### 客户端下载

从 [Releases](https://github.com/sky121666/sky-PersonalLedger/releases) 下载对应平台的客户端：

| 平台 | 说明 |
|------|------|
| Android | 直接安装 APK |
| macOS | 解压后运行，首次需在安全设置中允许 |
| Windows | 解压后运行，需安装 [WebView2](https://developer.microsoft.com/en-us/microsoft-edge/webview2/) |

## 配置

### 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| **LEDGER_JWT_SECRET** | JWT 密钥 (必须修改，至少32位随机字符串) | - |
| LEDGER_SECURITY_BASE_PATH | 自定义入口路径 (如 `/my-ledger`) | 空 |
| LEDGER_SECURITY_API_TOKEN | API Token (移动端验证，留空不验证) | 空 |
| LEDGER_JWT_ACCESS_EXPIRE | Access Token 过期 (分钟) | 15 |
| LEDGER_JWT_REFRESH_EXPIRE | Refresh Token 过期 (分钟) | 43200 (30天) |
| LEDGER_STORAGE_MAX_FILE_SIZE | 最大上传文件 (MB) | 10 |
| LEDGER_STORAGE_ALLOWED_TYPES | 允许上传的文件类型 | jpg,jpeg,png,gif... |
| LEDGER_RATE_LIMIT_MAX_REQUESTS | 每分钟最大请求数 | 1000 |
| LEDGER_RATE_LIMIT_WINDOW_SECS | 限流时间窗口 (秒) | 60 |
| LEDGER_LOG_LEVEL | 日志级别 (debug/info/warn/error) | info |
| LEDGER_LOG_FORMAT | 日志格式 (json/text) | json |
| TZ | 时区 | Asia/Shanghai |

### docker-compose.yml 示例

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
      - LEDGER_JWT_SECRET=please-change-this-to-a-random-secret-key
      
      # ========== 安全配置 (可选) ==========
      # - LEDGER_SECURITY_BASE_PATH=/my-secret-path
      # - LEDGER_SECURITY_API_TOKEN=sk-your-api-token
      
      # ========== JWT 配置 ==========
      - LEDGER_JWT_ACCESS_EXPIRE=15
      - LEDGER_JWT_REFRESH_EXPIRE=43200
      
      # ========== 存储配置 ==========
      - LEDGER_STORAGE_MAX_FILE_SIZE=10
      
      # ========== 限流配置 ==========
      - LEDGER_RATE_LIMIT_MAX_REQUESTS=2000
      - LEDGER_RATE_LIMIT_WINDOW_SECS=60
      
      # ========== 日志配置 ==========
      - LEDGER_LOG_LEVEL=info
      
      # ========== 时区 ==========
      - TZ=Asia/Shanghai
```

### 数据目录

Docker 容器的 `/data` 目录包含：

```
./data/
├── ledger.db      # SQLite 数据库
├── uploads/       # 上传的文件
└── backups/       # 备份文件
```

### config.yaml 配置 (本地开发)

复制 `config.example.yaml` 为 `config.yaml`，Docker 部署时优先使用环境变量。

环境变量格式：`LEDGER_分类_配置项`，如 `server.port` → `LEDGER_SERVER_PORT`

## 技术栈

- **后端**: Go + Gin + GORM + SQLite
- **前端**: Vue 3 + TypeScript + Tailwind CSS
- **客户端**: Flutter (WebView)

## 开发

```bash
# 后端
cd backend
go run ./cmd/server

# 前端
cd web
npm install
npm run dev

# 客户端
cd mobile
flutter run
```

## License

MIT
