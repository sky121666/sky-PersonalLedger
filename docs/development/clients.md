# 客户端开发

## Web

    cd web
    corepack pnpm@10.32.1 install --frozen-lockfile
    corepack pnpm@10.32.1 dev

Web API 使用同源 /api/v1；Vite 开发服务器把 /api 代理到 http://localhost:8080。

## Flutter

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

