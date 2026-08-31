# 发布治理合同

## 本地可验证合同

- 根目录 VERSION 是版本源；Web、Flutter 和发布输入必须一致。
- vX.Y.Z tag 必须指向 origin/main 已包含的提交，且 tag 创建后不得移动或删除。
- Release Docker/Web 的正常路径只由 v* tag 触发。Docker 工作流不能单独手动发布。
- Recover Docker/Web Release 只从默认分支调度；恢复工具固定为该次调度的 `github.sha`，
  产品源码单独检出已存在的注释 tag。两者不可混用：镜像和 Compose 模板来自 tag 源码，
  校验、恢复、附件生成工具来自受信的工具提交，避免重新执行旧 tag 中已修复的清理错误。
  入口核对远端 tag 对象、解引用提交、main ancestry、VERSION 和该源码提交已成功的
  Project Quality Gate / Public Git Safety。`failed_run_id` 保留原输入名称，但可以引用
  相同 tag/SHA 已结束的 Docker/Web tag run（启动失败、部分失败、取消或成功）。
  按已发布状态分流，不能借恢复覆盖镜像、移动 tag 或重建已有 Release，详见下文。
- Docker 只构建一次多架构 OCI layout。固定 digest 的 Skopeo 从该 layout 分别导出
  linux/amd64 和 linux/arm64 单平台 docker archive，并先断言 archive 元数据与目标架构
  一致；Trivy 分别扫描这两个已验证输入，不依赖从多架构索引中选择 manifest。
  构建/扫描 job 没有 `packages:write` 或 `release` environment；两个扫描通过后，它把 OCI
  layout 封装为带 SHA-256 的 artifact。只有依赖该 job 的发布 job 才进入受保护的
  `release` environment、取得 `packages:write`，复验 archive 与 OCI digest 后用 Skopeo
  把同一 layout 推送到不可变 version tag。checkout 不保留 GitHub 凭据。
  发布链不自动创建或更新 latest，部署使用版本标签或 digest。
- 发布前拒绝已有的 GitHub Release 或 GHCR version tag，避免覆盖历史版本。
- 正常 tag 与恢复入口共用 `scripts/release_contract.py publish`。创建前再次确认 tag 对象、
  源码 SHA、版本镜像 digest 和 Release 不存在；只调用 `gh release create --verify-tag`，
  不传 `--target` / `target_commitish`，不调用 edit/upload/clobber。已有 tag 是唯一来源，
  避免工作流令牌对旧提交 target 的限制。创建失败后不得自动重试写入，先重新查询真实状态。
- 每个 Docker/Web Release 附带版本专属 Compose 与 SHA-256；Compose 镜像引用固定到
  本次 GHCR digest。独立 `verify-assets` job 不使用部署环境、只有只读权限：重新下载公开
  附件，检查 Release 元数据、校验和、Compose 实际服务的 image 和镜像源码身份。
  不对包含注释的整个文件统计 digest 次数；创建结果与公开复验结果是两个不同的状态。
- Signed Mobile Release 只能从已有 vX.Y.Z tag 手动运行。它验证 main ancestry 和已有
  非 draft Docker/Web Release，下载并严格校验版本 Compose/校验和，并确认 Compose digest
  与 GHCR version tag 相同；只追加尚不存在且已验签/验 checksum 的移动端资产，不重建
  或覆盖 Docker 标签。
- 移动端签名只是可选发布教程，仓库当前不配置真实签名材料。若启用正式 signed workflow，
  签名 secrets 必须放在受保护的 `mobile-signing` environment；仓库变量
  `ANDROID_EXPECTED_SIGNER_SHA256` 和 `IOS_EXPECTED_TEAM_IDENTIFIER` 必须由管理员配置，
  缺失即失败。构建与下载复验都必须确认 APK/AAB 使用同一预期 signer，并确认 iOS
  TeamIdentifier、application-identifier 与 bundle id 一致。
- Docker/Web tag 发布与手动签名移动端发布共享全局 concurrency group。
  任何公开发布写入均串行执行，避免版本输入格式差异造成同一 Release 并发修改。
- 恢复工作流使用相同 concurrency group；它的 GHCR 与 Release 写入只进入单独受保护的
  `release-recovery` environment。该环境只允许默认分支调度且同样需要维护者审批，避免为
  恢复旧 tag 而放宽正常 `release` environment 的 `v*` 限制。
- Forgejo 仅提供仓库安全与可选本地 Docker build smoke，不承担公开发布。

运行本地结构门禁：

    ./scripts/check-version-consistency.sh
    python3 scripts/test_release_contract.py
    ./scripts/check-docker-release-preflight.sh
    ./scripts/check-release-artifacts-preflight.sh
    ./scripts/check-github-actions-pinning.sh

这些门禁验证仓库内合同，不证明 GitHub 远端保护已经配置，也不证明真实镜像、签名资产或
设备验收已经完成。

## GitHub 远端设置

2026-08-24 已通过 GitHub API 读取并复核以下真实配置：

1. `main` 受分支保护：必须通过 Pull Request、必须与最新 main 同步、必须解决对话、要求
   线性历史，禁止 force push 和删除，并且管理员同样受约束。
2. 当前 required checks 是 `Tracked file safety`、
   `Reject newly introduced vulnerable dependencies` 和 `Project quality gate`。审批数量为 0，
   因此自动化不能把“代码已人工审批”描述为 GitHub 强制事实。
3. 活跃 tag ruleset `Immutable version tags` 匹配 `refs/tags/v*`，禁止 update、delete 和
   non-fast-forward，且当前管理员不能绕过；tag 创建仍允许，所以版本只能创建一次。
4. `release` environment 已创建，要求 `sky121666` 审批，只允许匹配 `v*` 的 tag 部署。
   `prevent_self_review=false`，适合当前单维护者仓库，但每个公开写入 job 仍会产生明确审批停点。
5. `mobile-signing` environment 采用同一审批人与 `v*` tag 限制，当前没有签名 secrets；
   因此误触发 signed workflow 会 fail closed，不会凭空生成可信签名资产。
6. `GITHUB_TOKEN` 仓库默认权限为只读；仅 Docker 发布 job 授予 `packages:write`，仅 Release
   job 授予 `contents:write`。仓库中所有外部 GitHub Actions 均锁定到完整 commit SHA。
7. `release-recovery` environment 是不可变 tag 启动失败时的独立恢复边界；它只允许 `main`
   部署、要求 `sky121666` 审批且不保存签名 secrets。恢复工作流仍必须从 tag 读取源码并通过
   上述远端身份与历史门禁。

必需状态检查名称可能随 workflow job 重命名而变化。调整 workflow 后应再次从真实 PR/main
run 复核，不要只凭本文抄写。任何远端规则修改都应继续通过 API/UI 回读确认。

Docker/Web 有两个不同的公开写入点：先写 GHCR 不可变 version tag，再创建 GitHub Release，
因此两个 job 都引用 release environment。GitHub 若按 job 分别要求审批，这两次审批
分别确认“推广镜像”和“发布 Release”，不是重复的无副作用门禁。Signed Mobile 的
prepare 只做只读校验，不引用 environment；只有最终追加公开资产的 contents:write job
引用 release，从而避免同一手动流程在准备和发布阶段各审批一次。环境保护只约束这些
公开写入，不替代签名材料管理或真实设备验收。

## 操作顺序

1. 在干净的 main 提交上完成源代码门禁和版本一致性检查。
2. 确认 main/tag ruleset 与 release environment 当前生效。
3. 创建一次性 vX.Y.Z tag 并推送；不得重打同名 tag。
4. 等待 Docker/Web workflow 完成，记录 GHCR digest，下载并校验版本 Compose。
5. 对记录的 digest 运行发布镜像 smoke；不依赖可移动标签。
6. 发布任一步失败后，先经 PR 修复工具，再从 `main` 调度 Recover Docker/Web Release，输入
   原 tag 与该 tag 的已结束 run ID。镜像已存在时还必须提供 `expected_digest` 和
   `publisher_run_id`，不能直接重跑旧 tag 流程试图覆盖版本。
7. 如需签名移动端，在 Actions 中选择同一 tag 运行 Signed Mobile Release (manual)。
8. 下载、校验、验签并完成真实设备验收；未完成时不要宣称正式移动分发完成。

任何一步失败都保留日志与 digest，停止后续推广。不要通过移动 tag、覆盖 Release asset
或绕过受保护恢复入口来“修复”历史版本。

## 恢复状态与验证边界

仅验收现有版本时必须设置 `verify_only=true`（本地规划命令为 `--verify-only`）。
这会明确禁用构建和 Release 写入；若远端产物不完整，只能报错停止，不能转入补发。

| 远端状态 | 恢复动作 | 必须提供的证据 |
| --- | --- | --- |
| 镜像不存在，Release 不存在 | 单次构建、双架构扫描、受保护推送、运行验证、创建及公开复验 | 原 tag run、不可变 tag、源码门禁；仓库必须明确证明镜像不存在 |
| 镜像存在，Release 不存在 | 跳过构建/推送；固定 digest 验证运行后，审批创建 Release | 另需完整 digest 与成功构建/扫描/推送的 publisher run |
| 镜像和完整 Release 均存在 | 跳过所有公开写入，只复核 | 同上，并校验现有 Docker 附件对；可选移动附件保持不动 |
| 附件不完整、digest 不符、来源不明、查询失败 | 停止，不覆盖或清理 | 维护者对照日志与产物确认后另行处理 |

publisher run 只能来自同仓库的原 tag 发布流程，或默认分支上的恢复流程；工具检查该提交
属于 main。同一次 run attempt 内必须同时有成功的构建/双架构扫描与推送 job，并从原始
job 日志的环境字段验证源码 SHA 与扫描后 digest。job 日志缺失、过期或不一致时停止；
仅提供一个正确格式的 digest、或镜像里自报的标签，不足以授权补建 Release。

运行验证使用本次工具提交的隔离 Docker smoke，仍检查两架构 manifest、健康、指标鉴权、
非 root、持久化与清理。恢复不再把当前 main 的 VERSION 当成旧版本源数据。
这不替代生产升级/回滚、实体手机、VoiceOver/TalkBack 或签名分发验收。

2026-08-31 本地修复及公开产物复验记录：
[发布恢复验证](../quality/release-recovery-verification-2026-08-31.md)。只有修改合入后，
新的恢复入口才会在 GitHub 默认分支生效；本地检查不等于已触发远端恢复。

## 未解决的许可证边界

仓库当前没有 LICENSE 文件。本次工作不替项目所有者选择许可证；在许可证明确前，不应把
“公开可见源码”描述成已经获得通用开源授权。
