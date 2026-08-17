# 功能文档

README 只保留产品定位、快速部署和当前发布边界；具体功能按领域拆分：

- [记账与账本](accounting.md)：交易、账户、分类、标签、模板、预算、提醒、借贷、导入导出。
- [家庭与 AI](family-ai.md)：家庭成员、成员统计、成员预算、AI Provider、报告和通知。
- [数据、安全与运维](data-security.md)：认证、API Token、备份恢复、上传、审计、健康检查和指标。
- [客户端与验证](clients.md)：Web、Flutter、平台构建、E2E 和截图证据。

接口统一挂在 /api/v1 下。所有受保护接口支持登录 JWT；设备授权客户端可以使用带 scope 的 API Token。

