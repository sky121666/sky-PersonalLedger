# 客户端与验证

## Web

Web 是 Vue 3 + TypeScript + Vite 应用：

    cd web
    pnpm install --frozen-lockfile
    pnpm dev

生产检查：

    pnpm test
    pnpm build
    pnpm verify:bundle
    cd ..
    ./scripts/verify-web-e2e.sh

Web E2E 会启动隔离 Go 后端和临时 SQLite，覆盖登录、错误密码、交易新增/编辑/删除，以及移动视口主导航和快速记账。

## Flutter

Flutter 客户端包含认证、服务器配置、首页、明细、统计、账户、分类、标签、模板、预算、提醒、借贷、家庭、AI、通知、数据管理、设备授权和安全设置等模块。

远程服务地址必须使用 HTTPS。只有回环或私有网段地址可以使用
HTTP，并且必须同时满足平台构建允许明文传输、用户明确确认风险。确认会
绑定到规范化后的完整地址；地址、端口或路径改变后需要重新确认。升级前已保存但
没有确认记录的 HTTP 地址不会自动连接，客户端会先清理会话令牌并要求确认。

    cd mobile
    flutter pub get
    flutter analyze
    flutter test
    flutter run

真实后端 E2E：

    cd ..
    ./scripts/verify-mobile-e2e.sh

## 平台证据

- Android：本次 v1.0.8 采用 API 35 模拟器生成运行截图；USB Android 真机 debug 安装受到设备策略限制。
- iOS：iPhone 17 Simulator 生成运行截图；这是模拟器证据，不等同于实体 iPhone。
- Web：本地 Go 后端 + Web dist 真实登录和账本数据。

开发截图不代表商店发布包，也不替代正式签名和商店审核。
