# v1.0.9 运行截图证据

本目录截图均由当前 `1.0.9` 源码实际构建和运行后采集。后端使用 `mktemp -d` 创建的临时目录，数据库为临时 SQLite，上传、备份和首次配置文件也都写入该临时目录；未读取仓库中的 `backend/config.yaml`、`backend/data` 或任何 `.env` 文件。

截图数据为合成展示数据，包含现金、银行卡、支付宝、信用卡、房贷、基金账户和 8 笔合成交易，不来自真实用户。运行期间使用的本地测试凭据未写入仓库，也未出现在截图中。

## 截图清单

| 文件 | 实际运行环境 | 分辨率 | 内容 |
| --- | --- | --- | --- |
| `web-home-runtime.jpg` | Go 后端 + Web dist；Playwright Chromium 149 | 1280×720 | Web 已登录首页 |
| `web-transactions-runtime.jpg` | Go 后端 + Web dist；Playwright Chromium 149 | 1280×720 | Web 账单明细 |
| `web-quick-entry-runtime.jpg` | Go 后端 + Web dist；Playwright Chromium 149 | 1280×720 | Web 快速记账弹窗 |
| `android-home-runtime.png` | 临时 Pixel 8 AVD；Android 15 / API 35 | 1080×2400 | Android 已登录首页 |
| `android-quick-entry-runtime.png` | 临时 Pixel 8 AVD；Android 15 / API 35 | 1080×2400 | Android 快速记账底部表单 |
| `ios-home-runtime.png` | 临时 iPhone 17 Simulator；iOS 26.4 | 1206×2622 | iOS 已登录首页 |

Android 和 iOS 图均由同一套 Flutter 源码连接同一个隔离后端后，分别通过 `adb exec-out screencap` 和 `xcrun simctl io ... screenshot` 采集；不是组件测试、设计稿或桌面裁切图。

## 生成链

1. 构建 Web：

       pnpm --dir web build

2. 参考 `scripts/verify-web-e2e.sh` 的隔离方式启动 Go 后端：设置独立端口、临时 SQLite、临时 setup 配置、临时上传/备份目录，并让后端服务 `web/dist`。
3. 使用 `mobile/QA/seed_mobile_showcase_data.sh` 向回环地址写入合成展示数据。账户和 8 笔交易已成功写入；脚本随后在创建提醒时收到 HTTP 409，因此本次不把提醒、借贷和 AI 展示数据记为完整生成成功。
4. Web 使用 Playwright 登录真页，等待登录提示消失后依次采集首页、账单明细和快速记账弹窗。
5. Android 创建临时 API 35 AVD，以 `10.0.2.2` 访问隔离后端，运行当前 Flutter debug 构建，再用 ADB 采集系统屏幕。
6. iOS 创建临时 iPhone 17 Simulator，以 `127.0.0.1` 访问隔离后端，运行当前 Flutter debug 构建，再用 `simctl` 采集系统屏幕。

## 验证

每张图均通过 `file` 确认格式，通过 `sips` 确认像素尺寸，并通过 `stat` 确认文件非空；同时逐张进行了可视检查，未发现真实姓名、账号、令牌、服务器公网地址或其他本地用户数据。

这些截图证明当前源码能在上述本地浏览器和模拟器环境运行，不代表 Android/iOS 实体设备、正式签名包、应用商店分发或生产部署已经验收。
