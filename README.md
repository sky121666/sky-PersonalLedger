# sky-PersonalLedger

个人记账系统 - 简单、安全、跨平台

## 功能特点

- **多平台支持**: Web、Android、iOS、微信小程序
- **单用户设计**: 个人专属，无需复杂权限
- **本地优先**: SQLite 单文件数据库，数据完全自控
- **Docker 部署**: 一键部署，简单运维

## 技术栈

> ⚠️ 使用最新稳定版本

| 层级 | 技术 | 版本 |
|------|------|------|
| 前端 | uni-app (Vue 3 + TypeScript) | Vue 3.4+ |
| 构建 | Vite | 5.0+ |
| 状态 | Pinia | 2.1+ |
| 图表 | ECharts | 5.5+ |
| 后端 | Go (Gin) | Go 1.22+, Gin 1.9+ |
| ORM | GORM | 1.25+ |
| 数据库 | SQLite | 3.40+ |
| 部署 | Docker | 24.0+ |

---

## 📋 TODO

### Phase 1: 项目初始化

- [ ] 初始化 Go 后端项目结构
- [ ] 初始化 uni-app 前端项目
- [ ] 配置 Docker 环境
- [ ] 数据库表结构创建

### Phase 2: 认证模块

- [ ] 首次初始化接口 (创建用户)
- [ ] 登录/登出接口
- [ ] JWT Token 生成与验证
- [ ] Token 刷新机制
- [ ] 登录失败锁定

### Phase 3: 核心功能

- [ ] 账户管理 CRUD
- [ ] 分类管理 CRUD
- [ ] 交易管理 CRUD
- [ ] 账户余额自动计算 (触发器)

### Phase 4: 扩展功能

- [ ] 预算管理
- [ ] 还款提醒
- [ ] 定时任务 (robfig/cron)
- [ ] 多渠道通知 (企业微信/钉钉/邮件/公众号)
- [ ] 通知日志记录
- [ ] 数据统计 API
- [ ] 账单导入 (微信/支付宝/银行卡)
- [ ] 智能分类匹配规则
- [ ] 快捷记账模板
- [ ] 图片附件上传
- [ ] 标签功能

### Phase 5: 前端页面

- [ ] 登录页面
- [ ] 首页仪表盘
- [ ] 交易列表页 (含离线支持)
- [ ] 账户管理页
- [ ] 统计图表页 (ECharts)
- [ ] 账单导入页
- [ ] 设置页面

### Phase 6: 多端适配

- [ ] H5 适配
- [ ] Android 打包
- [ ] iOS 打包
- [ ] 微信小程序适配

### Phase 7: 部署上线

- [ ] Docker 镜像构建
- [ ] docker-compose 配置
- [ ] Nginx 配置
- [ ] SSL 证书配置

---

## 核心功能

| 功能 | 说明 |
|------|------|
| 账户管理 | 现金/银行卡/支付宝/微信/信用/贷款/应收/应付 |
| 交易记录 | 收入/支出/转账，自动更新账户余额 |
| 分类管理 | 收入/支出分类，自定义图标颜色 |
| 预算管理 | 月度总预算 + 分类预算 |
| 还款提醒 | 信用/贷款还款日提醒，多渠道通知 |
| 借贷管理 | 通过应收款/应付款账户 + 转账实现 |
| 数据统计 | 月度概览、分类占比、趋势图 |

## 不包含功能

- ❌ 理财/基金/股票投资
- ❌ 多用户/权限管理

---

## 项目结构

```
sky-PersonalLedger/
├── backend/              # Go 后端
│   ├── cmd/server/       # 入口
│   ├── internal/         # 内部模块
│   │   ├── handler/      # HTTP 处理
│   │   ├── service/      # 业务逻辑
│   │   ├── repository/   # 数据访问
│   │   ├── model/        # 数据模型
│   │   └── notify/       # 通知模块
│   └── pkg/              # 公共包
│
├── app/                  # uni-app 前端
│   └── src/
│       ├── pages/        # 页面
│       ├── components/   # 组件
│       ├── api/          # API 请求
│       ├── stores/       # 状态管理
│       └── utils/        # 工具函数
│
├── docker/               # Docker 配置
├── docs/                 # 项目文档
├── docker-compose.yml
└── README.md
```

---

## 快速开始

### 开发环境

```bash
# 启动后端
cd backend
go run cmd/server/main.go

# 启动前端
cd app
pnpm dev
```

### Docker 部署

```bash
# 开发环境
docker-compose up -d

# 生产环境
docker-compose -f docker-compose.prod.yml up -d
```

---

## 文档

- [需求文档](docs/REQUIREMENTS.md)
- [数据库设计](docs/DATABASE.md)
- [账单导入格式](docs/IMPORT_FORMATS.md)

## License

MIT
