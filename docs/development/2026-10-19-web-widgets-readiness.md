# Web 小组件开发准备记录

准备记录始于 2026-10-19；截至 2026-10-20 已完成 Gate 0 及 Task 1–6。以下初始准备段落保留历史状态，当前结果见各阶段执行记录与 [Task 6 验证交付](2026-10-20-web-widgets-task6-verification.md)。

## 工作区与约束

- 仓库：`sky-PersonalLedger`；分支 `main`；HEAD `b7209927e44eb8f683730a975d1889a912322f8a`。
- 开始时 214 项未提交状态，0 暂存。原有修改保留；没有提交、推送或分支切换。
- 已记录全部非忽略版本文件的初始内容哈希，检查准备工作没有覆盖既有源码。
- 本次新增设计规格、实施计划、准备记录与五张文档参考图；没有修改业务源码、配置或依赖。
- 最终背景按用户决定为纯色，不采用参考图片的背景曲线。

## 当前工具链

| 项目 | 核对结果 |
| --- | --- |
| Node | 实际 26.12.0；`.node-version` 为 26.12.0 |
| pnpm | 实际 12.11.2；packageManager 为 pnpm@12.11.2 |
| TypeScript | 锁定 6.0.3，保留已接受例外 |
| 前端依赖 | 按现有 package.json 与锁文件，无安装、升级或替换 |
| 构建目标 | Chrome 111 / Firefox 128 / Safari 16.4 |

## 隔离基线

从当前源码及未提交修改创建独立副本。仅复制前端和必要脚本；node_modules 为本机独立副本，不把构建缓存写回原目录。没有启动后端、打开数据库或操作真实附件。

证据目录：

`/var/folders/l6/smy8mmk15898tpm0vddrbyt00000gn/T/sky-widget-development-prep-20261019-3914jwu7`

| 检查 | 本轮结果 |
| --- | --- |
| `pnpm --dir web test` | 31 个文件、273 项测试通过 |
| `pnpm --dir web build` | 应用/测试 TypeScript 检查与生产构建通过 |
| `pnpm --dir web verify:attachments` | 通过 |
| `pnpm --dir web verify:brace-depth` | 通过 |
| `pnpm --dir web verify:bundle` | 通过 |

| 生产体积 | 当前 | 上限 |
| --- | ---: | ---: |
| 原始合计 | 800,781 B | 1,000,000 B |
| gzip 合计 | 247,287 B | 400,000 B |
| 最大 JS | 182,492 B | 200,000 B |
| 最大 CSS | 111,462 B | 120,000 B |
| 入口 HTML | 1,024 B | 20,000 B |

最大 CSS 仅余 8,538 B，最大 JS 单块余 17,508 B。实施时控制全局样式和公共 chunk；不能通过提高上限来代替优化。

日志为 `unit.log`、`build.log`、`attachments.log`、`parser.log`、`bundle.log`，聚合结果为 `baseline-results.json`。

工作区保全复核：928 个既有非忽略版本文件的内容哈希均未改变，214 项原状态完整保留；新增仅 4 份文档和 5 张参考图，9 个本地文档链接有效，HEAD 未变、暂存仍为 0。结果记录在证据目录的 `preparation-verification.json`。

## 已收敛的接口差异

- 用户 ID 可以通过现有 `authApi.getProfile()` 获得，不需要修改认证或解析 Token。
- 当前无独立账本 ID，不能宣称已具备多账本偏好隔离。
- 提醒汇总不返回下一笔金额/提醒 ID；不从名称、总负债或原型数字猜测。
- 分类预算可通过现有接口读取；大号组件按需加载。
- 净资产趋势虽有既有接口声明，首批仍不增加该组件或宣称历史资产口径已验证。
- 首页列表、日历、分页、迟到请求保护和记账刷新必须保留。

## 下一步与未执行项

按 [实施计划](../superpowers/plans/2026-10-19-web-widgets.md) 先做 Gate 0 隔离交互验证，再从配置目录、布局纯函数和隔离偏好开始，最后接真实读模型与页面。

没有运行 Go 测试或本轮浏览器业务流程，因为本轮不修改后端/页面。新界面的拖动、保存回读、导航切换、三浏览器和手机视口尚未实现或验证；旧验收结果不替代后续验收。

## 2026-10-20 方案批判修订

新增 [技术决策与风险边界](../architecture/2026-10-20-web-widgets-technical-decisions.md)，并同步设计规格与实施计划。本次仍只修改文档。

- 保留现有 Vue/Go/SQLite/Docker 组合及已接受的 TypeScript/Tailwind 兼容约定；未安装、升级或替换任何依赖。
- Node 26 的官方 LTS 日期为 2026-10-28；截至本次 2026-10-20 不称其已经 LTS，也不因此把 UI 改造扩展为工具链回退。
- 首选有限 Pointer Events 适配层，先在不访问 API 的合成实验验证；失败后重新比较排序依赖，不固执扩写自制引擎。
- 用精确配置联合、ResourceState、独立 home/navigation envelope 与 revision 补齐类型和存储边界；空/错/旧值不混用，不假报保存或并发强一致。
- 交付范围覆盖全部 11 个 kind 的 renderer；CalendarView 保留月份趋势读取所有权，其他资源按启用实例去重。
- 画廊使用原生 dialog，目录使用 disclosure；轻触排序与键盘排序分别验证，保持 LAN HTTP 可用。
- 新版三引擎、模拟视口/触摸、历史最低浏览器与物理设备证据分别记录，不外推验收结果。

2026-10-19 的 273 项测试和包体结果仍是原界面基线，本次未重跑或升级为新界面验收结果。后续执行必须在含当前 WIP 的隔离副本中生成新的证据。

本次文档与工作区验证：

- 2026-10-20 修订前 937 个文件，仅本方案的 3 份既有文档发生预期变化，新增 1 份技术决策文档；没有缺失或非预期改动。
- 218 项修订前状态全部保留；新增文档后共 219 项状态；HEAD 不变，暂存仍为 0。
- 开发准备最初记录的 928 个既有文件哈希仍全部相同；16 个本地文档/图片链接有效。
- 证据：`/var/folders/l6/smy8mmk15898tpm0vddrbyt00000gn/T/sky-widget-plan-review-20261020-qtkc3y5a/plan-verification.json`。
- 上述验证只覆盖文档和工作区保全，没有启动服务或执行新界面测试。

## Gate 0 隔离交互验证结果

日期：2026-10-20。状态：通过有限 Pointer 适配层可行性验证，未修改原工作区业务源码或依赖。

- 隔离副本：`/var/folders/l6/smy8mmk15898tpm0vddrbyt00000gn/T/sky-widget-gate0-20261020-081144-8308/source`，含当时 937 个文件和 219 项工作区状态；使用 APFS 克隆的 `node_modules`。
- 最终交互套件：44 项，42 通过、2 个明确跳过、0 失败；日志 `evidence/gate0-final-all.log`。
- 引擎：Chromium 156.0.8078.4、Firefox 157.0、WebKit 27.2；另有 Pixel 7 模拟触摸配置。
- 网络：只访问隔离 origin 的静态资源与 Vite websocket；无 `/api`、后端、数据库、账务数据或外部服务请求。
- 构建：隔离副本的 Vite 生产构建退出 0；日志 `evidence/build.log`。
- 首轮失败与修正：拖动中 Escape 曾错误退出编辑态；重排后卡片节点移动导致 pointer capture 失效。最终约束为开始拖动时记录快照、在 pointerdown 当次绑定 Escape/blur、由稳定网格容器承接指针事件。
- 跳过：移动配置的桌面专用布局断言；移动配置的桌面自动滚动断言。桌面自动滚动已由 Chromium/Firefox/WebKit 覆盖，移动端以单指轻触排序和 touch Pointer Events 探针覆盖。
- 边界：合成触摸事件不等于物理设备；历史最低浏览器 Safari 16.4 尚未实测。Gate 0 不代表正式首页、真实数据或业务页面已验收。

下一步：按计划 Task 1 实现组件目录与确定性布局纯函数。

## Task 3 隔离读模型与组件接入

日期：2026-10-20。状态：11 类组件与首页读模型接入完成；未修改后端、数据库或正式账本。

- 新增 `readModels.ts`、`useHomeOverview.ts`、`WidgetFrame.vue`、`HomeWidget.vue` 及 11 个组件。
- 默认首页改为组件网格；重复旧摘要卡和旧交易列表模板移除，日期交易加载、分页与刷新链路保留。
- 隔离后端浏览器验收：Chromium/Firefox/WebKit 共 9 项通过，覆盖 390px、1440px、组件导航、转账中性色、预算超支与提醒范围。
- 单测：39 文件 / 330 项通过；构建、brace、附件与包体门禁通过。
- 视觉复核修复了移动端提示遮挡、嵌套按钮语义、转账图标文本化和少数据大卡空白。
- 证据：`/var/folders/l6/smy8mmk15898tpm0vddrbyt00000gn/T/sky-widget-gate0-20261020-081144-8308/evidence/task3-workspace-after.json`。

## Task 4 共用导航与兼容验证

日期：2026-10-20。状态：实现与隔离回归完成，已将相同文件同步回原工作区；没有更新已存在的账本预览或正式服务。

| 改动 | 原因 |
| --- | --- |
| `WorkspaceHeader.vue` / `PinnedRail.vue` / `MobileNavigation.vue` | 顶部、侧栏和手机共用同一目录与偏好；桌面互斥，手机保留短标签 |
| `FunctionMenu.vue` / `navigation/icons.ts` | 全部入口仍可访问，链接与钉住按钮分开，图标集中映射 |
| `LayoutView.vue` | 接入身份隔离偏好及原主题/记账入口；保持路由视图和滚动容器实例，清理监听器 |
| `workspace.css` / `main.css` | 纯色背景、蓝色玻璃导航及菜单；局部样式不改变业务表单 |
| `HomeView.vue` | 侧栏改变可用宽度时重排网格；仅观察宽度并用 rAF 合并，避免 WebKit ResizeObserver 循环 |
| `home/preferences.ts` / `workspacePreferences.ts` / 对应 store 测试 | 重试只重载导航，不改变首页草稿 revision；明确损坏与未来版本，提供受限恢复 |
| `workspace-navigation.e2e.ts` / `allpages-layout.e2e.ts` | 新增跨端导航行为测试；账户日志按已确认规则归属账户 |

实际验证：

- `pnpm --dir web test`：39 文件 / 334 项通过。
- `pnpm --dir web build`：退出 0，包含应用和测试的 TypeScript 检查。
- `verify:brace-depth`、`verify:attachments`、`verify:bundle`：通过。
- `bash scripts/verify-web-e2e.sh e2e/workspace-navigation.e2e.ts e2e/home-widgets-readmodels.e2e.ts e2e/allpages-layout.e2e.ts e2e/stack-compatibility.e2e.ts`：Chromium、Firefox、WebKit 共 117 项通过，0 失败、0 跳过。
- 隔离副本显式使用 Node 26.12.0 / pnpm 12.11.2；临时目录不在项目 shell 自动选择版本的路径内，因此为验证进程指定已有工具链 PATH，没有改本机配置或项目依赖。
- 视口覆盖 320/390/768/820/900/960/1024/1280/1440px；覆盖浅深主题、减少动态效果、键盘、现有最长入口名、超量固定项、跨标签、失败与恢复路径。
- 路由实例标记、非零滚动位置、query、原交易表单金额保持；首页草稿及冲突保护由实际 store 验证，编辑 UI 尚待 Task 5。
- 导航交互网络守卫没有捕获账务写入。其他既有表单/附件回归使用脚本以 `env -i` 启动的新临时数据库、附件和备份目录，不连接已有模拟或正式账本。
- 独立审查发现的两个 P2 和一个焦点问题均以测试覆盖并处理；WebKit Escape 与 ResizeObserver 错误从失败转为通过，没有按引擎跳过。

| 生产包指标 | 实测 | 上限 |
| --- | ---: | ---: |
| 总原始 | 821,415 B | 1,000,000 B |
| 总 gzip | 254,410 B | 400,000 B |
| 最大 JS | 182,579 B | 200,000 B |
| 最大 CSS | 115,512 B | 120,000 B |
| HTML | 1,024 B | 20,000 B |

存储政策：读取失败用默认导航，验证身份前不读取个人偏好；保存失败保留当前显示并提示。损坏导航只有用户点击“恢复默认导航”才替换；未知未来版本保留原文并禁用偏好写入，所有业务目的地仍可访问。重试导航不会确认或覆盖其他标签的首页修改。仍不宣称 localStorage 提供事务级并发或跨设备同步。

证据根目录：`/var/folders/l6/smy8mmk15898tpm0vddrbyt00000gn/T/sky-widget-gate0-20261020-081144-8308/evidence`。

- 结果：`task4-suite.log`、`task4-build.log`、`task4-brace.log`、`task4-attachments.log`、`task4-bundle.log`、`task4-e2e-final.log`。
- 失败证据：`task4-red.log`、`task4-red-corrected.log`、`task4-grid-red.log`、`task4-retry-red.log`、`task4-storage-red.log`、`task4-focus-red.log`；中间 WebKit 告警已在最终构建修复。
- 截图：`task4-screenshots/`，含顶部、侧栏、目录及手机视口，以及合成读模型页面。
- 保全/回退：`task4-workspace-before.json`、`task4-workspace-after.json`、`task4-sync-files.json`、`task4-originals/`。只允许按本轮文件清单恢复增量，不能 reset/checkout 整个工作区。

剩余边界：Task 5 已完成；Task 6 的全规格最终验收未执行。物理手机、系统键盘/屏幕阅读器、实际文字放大和历史最低浏览器未实测。当前截图与新版引擎验证不替代这些验收。


## Task 5 网格编辑、画廊与拖动

日期：2026-10-20。状态：实现及隔离验证完成，已验证文件同步回原工作区；未更新既有预览，未提交/推送。

| 能力 | 实测行为 |
| --- | --- |
| 编辑事务 | 取消不落盘；完成成功才结束草稿；失败或跨标签冲突保留草稿；损坏配置显式恢复；未来版本禁写 |
| 布局 | 集合/账户配置共享；桌面与手机尺寸、顺序独立；轻触按钮、键盘与手柄指针都可排序 |
| 拖动 | 释放才提交；Escape/blur/pointercancel/容器重排取消；自动滚动仅当前容器，离开交集暂停 |
| 画廊 | 11 类真实 renderer；合成数据；账户必选；真实栅格尺寸；原生 dialog 焦点/背景锁；按需加载 |
| 可访问性 | 44px 操作目标；编辑控件带账户名；Tab 循环和关闭焦点返回；金额隐私覆盖可选 AI/日历金额 |
| 日历 | 复用现有日历及日期交易读取；首页刷新刷新已启用月份；预览不重复请求 |

验证结果：

- 单测：40 文件 / 345 项通过；应用和测试 TypeScript 检查及 Vite 构建退出 0。
- 最终三引擎浏览器回归：首页编辑/画廊、共用导航、读模型共 111 项通过，0 失败、0 跳过，覆盖 320/390/1440px。
- 原生触摸：Chromium 真实触摸开始/移动/结束，连续三次手柄拖动通过；非手柄触摸滚动。其他两引擎用轻触排序，不冒充触摸引擎实测。
- 网络：布局编辑和画廊没有账务写入或付费 AI 调用；登录/初始化/刷新仅访问脚本新建临时后端。
- 包体：原始 853,314 B、gzip 265,798 B、最大 JS 184,489 B、最大 CSS 116,632 B、HTML 1,024 B，均在现有上限内。
- 尺寸修正前还通过含既有页面、表单、附件、会话的 174 项回归；最终修改后已重跑相关套件，但 Task 6 必须重新跑完整集合。
- 未改依赖、后端、数据库、备份格式或正式数据。原生触摸和新版引擎不代表物理设备或历史最低浏览器实测。

证据根目录：`/var/folders/l6/smy8mmk15898tpm0vddrbyt00000gn/T/sky-widget-gate0-20261020-081144-8308/evidence`。

- 最终：`task5-suite.log`、`task5-build.log`、`task5-brace.log`、`task5-attachments.log`、`task5-bundle.log`、`task5-e2e-final.log`。
- 失败到通过：`task5-drag-red.log`、`task5-ui-red.log`、`task5-home-recovery-red.log`、`task5-scroll-red.log`、`task5-preview-red.log`、`task5-calendar-refresh-red.log`、`task5-touch-diagnose.log`、`task5-final-boundaries.log`。
- 视觉与回退：`task5-screenshots/`、`task5-sync-files.json`、`task5-originals/`、`task5.patch`、`task5-workspace-before.json`、`task5-workspace-after.json`。
- 剩余：Task 6 未执行；物理手机、系统屏幕阅读器、辅助键盘、文字放大、历史最低浏览器及真实安全区设备未实测。本机偏好不提供跨设备同步或事务级 CAS。


## Task 6 完整回归、性能与可检查交付

日期：2026-10-20。状态：代码及隔离自动化验收完成，详见 [完整交付报告](2026-10-20-web-widgets-task6-verification.md)。

- 独立审查的 6 项发现全部处理，补足迟到 profile 真正在途的测试；关键修复有失败到通过证据，没有改金融口径、历史余额、API、数据库或依赖。
- `useHomeOverview` 接入页面，补齐可选源按需加载、账户近期记录和大号分类预算；修复按查询 key 的在途刷新竞态。
- 修复提醒/账户未知与错误状态、分类预算告警、日历交易方向、首页交易入口、AI 报告状态、视觉/键盘顺序、跨标签导航同步、长金额/深色可读性及手机提示遮挡。
- 最终单测 40 文件 / 360 项通过；应用与测试类型检查、生产构建、brace、附件与包体门禁通过。
- 完整 E2E：Chromium、Firefox、WebKit 各 156 项，共 468 通过，0 失败、0 跳过、0 flaky。临时后端由脚本退出时关闭，没有更新既有账本或预览服务。
- 包体：原始 861,048 B，gzip 268,007 B，最大 JS 184,476 B，最大 CSS 117,038 B，HTML 1,024 B；CSS 余量 2,962 B。
- 三引擎画廊打开中位数分别 33.5 / 49.0 / 44.0 ms；仅为本机合成响应测量，非物理设备或现场 INP。
- 6 张最终截图位于 `docs/design/home-widgets/task6/`；原始 JSON、日志、独立审查与增量回退材料保留在既有 evidence 根目录。
- 隔离副本移出未使用的旧配置/数据/探针后重新构建，全部生产制品哈希与浏览器测试时一致。原工作区仅同步本轮文件增量，未暂存、提交、推送。
- 物理手机、历史最低浏览器、真实系统文字放大、屏幕阅读器/辅助键盘与安全区设备未实测；本机偏好不承诺跨设备同步或事务级 CAS。
