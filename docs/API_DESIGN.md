# API 设计规范

## 1. 基础约定

- **协议**: HTTPS + JSON
- **Base URL**: `/api/v1`
- **编码**: UTF-8
- **时间**: ISO8601 字符串，统一使用 UTC（示例：`2025-12-11T01:00:00Z`）
- **数值精度**: 金额使用字符串或小数点两位的 number，避免前端浮点误差

## 2. 认证与会话

- **认证**: Bearer Token (Access Token)，置于 `Authorization: Bearer <token>`
- **刷新**: Refresh Token 仅在登录/刷新接口返回，存储于安全存储
- **过期策略**: Access 15 分钟，Refresh 30 天
- **退出登录**: 后端废弃 Refresh Token 记录，前端清理本地 Token

## 3. 请求/响应封装

- **请求头**: `Content-Type: application/json`
- **响应包裹**:

```json
{
  "code": 0,
  "message": "ok",
  "data": {}
}
```

- **错误码示例**:
  - `0`: 成功
  - `40101`: 未认证/Token 无效
  - `40102`: Token 过期，需要刷新
  - `40301`: 禁止访问
  - `40401`: 资源不存在
  - `50001`: 服务器内部错误

## 4. 资源命名与方法

- **命名**: 复数资源名，如 `/accounts`, `/transactions`
- **HTTP 动词**:
  - GET /resource: 列表/查询
  - POST /resource: 创建
  - GET /resource/{id}: 详情
  - PUT /resource/{id}: 全量更新
  - PATCH /resource/{id}: 部分更新（如状态）
  - DELETE /resource/{id}: 删除或软删

## 5. 分页与过滤

- **分页参数**: `page`（默认1），`page_size`（默认20，最大100）
- **排序**: `sort_by`, `order`（asc|desc），默认按创建时间倒序
- **过滤**: 统一使用查询字符串，如 `?type=expense&month=2025-12`

## 6. 幂等与重试

- **幂等键**: 对关键写操作（导入、转账）可选 header `Idempotency-Key`
- **重试**: 网络失败由前端重试，写操作应配合幂等键避免重复写入

## 7. 常用资源字段约定

- **金额**: `amount` (number|string, 两位小数)
- **日期**: `transaction_date` (ISO8601)
- **软删除**: 后端保留软删，前端列表默认过滤删除状态

## 8. 安全与限流

- **限流**: 登录/刷新接口应有限流与验证码保护（防暴力破解）
- **CORS**: 允许受信任来源；默认关闭 `*`
- **文件上传**: 严格 MIME 校验与大小限制

## 9. 版本管理

- URL 前缀带版本：`/api/v1`
- 变更需在 Release Note 说明兼容性与迁移指引
