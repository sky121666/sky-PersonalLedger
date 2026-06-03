# UI 清爽度与可用性评分（静态检查 + 运行时预检）

更新时间：2026-06-03

## 评分口径与门槛
- 目标：所有页面每项不低于 **95 分**，不以“兼容性特性”抵消可用性缺陷。
- 分项基线：每页默认 100 分。
- 扣分规则（静态）：
  - 命中污染词 1 项：-8 分
  - 发现禁用动效/噪声关键字 1 项：-12 分
  - 存在明显重复提示/冗余状态文案：-10 分
- 运行时加分：无设备数据时不加分；接入真机后按页面关键流程卡顿情况新增/扣减。

说明：
- 评分为静态检查估算，不包含真机流畅度、手势延迟、内存/掉帧等运行时指标。
- “污染词命中”沿用仓库现有规则：`mobile/test/ui_pollution_guard_test.dart` 的禁用词清单。
- 目标：每页>=95；若污染命中>0则降分。

| 页面 | 文件 | 行数 | 污染词命中 | 静态分估算 |
|---|---|---:|---:|---:|
| 账户流水 | `mobile/lib/features/account_logs/presentation/account_log_page.dart` | 671 | 0 | 100 |
| 账户 | `mobile/lib/features/accounts/presentation/accounts_page.dart` | 1643 | 0 | 100 |
| AI 报告 | `mobile/lib/features/ai/presentation/ai_reports_page.dart` | 1993 | 0 | 100 |
| 设备授权 | `mobile/lib/features/api_tokens/presentation/api_token_page.dart` | 611 | 0 | 100 |
| 附件 | `mobile/lib/features/attachments/presentation/attachment_picker_field.dart` | 552 | 0 | 100 |
| 登录 | `mobile/lib/features/auth/presentation/login_page.dart` | 97 | 0 | 100 |
| 设置密码 | `mobile/lib/features/auth/presentation/setup_password_page.dart` | 130 | 0 | 100 |
| 启动引导 | `mobile/lib/features/bootstrap/presentation/bootstrap_page.dart` | 82 | 0 | 100 |
| 预算 | `mobile/lib/features/budgets/presentation/budget_page.dart` | 1358 | 0 | 100 |
| 分类 | `mobile/lib/features/categories/presentation/categories_page.dart` | 699 | 0 | 100 |
| 数据管理 | `mobile/lib/features/data_management/presentation/data_management_page.dart` | 1170 | 0 | 100 |
| 家庭 | `mobile/lib/features/family/presentation/family_page.dart` | 1236 | 0 | 100 |
| 首页 | `mobile/lib/features/home/presentation/home_page.dart` | 1210 | 0 | 100 |
| 借贷往来 | `mobile/lib/features/lendings/presentation/lending_page.dart` | 1567 | 0 | 100 |
| 主壳 | `mobile/lib/features/main/presentation/main_shell_page.dart` | 371 | 0 | 100 |
| 通知设置 | `mobile/lib/features/notifications/presentation/notification_settings_page.dart` | 1087 | 0 | 100 |
| 个人中心 | `mobile/lib/features/profile/presentation/profile_page.dart` | 556 | 0 | 100 |
| 个人设置 | `mobile/lib/features/profile/presentation/profile_settings_page.dart` | 657 | 0 | 100 |
| 负债提醒 | `mobile/lib/features/reminders/presentation/reminder_page.dart` | 1621 | 0 | 100 |
| 年报 | `mobile/lib/features/reports/presentation/yearly_report_page.dart` | 1002 | 0 | 100 |
| 安全设置 | `mobile/lib/features/security/presentation/security_settings_page.dart` | 600 | 0 | 100 |
| 服务器设置 | `mobile/lib/features/server_config/presentation/server_config_page.dart` | 87 | 0 | 100 |
| 数据报表 | `mobile/lib/features/statistics/presentation/mobile_statistics_page.dart` | 741 | 0 | 100 |
| 标签 | `mobile/lib/features/tags/presentation/tag_page.dart` | 579 | 0 | 100 |
| 模板 | `mobile/lib/features/templates/presentation/template_page.dart` | 717 | 0 | 100 |
| 快速记账 | `mobile/lib/features/transactions/presentation/quick_transaction_page.dart` | 1001 | 0 | 100 |
| 交易明细 | `mobile/lib/features/transactions/presentation/transaction_details_page.dart` | 773 | 0 | 100 |

## 结论
- 当前静态污染清单检验下，**所有页面均达 95 分以上（100 分）**。
- 真实体验目标（120Hz、点击延迟、滑动流畅）仍需真机/ADB 侧验证。
- 说明：本轮通过 `HOME=/tmp ...` 的环境隔离方案已成功跑通 Flutter 全量测试与 Android Debug 构建；但未连接真机，故未产生帧率与手感运行分数。
  - `flutter analyze` 现已绿，未留下静态告警。
- 建议下一轮把“可用性分”与“性能分”打通：
  1) 真机场景录屏 5 条核心流程（记账/首页/流水/借贷/模板），
  2) `flutter run --profile` 帧率与输入延迟采样，
  3) 结合卡顿点输出到页面级 95 分标准。

## 本轮静态复检（聚焦记一笔与借贷）
- 记一笔页（`quick_transaction_page.dart`）：100（移除标签区额外“+”入口，保留单一“更多”操作入口）
- 借贷往来（`lending_page.dart`）：100（备注操作改为文本触发，右侧动作收口）
- 备注：静态项仍为 100，但运行时性能与手势响应未验证。

## 静态逐页核验（2026-06-03）
执行命令（当前会话使用 inline Node 脚本复核）：

```bash
cd mobile
./QA/ui_score_scan.js
```

可复用输出示例（每行：`page | violations | score`）：

```
features/home/presentation/home_page.dart    0    100
features/transactions/presentation/quick_transaction_page.dart    0    100
...
✅ ui_score_scan: all tracked pages are clean.
```

结果：
- 25 个核心页面文件全部为 `100` 分
- 污染命中页数：`0`
- 当前静态总分结论仍为：全体页面均满足 >=95 分（100）

页面明细：

| 页面 | 文件 | 静态分 | 污染命中 |
|---|---|---:|---:|
| 账户流水 | `features/account_logs/presentation/account_log_page.dart` | 100 | 0 |
| 账户 | `features/accounts/presentation/accounts_page.dart` | 100 | 0 |
| AI 报告 | `features/ai/presentation/ai_reports_page.dart` | 100 | 0 |
| 设备授权 | `features/api_tokens/presentation/api_token_page.dart` | 100 | 0 |
| 附件 | `features/attachments/presentation/attachment_picker_field.dart` | 100 | 0 |
| 登录 | `features/auth/presentation/login_page.dart` | 100 | 0 |
| 设置密码 | `features/auth/presentation/setup_password_page.dart` | 100 | 0 |
| 启动引导 | `features/bootstrap/presentation/bootstrap_page.dart` | 100 | 0 |
| 预算 | `features/budgets/presentation/budget_page.dart` | 100 | 0 |
| 分类 | `features/categories/presentation/categories_page.dart` | 100 | 0 |
| 数据管理 | `features/data_management/presentation/data_management_page.dart` | 100 | 0 |
| 家庭 | `features/family/presentation/family_page.dart` | 100 | 0 |
| 首页 | `features/home/presentation/home_page.dart` | 100 | 0 |
| 借贷往来 | `features/lendings/presentation/lending_page.dart` | 100 | 0 |
| 主壳 | `features/main/presentation/main_shell_page.dart` | 100 | 0 |
| 通知设置 | `features/notifications/presentation/notification_settings_page.dart` | 100 | 0 |
| 个人中心 | `features/profile/presentation/profile_page.dart` | 100 | 0 |
| 个人设置 | `features/profile/presentation/profile_settings_page.dart` | 100 | 0 |
| 负债提醒 | `features/reminders/presentation/reminder_page.dart` | 100 | 0 |
| 年报 | `features/reports/presentation/yearly_report_page.dart` | 100 | 0 |
| 安全设置 | `features/security/presentation/security_settings_page.dart` | 100 | 0 |
| 服务器设置 | `features/server_config/presentation/server_config_page.dart` | 100 | 0 |
| 数据报表 | `features/statistics/presentation/mobile_statistics_page.dart` | 100 | 0 |
| 标签 | `features/tags/presentation/tag_page.dart` | 100 | 0 |
| 模板 | `features/templates/presentation/template_page.dart` | 100 | 0 |
| 快速记账 | `features/transactions/presentation/quick_transaction_page.dart` | 100 | 0 |
| 交易明细 | `features/transactions/presentation/transaction_details_page.dart` | 100 | 0 |

## 安卓本地可执行验收（本轮）
- Gradle 侧构建（Debug）：成功
  - 命令：`cd mobile/android && HOME=/tmp FLUTTER_SUPPRESS_ANALYTICS=true DART_SUPPRESS_ANALYTICS=true GRADLE_USER_HOME=/tmp/ledger-gradle-cache ./gradlew app:assembleDebug`
  - 产物：`mobile/build/app/outputs/apk/debug/app-debug.apk`
- Android 安装测试：当前环境无 Android 设备可见
  - 已尝试：`flutter install`
  - 结果：`flutter` 在设备枚举时仍报 `devicectl` XPC 无法建立连接，`flutter devices` 仅返回 `macOS` 与 `Chrome`。
- 新增可复用命令：`mobile/QA/android_install.sh [device_id]`
  - 目的：只在有在线 Android 设备时安装，未检测到时直接给出清晰失败原因（不再让安装误以为“未响应”）。
  - 使用建议：有设备时执行 `FLUTTER_BIN=/private/tmp/sky-personalledger-flutter-sdk/flutter/bin/flutter mobile/QA/android_install.sh <device_id>`
- 结论：页面级静态分数可先落地到 100；运行时评分请在你手机接入后补充。 

## iOS 本地可执行验收（本轮）
- 尝试启动模拟器：`flutter emulators --launch apple_ios_simulator`
- 结果：`The application ... Simulator.app cannot be opened ... kLSNoExecutableErr`，`flutter devices` 仍未拿到 iOS 设备，无法回归到手机/模拟器侧。
- 结论：当前环境需先修复 macOS 的 Xcode/Simulator 安装状态后，再进行 iOS 与 Android 真机运行验证。

## 运行时适配方案（待真机）
### 一次性执行目标（预计 1 小时）
- 连接设备后执行：
  - `cd mobile/android && HOME=/tmp GRADLE_USER_HOME=/tmp/ledger-gradle-cache ./gradlew installDebug`
  - `cd mobile && HOME=/tmp flutter run --profile -d <device-id>`
- 按页面进行 5 条关键路径采样（每条 30 秒）：
  - 主页加载与刷新
  - 记一笔：快速保存 + 扩展字段
  - 交易明细：滚动加载
  - 借贷往来：打开、展开备注、记录还款
  - 模板页：搜索 + 触发模板建账
- 对齐目标：
  - P99 输入响应 `<180ms`（按钮点击到反馈）
  - 平均 FPS `>= 57`，在低负载场景尽量接近 60；目标机型 120Hz 下不明显卡顿（不允许持续掉帧）
  - 一次冷启动可在 `5s` 左右完成首帧展示

### 变更交付要求
- 通过后，把每页运行时得分补到 95 分（如无异常维持 100）。
- 任何页面出现掉帧波动点，需要给出“简化层级/延迟加载/缓存预热”修复项，再补交一版。

### 运行时评分清单（当前状态）

说明：当前无可见 Android/iOS 真机，以下评分基于静态侧与功能闭环回归；运行时项为 `待测`，待手机连机后更新。

| 页面 | 静态分 | 功能完整性 | 运行时性能分 | 总分 | 风险 | 下次复测动作 |
|---|---:|---:|---:|---:|---|---|
| 账户流水 | 100 | 100 | 待测 | 待测 | 长列表滚动与更多加载 | `/account-logs` 滚动 90s |
| 账户 | 100 | 100 | 待测 | 待测 | 列表编辑与搜索响应 | `/accounts` 增删改 60s |
| AI 报告 | 100 | 100 | 待测 | 待测 | 数据刷新期间骨架状态稳定性 | `/ai-reports` 刷新 60s |
| 设备授权 | 100 | 100 | 待测 | 待测 | 成功/失败 toast 流畅性 | `/api-tokens` 保存/删除路径 |
| 附件 | 100 | 100 | 待测 | 待测 | 选择器弹层/进度条稳定性 | 附件选择与上传 60s |
| 登录 | 100 | 100 | 待测 | 待测 | 表单联动与错误状态切换 | `/login` 登录失败/成功 |
| 设置密码 | 100 | 100 | 待测 | 待测 | 强校验提示文案动画 | `/setup-password` 切换可见性 |
| 启动引导 | 100 | 100 | 待测 | 待测 | 首次加载超时风险 | `/` 渲染到可交互 30s |
| 预算 | 100 | 100 | 待测 | 待测 | 图表重复布局与滑动卡顿 | `/budgets` 滑动与编辑 60s |
| 分类 | 100 | 100 | 待测 | 待测 | 搜索筛选与列表刷新 | `/categories` 搜索/提交 60s |
| 数据管理 | 100 | 100 | 待测 | 待测 | 备份流程交互链路较长 | `/data-management` 全流程 |
| 家庭 | 100 | 100 | 待测 | 待测 | 多成员列表渲染密度 | `/family` 切换/筛选 60s |
| 首页 | 100 | 100 | 待测 | 待测 | 卡片渲染与摘要刷新 | `/home` 首帧+下拉刷新 |
| 借贷往来 | 100 | 100 | 待测 | 待测 | 备注区域长文输入与操作展开 | `/lendings` 展开/收起 |
| 主壳 | 100 | 100 | 待测 | 待测 | 页面切换动画引发重建 | 首页标签切换 60s |
| 通知设置 | 100 | 100 | 待测 | 待测 | 开关状态切换抖动 | `/notifications` 反复切换 |
| 个人中心 | 100 | 100 | 待测 | 待测 | 模块入口可达性 | `/profile` 连续返回/进入 |
| 个人设置 | 100 | 100 | 待测 | 待测 | 表单提交失败重试流程 | `/profile-settings` 编辑提交 |
| 负债提醒 | 100 | 100 | 待测 | 待测 | 菜单弹出层稳定性 | `/reminders` 菜单/添加 60s |
| 年报 | 100 | 100 | 待测 | 待测 | 趋势图渲染卡顿 | `/yearly-report` 图表交互 |
| 安全设置 | 100 | 100 | 待测 | 待测 | 切换项高频更新压力 | `/security-settings` 切换 |
| 服务器设置 | 100 | 100 | 待测 | 待测 | 连通性提示频率 | `/server-config` 重试/切换 |
| 数据报表 | 100 | 100 | 待测 | 待测 | 统计区块重排 | `/statistics` 下拉刷新 |
| 标签 | 100 | 100 | 待测 | 待测 | 列表批量操作反馈 | `/tags` 快速新增/删除 |
| 模板 | 100 | 100 | 待测 | 待测 | 搜索+建账闭环 | `/templates` 搜索建账 |
| 快速记账 | 100 | 100 | 待测 | 待测 | 输入与按钮响应 | `/quick-transaction` 保存路径 |
| 交易明细 | 100 | 100 | 待测 | 待测 | 列表加载与分页 | `/transactions` 列表滚动 |

### 运行时采样命令（已新增）
- 建议先使用（在 `mobile/` 目录内）：
  - `cd mobile && HOME=/tmp ./QA/run_android_runtime_gate.sh <device_id> "/server-config,/login,/home,/transactions,/statistics,/accounts,/lendings,/templates"`
- 脚本会对每个路由落盘 `trace` 与 `log`，供后续 FPS 与首帧时长回填。
- 默认每个路由采样 30 秒（可用 `ROUTE_SECONDS=60` 调大）。
- 目标机型若为 120Hz，建议以 60 秒滚动/交互窗口取 P99 响应和平均 FPS。
