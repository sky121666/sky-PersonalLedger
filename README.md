# Personal Ledger

Personal Ledger 是一个面向个人和家庭的私有部署记账系统。数据保存在你自己的服务器上，提供 Web 界面和原生 Flutter 客户端；后端 API 同时支持浏览器、移动端和受限的设备授权令牌。

## 当前边界

- Docker + Web 是当前最直接的自托管路径。
- Flutter 客户端源码覆盖 Android、iOS、macOS 和 Windows；对应构建工作流已经存在，但正式分发仍取决于签名材料、目标平台回归和设备证据。
- 本项目是单个拥有者范围内的个人/家庭账本，不是 SaaS 多租户系统。
- 默认数据库是 SQLite，也可以配置 PostgreSQL、MySQL 或 MariaDB。
- 仓库当前未包含 LICENSE 文件；如果要公开发行，请先补充明确的许可证声明。

## 功能

### 记账与数据管理

- 收入、支出、转账，以及账户余额和账户变更日志。
- 账户、分类、标签、模板、预算、提醒和借贷记录。
- 交易搜索、筛选、批量删除、附件上传、CSV 导出和年度报表。
- 交易导入预览、校验、提交和回滚。
- 自动备份、备份列表、JSON 备份恢复和恢复前后完整性校验。

### 家庭和分析

- 家庭成员管理、成员归属交易、家庭汇总和成员统计。
- 总预算、分类预算和成员预算相关界面。
- 统计总览、分类统计、趋势和资产趋势。
- 可选的 OpenAI-compatible AI Provider、AI 报告、报告计划任务和敏感信息保护。
- Webhook、SMTP、企业微信和钉钉等通知配置与测试入口。

### 安全与运维

- 首次初始化、JWT 会话、刷新令牌和带 scope 的设备授权 API Token。
- 生产模式全局限流、登录限流、CORS 白名单、安全响应头和审计日志。
- 可选的受保护 Prometheus /metrics，默认关闭。
- 上传文件类型/大小限制，备份恢复大小限制，以及 SSRF/私网出站防护。
- 健康检查：GET /api/v1/health。

## 架构

    Web 浏览器 ─┐
    Flutter 客户端 ─┼─> Go/Gin API (/api/v1) ─> GORM ─> SQLite/PostgreSQL/MySQL/MariaDB
    设备授权客户端 ─┘                 │
                                      ├─ /data/ledger.db
                                      ├─ /data/uploads/
                                      └─ /data/backups/

| 目录 | 内容 |
| --- | --- |
| backend/ | Go 后端、Gin 路由、GORM 数据访问、服务和测试 |
| web/ | Vue 3 + TypeScript + Vite Web 客户端 |
| mobile/ | Flutter 原生客户端、平台工程和移动端测试 |
| scripts/ | 本地质量门禁、备份演练、E2E 和发布前检查 |
| docs/ | 架构、移动端 QA、备份和发布运行手册 |
| .github/workflows/ | Web、后端数据库矩阵、Flutter、移动端 E2E、安全和发布工作流 |

## Docker 快速开始

### 使用已有镜像

需要 Docker Engine 和 Docker Compose v2。

    git clone https://github.com/sky121666/sky-PersonalLedger.git
    cd sky-PersonalLedger
    cp .env.example .env

编辑 .env，至少设置两个随机值：

    LEDGER_JWT_SECRET=<至少 32 个字符的随机值>
    LEDGER_SETUP_TOKEN=<至少 32 个字符的随机值>

可以用下面的命令生成值，再复制到 .env，不要把真实值提交到 Git：

    openssl rand -base64 32
    openssl rand -hex 32

启动并查看健康状态：

    docker compose up -d
    docker compose ps
    curl -fsS http://127.0.0.1:8080/api/v1/health

首次访问：

    http://localhost:8080/#/setup?setup_token=<LEDGER_SETUP_TOKEN 的值>

初始化向导会检查数据库并写入配置。若你在向导中切换了数据库连接配置，请按页面提示重启服务，再回到初始化页设置访问密码。初始化完成后，远程初始化接口会被禁用。

### 从当前源码构建镜像

如果没有可用的 GHCR 镜像，先在仓库根目录构建本地镜像：

    docker build -t personal-ledger:local .
    LEDGER_IMAGE=personal-ledger:local docker compose up -d

docker-compose.yml 默认把 ./data 挂载到容器 /data，包括数据库、上传文件和自动备份。更新镜像后，先备份 ./data，再执行：

    docker compose pull
    docker compose up -d

本地调试时可以显式叠加 docker-compose.debug.yml；它只把服务切换为 debug 模式，不应作为生产配置：

    docker compose -f docker-compose.yml -f docker-compose.debug.yml up -d

## 配置

完整示例见 .env.example、config.example.yaml 和 docker-compose.yml。常用配置如下：

| 变量 | 作用 | 默认值/要求 |
| --- | --- | --- |
| LEDGER_SERVER_PORT | HTTP 监听端口 | 8080 |
| LEDGER_SERVER_MODE | debug 或 release；生产模式启用全局限流 | debug（容器覆盖为 release） |
| LEDGER_SERVER_WEB_PATH | Web 构建产物目录 | ./web/dist |
| LEDGER_JWT_SECRET | JWT 签名密钥 | 必填，至少 32 字符 |
| LEDGER_SETUP_TOKEN | 首次远程初始化令牌 | 配置远程初始化时至少 32 字符 |
| LEDGER_DATABASE_DRIVER | sqlite、postgres、postgresql、mysql 或 mariadb | sqlite |
| LEDGER_DATABASE_PATH | SQLite 文件路径 | ./data/ledger.db |
| LEDGER_DATABASE_DSN | 外部数据库 DSN | 空 |
| LEDGER_SETUP_CONFIG_PATH | 初始化向导写入的 YAML 配置路径 | ./data/config.yaml |
| LEDGER_STORAGE_UPLOAD_PATH | 上传文件目录 | ./data/uploads |
| LEDGER_STORAGE_BACKUP_PATH | 自动备份目录 | ./data/backups |
| LEDGER_STORAGE_MAX_FILE_SIZE | 单个上传文件大小上限（MB） | 10 |
| LEDGER_STORAGE_RESTORE_MAX_FILE_SIZE | 备份恢复文件大小上限（MB） | 64 |
| LEDGER_SECURITY_BASE_PATH | 自定义访问入口路径 | 空 |
| LEDGER_SECURITY_ALLOW_PRIVATE_OUTBOUND | 是否允许用户配置的 AI/Webhook/SMTP 访问私网 | false |
| LEDGER_CORS_ALLOWED_ORIGINS | 跨域来源白名单 | 空；release 禁止 * |
| LEDGER_OBSERVABILITY_METRICS_ENABLED | 是否开放 Prometheus 指标 | false |
| LEDGER_OBSERVABILITY_METRICS_TOKEN | 指标 Bearer Token | 启用指标时至少 32 字符 |
| TZ | 应用时区 | Asia/Shanghai |

外部数据库示例：

    LEDGER_DATABASE_DRIVER=postgres
    LEDGER_DATABASE_DSN=postgres://ledger:password@db:5432/ledger?sslmode=disable&TimeZone=Asia/Shanghai

    LEDGER_DATABASE_DRIVER=mysql
    LEDGER_DATABASE_DSN=ledger:password@tcp(db:3306)/ledger?charset=utf8mb4&parseTime=True&loc=Local

## Web 开发

Web 使用 Node.js 20、pnpm 10.32.1 和 Vite。开发服务器默认监听 5173，/api 请求代理到 http://localhost:8080。

    cd web
    pnpm install --frozen-lockfile
    pnpm dev

常用检查：

    pnpm test
    pnpm verify:attachments
    pnpm build
    pnpm verify:bundle

真实后端浏览器 E2E 会启动隔离的 Go 后端和临时 SQLite 数据库；先构建 Web，再从仓库根目录执行：

    cd web && pnpm build
    cd ..
    ./scripts/verify-web-e2e.sh

该检查覆盖登录、错误密码、桌面端交易新增/编辑/删除，以及移动视口下的主导航和快速记账入口。

## 后端开发

后端要求 Go 1.25.12 或兼容版本；本地直接运行时需要准备 LEDGER_JWT_SECRET。默认 Web 静态目录为 ./web/dist。

    cd backend
    go mod download
    LEDGER_JWT_SECRET="$(openssl rand -base64 32)" go run ./cmd/server

回归测试：

    go test ./...
    go vet ./...

仓库根目录还提供数据库矩阵、备份、隐私、运行健康、外部集成和性能检查脚本。它们会使用临时目录或测试数据库，不要把生产数据路径传给测试脚本。

## Flutter 客户端

移动端首次启动时填写账本服务器根地址，例如 https://ledger.example.com 或本机/局域网地址。客户端会自动追加 /api/v1；不要在输入框里重复填写 /api/v1。

    cd mobile
    flutter pub get
    flutter analyze
    flutter test
    flutter run

真实后端移动端 E2E 默认使用 flutter-tester 和隔离 SQLite 后端：

    cd ..
    ./scripts/verify-mobile-e2e.sh

平台变体：

    RUN_FLUTTER_TESTER_E2E=0 RUN_ANDROID_E2E=1 ./scripts/verify-mobile-e2e.sh
    RUN_FLUTTER_TESTER_E2E=0 RUN_IOS_E2E=1 ./scripts/verify-mobile-e2e.sh

Android 默认只接受 emulator-* 设备；完整说明见 docs/mobile-real-backend-e2e.md。

### 平台产物与发布边界

GitHub Actions 提供 Android APK/AAB、iOS IPA、macOS ZIP 和 Windows ZIP 的构建工作流。Android/iOS 正式产物必须配置签名材料；仓库不包含任何 keystore、证书或 provisioning profile。正式发布前还需要目标平台回归、物理设备 QA 和必要的 VoiceOver/TalkBack 验收。

## 自动化门禁

提交前建议至少执行：

    ./scripts/check-public-git-safety.sh
    git diff --check

    cd backend && go test ./...
    cd ../web && pnpm install --frozen-lockfile && pnpm test && pnpm verify:attachments && pnpm build && pnpm verify:bundle
    cd ..
    ./scripts/verify-web-e2e.sh
    cd mobile && flutter analyze && flutter test
    cd ..
    ./scripts/verify-mobile-e2e.sh

更完整但更慢的本地发布演练：

    RUN_EXPENSIVE=1 ./scripts/check-production-readiness.sh

只验证本地源代码、备份、Docker 和结构门禁，并跳过真实签名产物、GHCR 线上镜像、物理 iPhone 和人工辅助功能证据：

    LOCAL_FINAL_RELEASE=1 ./scripts/check-final-release-gates.sh

STRICT_FINAL_RELEASE=1 ./scripts/check-final-release-gates.sh 只应在签名产物、设备和发布证据全部准备完成后执行。

## 发布工作流

.github/workflows/ 中的主要工作流包括：

- web.yml：pnpm 安装、单测、依赖审计、附件清理契约、生产构建、体积预算和浏览器 E2E。
- backend-database.yml：Go 测试、SQLite/PostgreSQL/MySQL 矩阵、覆盖率和性能预算。
- mobile-quality.yml：Dart 格式、Flutter 分析、Flutter 测试和 premium screen smoke。
- mobile-e2e.yml：真实后端 flutter-tester E2E。
- security-contracts.yml：健康检查、AI 隐私、备份 API 和外部集成契约。
- public-git-safety.yml：工作流固定引用和公开仓库敏感文件检查。
- release.yml：推送 v* 标签后串联 Web、后端、移动端、Docker、签名产物和 Release 校验。

发布前请先阅读 docs/quality/production-readiness-2026-05-27.md 和 docs/quality/final-release-runbook-2026-05-27.md。文档中的 PENDING、PREPARED 或历史 PASS 记录不等于当前已经有签名产物或物理设备证据。

## 数据安全注意事项

- .env、数据库、上传目录、备份目录、签名文件和本地构建产物不应提交到 Git。
- LEDGER_JWT_SECRET、LEDGER_SETUP_TOKEN、指标 Token、AI Provider Key 和通知凭据不要写入 README、Issue 或测试产物。
- AI Provider 是可选功能；新保存的凭据会按当前安全路径保护，正常备份不会导出 Provider 密钥。升级后应重新保存历史 Provider。
- 生产模式不要使用 LEDGER_CORS_ALLOWED_ORIGINS=*，也不要在未审查的情况下打开私网出站访问。
- 升级前先备份 ./data，保留旧镜像标签和备份，确认恢复演练通过后再清理旧版本。
