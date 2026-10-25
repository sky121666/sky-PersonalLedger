# Web 小组件 Task 6 验证交付

日期：2026-10-20。状态：实现、独立审查整改及隔离自动化验收完成；物理设备与历史最低浏览器的未验证边界见后文。

## 范围与隔离

- 原仓库：`sky-PersonalLedger`，`main`，HEAD `b7209927e44eb8f683730a975d1889a912322f8a`。
- Task 6 基线按 `git status --porcelain=v1 -uall` 记录 268 项状态、979 个现存非忽略普通文件；暂存为 0。该统计展开了未跟踪目录，与旧记录按目录折叠的项目数不能直接比较。
- 源码及当前 WIP 的独立副本：`/var/folders/l6/smy8mmk15898tpm0vddrbyt00000gn/T/sky-widget-gate0-20261020-081144-8308/source-task6`。
- 浏览器由现有 `scripts/verify-web-e2e.sh` 启动，每次使用新的临时 SQLite、附件、备份和配置目录；后端以 `env -i` 启动。没有连接既有预览、模拟账本或正式服务。
- 沿用 Node 26.12.0、pnpm 12.11.2 和现有锁文件；未改依赖、后端、API、schema、认证规则、CI、Docker、历史数据或备份格式。
- 原复制环境遗留的 Gate 0/debug 测试不属于仓库测试集合。首次广泛运行发现后已中断，删除的仅为隔离副本中的 8 个探针文件；记录在 `task6-isolation-cleanup.json`。最终回归只收集原仓库的 17 个 E2E 文件。进一步核对发现旧副本还遗留配置/数据目录（来源未核验）和一个未使用的 TypeScript 探针；仅将本轮临时副本中的这些对象移出，未打开/解析内容，也未作为测试数据。测试服务始终由显式临时路径隔离。移出后重新构建，全部 dist 文件的 SHA-256 与浏览器测试时完全一致，记录为 `task6-inherited-exclusion.json`、`task6-tested-build-hashes.json`。

证据根目录：

`/var/folders/l6/smy8mmk15898tpm0vddrbyt00000gn/T/sky-widget-gate0-20261020-081144-8308/evidence`

## 本轮发现与修复

| 问题 | 实际影响 | 修复及回归证据 |
| --- | --- | --- |
| 提醒错误被当成空状态 | 读取失败时出现“暂无还款提醒” | 保留未加载、失败、成功为空的差别；`task6-reminder-red.log`、`task6-unloaded-red.log` |
| 账户尚未加载被当成不可用 | profile 先到、账户慢响应时误报账户失效 | 只有成功账户列表确认缺失才显示不可用；账户网络失败保持错误状态 |
| 分类预算超支文案使用总预算余额 | 总预算未超支时把已超支分类写成接近上限 | 依据服务端 `OverLimit.percentage` 判断分类告警；`task6-budget-red.log` |
| 无总预算和真实零支出混用 | 未设置总预算显示为正常的零金额预算 | 区分无总预算、已设预算零支出、读取失败；`task6-readmodel-boundaries.log` |
| 可选来源未按实例读取 | 默认首页仍读取家庭/借贷/AI，账户记录与分类预算未接线 | `HomeView` 接入已有 `useHomeOverview`；按实例加载，同账户查询去重；预览无数据请求或付费调用；`task6-optional-red.log` |
| 在途可选刷新被另一组件配置作废 | 刷新中添加组件，已有可选汇总停留旧缓存且可能报告成功 | 按查询 key 复用在途请求，只失效被移除的来源；失效结果不报告成功；`task6-review-red.log` |
| 首页最近交易丢失备注和编辑入口 | 新增交易无法从首页直接辨认/打开 | 恢复备注及普通交易编辑，托管交易继续走受保护的业务入口 |
| 日历明细丢失交易方向 | 相同备注、金额的收入/支出/转账无法区分 | 复用交易展示转换，显式类型、正负号和中性转账；第二页及金额隐藏一起回归 |
| 网格回填前序空位 | 视觉顺序与源/键盘顺序不同，上下移可能看似无效 | 使用单调前进的放置游标，默认六组件布局保持；`task6-review-red.log` |
| AI 状态及 JSON 未转换 | 失败/生成中报告被写为“报告已生成”，完成内容显示原始 JSON | 显示真实状态，提取摘要/标题并兼容旧纯文本；隐私隐藏继续有效 |
| 编辑期间丢弃导航事件 | 完成或取消编辑后导航 revision 陈旧，下次钉住失败 | home 草稿与 navigation 独立同步；两种结束路径均验证；`task6-navigation-sync-red.log` |
| 长金额、文字放大溢出及详情触控目标不足 | 320–1440px 下金额跨出卡片，详情按钮过小 | 允许完整换行和内容增高，详情目标 44px，深色元信息对比修正；`task6-visual-red.log`、`task6-contrast-red.log` |
| 手机提示关闭按钮遮住页头操作 | WebKit 账户归档流程误点/阻挡页头切换 | 手机提示移到底部安全区上方，并限制栈高度；新增几何遮挡检查；`task6-calendar-toast-red.log` |
| 旧测试定位/等待条件失效 | 误点全局 header、查找旧日历入口，或把表单初始化禁用误当成恢复完成 | 范围限定到业务 main，沿新组件入口走查，延迟响应测试等待真正恢复状态；保留余额、请求键、CRUD、分页、附件和恢复断言 |

独立审查使用冻结目录 `review-task6`，源码哈希清单为 `task6-review-snapshot.json`；该快照未被主代理修改。审查发现 3 项 Important、3 项 Minor，另指出迟到 profile 测试原先没有真正发出请求。本轮将虚假 AI 成功、视觉顺序和导航保存失败按实际影响纳入修复，不留下这些功能缺陷；迟到 profile 用例以匹配代次启动并确认请求已发出。

未进行第二轮独立审查。审查后的修复通过新增失败用例、转绿和完整回归核对，独立审查与自动化回归的证据分别保留。

## 修改文件清单与原因

| 文件 | 原因 |
| --- | --- |
| `web/src/views/HomeView.vue`、`web/src/composables/useHomeOverview.ts` | 接线共享读取、按需来源、session 保护、日期交易方向和普通交易编辑入口 |
| `web/src/components/home/readModels.ts`、`HomeWidget.vue` | 区分未知/错误/空，分类告警、账户记录、分类预算和 AI 状态转换 |
| `web/src/components/home/widgets/AccountWidget.vue`、`BudgetWidget.vue`、`ReminderWidget.vue`、`TransactionsWidget.vue` | 呈现已接线数据、真实状态、摘要与受保护的交易操作 |
| `web/src/components/home/layout.ts`、`web/src/stores/workspacePreferences.ts` | 保持视觉顺序、跨标签导航独立更新 |
| `web/src/assets/main.css`、`workspace.css`、`web/src/components/Toast.vue` | 去重复样式、长金额/深色可读性/44px 目标及提示遮挡 |
| `web/src/components/home/layout.test.ts`、`readModels.test.ts`、`web/src/composables/useHomeOverview.test.ts`、`web/src/stores/workspacePreferences.test.ts` | 栅格顺序、状态与告警、在途刷新、身份及跨标签回归 |
| `web/src/views/auditReadModels.test.ts`、`loadingIdentity.test.ts` | 保留既有 VM 业务测试，提供新增读取边界所需 mock，不改原业务断言 |
| `web/e2e/home-widgets-readmodels.e2e.ts`、`audit-repairs.e2e.ts` | 五种宽度、200% 文字、对比、触控目标、性能、可选详情、101 条日期分页和隐私 |
| `web/e2e/ledger-flow.e2e.ts`、`management-flows.e2e.ts`、`reliability-state.e2e.ts`、`transaction-retry.e2e.ts`、`web-three-audit.e2e.ts` | 原功能端到端兼容、明确状态等待、避免误点新 shell，增加提示遮挡断言 |
| 本报告、readiness、实施计划、设计规格、技术决策 | 区分历史准备状态与当前证据，记录取舍及未验证范围 |
| `docs/design/home-widgets/task6/*.png`（6 张） | 最终版本的实际视口截图，全部为合成数据 |

上述相邻文件名的完整路径以 `task6-sync-files.json` 为准。没有依赖、后端、CI 或 Docker 文件进入本轮同步清单。

## 最终检查

| 检查 | 实际结果 |
| --- | --- |
| Vitest | 40 文件、360 项通过 |
| 应用及测试 TypeScript 检查、Vite 生产构建 | 通过 |
| brace / 附件延迟删除保护 | 通过 |
| 包体硬门槛 | 通过 |
| 全部 E2E | Chromium / Firefox / WebKit 各 156 项，共 468 通过；0 失败、0 跳过、0 flaky；脚本退出 0 |

日志：`task6-review-final-unit.log`、`task6-review-final-build.log`、`task6-review-final-brace.log`、`task6-review-final-attachments.log`、`task6-review-final-bundle.log`、`task6-e2e-final.log`、`task6-e2e-final.json`。

中间完整回归曾为 460 通过、8 失败；包括尚未启用 AI 的旧用例、带金额日历日期的失效定位、过早释放延迟响应及手机提示遮挡。该结果保留在 `task6-e2e-full.log/json`，不作为最终通过依据。

## 规格覆盖

| 规格 | 可检查证据 |
| --- | --- |
| 11 种 renderer、默认六项、多个账户与重复拦截、空首页 | model/renderer/store 单测；`home-widgets.e2e.ts` |
| 取消/完成/撤销、两端共享集合与独立顺序/尺寸 | preferences/store 单测及真实编辑 UI 回读 |
| 损坏、未来版本、拒绝存储、跨标签冲突 | 版本化存储和编辑测试；失败不冒充保存 |
| 未知身份不读偏好、身份切换及迟到响应 | store/profile 真实在途单测、导航 E2E、读模型 sessionGeneration 测试 |
| 账户加载中/读取失败/成功确认缺失 | readModels 单测和浏览器可配置账户测试 |
| 预算无总额/零支出/超支及分类明细 | readModels 单测；`home-widgets-readmodels`、`populated-layout` |
| 提醒无虚构金额与口径、转账中性 | renderer/readModels 与浏览器展示检查 |
| 日历选日、101 条分页、金额隐私、刷新 | `audit-repairs`、`home-widgets`、query identity 单测 |
| 320/390/768/1280/1440px | 导航及首页五宽度套件；长金额/名称、浅深主题 |
| 文字放大 | 将已计算的组件文字字号放大至 200%，保留原精度和金额；没有用 deviceScaleFactor 冒充文字放大 |
| 键盘、减少动态效果、触摸滚动、拖动取消 | navigation/widget/stack 套件；Chromium 原生 CDP 触摸和另外两引擎轻触替代分别记录 |
| 纯色、蓝色玻璃、图标一致、无虚构趋势或未来功能 | 源码和本轮截图；没有使用生成图替代运行页面 |
| 偏好不保存账务内容 | 运行时精确字段校验，只接受组件引用/尺寸/顺序及导航字段；身份未知不读个人 key |

`useHomeOverview` 负责共享核心及可选来源，日历选日及分页仍由 `HomeView` 的既有代次保护逻辑负责。该保守边界避免在最终回归阶段再移动分页契约；月份趋势仍归 `CalendarView`，不重复请求。不同资源不是数据库原子快照。

## 性能与兼容边界

| 指标 | 实测 | 原上限 | 余量 |
| --- | ---: | ---: | ---: |
| 总原始 | 861,048 B | 1,000,000 B | 138,952 B |
| 总 gzip | 268,007 B | 400,000 B | 131,993 B |
| 最大 JS | 184,476 B | 200,000 B | 15,524 B |
| 最大 CSS | 117,038 B | 120,000 B | 2,962 B |
| 入口 HTML | 1,024 B | 20,000 B | 18,976 B |

未提高门槛。去掉重复的首页全局样式，保留统一 `workspace.css`。CSS 余量仍小，后续功能须继续执行预算检查。

本机交互实测，原始数据为 `task6-performance.json`：

| 引擎 | 首页合成数据就绪 | 三次打开画廊的中位数 |
| --- | ---: | ---: |
| Chromium 156.0.8078.4 | 58.0 ms | 33.5 ms |
| Firefox 157.0 | 100.0 ms | 49.0 ms |
| WebKit 27.2 | 77.0 ms | 44.0 ms |

默认首页恰好 5 次共享财务来源 GET，不包含认证、静态资源和其他基础请求；每引擎连续三次打开/切换画廊预览均为 0 次额外数据请求、0 次写请求。浏览器版本由同一安装运行时另行读取，记录为 `task6-browser-versions.json`。

完整 E2E 实测耗时 691,845 ms（约 11.5 分钟），不是应用交互耗时。交互测量使用本机生产构建和合成响应；包括 Playwright 动作/断言开销，只有首页各一次、画廊各三次样本，不是现场 INP、弱网、低端手机或真实账本性能。

构建 target 仍为 `chrome111 / firefox128 / safari16.4`。本轮源码使用 CSS Grid、Pointer Events/capture、ResizeObserver、rAF、matchMedia、原生 dialog、inert 和 localStorage；没有引入 Popover、Anchor Positioning、View Transitions、Web Locks 或新的框架/交互依赖。target 声明与现代引擎测试均不能证明历史最低版本通过。

尚未实测：Safari 16.4/Chrome 111/Firefox 128 的真实历史版本、物理手机、真实系统文字放大、系统屏幕阅读器/辅助键盘、真实安全区设备、跨设备同步和 localStorage 事务级 CAS。模拟触摸、键盘事件和 200% CSS 文字测试不扩大为这些结论。

## 交付与回退

最终运行截图已逐张查看，位于 `docs/design/home-widgets/task6/`：

- [桌面默认首页](../design/home-widgets/task6/01-desktop.png)
- [桌面编辑状态](../design/home-widgets/task6/02-editor.png)
- [手机组件画廊](../design/home-widgets/task6/03-gallery-mobile.png)
- [钉住侧栏](../design/home-widgets/task6/04-pinned-rail.png)
- [手机首页](../design/home-widgets/task6/05-mobile.png)
- [320px 深色与 200% 组件文字](../design/home-widgets/task6/06-text-200-dark.png)

以上为运行页面的当前视口截图；内部滚动区的其余内容由实际滚动及操作断言覆盖。窄屏画廊的真实尺寸预览画布允许横向滚动，不通过缩放金额伪装为实际卡片大小。

工作区保全交付记录：`task6-workspace-before.json`、`task6-workspace-after.json`、`task6-sync-files.json`、`task6-originals/`、`task6.patch`。同步前逐项比对原工作区基线哈希，防止覆盖同期修改；同步后核对受影响文件与隔离验证版本一致，其余既有文件保持原哈希，HEAD 不变、暂存仍为 0。

只同步本轮逐文件增量。原文件备份、同步清单、补丁和前后哈希保留在证据目录；回退须先比较后续修改，只撤回 Task 6 的增量，禁止 reset/整份覆盖工作区。
