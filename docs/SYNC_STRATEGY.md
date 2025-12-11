# 同步与离线策略

## 1. 架构概述

本项目采用 **本地优先 (Local-First)** 架构：

- 所有数据优先写入本地 SQLite
- 网络可用时自动同步到服务端
- 离线状态下完全可用，联网后自动重试

## 2. 数据流向

```
[用户操作] → [本地 SQLite] → [离线队列] → [API 同步] → [服务端 SQLite]
                  ↓
            [即时 UI 更新]
```

## 3. 离线队列设计

### 3.1 队列存储结构

```typescript
interface OfflineOperation {
  id: string              // 操作唯一ID
  type: 'CREATE' | 'UPDATE' | 'DELETE'
  resource: string        // 资源类型: transactions, accounts, etc.
  resourceId: string      // 资源ID
  payload: object         // 请求数据
  timestamp: number       // 操作时间戳
  retryCount: number      // 重试次数
  status: 'pending' | 'syncing' | 'failed'
}
```

### 3.2 队列管理规则

- **入队时机**: 任何写操作（增删改）立即入队
- **执行顺序**: FIFO（先进先出），保证操作顺序
- **重试策略**: 指数退避，最多重试 5 次
- **失败处理**: 超过重试次数后标记为 `failed`，等待用户手动处理

## 4. 同步触发时机

| 触发条件 | 行为 |
|----------|------|
| App 启动 | 检查队列，有待同步项则开始同步 |
| 网络恢复 | 监听网络状态变化，恢复后立即同步 |
| 用户下拉刷新 | 先同步本地队列，再拉取服务端最新数据 |
| 后台定时 | 每 5 分钟检查一次（App 在前台时） |

## 5. 冲突解决策略

### 5.1 单用户场景（当前版本）

由于本项目为**单用户设计**，冲突场景有限：

- **同一设备**: 不存在冲突
- **多设备**: 采用 **Last-Write-Wins (LWW)** 策略
  - 以 `updated_at` 时间戳为准
  - 后更新的数据覆盖先更新的

### 5.2 冲突检测

```typescript
// 同步前检查
if (local.updated_at > remote.updated_at) {
  // 本地更新更晚，上传本地版本
  pushToServer(local)
} else if (local.updated_at < remote.updated_at) {
  // 服务端更新更晚，拉取服务端版本
  updateLocal(remote)
} else {
  // 时间戳相同，内容一致，无需操作
}
```

## 6. 增量同步

### 6.1 同步标记

- 每个资源表增加 `sync_version` 字段（服务端维护的递增版本号）
- 客户端记录 `last_sync_version`

### 6.2 拉取流程

```
GET /api/v1/sync?since_version={last_sync_version}

Response:
{
  "version": 12345,
  "changes": [
    { "resource": "transactions", "action": "upsert", "data": {...} },
    { "resource": "accounts", "action": "delete", "id": "xxx" }
  ]
}
```

## 7. 网络状态监听

```typescript
// uni-app x 网络监听
uni.onNetworkStatusChange((res) => {
  if (res.isConnected) {
    // 网络恢复，触发同步
    syncOfflineQueue()
  }
})
```

## 8. 用户体验优化

| 场景 | 处理方式 |
|------|----------|
| 离线新增交易 | 立即显示在列表，标记"待同步"图标 |
| 同步中 | 显示同步进度指示器 |
| 同步失败 | Toast 提示，提供重试入口 |
| 冲突覆盖 | 静默处理，不打扰用户（单用户场景冲突少） |

## 9. 数据一致性保障

- **本地事务**: 写操作使用 SQLite 事务，保证原子性
- **幂等键**: 每个离线操作带唯一 ID，服务端去重
- **校验和**: 可选，定期全量校验本地与服务端数据一致性

## 10. 未来扩展

- **多设备实时同步**: WebSocket 推送变更通知
- **选择性同步**: 按时间范围同步（如仅同步最近 3 个月）
- **冲突可视化**: 当检测到冲突时，提供用户手动选择版本
