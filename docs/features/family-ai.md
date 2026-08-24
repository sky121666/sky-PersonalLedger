# 家庭与 AI

## 家庭账本

项目采用单个拥有者范围内的家庭维度，不是 SaaS 多租户。

家庭功能包括：

- 家庭成员新增、编辑、停用和删除；
- 交易归属成员和付款成员；
- 家庭支出汇总；
- 成员支出统计和排行；
- 成员预算基础。

主要 API：

- /family/members
- /family/summary
- /family/statistics

## AI Provider

AI 是可选功能，使用 OpenAI-compatible 接口模型。支持预设 Provider 和自定义网关配置，可测试连通性，也可配置报告计划任务。

报告流程：

1. 选择 Provider 和报告周期；
2. 生成周报或月报；
3. 保存聚合快照；
4. 在 Web 或移动端查看、展开和删除报告。

默认快照不包含原始交易备注。新保存的 Provider 凭据按当前安全路径保护，正常备份不会导出 Provider 密钥。升级时启动迁移会处理受支持的历史凭据；只为迁移而重新保存 Provider 不是必需步骤，升级后应实际测试凭据读取与报告生成。

主要 API：

- /ai/providers
- /ai/reports
- /ai/schedule/settings
- /ai/schedule/trigger

## 通知

通知配置支持企业微信、钉钉、SMTP 和 Webhook 通道。每个通道都有单独的测试入口；网络出站默认不允许访问容器私网。
