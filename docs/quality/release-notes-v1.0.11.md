# Release Notes - v1.0.11

## Personal Ledger v1.0.11

**历史候选状态：安全扫描阻断，未发布。** 运行 `37410524297` 双架构构建成功，amd64 Trivy 因 OpenSSL `CVE-2026-14456` 与 Go x/crypto `CVE-2026-56854` 失败；arm64 扫描、publisher 和 Release 均跳过，未发布镜像或 Release。既有 tag 不可覆盖，后续说明见 [v1.0.12](release-notes-v1.0.12.md)。以下为原候选记录。

v1.0.10 因签名校验缺少可信调用 ref 约束而停止发布，既有 tag 不可覆盖。此说明列出 v1.0.11 的内容与发布前置条件；源码文档不单独证明发布完成，正式状态以 [GitHub Release](https://github.com/sky121666/sky-PersonalLedger/releases/tag/v1.0.11)、对应运行记录和公开产物核验为准。

## Supported Platforms

发布范围为 Docker image `ghcr.io/sky121666/sky-personalledger:1.0.11`、Vue Web 和不可变 digest 的 Compose；实际产物身份须从注册表和 Release 下载核验。Android、iOS 和 Flutter Web 同步源码与自动测试；本版本不包含签名 APK/AAB/IPA。

## Highlights

- 备份格式 2.4 明确保留软删除、禁用及归档状态，拒绝缺少必需集合的 JSON，避免恢复后删除记录复活或状态变化。
- Web 编辑绑定固定交易身份；家庭成员与付款人独立，修改备注不会改写付款人。迟到查询不覆盖当前日期、月份或登录状态。
- 首页区分核心账务、可选 AI 和查询失败，未知金额不显示为零，失效刷新不冒充成功。
- Flutter 恢复后重建业务缓存和页面；模板记账已完成时，列表刷新失败只允许重试读取。
- 原生导出使用系统保存入口；Flutter Web 发起本地下载并提示用户确认。macOS 写权限限于用户选中的文件。
- AI report 按报告类型使用不同任务，要求有效非空总结；每用户限制两项并发、每分钟六次供应商尝试，输出上限 4096 tokens。
- 自动 AI 完成只合并运行记录，不能覆盖用户最新开关；发送前重读计划设置。
- 干净 CI 检出仍检查从 v1.0.9 基线起的发布改动范围；备份演练绑定当前版本和源码。扫描证明的验收目标增加证书实际调用工作流、可信触发 ref 与来源提交约束，正常发布和恢复的工具/产品身份分别核验。
- Web 安全依赖已更新，braces 的无发布修复版栈耗尽问题使用经独立差分验证的精确源码补丁，冻结安装与深度回归纳入 CI。

## Security And Privacy

AI provider 为可选外部服务，测试使用本地合成响应。凭据不进入普通 backup；独立凭据加密 keyring 保持原有迁移和密钥轮换约束。认证和 Cookie 相关修改必须经过真实 HTTP 和响应交错检查，单凭前端 generation 不能证明后端撤销成功。

签名有效只能证明内容由证书所示身份签发，不能单独证明受保护发布 job 执行过扫描。正常路径要求 `release-web.yml` 的证书调用 ref 等于 `refs/tags/v1.0.11`，来源与 signer digest 等于产品 tag SHA。恢复路径要求 `release-web-recovery.yml` 的证书调用 ref 等于 API 返回的受保护默认分支，来源与 signer digest 等于通过 main ancestry 核验的工具 SHA；谓词中的产品 `source_sha` 仍是产品 tag SHA。普通分支、错误 ref 或混淆两种 SHA 的证明必须拒绝。

## Known Limitations

- iOS and Android device validation、签名安装和手动 VoiceOver/TalkBack 验收不由单元测试或模拟器结果替代。
- 共享账本与附件目录只支持单个可写实例；家庭记账成员并非独立权限账号。
- AI 限额为单进程请求约束，重启会重置；未实现货币预算，也未声称给出投资建议。
- 旧备份若已丢失删除状态，无法恢复其未知原状态；2.1–2.3 的有效旧数据仍可读取。
- 仓库未声明开源 LICENSE；本次不代替所有者选择许可证。
- 服务尚未验证 HTTP 请求排空的优雅停止；演练中停止容器命令成功，但应用退出码为 2。升级先停止业务写入，再停止实例并保留一致性副本。
- 全依赖版本扫描仍命中上游 braces 3.0.3 high 公告；生产依赖审计为 0。本地补丁默认限制深度并覆盖实际消费链，不能据此声称上游已经发布修复版本；维护见 `docs/development/dependency-security.md`。

## Upgrade Notes

1. 停止写入，保留升级前数据库、附件目录、配置及凭据加密密钥的一致性副本和旧镜像 digest。
2. 核验该版本 Release 存在，下载 `docker-compose-v1.0.11.yml`、`.sha256` 和 `docker-scan-proof-v1.0.11.jsonl`，确认 checksum、签名来源与公开资产身份后部署。
3. 使用一次受控 backup/restore 演练确认余额、删除状态、成员/付款人、附件和历史报告不变，再恢复日常写入。
4. v1.0.9 的 schema 10 升级至本版本 schema 11。旧版不能直接读取已升级数据库或新版 2.4 备份；回滚使用升级前副本。

## Rollback

停止新版本，保留其运行日志和新增数据，使用旧镜像 digest 与**升级前一致性副本**恢复。不要把 2.4 JSON 改标为 2.3，也不要让旧版本直接打开未确认兼容的升级后数据目录。随后复核登录、余额、交易和附件；升级后的新增写入需要另行审查后迁移。

## Verification Summary

各项运行结果记录在当前 CI run、外部演练 JSON 和最终交付报告；历史 2026-05/08 的 PASS 不能充当本次证据。必需验证包含 Go 普通/race/vet 和 SQLite/PostgreSQL/MySQL、Web 单元/构建/实际浏览器、Flutter analyzer/单元/真实后端、合成数据备份往返、容器重建以及公开产物身份。

此前 v1.0.10 候选源码阶段已核验：三数据库矩阵、全量 race/vet、覆盖率/性能门禁；Web 91 单测和 9 真实浏览器 E2E；Flutter 441 测试/1 默认截图 skip、3 Chrome 导出和 flutter-tester 真实后端；2.4 HTTP 演练。独立 Docker 升级/回滚验证 schema 10→11→10、余额 923.05→911.95→923.05、软删除/禁用/附件/成员不变及升级前副本 hash 未改。这些业务结果保留原范围，但旧测试未覆盖同仓库普通分支伪造扫描证明的来源反例。

四项新增来源反例在旧校验器产生的 RED 已归档；来源修复阶段 17 项本地来源回归通过。本地结果须与本轮独立复审、确切源码 SHA 的受影响门禁及真实 CI 签名/公开产物核验分别记录，全部满足后才可发布。测试数量与旧评审分数均不替代这项信任边界验收。

Docker/Web 门禁：`RELEASE_SCOPE=docker-web RELEASE_PHASE=source STRICT_FINAL_RELEASE=1 ./scripts/check-final-release-gates.sh`。`STRICT_FINAL_RELEASE=1 ./scripts/check-final-release-gates.sh` 的默认签名移动门禁属于单独发布范围。

## Release Decision

只有候选源码检查、可信来源反例、独立复审、正常受保护 PR 合并和 main 必需检查通过后，才创建一次 v1.0.11 注释 tag。v1.0.10 保持停止发布状态，禁止覆盖旧 tag 或用旧源码补发。发布完成须核实两架构扫描、源码 SHA、镜像 digest、签名证明的证书来源、公开 Compose checksum 与实际容器运行相符。自动化失败必须停止对应写入，先读取状态再决定恢复，不能覆盖现有版本。
