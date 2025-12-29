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
  -e LEDGER_JWT_SECRET=your-random-secret-key \
  ghcr.io/sky121666/sky-personalledger:latest
```

或使用 docker-compose:

```bash
wget https://raw.githubusercontent.com/sky121666/sky-PersonalLedger/main/docker-compose.yml
# 编辑 docker-compose.yml 修改 JWT_SECRET
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
| `LEDGER_JWT_SECRET` | JWT 密钥 (必须修改) | - |
| `LEDGER_SECURITY_BASE_PATH` | 自定义入口路径 | 空 |
| `LEDGER_JWT_ACCESS_EXPIRE` | Access Token 过期(分钟) | 15 |
| `LEDGER_JWT_REFRESH_EXPIRE` | Refresh Token 过期(分钟) | 43200 |
| `LEDGER_STORAGE_MAX_FILE_SIZE` | 最大上传文件(MB) | 10 |
| `LEDGER_LOG_LEVEL` | 日志级别 | info |

### 数据目录

Docker 容器的 `/data` 目录包含：
```
/data
├── ledger.db      # SQLite 数据库
├── uploads/       # 上传的文件
└── backups/       # 备份文件
```

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
