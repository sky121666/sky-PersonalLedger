# sky-PersonalLedger

个人记账系统 - 简单、安全、跨平台

## 功能特点

- **多平台支持**: Android、iOS、微信小程序、Web (H5/PC)
- **原生渲染**: uni-app x 原生引擎，性能接近原生
- **响应式设计**: 统一 Apple 简约风，自适应移动端/PC 端布局
- **单用户设计**: 个人专属，无需复杂权限
- **本地优先**: SQLite 单文件数据库，数据完全自控

## UI/UX 设计

**统一设计风格**: Apple 极简主义 (iOS Human Interface Guidelines)

- **视觉语言**: 大量留白、圆角卡片、毛玻璃效果、细腻阴影
- **图标系统**: SF Symbols 风格线性图标
- **响应式布局**:
  - **移动端** (App / 小程序 / H5 < 768px): 单栏全屏 + 底部 Tab Bar
  - **PC 端** (H5 ≥ 768px): 侧边栏导航 + 多列卡片布局

## 技术栈

### 后端

| 技术 | 版本 |
|------|------|
| Go | 1.23+ |
| Gin | 1.11.0 |
| GORM | 1.31.1 |
| SQLite | 1.14.32 |
| Zap | 1.27.1 |
| Viper | 1.21.0 |
| JWT | 5.3.0 |

### 前端

| 技术 | 版本 |
|------|------|
| uni-app x | 0.7.82 |
| UTS | latest |
| Vue | 3.5.13 |
| Vite | 5.2.8 |

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
| 账单导入 | 微信/支付宝/银行账单导入 |

## 项目结构

```
sky-PersonalLedger/
├── backend/              # Go 后端
│   ├── cmd/server/       # 入口
│   ├── internal/         # 内部模块
│   └── pkg/              # 公共包
├── app/                  # uni-app x 前端
│   ├── src/
│   │   ├── pages/        # 页面 (.uvue)
│   │   ├── api/          # API 接口 (.uts)
│   │   ├── utils/        # 工具函数 (.uts)
│   │   └── static/       # 静态资源
│   └── package.json
└── docs/                 # 项目文档
```

## 快速开始

```bash
# 启动后端
cd backend
go run cmd/server/main.go

# 启动前端 (H5)
cd app
npm install
npm run dev:h5

# 启动前端 (Android)
npm run dev:app-android

# 启动前端 (iOS)
npm run dev:app-ios
```

## 文档

### 需求规格

- [功能需求规格](docs/REQUIREMENTS.md)
- [API 接口定义](docs/API_ENDPOINTS.md)
- [账单导入格式](docs/IMPORT_FORMATS.md)

### 设计规范

- [UI/UX 设计规范](docs/UI_DESIGN.md)
- [API 设计规范](docs/API_DESIGN.md)
- [数据库设计规范](docs/DATABASE_DESIGN.md)
- [同步与离线策略](docs/SYNC_STRATEGY.md)
- [工程代码规范](docs/CODE_STYLE.md)
- [安全设计规范](docs/SECURITY.md)

## License

MIT
