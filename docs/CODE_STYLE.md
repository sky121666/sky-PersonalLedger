# 工程代码规范

## 1. 项目结构

### 1.1 后端 (Go)

```
backend/
├── cmd/
│   └── server/
│       └── main.go           # 入口文件
├── config.yaml               # 配置文件
├── internal/
│   ├── config/               # 配置加载
│   ├── database/             # 数据库初始化
│   ├── handler/              # HTTP 处理器
│   ├── middleware/           # 中间件 (认证、日志、CORS)
│   ├── model/                # 数据模型 (GORM)
│   ├── repository/           # 数据访问层
│   ├── service/              # 业务逻辑层
│   ├── cron/                 # 定时任务
│   └── notify/               # 通知服务
├── pkg/                      # 可复用公共包
│   ├── jwt/
│   ├── logger/
│   └── response/
├── data/                     # SQLite 数据文件 (gitignore)
└── logs/                     # 日志文件 (gitignore)
```

### 1.2 前端 (uni-app x)

```
app/
├── src/
│   ├── pages/                # 页面 (.uvue)
│   │   ├── index/
│   │   ├── transaction/
│   │   ├── account/
│   │   ├── category/
│   │   ├── budget/
│   │   ├── statistics/
│   │   ├── settings/
│   │   └── auth/
│   ├── components/           # 公共组件 (.uvue)
│   ├── api/                  # API 接口封装 (.uts)
│   ├── utils/                # 工具函数 (.uts)
│   ├── store/                # 状态管理 (.uts)
│   ├── types/                # 类型定义 (.uts)
│   ├── static/               # 静态资源 (图标、图片)
│   ├── styles/               # 全局样式
│   ├── App.uvue              # 应用入口
│   ├── main.uts              # 入口脚本
│   ├── pages.json            # 页面配置
│   └── manifest.json         # 应用配置
├── package.json
└── vite.config.ts
```

## 2. 命名规范

### 2.1 通用规则

| 类型 | 规范 | 示例 |
|------|------|------|
| 文件名 | 小写，短横线分隔 | `transaction-list.uvue` |
| 目录名 | 小写，短横线分隔 | `category-rules/` |
| 常量 | 全大写，下划线分隔 | `MAX_RETRY_COUNT` |
| 类型/接口 | PascalCase | `Transaction`, `ApiResponse` |
| 函数/变量 | camelCase | `formatAmount()`, `isLoading` |
| 组件 | PascalCase | `TransactionItem.uvue` |

### 2.2 Go 特定规则

- **包名**: 小写单词，无下划线
- **导出**: 首字母大写
- **接口**: 以 `er` 结尾（如 `Reader`, `AccountService`）
- **错误**: `ErrXxx` 格式（如 `ErrNotFound`）

### 2.3 UTS 特定规则

- **类型导出**: 使用 `export type`
- **函数导出**: 使用 `export function`
- **避免 `any`**: 尽量显式声明类型

## 3. uni-app x (UTS) 注意事项

### 3.1 与 TypeScript 的差异

| 特性 | TypeScript | UTS |
|------|------------|-----|
| 可选链 | `obj?.prop` | 支持 |
| 空值合并 | `a ?? b` | 支持 |
| 类型断言 | `as Type` | 支持 |
| 泛型 | 完整支持 | 部分支持 |
| 装饰器 | 支持 | 不支持 |
| `any` 类型 | 允许 | 尽量避免 |

### 3.2 平台差异处理

```typescript
// 条件编译
// #ifdef APP-ANDROID
androidSpecificCode()
// #endif

// #ifdef APP-IOS
iosSpecificCode()
// #endif

// #ifdef H5
webSpecificCode()
// #endif
```

### 3.3 API 调用规范

```typescript
// 推荐：使用 async/await
async function fetchData(): Promise<ApiResponse<Data>> {
  const res = await uni.request({
    url: BASE_URL + '/endpoint',
    method: 'GET'
  })
  return res.data as ApiResponse<Data>
}
```

## 4. 组件规范

### 4.1 单文件组件结构 (.uvue)

```vue
<template>
  <!-- 模板内容 -->
</template>

<script lang="uts">
  // 脚本逻辑
  export default {
    data() {
      return {}
    },
    methods: {}
  }
</script>

<style lang="scss">
  /* 样式 */
</style>
```

### 4.2 组件职责

- **页面组件** (`pages/`): 负责页面级逻辑、路由、数据获取
- **公共组件** (`components/`): 可复用 UI 组件，通过 props 传入数据
- **业务组件**: 放在对应页面目录下，非通用

## 5. 样式规范

### 5.1 CSS 类命名

采用 BEM 变体：

```css
.card {}
.card__header {}
.card__body {}
.card--active {}
.card--disabled {}
```

### 5.2 变量使用

```scss
// styles/variables.scss
$primary-color: #007AFF;
$text-primary: #000000;
$spacing-md: 16px;
$radius-md: 12px;

// 使用
.button {
  background: $primary-color;
  padding: $spacing-md;
  border-radius: $radius-md;
}
```

### 5.3 响应式单位

- **尺寸**: 使用 `rpx`（750 设计稿基准）或 `px`
- **字体**: 使用 `px`，配合系统动态字体

## 6. Git 提交规范

### 6.1 Commit Message 格式

```
<type>(<scope>): <subject>

<body>
```

### 6.2 Type 类型

| Type | 说明 |
|------|------|
| feat | 新功能 |
| fix | Bug 修复 |
| docs | 文档更新 |
| style | 代码格式（不影响逻辑） |
| refactor | 重构 |
| test | 测试相关 |
| chore | 构建/工具变动 |

### 6.3 示例

```
feat(transaction): 添加交易编辑功能

- 支持修改金额、分类、备注
- 添加删除确认弹窗
```

## 7. 注释规范

### 7.1 文件头注释（可选）

```go
// Package service implements business logic layer.
package service
```

### 7.2 函数注释

```go
// CreateTransaction creates a new transaction and updates account balance.
// It returns the created transaction or an error if validation fails.
func (s *TransactionService) CreateTransaction(req CreateTransactionReq) (*Transaction, error) {
```

### 7.3 TODO/FIXME

```go
// TODO: 添加缓存优化
// FIXME: 修复并发写入问题
```

## 8. 错误处理

### 8.1 后端

```go
// 定义业务错误
var ErrAccountNotFound = errors.New("account not found")

// 返回统一错误响应
if err != nil {
    c.JSON(http.StatusNotFound, response.Error(40401, "账户不存在"))
    return
}
```

### 8.2 前端

```typescript
try {
  const res = await api.createTransaction(data)
  uni.showToast({ title: '保存成功', icon: 'success' })
} catch (e) {
  uni.showToast({ title: e.message || '保存失败', icon: 'none' })
}
```
