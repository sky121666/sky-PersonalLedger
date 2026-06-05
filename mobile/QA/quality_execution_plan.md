# 质量与适配执行方案（V2）

## 目标（验收标准）
- 每个可见界面静态评分 >= 95（含 27 个页面）。
- 页面信息架构保持高效、实用、界面高级但不喧宾夺主（减少重复文案与重复入口）。
- 模拟器性能目标达成：
  - 首屏可交互时间 <= 3000ms
  - 核心交互 P99 <= 180ms
  - 长列表平均 FPS >= 57（120Hz 机型目标）

## 当前静态状态（可核验）
- 质量扫描：通过
  - 命令：`cd mobile && HOME=/private/tmp ./QA/run_ui_quality_gate.sh`
  - 最新报告：`mobile/QA/quality_audit_latest.md`
  - 最新报告：`mobile/QA/quality_audit_latest.json`（27页面，污染命中0）
  - 页面数：27，污染命中：0，最低分：100，均通过 95+。
- 路由闭环：通过
  - 命令：`cd mobile && node QA/route_quality_matrix.js`
  - 26/26 路由闭环 PASS，最低路由分：100。
- 回归与静态校验通过：
  - `cd mobile && HOME=/private/tmp flutter test -r compact`
  - `cd mobile && HOME=/private/tmp flutter analyze`
  - `cd mobile && HOME=/private/tmp ./QA/run_ui_quality_gate.sh`（包含污染与洁净分数）

### 最新达成快照（2026-06-04）
- 执行入口：`cd mobile && HOME=/private/tmp ./QA/run_ui_quality_gate.sh`
- 扫描摘要：
  - 页面总数：27
  - 触发污染：0
  - 最低污染分：100
  - 静态清洁度平均分：100
  - 路由映射覆盖：26 / 26
  - 结论：所有路由与页面均满足 ≥95 分（当前阈值 95）。
- 关键风险项：无。

### 目标达成定义（本次可交付）
1. 每个界面得分 >= 95：是（当前 27/27 均为 100）。
2. 不重构现有功能前提下完成“可测性优先”：所有测试已去除脆弱文案定位。
3. UI 污染与噪声控制：`mobile/test/ui_pollution_guard_test.dart` 与脚本闸门全部通过。
4. 模拟器运行时适配闭环完成后再认定“高效+实用+优美”目标完全达成：
   - 首屏可交互时间 <= 3000ms
   - 滚动体验 P99 响应 <= 180ms
   - 长列表 FPS P95 >= 57（120Hz 目标）

## 模拟器适配闭环（当前阻塞）
- 当前阻塞点：`adb devices -l` 无在线设备；`flutter devices` 无 Android 模拟器目标（iOS dev 服务也有连接异常）。
- 处理方式：
  - Android：`cd mobile && HOME=/private/tmp ANDROID_PREFER_EMULATOR=1 ./QA/android_install.sh`
  - Android 运行时采样：`cd mobile && HOME=/private/tmp ANDROID_PREFER_EMULATOR=1 ./QA/run_android_runtime_gate.sh`
- 如果出现“安装/运行无输出”卡住，先执行：
  - `./QA/check_device_readiness.sh`
  - `adb kill-server && adb start-server && adb devices -l`
  - 设备端确认 USB 调试授权弹窗，必要时重插线/切换 USB 模式。
- 有设备后再补关键页面（记一笔、借贷、交易列表、首页）FPS/交互样本。

## 安装链路优化（已落地）
- 目标：减少“未产出 APK 即阻塞安装”的摩擦。
- 已执行：`QA/android_install.sh`
  - 在未检测到 APK 时尝试自动构建 `flutter build apk --debug`，并使用隔离环境变量（`HOME=/tmp/sky-personalledger` 等）。
  - 保持与现有 `SKY_LEDGER_TMP_ROOT`/`GRADLE_USER_HOME` 兼容。
  - 增补执行期输出：`android_install.sh` 与 `run_android_runtime_gate.sh` 在超时等待期间每 10~15 秒输出一次进度与最新日志，降低“假卡顿”误判。

- 报告索引统一：补齐 `mobile/QA/quality_audit_latest.json` 快速快照（脚本已更新为每次闸门执行后自动同步）。

## 模拟器性能验收与下一步节奏
1. 先跑静态闸门：`run_ui_quality_gate.sh`。
2. 代码变更后补 `ui_pollution_guard_test.dart` 与相关页面测试。
3. 启动 Android 模拟器后先跑 `android_install.sh`，确认安装链路。
4. 接着跑 `run_android_runtime_gate.sh`（脚本会采集：
   - 首页首帧时间
   - 关键路由截图
   - Android `dumpsys gfxinfo` 帧统计
   - 交易列表与借贷列表滚动稳定性样本
   - 记一笔表单与更多选项交互样本）
5. `run_android_runtime_gate.sh` 产出结果补到：
   - `mobile/QA/quality_audit_latest.md` 与 `mobile/QA/quality_audit_latest.json`
   - `mobile/QA/route_quality_check_latest.md` 与 `mobile/QA/route_quality_check_latest.json`
6. 如出现“启动无响应/安装后卡顿”：
   - `./QA/check_device_readiness.sh`
   - `adb kill-server && adb start-server && adb devices -l`
   - 仅保留安卓模拟器链路：检查并重启 Android Emulator（清理 AVD 进程、确认 emulator-* 在线）后再复测
   - 复测期间保留 `run_android_runtime_gate.sh` 的 runtime report 和系统日志路径
7. 关闭阻塞后复盘评分闭环：静态分 + 路由分 + 运行时分必须同时达标。

## 一致性与风险管理
- 不以“看起来好看”替代指标：每次提交前至少保留以下最小闭环文件：
  - `mobile/QA/quality_audit_*.json`
  - `mobile/QA/route_quality_check_*.json`
  - `mobile/QA/quality_scores_latest_check.json`
  - `run_android_runtime_gate.sh` runtime report（有设备后）
  - `mobile/QA/runtime/gfxinfo/*.txt`
- 若运行时出现回归（掉帧/输入延迟提升），按优先级：
  1) 移除非关键动画与阴影层级（先恢复性能）
  2) 减少首屏列表/表单初始并发加载
  3) 优化重建开销（缓存、`const` 化、减少重复计算）

## 执行节奏（每次迭代）
1. 先跑静态闸门：`run_ui_quality_gate.sh`。
2. 代码变更后补 `ui_pollution_guard_test.dart` 与相关页面测试。
3. 启动 Android 模拟器后再跑 `run_android_runtime_gate.sh`。
4. 每次闭环形成报告后更新：
  - `mobile/QA/quality_audit_latest.md` 与 `mobile/QA/quality_audit_latest.json`
  - `mobile/QA/route_quality_check_latest.md` 与 `mobile/QA/route_quality_check_latest.json`
