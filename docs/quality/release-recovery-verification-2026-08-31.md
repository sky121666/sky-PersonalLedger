# Docker/Web 发布恢复修复与验证（2026-08-31）

## 结论与范围

以下记录是本地修复阶段的快照；远端合入、CI 与实际调度结果应以对应 PR / Actions 为准。

v1.0.9 公开镜像和 Docker/Web 附件真实存在；本次重新下载、校验和隔离运行均通过。
已完成发布恢复工具的本地修复。未提交、推送、触发 GitHub 工作流、创建 Release、移动 tag、
覆盖镜像或清理历史失败记录。后续合入和 GitHub runner 验收仍是单独步骤。

本地基线：`main`，`9248623f93baf3b2e43d127624afdd1b55d6109c`。
本文件及本轮工具修改属于基线之后的未提交改动，不属于 v1.0.9 原 tag 的产品源码。

## 修复目标与结果

- 统一正常发布与恢复入口的 Release 创建逻辑：核对现有 tag 对象、源码 SHA、镜像摘要，
  只允许创建不存在的 Release；不再传 `--target`，不自动更新附件或重试失败写入。
- 恢复按三种状态分流：未发布才构建；已有镜像则验证原扫描/推送证据后续跑；
  已有完整 Release 则只复核。缺失或冲突的证据一律停止。
- 产品源码锁定 tag，恢复脚本锁定本次默认分支调度的提交，避免旧 tag 中的脚本错误复现。
- 附件复验独立为只读 job；根据 Compose 解析出的实际服务镜像检查摘要，
  不再对同时含有注释和 image 的全文统计出现次数。
- 原有双架构扫描、受保护写入环境、固定摘要、串行发布和不更新 latest 的约束保留。
- 主分支安全合同工作流加入离线行为回归测试及发布结构门禁。

## 已复核的公开身份

| 项目 | 实际值 |
| --- | --- |
| Release | [v1.0.9](https://github.com/sky121666/sky-PersonalLedger/releases/tag/v1.0.9)，非 draft、非 prerelease |
| 产品源码 SHA | `134c4fdbcfb6860672af9c044fcad96aa606b8cc` |
| 注释 tag 对象 | `f85188e8ca65579283df40692b5889202fc23842` |
| 镜像摘要 | `sha256:db2e60c66f72338357a3541845e6f52fae40f1c701d2b4124536f4663c43c457` |
| Compose | `docker-compose-v1.0.9.yml`，4754 字节 |
| Compose SHA-256 | `a18652ad338565d1df905ef8fd2ffb8ac1bb00ba6a9d6da119f1b32726b7efff` |

原 tag run：[32704520039](https://github.com/sky121666/sky-PersonalLedger/actions/runs/32704520039)，
状态为 `startup_failure`。成功构建/扫描及推送来自恢复 run
[32710642183](https://github.com/sky121666/sky-PersonalLedger/actions/runs/32710642183)，
具体 job 为 `97381169830`、`97381607415`。本次读取同一 attempt 的 job 原始日志，
源码 SHA 与扫描后摘要均匹配。该 run 整体的失败状态不能抹去已成功写入 GHCR 的事实。

## 本轮验证

1. **27 个离线测试通过**：三种恢复状态及编排、错误来源、缺少门禁、缺失/重复/失败的
   发布 job、日志绑定、附件缺失/重复/校验失败、错误镜像与服务、tag 变化、只创建不覆盖、
   模糊写入失败不重试、仓库网络/权限错误不视为“镜像不存在”、仅复核模式禁止转入发布。
2. **真实恢复入口只读演练通过**：临时检出 v1.0.9，调用当前本地 `recover-plan`，
   读取远端 tag、main ancestry、源码门禁、publisher job 与公开附件，得到 `mode=verify`。
   未调用 `publish`。这验证的是本地工具行为，不等于 GitHub job 已调度。
3. **公开附件复验通过**：重新下载 Compose 和 `.sha256`，校验字节摘要和实际服务 image。
4. **两架构镜像身份通过**：直接查询仓库配置，`linux/amd64`、`linux/arm64` 的 source、
   revision、version 与预期一致。没有把两架构元数据检查当作两种架构都已运行。
5. **固定摘要本地 smoke 通过**：健康检查 `healthy`、运行 UID `10001`、指标鉴权、
   `ledger.db/uploads/backups` 持久化、临时容器/数据清理；服务使用随机回环端口和合成配置。
6. **本地门禁通过**：actionlint（3 个改动工作流）、Bash 语法、Docker 发布预检、
   Actions SHA 锁定、公共仓库安全、版本一致性、移动发布附件预检、发布运行手册、
   发布说明候选、改动清单，以及 `git diff --check`。

复验命令（在项目根目录；以下命令不写远端发布状态）：

```sh
python3 scripts/test_release_contract.py
./scripts/check-docker-release-preflight.sh
GITHUB_REPOSITORY=sky121666/sky-PersonalLedger python3 scripts/release_contract.py verify-assets \
  --tag v1.0.9 \
  --digest sha256:db2e60c66f72338357a3541845e6f52fae40f1c701d2b4124536f4663c43c457
GITHUB_REPOSITORY=sky121666/sky-PersonalLedger python3 scripts/release_contract.py verify-image \
  --tag v1.0.9 --sha 134c4fdbcfb6860672af9c044fcad96aa606b8cc \
  --digest sha256:db2e60c66f72338357a3541845e6f52fae40f1c701d2b4124536f4663c43c457
DOCKER_RELEASE_IMAGE=ghcr.io/sky121666/sky-personalledger@sha256:db2e60c66f72338357a3541845e6f52fae40f1c701d2b4124536f4663c43c457 \
  RUNTIME_DOCKER_RELEASE_EVIDENCE=1 RUN_DOCKER_RELEASE_SMOKE=1 \
  ./scripts/check-docker-release-evidence.sh
```

## 未验证及后续动作

- 本轮没有重新构建/扫描双架构镜像；复用的是上述原始成功日志，并核对公开镜像身份。
- 没有触发远端恢复工作流。工作流审批、跳过依赖的实际调度、只读复验 job 仍需合入后
  在 GitHub 验证。若使用 v1.0.9 验收，应输入上述原 tag run、publisher run 和完整 digest，并设置 `verify_only=true`，
  预期只读模式，不再生成新部署或发布产物。
- 没有重跑全部 Go/Web/Flutter 测试、真实生产升级/回滚或实体设备与读屏验收；
  本轮没有修改业务代码。既有测试历史不表述为本轮新结果。
- 未提交的工作区不能通过“干净工作区”的正式发布门禁；本次没有将其标为通过。
- 不配置签名材料，不代替所有者选择许可证。

规则及操作入口见 [发布治理合同](../development/release-governance.md)。
