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

> 📦 **客户端说明**: 当前客户端已切换为原生 Flutter 应用，通过 API Client 直连服务端；旧 WebView 兜底入口已移除。Android 已完成当前原生范围验证，macOS/Windows 需要按目标平台单独回归。

从 [Releases](https://github.com/sky121666/sky-PersonalLedger/releases) 下载对应平台的客户端：

| 平台 | 文件名 | 说明 | 测试状态 |
|------|--------|------|----------|
| 🤖 Android | `personal-ledger-xxx-android.apk` | 原生 Flutter 客户端，正式包必须使用 release keystore 签名 | ✅ Android 模拟器 smoke 通过 |
| 🍎 macOS | `personal-ledger-xxx-macos.zip` | 原生 Flutter 客户端，首次需在安全设置中允许 | ⏳ 待平台回归 |
| 🪟 Windows | `personal-ledger-xxx-windows.zip` | 原生 Flutter 客户端 | ⏳ 待平台回归 |

### Android 正式签名

正式 Android APK 不允许使用 debug key 签名。发布前需要在 `mobile/android/key.properties` 配置 release keystore，或在 GitHub Actions 中配置同名 secrets：

```properties
storeFile=app/upload-keystore.jks
storePassword=your-store-password
keyAlias=upload
keyPassword=your-key-password
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
- **客户端**: Flutter 原生客户端
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

### Mobile runtime smoke

Run the backend locally, then run:

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
