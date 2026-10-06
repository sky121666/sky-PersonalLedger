# Ledger Reliability and Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 修复评审确认的账本可靠性缺陷，验证并发布 v1.0.10 Docker/Web。

**Architecture:** 保留现有单体 API 和双客户端。备份建立独立格式契约，异步操作绑定身份/代次，设置更新区分用户配置与运行记录；交付证据绑定不可变源码和产物。

**Tech Stack:** Go 1.26.6、Gin/GORM、Vue 3/Tailwind 3、Node 24、pnpm 10.32.1、Flutter 3.35.7/Dart 3.9.2。

**Spec:** `docs/superpowers/specs/2026-10-06-ledger-reliability-design.md`

## Global Constraints

- 工作树 `codex/ledger-reliability-release-v1.0.10`，原 84 个修复路径均保留。
- 支持 SQLite/PostgreSQL/MySQL，单可写实例，不引入离线同步、多租户或分布式系统。
- 编辑、测试、提交、PR/合并及既有 GitHub/GHCR 发布已获用户授权；保留平台保护。
- 保留旧备份读取语义，新增格式不能让有效数据因未知新增规则丢失。
- 真实账本、密钥、用户容器、不可变已发布版本不参与破坏性操作。

## Review Focus

- 软删除引用、已清偿借贷及用户已归档对象，在备份往返后仍保持原状态。
- A/B 表单切换、退出再登录、迟到成功/失败均不得跨越操作身份。
- 用户关闭自动化与正在执行任务完成交错，关闭状态优先。
- 核心写入已提交但辅助刷新失败时，保存结果真实，不重复写入。
- 干净 CI 检出、旧备份、升级/回滚和历史发布证据在各自兼容边界内可验收。

## Task 1: Backup roundtrip and envelope safety

**Files:** `backend/internal/service/backup.go`, `backup_json.go`, new `backup_codec.go`, corresponding tests, `docs/architecture/backup-scope.md`.

**Interfaces:** 保留 `FullBackupData` 服务调用；序列化/解码走独立备份字段契约。新增 2.4 保留 deleted_at，不更改业务 API 的秘密字段排除。

- [ ] 写 `TestBackupRoundTripPreservesDeletedTransactions`：活动交易 0、余额100、支出0，往返后相同；关联删除对象状态保留。
- [ ] 写 partial envelope 拒绝且当前账户不变的测试；加入真实旧格式兼容与显式空集合测试。
- [ ] 运行定向测试确认旧代码失败，再实现 DTO/codec 与版本必需字段校验。
- [ ] 跑备份包相关普通/race、现有恢复与安全测试，更新兼容说明，独立复核。
- [ ] 协调者选择性提交。

## Task 2: Web editing, session and loading state

**Files:** `web/src/components/TransactionDialog.vue`, `stores/auth.ts`, `utils/request.ts`, `views/HomeView.vue`, `StatisticsView.vue`, unit/E2E tests.

**Interfaces:** `member_id`、`paid_by_member_id` 独立；编辑目标固定；认证 store 暴露会话代次供重放检验；数据保留成功查询身份。

- [ ] 写旧响应A不能保存到B、只改备注保留付款人B的受控响应回归，看到旧实现失败。
- [ ] 写退出后refresh成功与新登录后旧refresh失败不跨会话的回归。
- [ ] 写首页可选AI失败不隐藏资产/不误报刷新成功，换月失败不冒充新月数据的回归。
- [ ] 实现根因修复，验证既有60单测与真实后端E2E、390/1280/1536视口。
- [ ] 独立复核并由协调者提交。

## Task 3: Flutter member, restore and export closure

**Files:** `mobile/lib/features/transactions/presentation/quick_transaction_page.dart`, `application/ledger_refresh.dart`, data_management repository/page, templates page, tests.

**Interfaces:** 两成员字段独立；恢复以新的账本数据代次重建业务仓库/缓存；导出复用 file_picker 的系统保存接口并明确取消状态。

- [ ] 写备注编辑保留原始付款人、恢复后首页/分类/统计重建、模板apply成功list失败不再失败或重做的回归并确认RED。
- [ ] 写保存入口收到真实字节/安全文件名、取消不会宣称已保存的测试。
- [ ] 实现并跑定向测试、全量analyze/test和隔离真实后端E2E。
- [ ] 独立复核并由协调者提交。

## Task 4: AI automation and report contracts

**Files:** `backend/internal/service/ai_report.go`, `ai_openai_client.go`, `ai_report_scheduler.go`, system repository atomic settings helper, AI tests, AI docs.

**Interfaces:** report_type进入任务/提示，非空有效summary为最低合同，prompt version更新；运行记录原子合并，用户配置永不由旧任务覆盖。

- [ ] 写关计划与生成结束交错测试，类型请求不同、null/数组/错误summary拒绝且不completed缓存的测试，确认RED。
- [ ] 实现设置合并和发送前开关复核、报告契约及输出/并发/频率约束。
- [ ] 跑AI定向普通/race、调度与供应商兼容测试，不连接真实外部AI。
- [ ] 独立复核并由协调者提交。

## Task 5: Release evidence and automation

**Files:** release inventory/drill scripts and tests, final gates, `release_contract.py`, Docker/Web workflows, VERSION/Web/Flutter versions, release notes/runbook, new release proof.

**Interfaces:** inventory消费基线SHA和候选源码；drill产生JSON结果与源码指纹；Release保留扫描/产物证明，恢复只信任经过身份校验的记录。

- [ ] 写干净git仓库已提交但未登记路径仍失败、历史演练不满足当前源码、证明篡改/缺失拒绝的离线回归并确认RED。
- [ ] 实现可执行证据检查，将候选版本一致更新到1.0.10，整理全部变更范围。
- [ ] 执行真实备份HTTP往返、升级/回滚与容器重建；生成本次证据，跑严格门禁。
- [ ] 独立全分支审查、修复其确定问题，提交并创建PR。
- [ ] 等远端必要checks通过，正常合并；确认远端main源码门禁后创建一次v1.0.10注释tag。
- [ ] 完成受保护镜像推广和Release发布，独立下载/校验/运行验收。

## 完成核对

- [ ] 各项关键反证全部消除，原84路径修复未被丢弃。
- [ ] Go普通/race/vet与真实数据库矩阵、Web完整门禁、Flutter完整门禁和当前备份演练通过。
- [ ] PR、源码SHA、tag对象、GHCR digest、Compose checksum与公开运行证据相互一致。
- [ ] 原工作区核对无并发新改动后安全同步，保留必要恢复快照；最终准确交付。
