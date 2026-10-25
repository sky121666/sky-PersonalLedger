# Web 构建依赖安全

## Tailwind v4 与旧 braces 补丁

2026-10-15 的 Web 升级使用 Tailwind 4.3.3 及其 Vite 插件，源码扫描由
`@tailwindcss/oxide` 执行。当前冻结依赖图不再包含 `braces`，因此移除了旧
`braces@3.0.3` 补丁、补丁登记及 Docker 的补丁复制步骤。

旧补丁曾防止 Tailwind 3 经 fast-glob / micromatch / chokidar 调用 braces 时发生
无界递归；移除依据是消费链已退出依赖图，不是忽略漏洞告警。历史实现保留在 Git 历史中。

`pnpm verify:brace-depth` 保留原命令入口，现在检查整个锁文件中没有任何 braces
版本或依赖边，同时确认实际安装的是 Tailwind 4 及其原生扫描器。如果任何未来依赖
重新引入 braces，门禁必须失败；届时需审查上游修复，并恢复适用的深度攻击回归或补丁，
不能直接放行。

旧 overrides 也已根据新依赖图移除。冻结安装与实际构建用于发现平台原生依赖缺失；
安全审计不配置 ignore，也不降低告警等级。

## pnpm 12 安装策略

Node、pnpm 和直接依赖使用明确版本，锁文件由 pnpm 12.11.2 生成。
`pnpm-workspace.yaml` 的 `minimumReleaseAgeExclude` 仅列出本次选择、尚处于 pnpm
默认发布时间等待期的精确版本，不按包通配符豁免，不全局关闭等待期。后续升级应重新
审查该列表，不能把这些例外扩展到未来版本。

本次收尾刷新了上游允许范围内的传递依赖，包括 Rolldown 1.2.14、
follow-redirects 1.16.1 和 Vue 3.5.44 编译工具包。Rolldown、对应平台 binding
和 OXC 类型包的发布时间例外仍精确到版本。没有新增 overrides，也没有改写
上游的固定版本：Tailwind 使用的 Lightning CSS 1.32.0、Vitest 使用的
why-is-node-running 3.2.1 等仍遵循原始依赖声明。

Docker 最终镜像只复制 Go 二进制和 `web/dist`，不复制 Node 或 `node_modules`。
此边界不降低构建阶段的安全要求。
Web CI 同时运行生产依赖 high 门禁和包含构建/测试依赖的 moderate 门禁。

最终镜像扫描还发现了后端传递依赖的 GO-2026-6611 / CVE-2026-78669：
Gin 引入的 `golang.org/x/net/http2` 来自旧的 x/net 0.57.0。
现已更新到修复版本 0.60.0，并采用该模块要求的 x/crypto、x/sys、x/text
及随依赖图选出的 x/sync 版本。该修复要求 Go 1.26.0，仍兼容本项目的
Go 1.26.9。没有为此添加漏洞忽略；双架构镜像需重新通过现有扫描门禁。

## 安装与验收

```bash
pnpm --dir web install --frozen-lockfile --strict-peer-dependencies
pnpm --dir web verify:brace-depth
pnpm --dir web audit --prod --audit-level=high
pnpm --dir web audit --audit-level=moderate
pnpm --dir web test
pnpm --dir web build
pnpm --dir web verify:bundle
pnpm --dir web verify:attachments
./scripts/verify-web-e2e.sh
```

生产依赖审计与包含构建依赖的完整审计分别报告，以当次命令结果为准。通过审计不等于
所有安全风险均被排除；版本锁定、真实消费链检查、浏览器回归和隔离 Docker 构建仍是
独立证据。发布验证与远程 CI 的执行状态也不能由本地检查替代。
