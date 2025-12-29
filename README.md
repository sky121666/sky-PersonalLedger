# Personal Ledger 个人记账本

一款现代化的个人财务管理应用，支持 Web 和移动端，帮助您轻松管理日常收支、预算、借贷和债务。

## 🏗️ 项目架构

```
┌─────────────────────────────────────────────────────────────┐
│                        客户端                                │
│  ┌─────────────────┐              ┌─────────────────────┐   │
│  │   Web (Vue 3)   │              │  Mobile (Flutter)   │   │
│  │   SPA 应用      │              │  WebView 封装       │   │
│  └────────┬────────┘              └──────────┬──────────┘   │
│           │                                  │              │
│           │  HTTP/HTTPS                      │              │
│           └──────────────┬───────────────────┘              │
└──────────────────────────┼──────────────────────────────────┘
                           │
┌──────────────────────────┼──────────────────────────────────┐
│                          ▼                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Go Backend (Gin)                        │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐             │   │
│  │  │ Handler │→ │ Service │→ │  Repo   │→ SQLite     │   │
│  │  └─────────┘  └─────────┘  └─────────┘             │   │
│  │                                                      │   │
│  │  中间件: JWT认证 | API Token | 安全入口 | 限速      │   │
│  └─────────────────────────────────────────────────────┘   │
│                        服务端                               │
└─────────────────────────────────────────────────────────────┘
```

### 技术栈

| 层级 | 技术 | 说明 |
|-----|------|-----|
| 后端 | Go + Gin + GORM | 分层架构 (Handler → Service → Repository) |
| 数据库 | SQLite | 嵌入式数据库，零配置 |
| Web 前端 | Vue 3 + TypeScript + Vite | SPA 单页应用 |
| 移动端 | Flutter + WebView | 封装 Web 端，共享全部功能 |
| 样式 | TailwindCSS | 原子化 CSS |
| 状态管理 | Pinia | Vue 3 官方推荐 |

## ✨ 功能特性

### 📊 记账管理
- 收支记录 - 支持收入/支出/转账
- 多账户 - 现金、银行卡、信用卡、支付宝、微信等
- 分类管理 - 自定义收支分类和图标
- 标签系统 - 灵活的交易标签
- 交易模板 - 常用交易一键快速记录
- 周期性交易 - 自动定期记账

### 💰 财务分析
- 统计概览 - 收支趋势、分类占比
- 年度报告 - 年度财务汇总和资产趋势
- 预算管理 - 月度预算和超支提醒
- 账户变动日志 - 完整的资金流水追踪

### 💳 债务管理
- 负债追踪 - 信用卡、贷款等还款进度
- 借贷管理 - 借入借出记录，还款追踪
- 还款提醒 - 到期提醒通知

### 🔔 通知推送
- 企业微信 / 钉钉 / 邮件 / 自定义 Webhook
- 还款提醒、预算超支、登录通知

### 🔐 安全特性
- JWT 认证 - 安全的用户认证机制
- API Token - 移动端长期访问凭证
- 安全入口 - 可设置隐蔽访问路径
- 请求限速 - 防止暴力破解
- 数据备份 - 支持自动/手动备份

## 📱 桌面端 & 移动端

采用 **Flutter WebView 封装** 方案，一套代码支持多平台：

| 平台 | 支持 | 说明 |
|-----|-----|------|
| Android | ✅ | SDK 20+ |
| macOS | ✅ | 原生 WebView |
| Windows | ✅ | Win 10+ |

### 工作原理
1. 用户首次启动，输入服务器地址（支持安全入口路径）
2. WebView 加载 Web 应用
3. 通过 JWT 认证，享受完整的 Web 端功能

### 构建命令

```bash
cd mobile
flutter pub get

# macOS
flutter build macos

# Windows
flutter build windows

# Android
flutter build apk
```

## 🔒 安全入口机制

安全入口是一种隐蔽访问机制，防止应用被随意发现：

```yaml
# config.yaml
security:
  base_path: "/my-secret-2024"  # 设置后只能通过此路径访问
```

**工作原理：**
1. 未配置时：直接访问 `http://host:8080/` 即可
2. 配置后：必须访问 `http://host:8080/my-secret-2024` 才能进入
3. 首次访问正确路径后，服务端设置 Cookie 记住验证状态
4. 直接访问根路径返回 404，隐藏应用存在

**移动端使用：** 在服务器地址中包含入口路径，如 `example.com/my-secret-2024`

## 🛠️ API 接口

所有 API 以 `/api/v1` 为前缀，支持 JWT 和 API Token 两种认证方式。

### 认证相关
| 方法 | 路径 | 说明 |
|-----|------|-----|
| GET | /auth/status | 检查系统状态 |
| POST | /auth/init | 初始化管理员 |
| POST | /auth/login | 用户登录 |
| POST | /auth/refresh | 刷新 Token |
| POST | /auth/verify-token | 验证 API Token |

### 核心功能
| 模块 | 路径前缀 | 说明 |
|-----|---------|-----|
| 账户 | /accounts | 账户 CRUD、归档、排序 |
| 分类 | /categories | 收支分类管理 |
| 交易 | /transactions | 交易记录 CRUD、批量删除 |
| 预算 | /budgets | 预算设置和统计 |
| 负债 | /reminders | 负债追踪和还款记录 |
| 借贷 | /lendings | 借入借出管理 |
| 统计 | /statistics | 概览、分类统计、趋势 |
| 标签 | /tags | 交易标签管理 |

### 系统功能
| 模块 | 路径前缀 | 说明 |
|-----|---------|-----|
| 备份 | /backup | 手动/自动备份和恢复 |
| 导出 | /export | CSV 导出、年度报告 |
| 上传 | /upload | 文件/头像上传 |
| 通知 | /notifications | 通知渠道配置 |
| 系统 | /system | 安全入口设置 |
| API Token | /api-tokens | 移动端 Token 管理 |

## 📦 快速开始

### 环境要求
- Go 1.21+
- Node.js 18+
- pnpm / npm

### 开发模式

```bash
# 1. 克隆项目
git clone https://github.com/yourusername/personal-ledger.git
cd personal-ledger

# 2. 启动后端 (终端 1)
cd backend
cp config.yaml.example config.yaml  # 首次需要
go run cmd/server/main.go

# 3. 启动前端 (终端 2)
cd web
npm install
npm run dev
```

前端开发服务器 `http://localhost:5173` 会自动代理 API 到后端。

### 生产构建

```bash
# 构建前端
cd web
npm run build

# 运行后端 (会自动服务前端静态文件)
cd backend
go run cmd/server/main.go
```

访问 `http://localhost:8080`

### Docker 部署

```bash
docker run -d \
  -p 8080:8080 \
  -v ./data:/app/data \
  -v ./config.yaml:/app/config.yaml \
  -e LEDGER_JWT_SECRET="your-secure-secret-key-at-least-32-chars" \
  personal-ledger
```

## ⚙️ 配置说明

支持配置文件 (`config.yaml`) 和环境变量两种方式，环境变量优先级更高。

```yaml
server:
  port: "8080"              # 服务端口 | LEDGER_SERVER_PORT
  mode: "release"           # debug/release | LEDGER_SERVER_MODE
  web_path: "./web/dist"    # 前端文件路径 | LEDGER_SERVER_WEB_PATH

database:
  path: "./data/ledger.db"  # 数据库路径 | LEDGER_DATABASE_PATH

jwt:
  secret: ""                # JWT 密钥 (必须 ≥32 字符) | LEDGER_JWT_SECRET
  access_expire: 15         # 访问令牌过期(分钟) | LEDGER_JWT_ACCESS_EXPIRE
  refresh_expire: 43200     # 刷新令牌过期(分钟) | LEDGER_JWT_REFRESH_EXPIRE

security:
  base_path: ""             # 安全入口路径 | LEDGER_SECURITY_BASE_PATH

storage:
  upload_path: "./data/uploads"   # 上传文件路径
  backup_path: "./data/backups"   # 备份文件路径
  max_file_size: 10               # 最大文件大小(MB)

rate_limit:
  max_requests: 1000        # 每窗口最大请求数 (仅 release 模式)
  window_secs: 60           # 时间窗口(秒)

cors:
  allowed_origins: "*"      # 允许的跨域来源 (生产环境应指定域名)
```

## 📁 项目结构

```
personal-ledger/
├── backend/                    # Go 后端
│   ├── cmd/server/main.go     # 入口文件
│   ├── internal/
│   │   ├── config/            # 配置加载
│   │   ├── database/          # 数据库初始化
│   │   ├── handler/           # HTTP 处理器
│   │   ├── middleware/        # 中间件 (认证/限速/日志)
│   │   ├── model/             # 数据模型
│   │   ├── repository/        # 数据访问层
│   │   └── service/           # 业务逻辑层
│   └── pkg/                   # 公共包 (jwt/logger/response)
│
├── web/                       # Vue 3 前端
│   ├── src/
│   │   ├── api/              # API 接口封装
│   │   ├── components/       # 通用组件
│   │   ├── composables/      # 组合式函数
│   │   ├── router/           # 路由配置
│   │   ├── stores/           # Pinia 状态管理
│   │   ├── utils/            # 工具函数
│   │   └── views/            # 页面组件
│   └── ...
│
├── mobile/                    # Flutter 客户端 (macOS/Windows/Android)
│   └── lib/main.dart         # WebView 封装实现
│
└── config.example.yaml        # 配置示例
```

## 📄 License

MIT License

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！
