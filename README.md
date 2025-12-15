# Personal Ledger 个人记账本

一款现代化的个人财务管理应用，支持 Web 和移动端，帮助您轻松管理日常收支、预算、借贷和债务。

## ✨ 功能特性

### 📊 记账管理
- **收支记录** - 快速记录收入、支出和转账
- **分类管理** - 自定义收支分类和图标
- **多账户** - 支持现金、银行卡、信用卡等多种账户类型
- **交易模板** - 常用交易一键快速记录

### 💰 财务分析
- **统计概览** - 收支趋势、分类占比一目了然
- **年度报告** - 年度财务汇总和资产趋势
- **预算管理** - 设置月度预算，超支提醒

### 💳 债务管理
- **负债追踪** - 信用卡、贷款等债务还款进度
- **借贷管理** - 借入借出记录，还款追踪
- **联动撤回** - 删除明细时自动撤回关联数据

### 🔐 安全特性
- **JWT 认证** - 安全的用户认证机制
- **自定义入口** - 可设置隐蔽访问路径
- **API Token** - 移动端访问安全验证
- **数据备份** - 支持数据导入导出

## 🛠️ 技术栈

### 后端

| 技术 | 版本 | 说明 |
|-----|------|-----|
| Go | 1.21+ | 高性能后端语言 |
| Gin | 1.11.0 | 轻量级 Web 框架 |
| GORM | 1.31.1 | ORM 框架 |
| SQLite | 1.6.0 | 嵌入式数据库 |
| JWT | 5.3.0 | 用户认证 |
| Zap | 1.27.1 | 结构化日志 |
| Viper | 1.21.0 | 配置管理 |

### 前端

| 技术 | 版本 | 说明 |
|-----|------|-----|
| Vue | 3.4.29 | 渐进式前端框架 |
| TypeScript | 5.4.5 | 类型安全 |
| Vite | 5.3.1 | 快速构建工具 |
| TailwindCSS | 3.4.4 | 原子化 CSS |
| Pinia | 2.1.7 | 状态管理 |
| Vue Router | 4.3.3 | 路由管理 |
| Axios | 1.7.2 | HTTP 客户端 |
| Lucide | 0.378.0 | 图标库 |
| Day.js | 1.11.11 | 日期处理 |

## 📦 快速开始

### 环境要求

- **Go** 1.21+
- **Node.js** 18+
- **pnpm** / npm / yarn

### 1. 克隆项目
```bash
git clone https://github.com/yourusername/personal-ledger.git
cd personal-ledger
```

### 2. 配置文件
```bash
cp config.example.yaml config.yaml
# 编辑 config.yaml 修改配置
```

### 3. 构建前端
```bash
cd web
npm install
npm run build
cd ..
```

### 4. 运行后端
```bash
cd backend
go run cmd/server/main.go
```

### 5. 访问应用
打开浏览器访问 `http://localhost:8080`

## 🐳 Docker 部署

```bash
# 构建镜像
docker build -t personal-ledger .

# 运行容器
docker run -d \
  -p 8080:8080 \
  -v ./data:/app/data \
  -v ./config.yaml:/app/config.yaml \
  personal-ledger
```

## ⚙️ 配置说明

```yaml
server:
  port: "8080"           # 服务端口
  mode: "release"        # debug / release
  web_path: "./web/dist" # 前端文件路径

database:
  path: "./data/ledger.db"  # 数据库路径

jwt:
  secret: "your-secret"     # JWT 密钥 (请修改!)
  access_expire: 15         # 访问令牌过期时间 (分钟)
  refresh_expire: 43200     # 刷新令牌过期时间 (分钟)

security:
  base_path: ""             # 自定义入口路径
  api_token: ""             # API Token (移动端需要)

storage:
  upload_path: "./data/uploads"  # 上传文件路径
  max_file_size: 10              # 最大文件大小 (MB)
```

## 📱 移动端

项目包含基于 Capacitor 的移动端应用，支持 iOS 和 Android。

```bash
cd mobile
npm install
npm run build
npx cap sync
```

## 📁 项目结构

```
personal-ledger/
├── backend/                # 后端代码
│   ├── cmd/server/        # 入口文件
│   └── internal/          # 内部模块
│       ├── config/        # 配置
│       ├── handler/       # HTTP 处理器
│       ├── middleware/    # 中间件
│       ├── model/         # 数据模型
│       ├── repository/    # 数据访问层
│       └── service/       # 业务逻辑层
├── web/                   # 前端代码
│   ├── src/
│   │   ├── api/          # API 接口
│   │   ├── components/   # 组件
│   │   ├── stores/       # 状态管理
│   │   ├── utils/        # 工具函数
│   │   └── views/        # 页面
│   └── ...
├── mobile/               # 移动端代码
├── config.example.yaml   # 配置示例
└── README.md
```

## 🔧 开发

### 后端开发
```bash
cd backend
go run cmd/server/main.go
```

### 前端开发
```bash
cd web
npm run dev
```

前端开发服务器默认运行在 `http://localhost:5173`，会自动代理 API 请求到后端。

## 📄 License

MIT License

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！
