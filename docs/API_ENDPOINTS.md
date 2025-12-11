# API 接口详细定义

Base URL: `/api/v1`

---

## 1. 认证接口

### 1.1 初始化/注册

```
POST /auth/init
```

**请求体**:

```json
{
  "password": "string (6-20位)"
}
```

**响应**:

```json
{
  "code": 0,
  "message": "ok",
  "data": {
    "access_token": "string",
    "refresh_token": "string",
    "expires_in": 900
  }
}
```

### 1.2 登录

```
POST /auth/login
```

**请求体**:

```json
{
  "password": "string"
}
```

**响应**: 同初始化

**错误码**:

- `40101`: 密码错误
- `40301`: 账户已锁定

### 1.3 刷新 Token

```
POST /auth/refresh
```

**请求体**:

```json
{
  "refresh_token": "string"
}
```

### 1.4 登出

```
POST /auth/logout
```

**请求头**: `Authorization: Bearer <access_token>`

---

## 2. 账户接口

### 2.1 账户列表

```
GET /accounts
```

**查询参数**:

| 参数 | 类型 | 说明 |
|------|------|------|
| include_archived | bool | 是否包含归档账户，默认 false |

**响应**:

```json
{
  "code": 0,
  "data": {
    "list": [
      {
        "id": "uuid",
        "name": "招商银行",
        "type": "bank_card",
        "icon": "bank",
        "initial_balance": "10000.00",
        "current_balance": "8500.50",
        "payment_day": null,
        "is_archived": false,
        "sort_order": 1,
        "created_at": "2025-01-01T00:00:00Z"
      }
    ],
    "total_assets": "50000.00",
    "total_liabilities": "5000.00",
    "net_assets": "45000.00"
  }
}
```

### 2.2 创建账户

```
POST /accounts
```

**请求体**:

```json
{
  "name": "string",
  "type": "cash|bank_card|alipay|wechat|credit|loan|receivable|payable",
  "icon": "string",
  "initial_balance": "number",
  "payment_day": "number (1-31)",
  "remark": "string"
}
```

### 2.3 账户详情

```
GET /accounts/:id
```

### 2.4 更新账户

```
PUT /accounts/:id
```

**请求体**:

```json
{
  "name": "string",
  "icon": "string",
  "payment_day": "number",
  "remark": "string"
}
```

### 2.5 删除账户

```
DELETE /accounts/:id
```

### 2.6 归档/取消归档

```
PATCH /accounts/:id/archive
```

**请求体**:

```json
{
  "is_archived": true
}
```

### 2.7 账户排序

```
PUT /accounts/sort
```

**请求体**:

```json
{
  "ids": ["uuid1", "uuid2", "uuid3"]
}
```

---

## 3. 分类接口

### 3.1 分类列表

```
GET /categories
```

**查询参数**:

| 参数 | 类型 | 说明 |
|------|------|------|
| type | string | income / expense |

### 3.2 创建分类

```
POST /categories
```

**请求体**:

```json
{
  "name": "string",
  "type": "income|expense",
  "icon": "string",
  "color": "#RRGGBB"
}
```

### 3.3 更新分类

```
PUT /categories/:id
```

### 3.4 删除分类

```
DELETE /categories/:id
```

### 3.5 分类排序

```
PUT /categories/sort
```

---

## 4. 交易接口

### 4.1 交易列表

```
GET /transactions
```

**查询参数**:

| 参数 | 类型 | 说明 |
|------|------|------|
| page | int | 页码，默认 1 |
| page_size | int | 每页数量，默认 20 |
| start_date | string | 开始日期 YYYY-MM-DD |
| end_date | string | 结束日期 YYYY-MM-DD |
| type | string | income/expense/transfer |
| account_id | string | 账户 ID |
| category_id | string | 分类 ID |
| min_amount | number | 最小金额 |
| max_amount | number | 最大金额 |
| keyword | string | 备注关键词搜索 |

**响应**:

```json
{
  "code": 0,
  "data": {
    "list": [
      {
        "id": "uuid",
        "type": "expense",
        "amount": "50.00",
        "account_id": "uuid",
        "account_name": "微信",
        "category_id": "uuid",
        "category_name": "餐饮",
        "category_icon": "food",
        "category_color": "#FF9500",
        "transaction_date": "2025-12-11",
        "remark": "午餐",
        "tags": ["工作日"],
        "created_at": "2025-12-11T12:00:00Z"
      }
    ],
    "total": 100,
    "page": 1,
    "page_size": 20
  }
}
```

### 4.2 创建交易

```
POST /transactions
```

**请求体**:

```json
{
  "type": "expense|income|transfer",
  "amount": "number",
  "account_id": "uuid",
  "to_account_id": "uuid (转账时必填)",
  "category_id": "uuid",
  "transaction_date": "YYYY-MM-DD",
  "remark": "string",
  "tags": ["string"],
  "images": ["base64 或 url"]
}
```

### 4.3 交易详情

```
GET /transactions/:id
```

### 4.4 更新交易

```
PUT /transactions/:id
```

### 4.5 删除交易

```
DELETE /transactions/:id
```

### 4.6 批量删除

```
POST /transactions/batch-delete
```

**请求体**:

```json
{
  "ids": ["uuid1", "uuid2"]
}
```

---

## 5. 预算接口

### 5.1 预算列表

```
GET /budgets
```

**查询参数**:

| 参数 | 类型 | 说明 |
|------|------|------|
| month | string | YYYY-MM，默认当月 |

**响应**:

```json
{
  "code": 0,
  "data": {
    "total_budget": {
      "id": "uuid",
      "amount": "5000.00",
      "spent": "3500.00",
      "remaining": "1500.00",
      "percentage": 70,
      "alert_threshold": 80
    },
    "category_budgets": [
      {
        "id": "uuid",
        "category_id": "uuid",
        "category_name": "餐饮",
        "amount": "1000.00",
        "spent": "800.00",
        "remaining": "200.00",
        "percentage": 80
      }
    ]
  }
}
```

### 5.2 设置总预算

```
POST /budgets/total
```

**请求体**:

```json
{
  "amount": "number",
  "alert_threshold": "number (0-100)"
}
```

### 5.3 设置分类预算

```
POST /budgets/category
```

**请求体**:

```json
{
  "category_id": "uuid",
  "amount": "number",
  "alert_threshold": "number"
}
```

### 5.4 删除预算

```
DELETE /budgets/:id
```

---

## 6. 提醒接口

### 6.1 提醒列表

```
GET /reminders
```

### 6.2 创建提醒

```
POST /reminders
```

**请求体**:

```json
{
  "account_id": "uuid",
  "payment_day": "number (1-31)",
  "advance_days": "number",
  "amount": "number (可选)",
  "remark": "string"
}
```

### 6.3 更新提醒

```
PUT /reminders/:id
```

### 6.4 删除提醒

```
DELETE /reminders/:id
```

### 6.5 启用/禁用提醒

```
PATCH /reminders/:id/toggle
```

---

## 7. 统计接口

### 7.1 月度概览

```
GET /statistics/overview
```

**查询参数**:

| 参数 | 类型 | 说明 |
|------|------|------|
| month | string | YYYY-MM |

**响应**:

```json
{
  "code": 0,
  "data": {
    "income": "10000.00",
    "expense": "8000.00",
    "balance": "2000.00",
    "income_change": 5.2,
    "expense_change": -3.1,
    "daily_average": "266.67",
    "transaction_count": 45
  }
}
```

### 7.2 分类统计

```
GET /statistics/categories
```

**查询参数**:

| 参数 | 类型 | 说明 |
|------|------|------|
| month | string | YYYY-MM |
| type | string | income / expense |

**响应**:

```json
{
  "code": 0,
  "data": {
    "total": "8000.00",
    "items": [
      {
        "category_id": "uuid",
        "category_name": "餐饮",
        "icon": "food",
        "color": "#FF9500",
        "amount": "2000.00",
        "percentage": 25,
        "count": 30
      }
    ]
  }
}
```

### 7.3 趋势统计

```
GET /statistics/trends
```

**查询参数**:

| 参数 | 类型 | 说明 |
|------|------|------|
| start_date | string | YYYY-MM-DD |
| end_date | string | YYYY-MM-DD |
| group_by | string | day / week / month |

---

## 8. 导入接口

### 8.1 解析账单

```
POST /import/parse
```

**请求体**: `multipart/form-data`

| 字段 | 类型 | 说明 |
|------|------|------|
| file | file | CSV 文件 |
| source | string | wechat / alipay / bank |

**响应**:

```json
{
  "code": 0,
  "data": {
    "preview": [
      {
        "date": "2025-12-11",
        "type": "expense",
        "amount": "50.00",
        "counterparty": "美团外卖",
        "remark": "午餐",
        "suggested_category": "餐饮"
      }
    ],
    "total_count": 100,
    "preview_count": 10
  }
}
```

### 8.2 执行导入

```
POST /import/execute
```

**请求体**:

```json
{
  "source": "wechat",
  "account_id": "uuid",
  "category_mappings": {
    "美团外卖": "category_uuid",
    "滴滴出行": "category_uuid"
  },
  "file_id": "string (解析时返回)"
}
```

---

## 9. 数据管理接口

### 9.1 导出数据

```
GET /data/export
```

**查询参数**:

| 参数 | 类型 | 说明 |
|------|------|------|
| format | string | csv / json |
| start_date | string | YYYY-MM-DD |
| end_date | string | YYYY-MM-DD |

### 9.2 备份数据库

```
GET /data/backup
```

**响应**: 返回 SQLite 数据库文件

### 9.3 恢复数据

```
POST /data/restore
```

**请求体**: `multipart/form-data` (数据库文件)

---

## 10. 快捷模板接口

### 10.1 模板列表

```
GET /templates
```

### 10.2 创建模板

```
POST /templates
```

**请求体**:

```json
{
  "name": "string",
  "amount": "number",
  "type": "expense|income",
  "account_id": "uuid",
  "category_id": "uuid",
  "remark": "string"
}
```

### 10.3 使用模板记账

```
POST /templates/:id/apply
```

**请求体**:

```json
{
  "transaction_date": "YYYY-MM-DD",
  "amount": "number (可覆盖)"
}
```

### 10.4 删除模板

```
DELETE /templates/:id
```
