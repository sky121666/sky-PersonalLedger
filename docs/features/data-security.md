# 数据、安全与运维

## 认证与权限

- 首次初始化后使用密码登录；
- JWT Access/Refresh Token 维护浏览器会话；
- 设备授权页生成 API Token；
- API Token 通过 scope 限制读取账本、修改账本和查看报表等能力；
- 不存在全局万能移动端令牌。

### 浏览器退出与并发响应

v1.0.10 的浏览器退出使用 HttpOnly Refresh Cookie 验证会话，同时要求同源
`Origin` 和匹配的 CSRF Cookie/Header，因此 Access Token 已过期也能撤销会话。
撤销只影响该刷新会话及其轮转后继，不会删除同一用户另一次独立登录的刷新令牌。
Cookie 缺失、签名无效或会话已撤销时，退出不改动服务端会话，也不发送覆盖其他登录的 Cookie。
刷新失败响应同样不清 Cookie；页面中的会话状态由请求所属代次决定。

刷新 JWT 新增可选 `session_id`，服务端复用 `refresh_tokens.id` 保存稳定会话身份，
数据库仍为 schema 11。旧版无此字段的 JWT 继续有效，首次轮转时使用其已签名的
`jti` 作为会话身份；旧版哈希和更早的明文刷新令牌均保留读取迁移能力。所有撤销
条件同时限定经签名验证的用户 ID，伪造、过期、类型错误的 JWT 不具备撤销能力。
原生客户端 JSON Body 刷新方式不变；其 JWT 鉴权退出继续沿用原有用户级撤销语义。

Web 将初始化、登录、刷新、退出串行执行至响应结束，再允许下一次 Cookie 写入；
这样迟到响应不会在同一页面的新登录之后覆盖 Cookie。支持 Web Locks 的浏览器
还会在同源标签页间协调此顺序；不支持时仅保证当前页面内的顺序。服务端的事务锁
独立保证刷新单次消费及退出后旧会话不能复活，并不承诺未协调客户端任意响应乱序
下的 Cookie 可用性。已签发的 Access JWT 仍有效至其配置的过期时间。

此改动不迁移账目或上传文件。回退兼容 schema 11 的旧版程序不需要回退数据库结构，
但旧版不提供上述响应顺序和定向会话撤销保证；认证异常时需要重新登录。

## 备份与恢复

数据目录包含：

- ledger.db：默认 SQLite 数据库；
- uploads/：用户上传文件；
- backups/：自动备份文件。

系统支持手动 JSON 备份、自动备份设置、备份列表和恢复。恢复会校验跨用户引用、文件路径、凭据字段和数据完整性。

建议升级前执行：

    ./scripts/check-backup-restore-rehearsal.sh
    ./scripts/check-backup-api-rehearsal.sh

## 上传与隐私

上传目录、类型和大小均受配置限制。备份不包含密码哈希、刷新令牌、API Token 和 Provider 密钥等认证材料。

不要把以下内容写入 README、Issue、测试截图或日志：

- LEDGER_JWT_SECRET；
- LEDGER_CREDENTIAL_ENCRYPTION_KEY；
- LEDGER_CREDENTIAL_ENCRYPTION_PREVIOUS_KEY；
- LEDGER_SETUP_TOKEN；
- AI Provider Key；
- SMTP、Webhook、企业微信或钉钉凭据；
- 真实账本、账户和人员信息。

## 安全边界

生产模式默认启用限流，CORS 不允许使用星号。用户可配置的 AI、Webhook、SMTP 出站请求默认禁止访问回环和私网地址。

可选的 /metrics 只暴露受保护的运行指标，默认关闭，启用时需要独立的 32 字符以上 Token。

当前 JSON 备份格式是 2.4，保留软删除及禁用状态。附件内容使用 Base64 而不是加密；通知设置只迁移安全偏好，
不导出或覆盖 webhook、钉钉、企业微信和 SMTP 凭据。完整兼容语义见
[备份范围合同](../architecture/backup-scope.md)。

改密在服务端事务中撤销现有刷新会话，成功响应不写 Cookie，避免迟到响应删除新密码登录的 Cookie。
Web 成功后清除本地 Access Token；原 HttpOnly Cookie 已失效，可能留在浏览器直至下一次登录或到期，不能据此恢复服务器会话。
改密请求继续使用正常过期 Access Token 刷新路径，不在认证队列内嵌套等待刷新。

附件恢复、上传、下载和删除通过进程内维护屏障协调。共享同一上传目录时仅支持一个
可写应用实例；多副本写入需要外部分布式租约，当前不属于支持范围。

## 健康与安全检查

    curl -fsS http://127.0.0.1:8080/api/v1/health
    ./scripts/check-runtime-health-contract.sh
    ./scripts/check-ai-privacy-contract.sh
    ./scripts/check-public-git-safety.sh
