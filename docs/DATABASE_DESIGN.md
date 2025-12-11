# 数据库设计规范

## 1. 存储引擎

- **数据库**: SQLite 3
- **文件位置**: `data/ledger.db`（后端）/ App 沙盒目录（移动端）
- **编码**: UTF-8
- **WAL 模式**: 启用 (Write-Ahead Logging)，提升并发读写性能

## 2. 命名规范

- **表名**: 小写复数，下划线分隔（如 `accounts`, `transactions`, `category_rules`）
- **字段名**: 小写，下划线分隔（如 `created_at`, `account_id`）
- **主键**: 使用 UUID 字符串（36位），字段名 `id`
- **外键**: `<关联表单数>_id`（如 `account_id`, `category_id`）
- **时间戳**: `created_at`, `updated_at`, `deleted_at`（软删除）

## 3. 核心表结构

### 3.1 users (用户表)

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | INTEGER | PK, AUTO | 用户ID |
| username | VARCHAR(50) | UNIQUE, NOT NULL | 用户名 |
| password_hash | VARCHAR(255) | NOT NULL | 密码哈希 |
| created_at | DATETIME | NOT NULL | 创建时间 |
| updated_at | DATETIME | NOT NULL | 更新时间 |
| last_login_at | DATETIME | NULL | 最后登录 |
| login_fail_count | INTEGER | DEFAULT 0 | 登录失败次数 |
| locked_until | DATETIME | NULL | 锁定截止时间 |
| deleted_at | DATETIME | NULL | 软删除时间 |

### 3.2 accounts (账户表)

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | VARCHAR(36) | PK | UUID |
| user_id | INTEGER | FK, NOT NULL | 用户ID |
| name | VARCHAR(100) | NOT NULL | 账户名称 |
| type | VARCHAR(20) | NOT NULL | 类型枚举 |
| icon | VARCHAR(50) | NULL | 图标标识 |
| initial_balance | DECIMAL(15,2) | DEFAULT 0 | 初始余额 |
| current_balance | DECIMAL(15,2) | DEFAULT 0 | 当前余额 |
| payment_day | INTEGER | NULL | 还款日(1-31) |
| remark | TEXT | NULL | 备注 |
| is_archived | BOOLEAN | DEFAULT FALSE | 是否归档 |
| sort_order | INTEGER | DEFAULT 0 | 排序权重 |
| created_at | DATETIME | NOT NULL | 创建时间 |
| updated_at | DATETIME | NOT NULL | 更新时间 |
| deleted_at | DATETIME | NULL | 软删除时间 |

**账户类型枚举 (type)**:

- `cash`: 现金
- `bank_card`: 银行卡
- `alipay`: 支付宝
- `wechat`: 微信
- `credit`: 信用卡
- `loan`: 贷款
- `receivable`: 应收款
- `payable`: 应付款

### 3.3 categories (分类表)

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | VARCHAR(36) | PK | UUID |
| user_id | INTEGER | FK, NOT NULL | 用户ID |
| name | VARCHAR(100) | NOT NULL | 分类名称 |
| type | VARCHAR(20) | NOT NULL | income/expense |
| icon | VARCHAR(50) | NULL | 图标 |
| color | VARCHAR(20) | NULL | 颜色 #RRGGBB |
| is_system | BOOLEAN | DEFAULT FALSE | 系统预设 |
| sort_order | INTEGER | DEFAULT 0 | 排序 |
| created_at | DATETIME | NOT NULL | 创建时间 |
| updated_at | DATETIME | NOT NULL | 更新时间 |
| deleted_at | DATETIME | NULL | 软删除时间 |

### 3.4 transactions (交易表)

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | VARCHAR(36) | PK | UUID |
| user_id | INTEGER | FK, NOT NULL | 用户ID |
| account_id | VARCHAR(36) | FK, NOT NULL | 账户ID |
| category_id | VARCHAR(36) | FK, NULL | 分类ID |
| type | VARCHAR(20) | NOT NULL | income/expense/transfer |
| amount | DECIMAL(15,2) | NOT NULL | 金额(正数) |
| transaction_date | DATETIME | NOT NULL | 交易日期 |
| remark | TEXT | NULL | 备注 |
| tags | TEXT | NULL | 标签 JSON 数组 |
| images | TEXT | NULL | 图片路径 JSON 数组 |
| to_account_id | VARCHAR(36) | FK, NULL | 转账目标账户 |
| source | VARCHAR(50) | DEFAULT 'manual' | 来源 |
| created_at | DATETIME | NOT NULL | 创建时间 |
| updated_at | DATETIME | NOT NULL | 更新时间 |
| deleted_at | DATETIME | NULL | 软删除时间 |

**交易来源枚举 (source)**:

- `manual`: 手动录入
- `import_wechat`: 微信账单导入
- `import_alipay`: 支付宝账单导入
- `import_bank`: 银行账单导入

### 3.5 budgets (预算表)

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | VARCHAR(36) | PK | UUID |
| user_id | INTEGER | FK, NOT NULL | 用户ID |
| category_id | VARCHAR(36) | FK, NULL | 分类ID (NULL=总预算) |
| amount | DECIMAL(15,2) | NOT NULL | 预算金额 |
| period | VARCHAR(20) | DEFAULT 'monthly' | 周期 |
| alert_threshold | INTEGER | DEFAULT 80 | 预警阈值(%) |
| is_active | BOOLEAN | DEFAULT TRUE | 是否启用 |
| created_at | DATETIME | NOT NULL | 创建时间 |
| updated_at | DATETIME | NOT NULL | 更新时间 |
| deleted_at | DATETIME | NULL | 软删除时间 |

### 3.6 reminders (还款提醒表)

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | VARCHAR(36) | PK | UUID |
| user_id | INTEGER | FK, NOT NULL | 用户ID |
| account_id | VARCHAR(36) | FK, NOT NULL | 关联账户 |
| payment_day | INTEGER | NOT NULL | 还款日(1-31) |
| advance_days | INTEGER | DEFAULT 3 | 提前提醒天数 |
| amount | DECIMAL(15,2) | NULL | 还款金额 |
| remark | TEXT | NULL | 备注 |
| is_enabled | BOOLEAN | DEFAULT TRUE | 是否启用 |
| last_notified_at | DATETIME | NULL | 上次通知时间 |
| created_at | DATETIME | NOT NULL | 创建时间 |
| updated_at | DATETIME | NOT NULL | 更新时间 |
| deleted_at | DATETIME | NULL | 软删除时间 |

### 3.7 refresh_tokens (刷新令牌表)

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | VARCHAR(36) | PK | UUID |
| user_id | INTEGER | FK, NOT NULL | 用户ID |
| token | VARCHAR(255) | UNIQUE, NOT NULL | Token 哈希 |
| expires_at | DATETIME | NOT NULL | 过期时间 |
| created_at | DATETIME | NOT NULL | 创建时间 |

## 4. 索引策略

```sql
-- 交易查询优化
CREATE INDEX idx_transactions_user_date ON transactions(user_id, transaction_date);
CREATE INDEX idx_transactions_user_type ON transactions(user_id, type);
CREATE INDEX idx_transactions_account ON transactions(account_id);
CREATE INDEX idx_transactions_category ON transactions(category_id);

-- 账户查询
CREATE INDEX idx_accounts_user ON accounts(user_id);

-- 软删除过滤
CREATE INDEX idx_transactions_deleted ON transactions(deleted_at);
CREATE INDEX idx_accounts_deleted ON accounts(deleted_at);
```

## 5. 金额精度处理

- **存储**: DECIMAL(15,2)，最大支持万亿级，精确到分
- **计算**: 后端使用 decimal 库，避免浮点误差
- **传输**: API 返回字符串或保留两位小数的数字
- **前端显示**: 千分位格式化，负数用红色

## 6. 时间处理

- **存储**: UTC 时间，ISO8601 格式字符串或 Unix 时间戳
- **显示**: 前端根据用户时区转换显示
- **查询**: 按月统计时使用 UTC 月份边界

## 7. 数据迁移策略

- **版本号**: 在数据库中维护 `schema_version` 表
- **升级脚本**: 每个版本对应一个迁移脚本
- **回滚**: 保留回滚 SQL（仅限开发环境）
- **备份**: App 更新前自动备份旧数据库文件
