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

- Android：v1.0.9 采用临时 Pixel 8 API 35 模拟器完成真实后端运行与截图。
- iOS：v1.0.9 采用临时 iPhone 17 / iOS 26.4 Simulator 完成真实后端运行与截图；这不等同于实体 iPhone。
- Web：v1.0.9 使用本地 Go 后端 + Web dist 完成真实登录、账本数据和浏览器截图。

完整证据见 [v1.0.9 运行截图](../screenshots/v1.0.9/README.md)。

开发截图不代表商店发布包，也不替代正式签名和商店审核。
