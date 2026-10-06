# 当前发布库存与备份演练证据

历史 Markdown 是背景记录，严格发布不能从其中的 PASS 或旧执行日期推断当前源码已通过。

库存使用 `docs/quality/release-change-inventory.json`，保存 `schema_version=1`、`base_ref=v1.0.9`、实际 tag 的 `base_commit`、当前 `VERSION` 和全部精确文件路径。它刻意不写候选 HEAD SHA，避免清单自己的提交导致循环更新。当前 `v1.0.9` 的 peeled SHA 为 `134c4fdbcfb6860672af9c044fcad96aa606b8cc`；生成和校验都重新读取本地 tag，并核对固定基线 SHA。`RELEASE_INVENTORY_BASE_COMMIT` 仅供隔离测试仓库覆盖固定值，正式发布沿用固定基线。

```bash
python3 scripts/release_evidence.py inventory --file docs/quality/release-change-inventory.json --write
STRICT_RELEASE_SCOPE=1 ./scripts/check-release-change-inventory.sh
```

检查集合为基线到候选 HEAD 的已提交差异、候选 HEAD 到本地索引/工作区差异、未忽略的未跟踪文件。Git 用 NUL 分隔路径，重命名拆成旧/新路径；不存在目录前缀、文本子串或空 `git status` 的豁免。每个实际路径均在清单内以 JSON 字符串保存；默认输出仅包含基线、候选和数量，`--list-paths` 可显式列出全部路径。最终编辑完成后再生成一次清单。

HTTP 演练只使用临时目录内两个 SQLite 实例和本地假 AI。Go 编译一次，直接管理服务器进程并回收；不会用 `go run` 子进程或命令替换取得 PID。所有 `LEDGER_` 环境变量先清除再设置隔离路径；仅这两个临时实例开启 `LEDGER_SECURITY_ALLOW_PRIVATE_OUTBOUND=true`，供 loopback 假 AI 调用。真实账号、数据库、上传目录和外部 AI 不参与。

```bash
BACKUP_OPERATOR_DRILL_PROOF_FILE=/tmp/ledger-backup-http-proof.json ./scripts/check-backup-operator-drill-local.sh
BACKUP_OPERATOR_DRILL_PROOF_FILE=/tmp/ledger-backup-http-proof.json ./scripts/check-backup-operator-drill.sh
```

结果 JSON 的 `kind` 为 `personal-ledger-backup-http-drill`，包含实际版本、HEAD `source_commit`、`source_fingerprint`、`runtime_source_count`、`source_dirty`、UTC `executed_at`、备份格式 `2.4`、测量值和十项不变性结果。运行源码指纹按当前生产 Go 文件、Go 模块文件、VERSION、演练程序及严格校验脚本的路径和字节计算；不包括测试、历史文档或结果文件。运行中源码变更会让演练失败。被删除的交易直接从目标临时 SQLite 核对 tombstone，并在再次 HTTP 导出中核对原删除时间。

验收涵盖：2.4 格式；软删除支出仍被删除；活动交易集合、资产余额与月统计不变；归属 A 和付款 B 分别保留；缺少必需集合的恢复返回 400 且目标数据不变；AI 报告历史保留；Provider 和登录凭据不泄漏。失败不写 PASS 结果；已有结果仍必须重新校验当前源码指纹和时间，不能凭文件存在放行。

机器证据只能写在 checkout 外的 runner temp 或 `/tmp`，不能提交含猜测 SHA 的结果。严格校验默认最多接受 48 小时前的执行，缺失证据、历史 Markdown、错误版本/提交、被改动的源码指纹或缺少不变性均失败。发布可通过 `BACKUP_OPERATOR_DRILL_EXPECTED_COMMIT` 指定可信候选 SHA，并设置 `BACKUP_OPERATOR_DRILL_REQUIRE_CLEAN=1` 拒绝脏源码证据。`BACKUP_OPERATOR_DRILL_MAX_AGE_HOURS` 可显式控制有效期。

Security Contracts workflow 直接运行演练并上传 `backup-operator-drill-proof` artifact，文件名为 `backup-operator-drill-proof.json`。发布 source/published 门禁须从已经通过的、同一源码 SHA 的可信 workflow run 下载该 artifact；设置 `BACKUP_OPERATOR_DRILL_PROOF_FILE` 和期望 SHA 后执行严格检查。JSON 内容校验本身不认证来源，不能接受任意用户上传或手工编造的 JSON 作为可信 CI 执行证明。
