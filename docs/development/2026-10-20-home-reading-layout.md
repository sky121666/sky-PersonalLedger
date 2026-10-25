# 首页阅读布局恢复与自定义兼容验证

日期：2026-10-20。状态：本轮前端修复、隔离回归、Demo 静态预览更新及桌面/手机实查完成。

## 范围与依据

沿用用户确认的方案：原首页的居中阅读结构、原卡片视觉与自定义组件并存。结构基准为 `HEAD:web/src/views/HomeView.vue` 和 `docs/screenshots/v1.0.9/web-home-runtime.jpg`。

分支 `main`，HEAD `b7209927e44eb8f683730a975d1889a912322f8a`。全部既有 WIP 保留。未暂存、提交、推送；没有后端、账务 API、schema、依赖、CI、Docker 或财务规则变更。

源码与测试副本、日志和增量备份：

`/var/folders/l6/smy8mmk15898tpm0vddrbyt00000gn/T/sky-home-flow-20261020-4s20hpqz`

测试复用 `scripts/verify-web-e2e.sh`，每轮创建临时数据库、附件、备份与配置目录。没有对现有 Demo 运行创建账务数据的自动化测试。现有 Demo 只用于最终读取、临时布局草稿操作及显示检查。

## 本轮实现

| 文件 | 原因 |
| --- | --- |
| `web/src/components/home/layout.ts` | 中、大卡整行，小卡半行；自动内容行高；手机提醒显示整行，保留旧存储尺寸 |
| `web/src/components/home/model.ts` | 仅新建/主动恢复默认时使用资产、账户、收支、预算、提醒、交易的默认顺序；手机默认提醒中尺寸 |
| `web/src/components/home/WidgetGrid.vue` | 取消正方形行高，保留实际矩形拖动、动画与取消；移除后聚焦存活控件 |
| `web/src/components/home/WidgetFrame.vue`、`web/src/assets/home-cards.css` | 保留原卡片表面，使用按组件区分的最低高度；内容自然增长，移除默认纵向内部滚动及多余焦点停靠 |
| `widgets/MonthlyFlowWidget.vue`、`widgets/AccountsWidget.vue` | 区分收支矮卡、账户横条的合理最低高度 |
| `widgets/TransactionsWidget.vue` | 中尺寸 3 条、大尺寸 5 条交易摘要；完整记录继续由明细页承载 |
| `widgets/ReminderWidget.vue` | 小提醒完整显示名称与日期，避免省略关键对象 |
| `web/src/components/home/WidgetMenu.vue` | 手机移除收进选项；退出中的菜单取消可访问性与 ID，避免快速重开出现双菜单 |
| `web/src/components/home/WidgetGallery.vue`、新增 `galleryPreview.ts` | 共用首页宽度规则、内容高度、本地示例；手机纵向组件目录与足够的预览可用宽度 |
| `web/src/components/CalendarView.vue`、`widgets/CalendarWidget.vue` | 预览复用真实月份、星期及 42 个日期格；可选预览模式只用本地金额，不读取账务来源 |
| `layout.test.ts`、`model.test.ts` 和 4 个现有首页 E2E 文件 | 固定新布局、旧偏好保留、两端交互、画廊可见性、焦点与动画边界 |

共 20 个源码/测试文件的本轮增量，其中 14 个产品文件、6 个测试文件。只同步这些经验证的文件，没有整体覆盖原工作区。

## 明确取舍与兼容边界

- 外层继续 `max-w-3xl`，最大 768px，内部桌面卡片区 704px，居中于侧栏之外的主内容区。
- 小卡采用信息简版，不等同于永久锁定方形。可用宽度小于 400px 时单列；达到 400px 时允许两个至少 192px 的半宽摘要加 16px 间距。这个数值是当前设计约束，并非用户研究所得的普适最优值。
- 保留现有 `ColumnCount`、组件 ID、配置、尺寸枚举、偏好版本与两端顺序。不迁移、不重置有效偏好；显示投影改变不回写已保存尺寸。
- 原有 Demo 的账户组件仍在用户已保存的位置，没有静默移动到第二位。新默认顺序只在没有保存布局或主动恢复默认时采用。
- 集合与移除仍影响两端，排序和尺寸仍分端保存。没有顺手改成两套组件集合。
- 内容高度使首页比压缩网格更长，这是用页面滚动换取摘要完整。列表条数受限；没有用瀑布流回填改变阅读/键盘顺序。
- 手机布局编辑保留拖动与选项，将移除放入选项。物理设备、屏幕阅读器和历史最低浏览器版本仍需另行验证。

## 失败证据与修复

| 阶段 | 结果与处理 |
| --- | --- |
| 布局单测首次运行 | 7 项失败，确认旧四列投影、固定双行与默认布局不符合新目标；修改后相关 54 项通过 |
| 初始浏览器复现 | 4 项失败，确认中卡半行、交易内部滚动和预览高度统一问题 |
| 独立审查 | 指出移除后焦点丢失、简化日历不能代表真实占位；新增用例复现后修复 |
| 三引擎中间回归 | 225 通过、6 失败；包含失效的 28 格日期断言、动画采样竞争和退出菜单仍可访问的问题 |
| 定向整改回归 | 30 项通过；保留严格几何/保存/拖动断言，等待动画就绪，不通过放宽容差掩盖问题 |
| 手机 Demo 实查 | 发现画廊虽宽度正确，但内边距截住卡片右侧；补充“预览画布无横向溢出”断言并先看到失败，再修复手机弹窗可用宽度 |
| 最终回归 | 最后一次修改后完整重跑以下最终检查，全部通过 |

惯性滚动诊断记录表明，浏览器在到达底部后仍可能保留合成手势的惯性状态，直接重置 `scrollTop` 会继续移动。把原来混合的用例拆成独立真实滑动与真实拖动，未为此更改产品滚动逻辑。Chromium 使用 CDP 原生触摸；Firefox/WebKit 对应项使用滚轮/菜单替代，不能据此宣称后两者的物理触摸验收。

独立审查是针对当时增量的只读检查，审查期间测试文件仍有补充，审查员未宣称最终快照全量关闭。两项发现与后续实查问题均有回归覆盖；没有第二次独立审查，不把测试通过等同于独立审查最终签署。

## 最终检查

| 检查 | 结果 |
| --- | --- |
| Vitest | 40 文件，364 项通过 |
| 应用/测试 TypeScript、Vite 生产构建 | 通过 |
| 六个受影响 E2E 文件 | Chromium、Firefox、WebKit 各 94 项；共 282 通过，0 失败、0 跳过 |
| brace / 附件延迟删除保护 | 通过 |
| 包体门槛 | 889,449 B 原始 / 276,493 B gzip；最大 JS 184,603 B、CSS 115,866 B；均低于原门槛 |
| 源码保全 | 同步前检查原文件哈希；同步后本轮文件与隔离副本一致，无关既有文件与基线一致 |
| 现有 Demo 数据 | 8 张财务表行数及内容哈希前后一致；没有输出账单内容 |
| Demo 构建身份 | 93 个新构建文件逐一经 HTTP 回读，哈希与验证构建一致 |
| Git | HEAD 不变，暂存为空，无提交或推送 |

最后一轮日志：`unit-final-visible.log`、`build-final-visible.log`、`e2e-final-visible.log`、`brace-final-visible.log`、`attachments-final-visible.log`、`bundle-final-visible.log`。记录总数为实际执行结果，不等同于全仓所有测试；本轮没有重跑整个 Go/Flutter 套件。

验证使用 Node 26.12.0 与本机已安装 pnpm 12.11.2 的 JavaScript 入口。系统 `pnpm` 原生启动器在隔离目录的自动切换曾失败，因此仅在临时目录使用显式版本入口并关闭脚本前自动安装检查；没有改主机工具配置或项目依赖。

## Demo 实查

桌面 1440×1000：

- 外层 768px、网格 704px。
- 净资产 704×200、收支 704×129、账户 704×184。
- 预算与提醒各 344×160。
- 最近交易 704×460，5 条摘要；所有默认组件内容区纵向溢出为 0。
- 实际完成不同高度卡片的拖动、撤销、打开画廊和取消编辑；未保存测试排序。

手机 390×844：

- 网格与卡片均为 358px 宽。
- 净资产高 180px、收支 114px、预算/提醒 160px，交易摘要 398px、账户 164px。
- 画廊预览画布宽/内容宽均为 360px，横向溢出 0；日历预览 42 格。
- 检查编辑与画廊后取消草稿。预览最终留在桌面尺寸。

截图位于 `docs/design/home-widgets/reading-layout/`：

- [桌面](../design/home-widgets/reading-layout/07-live-preview.png)
- [桌面编辑](../design/home-widgets/reading-layout/02-desktop-editor.png)
- [桌面画廊](../design/home-widgets/reading-layout/03-desktop-gallery.png)
- [手机首页](../design/home-widgets/reading-layout/05-mobile-home.png)
- [手机编辑](../design/home-widgets/reading-layout/06-mobile-editor.png)
- [手机画廊](../design/home-widgets/reading-layout/04-mobile-gallery.png)

## 恢复与剩余边界

临时证据目录保留 `originals/`、`incremental.patch`、`baseline.json`、`source-final-hashes.json`、`preview-dist-before/`、`preview-build-hashes.json` 及 Demo 财务表摘要指纹。恢复只撤回本轮增量，先核对后续修改，不能使用 reset/整份覆盖原仓库。

仅更新现有 Demo 的前端静态文件，未重启后端；旧哈希静态资源保留，避免打断尚未刷新的标签。没有运行生产迁移、恢复或部署。

尚未验证：物理手机、系统屏幕阅读器、真实系统 200% 字号、Safari 16.4/Chrome 111/Firefox 128 的历史运行时。本轮浏览器文字放大及现代引擎测试不扩大为这些结论。
