# 发布治理合同

## 本地可验证合同

- 根目录 VERSION 是版本源；Web、Flutter 和发布输入必须一致。
- vX.Y.Z tag 必须指向 origin/main 已包含的提交，且 tag 创建后不得移动或删除。
- Release Docker/Web 只由 v* tag 触发。Docker 工作流不能单独手动发布。
- Docker 只构建一次多架构 OCI layout。固定 digest 的 Skopeo 从该 layout 分别导出
  linux/amd64 和 linux/arm64 单平台 docker archive，并先断言 archive 元数据与目标架构
  一致；Trivy 分别扫描这两个已验证输入，不依赖从多架构索引中选择 manifest。
  构建/扫描 job 没有 `packages:write` 或 `release` environment；两个扫描通过后，它把 OCI
  layout 封装为带 SHA-256 的 artifact。只有依赖该 job 的发布 job 才进入受保护的
  `release` environment、取得 `packages:write`，复验 archive 与 OCI digest 后用 Skopeo
  把同一 layout 推送到不可变 version tag。checkout 不保留 GitHub 凭据。
  发布链不自动创建或更新 latest，部署使用版本标签或 digest。
- 发布前拒绝已有的 GitHub Release 或 GHCR version tag，避免覆盖历史版本。
- GitHub Release action 必须显式设置 tag_name、target_commitish、
  fail_on_unmatched_files=true 和 overwrite_files=false。
- 每个 Docker/Web Release 附带版本专属 Compose 与 SHA-256；Compose 镜像引用固定到
  本次 GHCR digest。
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
- Forgejo 仅提供仓库安全与可选本地 Docker build smoke，不承担公开发布。

运行本地结构门禁：

    ./scripts/check-version-consistency.sh
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
6. 如需签名移动端，在 Actions 中选择同一 tag 运行 Signed Mobile Release (manual)。
7. 下载、校验、验签并完成真实设备验收；未完成时不要宣称正式移动分发完成。

任何一步失败都保留日志与 digest，停止后续推广。不要通过移动 tag、覆盖 Release asset
或重跑可独立发布的工作流来“修复”历史版本。

## 未解决的许可证边界

仓库当前没有 LICENSE 文件。本次工作不替项目所有者选择许可证；在许可证明确前，不应把
“公开可见源码”描述成已经获得通用开源授权。
