# Final Release Runbook - v1.0.11

## Conclusion

本手册列出 v1.0.11 的发布步骤与前置合同，不证明步骤已执行。正式状态以 [GitHub Release](https://github.com/sky121666/sky-PersonalLedger/releases/tag/v1.0.11)、对应运行记录和公开产物核验为准。范围为现有 GitHub/GHCR Docker/Web；保留 PR、必需检查和 `release` 环境保护，正常批准已授权的具体产物，不使用强制推送、管理员绕过或移动历史 tag。

v1.0.10 因证书调用 ref 未受约束而停止发布。原发布运行 `37407444646` 已停止后续发布，停止时无 GHCR 版本或 GitHub Release；既有 tag 保留且不可覆盖，不能重跑旧源码完成发布。

## Preconditions

- VERSION/Web/Flutter 同为 1.0.11，原有未提交修复已纳入独立工作树和发布库存；真实数据未参与测试。
- 所有功能回归、签名来源反例和独立复审须通过；当前备份演练 JSON 绑定新版本及当前源码，干净检出库存仍覆盖从 v1.0.9 基线起的完整改动。旧候选测试未覆盖来源反例，不能沿用其 PASS 证明来源可信。
- 远端 main 的 Project quality gate、Tracked file safety 和 Reject newly introduced vulnerable dependencies 通过。
- 创建前读取 GitHub Release、tag 和 GHCR 版本 manifest，确认新版本不存在；未知结果先读状态。

## 1. Configure Signing

Docker scan attestation 由受保护发布 job 的 OIDC 身份签名，只有 publisher 具有 `id-token` / `attestations` 写权限。签名 APK/AAB/IPA 不属于本次范围。未来单独移动发布才执行 `CHECK_SIGNING_SECRETS=1 ./scripts/check-release-artifacts-preflight.sh`，不得为本次流程增加机器签名材料。

发布前验证的目标是证书实际调用 URI、ref 与来源提交，而不是仅匹配仓库和工作流文件名或相信谓词自报字段。正常签名必须来自 `release-web.yml`，调用 ref 精确为 `refs/tags/v1.0.11`，source/signer digest 为确切产品 tag SHA。恢复签名必须来自 `release-web-recovery.yml`，调用 ref 为 API 核对的受保护默认分支（当前为 `refs/heads/main`），source/signer digest 为通过 main ancestry 核验的工具 SHA；产品 `source_sha` 仍绑定独立产品 tag SHA。

## 2. Run Release Workflow

提交经验证的指定路径，创建 PR，等待检查通过后正常合并。main 检查通过后，在确切合并提交创建一次 `git tag -a v1.0.11 -m "Release v1.0.11"`，推送该 tag。`.github/workflows/release-web.yml` 构建一次 OCI、验证两架构并扫描，通过环境批准后推广原 digest，签名并做运行门禁，再创建 Release。

## 3. Download And Verify Artifacts

正式发布后下载 Compose、checksum 和签名证明。以 `release_contract.py verify-tag / verify-image / verify-assets` 核验注释 tag、远端对象、源码、两架构 OCI 配置、digest 和签名；`gh attestation verify` 的成功结果还须经过证书调用 URI/ref 与 source/signer digest 的精确来源检查，再核对自定义扫描 predicate。普通同仓库分支签发的证明必须拒绝。

旧版本仍依赖其原发布日志；v1.0.11 起必须有签名证明，缺失不能降级为普通 JSON 或历史日志。签名来源可靠仍不等于未来无漏洞：策略仅要求当次 HIGH/CRITICAL、os/library 扫描忽略未修复项。

未来移动签名资产才使用 `RELEASE_ARTIFACT_DIR=artifacts RELEASE_VERSION=1.0.11 REQUIRE_IOS_ARTIFACT=1 VERIFY_ARTIFACT_SIGNATURES=1 ./scripts/check-release-artifact-files.sh`；历史范围见 `docs/quality/release-artifact-evidence-2026-05-27.md`。

## 4. Mobile Device QA

运行当前 Flutter 真实后端测试，物理设备和签名安装单独记录。未来签名发布命令为 `REQUIRE_PHYSICAL_IOS=1 REQUIRE_ANDROID_EMULATOR=1 ./scripts/check-mobile-device-qa-preflight.sh` 和 `RUN_ANDROID_E2E=1 ./scripts/check-mobile-device-qa-preflight.sh`。旧清单 `docs/quality/mobile-device-qa-checklist-2026-05-27.md` 不作为本次 PASS。

## 5. Backup Operator Drill

执行 `scripts/check-backup-operator-drill-local.sh`，只创建临时 SQLite 和本地假 AI。生成外部 JSON 证据并运行严格检查。当前检查要求源码指纹、版本、时间、删除状态、金额及成员/付款人均一致。`docs/quality/backup-operator-drill-2026-05-27.md` 只保留历史说明。

升级/回滚演练使用 v1.0.9 一致性数据副本，新版本写入不让旧版本原地读取；回滚后复核原合成账本。新 2.4 备份不能改标旧版本格式。

## 6. Accessibility Pass

自动语义/布局检查与真实屏幕阅读器验收分开；历史 `docs/quality/accessibility-release-evidence-2026-05-27.md` 不更新为虚假本次结论。

## 7. Finalize Release Notes

当前说明为 `docs/quality/release-notes-v1.0.11.md`，历史 `docs/quality/release-notes-candidate-2026-05-27.md` 保持历史。`STRICT_RELEASE_NOTES=1 ./scripts/check-release-notes-candidate.sh` 校验当前默认说明。

## 8. Final Gate

设置当前机器演练证据位置后执行 `RELEASE_SCOPE=docker-web RELEASE_PHASE=source STRICT_FINAL_RELEASE=1 ./scripts/check-final-release-gates.sh`。发布镜像后以相同候选证据执行 published 阶段及公开资产独立检查。`STRICT_FINAL_RELEASE=1 ./scripts/check-final-release-gates.sh` 默认移动签名门禁不代替 Docker/Web 门禁。

## Failure Handling

- PR 检查失败：定位根因、写回归、重新提交，不能删除断言换取成功。
- 签名来源反例成立：停止受影响候选的推广，保留旧 tag 和失败证据，在新版本、新源码上修复并重新验收；不能用签名存在、同仓库身份或旧测试全绿放行。
- 推送或创建 Release 超时：先查询 tag、manifest、Release 与运行状态，不重复写入。
- 镜像已发布而 Release 尚缺：使用现有 recovery 流程，提供精确 digest 和 publisher run；签名核验失败即停止。
- 原工作区发生新改动：保留快照和隔离分支，重新比对后选择性同步，不覆盖新工作。
- 缺少真实部署对象、签名或设备：报告该外部范围，继续已授权且独立的自动验收。
