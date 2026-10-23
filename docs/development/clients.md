# 客户端开发

## Web

Node.js 版本以仓库根目录 `.node-version` 为准，当前为 26.12.0；
pnpm 版本由 `web/package.json` 锁定为 12.11.2，CI 和 Docker 使用相同版本。
Node 26 不依赖内置 Corepack，可先安装对应版本的 pnpm：

    npm install --global pnpm@12.11.2
    cd web
    pnpm install --frozen-lockfile
    pnpm dev

Web API 使用同源 /api/v1；Vite 开发服务器把 /api 代理到 http://localhost:8080。

非交互式脚本也必须使用项目版本，不能只依赖交互式 `.zshrc` 初始化 NVM。
运行 `./scripts/check-toolchain-consistency.sh --runtime` 可同时核对实际 Node/pnpm；
不带参数时只检查仓库声明，供不安装 Web 工具链的发布预检复用。
本机已在 `~/.zshenv` 为本项目目录配置轻量版本选择，读取 `.node-version` 并使用
对应的已安装 NVM `bin` 目录；其他项目和交互式终端的选择方式不变。
`~/.zlogin` 在登录初始化结束后再次应用该选择，防止登录配置重排 PATH。
其他机器需要自行选择对应运行时，CI 则由 setup-node 和 pnpm/action-setup 完成。

### 当前技术栈和兼容边界

| 范围 | 版本 |
| --- | --- |
| Vue / Vue Router / Pinia | 3.5.44 / 5.4.0 / 4.1.0 |
| Vite / Vue 插件 | 8.3.4 / 6.0.10 |
| Tailwind CSS / Vite 插件 | 4.3.3 / 4.3.3 |
| TypeScript / vue-tsc | 6.0.3 / 3.3.13 |
| Vitest / Playwright | 5.0.4 / 1.64.1 |
| Axios / Day.js / Lucide Vue | 1.20.0 / 1.11.23 / @lucide/vue 1.57.0 |

TypeScript 暂留 6.0.3，属于已接受的兼容例外。`vue-tsc` 和现有测试辅助工具
使用 TypeScript JavaScript 编译器 API；升级到 TypeScript 7 前需重新验证该接口，
不能只依据 peer dependency 的版本范围。

浏览器最低要求为 Safari 16.4、Chrome 111、Firefox 128；Vite 的构建目标与此一致。
自动化使用 Playwright 随附的当前 Chromium、Firefox、WebKit，不能等同于逐一验证
上述最低版本或真实 iOS/Android 设备。

样式通过 `@tailwindcss/vite` 编译。`src/assets/theme.css` 保留既有颜色、圆角、
阴影和 sRGB 渐变；暗色模式继续由 `.dark` 控制。组件使用显式导入，不再使用 Vant
resolver 或自动组件注册。Lucide 沿用原图标体系，包名迁移到官方维护的 `@lucide/vue`。

### Web 验证

    cd web
    pnpm install --frozen-lockfile --strict-peer-dependencies
    pnpm test
    pnpm build
    pnpm verify:bundle
    pnpm verify:brace-depth
    pnpm verify:attachments
    pnpm audit --prod --audit-level=high
    pnpm audit --audit-level=moderate
    pnpm exec playwright install chromium firefox webkit
    cd ..
    ./scripts/verify-web-e2e.sh

Vitest 只执行 `src/**/*.test.ts`；应用、Node 工具配置、测试代码分别设置 TypeScript
类型环境。`pnpm build` 同时检查应用和测试类型。配置编译产物写入 `node_modules/.cache/tsc`。

Docker 的 Go 构建器与 `backend/go.mod` 同步为 1.26.9，最终镜像为 Alpine 3.24.2。
Go 保持现有 1.26 分支并补齐补丁；跨到 1.27 的迁移不包含在本次 Web 收尾中。
Docker CI 使用 Buildx 0.38.0 / BuildKit 0.34.0；基础镜像、BuildKit 和 Skopeo 均固定 digest，
GitHub Actions 固定经核实的 release commit SHA。
Trivy 扫描器显式固定为 0.76.0，避免其版本隐式依赖 Action 的默认值。
可选 Forgejo smoke 同步使用其官方镜像仓库的 checkout 7.0.1（固定相同 commit SHA）。
该 Action 使用 Node 24；自托管 Forgejo runner 及其执行镜像必须支持此 JavaScript runtime。
本地静态检查不能替代该自托管 runner 或 GitHub Actions 的实际执行验收。

Web E2E 脚本创建临时 SQLite、上传和备份目录，在该目录中以显式环境启动真实 Go 后端，
避免读取仓库配置或继承宿主 `LEDGER_*` 设置；结束时回收该后端与临时数据。
可传入 `--project=chromium` 或测试文件名缩小调试范围。
设置 `LEDGER_WEB_VISUAL_BASELINE_DIR` 后，兼容测试额外比较该目录下的平台基线截图；
日常 CI 使用几何、颜色、交互断言并输出截图，不跨操作系统复用像素基线。

## Flutter

CI 与本项目当前验证基线使用 Flutter 3.35.7（Dart 3.9.2）。使用其他 SDK 前，先确认 `pubspec.yaml` 的 SDK 约束和锁定依赖仍可解析。

    cd mobile
    flutter pub get
    flutter analyze
    flutter test
    flutter run

常用平台：

    flutter run -d emulator-5554
    flutter run -d C417531C-3ABC-4357-880C-4ECC9A1752D1
    flutter run -d macos

## 真实后端验证

    ./scripts/verify-mobile-e2e.sh

脚本会创建临时 SQLite 后端，完成认证、账户、交易新增/编辑/删除和余额校验。Android 模拟器通过 10.0.2.2 访问宿主机，iOS Simulator 和 flutter-tester 使用 127.0.0.1。

## UI 截图测试

    cd mobile
    flutter test -d flutter-tester integration_test/premium_screens_smoke_test.dart

截图测试覆盖浅色/深色主题、首页、交易、账户、报表、家庭、AI、数据管理、设备授权和设置页。
