# Release Notes - v1.0.10

## Personal Ledger v1.0.10

## Supported Platforms

正式发布范围为 Docker image `ghcr.io/sky121666/sky-personalledger:1.0.10`、Vue Web 和不可变 digest 的 Compose。Android、iOS 和 Flutter Web 同步源码与自动测试；本版本不包含签名 APK/AAB/IPA。

## Highlights

- 备份格式 2.4 明确保留软删除、禁用及归档状态，拒绝缺少必需集合的 JSON，避免恢复后删除记录复活或状态变化。
- Web 编辑绑定固定交易身份；家庭成员与付款人独立，修改备注不会改写付款人。迟到查询不覆盖当前日期、月份或登录状态。
- 首页区分核心账务、可选 AI 和查询失败，未知金额不显示为零，失效刷新不冒充成功。
- Flutter 恢复后重建业务缓存和页面；模板记账已完成时，列表刷新失败只允许重试读取。
- 原生导出使用系统保存入口；Flutter Web 发起本地下载并提示用户确认。macOS 写权限限于用户选中的文件。
- AI report 按报告类型使用不同任务，要求有效非空总结；每用户限制两项并发、每分钟六次供应商尝试，输出上限 4096 tokens。
- 自动 AI 完成只合并运行记录，不能覆盖用户最新开关；发送前重读计划设置。
- 干净 CI 检出仍检查发布改动范围；备份演练绑定当前版本和源码。扫描证明通过受保护流程签名，保存到注册表和 Release，支持日志过期后的核验。

## Security And Privacy

AI provider 为可选外部服务，测试使用本地合成响应。凭据不进入普通 backup；独立凭据加密 keyring 保持原有迁移和密钥轮换约束。认证和 Cookie 相关修改必须经过真实 HTTP 和响应交错检查，单凭前端 generation 不能证明后端撤销成功。

## Known Limitations

- iOS and Android device validation、签名安装和手动 VoiceOver/TalkBack 验收不由单元测试或模拟器结果替代。
- 共享账本与附件目录只支持单个可写实例；家庭记账成员并非独立权限账号。
- AI 限额为单进程请求约束，重启会重置；未实现货币预算，也未声称给出投资建议。
- 旧备份若已丢失删除状态，无法恢复其未知原状态；2.1–2.3 的有效旧数据仍可读取。
- 仓库未声明开源 LICENSE；本次不代替所有者选择许可证。
- 服务尚未验证 HTTP 请求排空的优雅停止；演练中停止容器命令成功，但应用退出码为 2。升级先停止业务写入，再停止实例并保留一致性副本。

## Upgrade Notes

1. 停止写入，保留升级前数据库、附件目录、配置及凭据加密密钥的一致性副本和旧镜像 digest。
2. 下载 `docker-compose-v1.0.10.yml`、`.sha256` 和 `docker-scan-proof-v1.0.10.jsonl`，校验后部署。
3. 使用一次受控 backup/restore 演练确认余额、删除状态、成员/付款人、附件和历史报告不变，再恢复日常写入。
4. v1.0.9 的 schema 10 升级至本版本 schema 11。旧版不能直接读取已升级数据库或新版 2.4 备份；回滚使用升级前副本。

## Rollback

停止新版本，保留其运行日志和新增数据，使用旧镜像 digest 与**升级前一致性副本**恢复。不要把 2.4 JSON 改标为 2.3，也不要让旧版本直接打开未确认兼容的升级后数据目录。随后复核登录、余额、交易和附件；升级后的新增写入需要另行审查后迁移。

## Verification Summary

各项运行结果记录在当前 CI run、外部演练 JSON 和最终交付报告；历史 2026-05/08 的 PASS 不能充当本次证据。必需验证包含 Go 普通/race/vet 和 SQLite/PostgreSQL/MySQL、Web 单元/构建/实际浏览器、Flutter analyzer/单元/真实后端、合成数据备份往返、容器重建以及公开产物身份。

本次本地已核验：三数据库矩阵、全量 race/vet、覆盖率/性能门禁；Web 91 单测和 9 真实浏览器 E2E；Flutter 441 测试/1 默认截图 skip、3 Chrome 导出和 flutter-tester 真实后端；当前 2.4 HTTP 演练。独立 Docker 升级/回滚验证 schema 10→11→10、余额 923.05→911.95→923.05、软删除/禁用/附件/成员不变及升级前副本 hash 未改。远端发布与产物核验另由实际 CI 执行。

Docker/Web 门禁：`RELEASE_SCOPE=docker-web RELEASE_PHASE=source STRICT_FINAL_RELEASE=1 ./scripts/check-final-release-gates.sh`。`STRICT_FINAL_RELEASE=1 ./scripts/check-final-release-gates.sh` 的默认签名移动门禁属于单独发布范围。

## Release Decision

只有候选源码检查、独立复审、正常受保护 PR 合并、main 必需检查通过后，才创建一次 v1.0.10 注释 tag。发布完成须核实两架构扫描、源码 SHA、镜像 digest、签名证明、公开 Compose checksum 与实际容器运行相符。自动化失败必须停止对应写入，先读取状态再决定恢复，不能覆盖现有版本。
