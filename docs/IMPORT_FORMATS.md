# 账单导入格式规范

## 1. 概述

本文档定义了支持导入的第三方账单格式，以及系统如何解析和映射这些数据。

---

## 2. 微信账单

### 2.1 获取方式

微信 > 我 > 服务 > 钱包 > 账单 > 常见问题 > 下载账单 > 用于个人对账

### 2.2 文件格式

- **编码**: UTF-8 with BOM
- **格式**: CSV
- **文件名**: `微信支付账单(YYYYMMDD-YYYYMMDD).csv`

### 2.3 表头结构

```csv
交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
```

### 2.4 字段映射

| 微信字段 | 系统字段 | 说明 |
|----------|----------|------|
| 交易时间 | transaction_date | 格式: YYYY-MM-DD HH:mm:ss |
| 收/支 | type | 支出→expense, 收入→income, 其他→忽略 |
| 金额(元) | amount | 去掉 ¥ 符号，转数字 |
| 交易对方 | counterparty | 用于分类推断 |
| 商品 | remark | 交易备注 |
| 当前状态 | - | 仅导入"支付成功"/"已收钱"的记录 |
| 支付方式 | - | 可用于账户匹配 |

### 2.5 解析规则

```typescript
function parseWechatBill(row: string[]): Transaction | null {
  const status = row[7]
  // 仅处理成功的交易
  if (!['支付成功', '已收钱', '已存入'].includes(status)) {
    return null
  }
  
  const direction = row[4] // 收/支
  let type: TransactionType
  if (direction === '支出') {
    type = 'expense'
  } else if (direction === '收入') {
    type = 'income'
  } else {
    return null // 忽略 "不计收支" 等
  }
  
  return {
    transaction_date: parseDate(row[0]),
    type,
    amount: parseAmount(row[5]), // 去掉 ¥ 和逗号
    counterparty: row[2],
    remark: row[3],
    source: 'import_wechat'
  }
}
```

---

## 3. 支付宝账单

### 3.1 获取方式

支付宝 > 我的 > 账单 > 右上角 ··· > 开具交易流水证明 > 用于个人对账

### 3.2 文件格式

- **编码**: GBK (注意转换)
- **格式**: CSV
- **文件名**: `alipay_record_YYYYMMDD_XXXXXXXX.csv`

### 3.3 表头结构

```csv
交易创建时间,付款时间,最近修改时间,交易来源地,类型,交易对方,商品名称,金额（元）,收/支,交易状态,服务费（元）,成功退款（元）,备注,资金状态
```

### 3.4 字段映射

| 支付宝字段 | 系统字段 | 说明 |
|------------|----------|------|
| 付款时间 | transaction_date | 格式: YYYY-MM-DD HH:mm:ss |
| 收/支 | type | 支出→expense, 收入→income |
| 金额（元） | amount | 转数字 |
| 交易对方 | counterparty | 用于分类推断 |
| 商品名称 | remark | 交易备注 |
| 交易状态 | - | 仅导入"交易成功"的记录 |

### 3.5 解析规则

```typescript
function parseAlipayBill(row: string[]): Transaction | null {
  const status = row[9].trim()
  if (status !== '交易成功') {
    return null
  }
  
  const direction = row[8].trim()
  let type: TransactionType
  if (direction === '支出') {
    type = 'expense'
  } else if (direction === '收入') {
    type = 'income'
  } else {
    return null
  }
  
  return {
    transaction_date: parseDate(row[1]),
    type,
    amount: parseAmount(row[7]),
    counterparty: row[5].trim(),
    remark: row[6].trim(),
    source: 'import_alipay'
  }
}
```

---

## 4. 银行账单

### 4.1 通用格式

由于各银行格式差异较大，采用通用模板匹配：

```csv
交易日期,交易金额,余额,交易类型,对方账户,摘要
```

### 4.2 支持的银行

| 银行 | 字段顺序 | 日期格式 | 金额格式 |
|------|----------|----------|----------|
| 招商银行 | 日期,摘要,金额,余额 | YYYYMMDD | 支出为负 |
| 工商银行 | 交易日期,交易金额,账户余额,对方户名,摘要 | YYYY-MM-DD | 支出为负 |
| 建设银行 | 交易时间,收入,支出,余额,摘要 | YYYY/MM/DD | 分列显示 |

### 4.3 金额处理

```typescript
function parseAmount(value: string): { amount: number; type: TransactionType } {
  const num = parseFloat(value.replace(/[,，]/g, ''))
  
  if (num < 0) {
    return { amount: Math.abs(num), type: 'expense' }
  } else {
    return { amount: num, type: 'income' }
  }
}
```

---

## 5. 分类自动映射

### 5.1 映射规则表

系统内置常见商户到分类的映射规则：

| 关键词匹配 | 分类 |
|------------|------|
| 美团、饿了么、肯德基、麦当劳、星巴克 | 餐饮 |
| 滴滴、高德、嘀嗒、出租车、地铁、公交 | 交通 |
| 淘宝、京东、拼多多、天猫 | 购物 |
| 电影、游戏、网易云、QQ音乐、B站 | 娱乐 |
| 中国移动、中国联通、中国电信 | 通讯 |
| 医院、药店、挂号 | 医疗 |
| 房租、水费、电费、燃气、物业 | 居住 |
| 工资、薪资 | 工资 |
| 转账、红包 | 需用户确认 |

### 5.2 自定义规则

用户可添加自定义映射规则：

```json
{
  "rules": [
    {
      "keyword": "盒马",
      "category_id": "uuid",
      "match_type": "contains"
    },
    {
      "keyword": "^交通银行",
      "category_id": "uuid",
      "match_type": "regex"
    }
  ]
}
```

---

## 6. 去重策略

### 6.1 唯一性判断

导入时根据以下字段组合判断是否已存在：

- transaction_date (精确到日)
- amount
- counterparty
- remark

### 6.2 处理方式

| 场景 | 处理 |
|------|------|
| 完全匹配 | 跳过，标记为"已存在" |
| 部分匹配 | 提示用户确认 |
| 无匹配 | 正常导入 |

---

## 7. 导入结果

### 7.1 结果统计

```json
{
  "total": 100,
  "imported": 85,
  "skipped": 10,
  "failed": 5,
  "details": {
    "skipped_reasons": {
      "duplicate": 8,
      "invalid_status": 2
    },
    "failed_records": [
      {
        "row": 15,
        "reason": "金额格式错误",
        "data": "..."
      }
    ]
  }
}
```

### 7.2 导入日志

每次导入记录到 `import_logs` 表：

- 导入时间
- 来源类型
- 文件名
- 导入数量
- 目标账户
