# v1.0.8 运行截图证据

截图来自同一组隔离账本数据：

- 数据库：临时 SQLite；
- 账户：现金、银行卡、支付宝、微信；
- 交易：工资收入、工作日午餐、家庭采购；
- 时间：2026 年 8 月；
- 数据不来自真实用户。

## Web

| 文件 | 运行环境 | 内容 |
| --- | --- | --- |
| web-login-runtime.jpg | Go 后端 + Web dist | 登录页 |
| web-home-runtime.jpg | Go 后端 + Web dist | 已登录首页 |
| web-transactions-runtime.jpg | Go 后端 + Web dist | 账单明细 |
| web-quick-entry-runtime.jpg | Go 后端 + Web dist | 快速记账弹窗 |

## Android

| 文件 | 运行环境 | 内容 |
| --- | --- | --- |
| android-home-runtime.png | Android 14/API 35 模拟器 | 已登录首页 |

Android 真机曾成功构建 debug APK，但安装被系统返回 INSTALL_FAILED_USER_RESTRICTED，因此没有把真机当作本版本截图证据。

## iOS

| 文件 | 运行环境 | 内容 |
| --- | --- | --- |
| ios-home-runtime.png | iPhone 17 Simulator / iOS 26.4 | 已登录首页 |

iOS 截图是模拟器证据，不代表实体 iPhone 或 App Store 分发包。

## 生成方式

Web：

    cd web
    pnpm build
    cd ..
    ./scripts/verify-web-e2e.sh

Flutter UI smoke：

    cd mobile
    flutter test -d flutter-tester integration_test/premium_screens_smoke_test.dart

真实客户端运行截图使用自动化测试账号和隔离本地后端，测试密码不进入仓库。

