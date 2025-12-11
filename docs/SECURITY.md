# 安全设计规范

## 1. 认证安全

### 1.1 密码存储

- **算法**: bcrypt（cost factor >= 12）
- **禁止**: 明文存储、MD5、SHA1 等弱哈希
- **示例**:

```go
import "golang.org/x/crypto/bcrypt"

hash, _ := bcrypt.GenerateFromPassword([]byte(password), 12)
err := bcrypt.CompareHashAndPassword(hash, []byte(password))
```

### 1.2 登录保护

| 机制 | 实现 |
|------|------|
| 登录失败锁定 | 连续 5 次失败后锁定 15 分钟 |
| 登录日志 | 记录 IP、时间、User-Agent |
| 验证码 | 连续 3 次失败后要求验证码（可选） |

### 1.3 JWT 安全

- **签名算法**: HS256 或 RS256
- **密钥长度**: 至少 256 位随机字符串
- **载荷限制**: 不存储敏感信息（仅 user_id、exp）
- **过期策略**:
  - Access Token: 15 分钟
  - Refresh Token: 30 天
- **刷新机制**: Refresh Token 单次有效，刷新后作废旧 Token

## 2. 传输安全

### 2.1 HTTPS 强制

- 生产环境强制 HTTPS
- HSTS 头: `Strict-Transport-Security: max-age=31536000; includeSubDomains`
- 禁止 HTTP 降级

### 2.2 请求头安全

```go
// 安全响应头
c.Header("X-Content-Type-Options", "nosniff")
c.Header("X-Frame-Options", "DENY")
c.Header("X-XSS-Protection", "1; mode=block")
c.Header("Content-Security-Policy", "default-src 'self'")
```

### 2.3 CORS 配置

```go
// 仅允许受信任来源
cors.Config{
    AllowOrigins:     []string{"https://your-domain.com"},
    AllowMethods:     []string{"GET", "POST", "PUT", "DELETE"},
    AllowHeaders:     []string{"Authorization", "Content-Type"},
    AllowCredentials: true,
}
```

## 3. 数据存储安全

### 3.1 本地存储

| 数据类型 | 存储方式 | 加密 |
|----------|----------|------|
| Access Token | 内存 / SecureStorage | 是 |
| Refresh Token | SecureStorage (Keychain/Keystore) | 是 |
| 用户设置 | uni.setStorageSync | 否 |
| SQLite 数据库 | 沙盒目录 | 可选 (SQLCipher) |

### 3.2 敏感数据处理

- **密码**: 仅在登录时传输，前端不持久化
- **Token**: 使用平台安全存储 API
- **金额**: 可在 UI 层提供隐藏/显示切换

### 3.3 数据库加密（可选）

```go
// 使用 SQLCipher 加密 SQLite
db, err := sql.Open("sqlite3", "file:data.db?_cipher=sqlcipher&_key=secret")
```

## 4. 输入验证

### 4.1 后端校验

```go
type CreateTransactionReq struct {
    Amount    float64 `json:"amount" binding:"required,gt=0"`
    Type      string  `json:"type" binding:"required,oneof=income expense transfer"`
    AccountID string  `json:"account_id" binding:"required,uuid"`
    Date      string  `json:"date" binding:"required,datetime=2006-01-02"`
}
```

### 4.2 防注入

- **SQL 注入**: 使用 ORM 参数化查询，禁止拼接 SQL
- **XSS**: 输出编码，前端使用 `{{ }}` 自动转义
- **路径遍历**: 文件操作使用白名单路径

### 4.3 文件上传

```go
// 限制文件类型和大小
allowedTypes := []string{"image/jpeg", "image/png"}
maxSize := 5 * 1024 * 1024 // 5MB

// 验证 MIME 类型（不信任扩展名）
fileHeader, _ := file.Open()
buffer := make([]byte, 512)
fileHeader.Read(buffer)
contentType := http.DetectContentType(buffer)
```

## 5. 接口安全

### 5.1 限流 (Rate Limiting)

| 接口类型 | 限制 |
|----------|------|
| 登录 | 5 次/分钟/IP |
| 注册/初始化 | 3 次/小时/IP |
| 普通 API | 100 次/分钟/用户 |
| 文件上传 | 10 次/分钟/用户 |

### 5.2 幂等性

- 关键写操作支持 `Idempotency-Key` 头
- 服务端缓存 Key 24 小时，重复请求返回缓存结果

### 5.3 权限校验

```go
// 确保用户只能访问自己的数据
func (s *TransactionService) GetByID(userID uint, txID string) (*Transaction, error) {
    tx, err := s.repo.FindByID(txID)
    if err != nil {
        return nil, err
    }
    if tx.UserID != userID {
        return nil, ErrForbidden
    }
    return tx, nil
}
```

## 6. 日志与审计

### 6.1 日志内容

| 记录 | 不记录 |
|------|--------|
| 请求 IP、时间 | 密码明文 |
| 用户 ID | 完整 Token |
| 操作类型 | 敏感个人信息 |
| 错误信息 | 信用卡号 |

### 6.2 日志格式

```json
{
  "time": "2025-12-11T10:00:00Z",
  "level": "info",
  "user_id": 1,
  "action": "create_transaction",
  "ip": "192.168.1.1",
  "status": 200
}
```

## 7. 依赖安全

- 定期更新依赖包
- 使用 `go mod tidy` / `npm audit` 检查漏洞
- CI/CD 集成安全扫描（如 Snyk, Dependabot）

## 8. 密钥管理

| 环境 | 管理方式 |
|------|----------|
| 开发 | `.env.local`（gitignore） |
| 生产 | 环境变量 / Secret Manager |

**禁止**:

- 密钥硬编码在代码中
- 密钥提交到版本控制
- 多环境共用同一密钥

## 9. 安全检查清单

- [ ] 密码使用 bcrypt 存储
- [ ] JWT 密钥足够复杂且安全存储
- [ ] HTTPS 强制开启
- [ ] 输入校验完整
- [ ] SQL 使用参数化查询
- [ ] 文件上传有类型和大小限制
- [ ] 限流机制已配置
- [ ] 敏感日志已脱敏
- [ ] 依赖无已知漏洞
