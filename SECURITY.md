# 安全功能说明

## 1. 登录限流（防暴力破解）

系统已实现双重登录限流机制，防止暴力破解攻击。

### IP 限流
- **规则**：同一 IP 地址在 5 分钟内最多尝试登录 5 次
- **触发后**：该 IP 被锁定 30 分钟
- **响应码**：429 Too Many Requests

### 账号锁定
- **规则**：同一账号连续失败 5 次
- **触发后**：该账号被锁定 30 分钟
- **响应码**：429 Too Many Requests

### 错误响应示例
```json
{
  "code": 42901,
  "message": "Too many login attempts. Please try again later.",
  "locked_until": "2024-12-15T15:30:00Z",
  "retry_after": 1800
}
```

## 2. 安全入口路径

通过隐藏的 URL 路径保护应用，防止未授权访问。

### 配置方式

#### 方式 1：配置文件
```yaml
# config.yaml
security:
  base_path: "/abc123xyz"
```

#### 方式 2：环境变量（推荐用于 Docker）
```bash
LEDGER_SECURITY_BASE_PATH=/abc123xyz
```

### 访问方式
启用后，所有 URL 都需要加上安全路径前缀：

- 登录页：`https://your-domain.com/abc123xyz/`
- API：`https://your-domain.com/abc123xyz/api/v1/...`

### 移动端配置
Android App 需要在服务器配置中填写安全入口路径：

```
服务器地址：https://your-domain.com
安全入口路径：/abc123xyz
```

## 3. JWT 认证

系统使用 JWT (JSON Web Token) 进行身份验证。

### Token 类型
- **Access Token**：有效期 15 分钟，用于 API 请求
- **Refresh Token**：有效期 30 天，用于刷新 Access Token

### 使用方式
```bash
# API 请求头
Authorization: Bearer {access_token}
```

### Token 刷新
```bash
POST /api/v1/auth/refresh
{
  "refresh_token": "your_refresh_token"
}
```

## 4. 环境变量配置

支持通过环境变量配置所有敏感信息，避免硬编码。

### 重要配置项

```bash
# JWT 密钥（必须修改！）
LEDGER_JWT_SECRET=your-super-secret-key

# 安全入口路径（可选）
LEDGER_SECURITY_BASE_PATH=/your-random-path

# 服务器模式（生产环境使用 release）
LEDGER_SERVER_MODE=release
```

## 5. Docker 部署安全建议

### 1. 使用环境变量文件
```bash
# 创建 .env 文件（不要提交到 Git）
cp .env.example .env
# 修改敏感配置
nano .env
```

### 2. 启动容器
```bash
docker-compose up -d
```

### 3. 定期备份
```bash
# 备份数据目录
tar -czf backup-$(date +%Y%m%d).tar.gz ./data
```

## 6. 安全最佳实践

### ✅ 推荐做法
1. **修改默认 JWT Secret**：使用强随机密钥
2. **启用安全入口**：设置难以猜测的路径
3. **使用 HTTPS**：配置 SSL 证书
4. **定期备份**：启用自动备份功能
5. **限制访问**：使用防火墙限制 IP 访问
6. **监控日志**：定期检查登录失败记录

### ❌ 避免做法
1. 不要使用弱密码
2. 不要在公网暴露 HTTP 端口
3. 不要禁用登录限流
4. 不要泄露安全入口路径
5. 不要使用默认的 JWT Secret

## 7. 移动端安全

### Android App 配置
```
服务器地址：https://your-domain.com
安全入口路径：/abc123xyz （如果启用）
用户名：admin
密码：******
```

### 数据存储
- 服务器配置和 Token 使用 Android DataStore 加密存储
- 不会明文保存密码

## 8. 应急响应

### 如果发现异常登录
1. 立即修改密码
2. 检查登录日志
3. 更换安全入口路径
4. 重新生成 JWT Secret

### 如果忘记安全入口路径
1. 停止服务
2. 修改配置文件或环境变量
3. 重启服务

## 9. 联系方式

如发现安全漏洞，请通过以下方式报告：
- GitHub Issues（标记为 Security）
- 或直接联系开发者

---


