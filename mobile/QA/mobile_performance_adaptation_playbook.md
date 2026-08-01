# 手机端适配与性能验收手册（面向 95+ 目标）

## 1. 目的
- 保证界面质量评分达标（>=95）后，覆盖真实设备的适配与性能闭环。
- 以“高效 + 实用 + 美观”为优先：去掉冗余文案与噪点，保留关键操作的高频可达性。

## 2. Android 安装与验收

### 2.1 设备准备
```bash
adb devices -l
```
- 目标：看到 `device` 状态。
- 模拟器链路优先：
  - 未启动 Android Emulator 时，请先启动并确认 `adb devices -l` 中出现 `emulator-*`。

### 2.2 安装与链路运行
```bash
cd /Users/sky/项目/sky-PersonalLedger/mobile
HOME=/private/tmp FLUTTER_SUPPRESS_ANALYTICS=true DART_SUPPRESS_ANALYTICS=true ANDROID_PREFER_EMULATOR=1 ./QA/android_install.sh
HOME=/private/tmp FLUTTER_SUPPRESS_ANALYTICS=true DART_SUPPRESS_ANALYTICS=true ANDROID_PREFER_EMULATOR=1 ./QA/run_android_runtime_gate.sh
```
- `run_android_runtime_gate.sh` 现已优先采集 Android 系统级 `dumpsys gfxinfo` 帧统计，不再只依赖 Flutter timeline。
- 关键热区的人工复测路径应由测试者执行，路由路径与日志会落在 `mobile/QA/runtime/`，用于后续对比。

### 2.3 模拟器性能验收（建议）
- 进入主要路径（记一笔、交易列表、预算/统计）快速 1 分钟操作
- 关注：
  - 下拉/点击有无明显卡顿
  - 列表滚动是否稳定
  - 主要按钮（尤其记一笔）误触率是否降低

## 3. iOS 侧适配（如需）
```bash
HOME=/private/tmp FLUTTER_SUPPRESS_ANALYTICS=true DART_SUPPRESS_ANALYTICS=true /private/tmp/sky-personalledger-flutter-sdk/flutter/bin/flutter devices
```
- 当前环境在 `devicectl` 有权限/超时波动，建议先确保 macOS 与 Xcode 连接服务稳定后再复测。

## 4. 当前已完成的质量证据
- 质量闸门：`./QA/quality_audit_latest.md`
- 路由闭环：`./QA/route_quality_check_latest.md`
- 本地快照：`./QA/quality_alignment_snapshot.md`
- 当前门禁结论：静态评分、清洁度、路由闭环全部通过；设备链路待安卓模拟器复测。
