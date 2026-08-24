# 数据、安全与运维

## 认证与权限

- 首次初始化后使用密码登录；
- JWT Access/Refresh Token 维护浏览器会话；
- 设备授权页生成 API Token；
- API Token 通过 scope 限制读取账本、修改账本和查看报表等能力；
- 不存在全局万能移动端令牌。

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

当前 JSON 备份格式是 2.3。附件内容使用 Base64 而不是加密；通知设置只迁移安全偏好，
不导出或覆盖 webhook、钉钉、企业微信和 SMTP 凭据。完整兼容语义见
[备份范围合同](../architecture/backup-scope.md)。

## 健康与安全检查

    curl -fsS http://127.0.0.1:8080/api/v1/health
    ./scripts/check-runtime-health-contract.sh
    ./scripts/check-ai-privacy-contract.sh
    ./scripts/check-public-git-safety.sh
