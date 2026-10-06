# Web 构建依赖安全

## braces 的本地修复

`GHSA-vfj7-8cjw-p6xm` / `CVE-2026-93687` 影响 `braces <=3.0.3`。截至本次核验，上游尚未发布修复版本。9003 字符、4500 层嵌套可在默认 compile 或 expand 路径耗尽 Node 调用栈；字符数未超过原有 10000 上限。

本项目通过 pnpm 10 的正式 `patch` / `patch-commit` 流程维护 `web/patches/braces@3.0.3.patch`，精确登记 `braces@3.0.3` 并由 lockfile 保存补丁 hash，不改上游版本号和许可证，也不配置 audit ignore 或调整告警等级。

补丁只处理本次递归深度根因：

- 默认最大容器深度为 100，解析字符串时同时限制大括号和圆括号；转义、引号和字符类沿用原有解析语义。
- compile、expand 和 stringify 的 AST 遍历同样限制深度，直接传入 AST 不能绕过字符串解析限制。
- expand 转入 invalid、dollar 或空范围的 stringify 分支时保留已消耗的深度，不能重新从零计数。
- 100 层仍可使用，101 层拒绝。超过限制是受控的输入错误，不能变成 `Maximum call stack size exceeded`。

上游 [PR #77](https://github.com/micromatch/braces/pull/77) 的草案默认不启用 `maxDepth`，依赖链没有传入该选项，因此不能直接视为当前项目已修复。新上游版本发布后，需核对其默认限制及兼容性，重新运行回归，再评估移除本地补丁。

## 当前调用范围

Tailwind 3.4.19 的 content 配置经 fast-glob 3.3.3 / micromatch 4.0.8 调用 braces 3.0.3；chokidar 3.6.0 也直接调用其 expand。模式来自已检出的 `web/tailwind.config.js`，当前为 `./index.html` 和 `./src/**/*.{vue,js,ts,jsx,tsx}`。这是构建和开发工具输入，不读取账本 API 的交易文本或运行中的上传目录。

Docker 最终镜像只复制 Go 二进制和 `web/dist`，不复制 Node 或 `node_modules`。这一范围说明不降低上游告警级别；修改配置的源码仍须经过仓库审查，任意不可信模式也必须先被补丁拒绝。

## 安装与验收

Docker 的依赖安装层先复制 `web/patches`。pnpm 的精确版本 patch 默认在无法应用时失败；不启用 `allowUnusedPatches` 或 `ignorePatchFailures`。每次冻结安装之后执行：

```bash
pnpm --dir web install --frozen-lockfile
pnpm --dir web verify:brace-depth
```

回归脚本从实际安装的 Tailwind、micromatch、fast-glob 和 chokidar 定位传递依赖，不加载临时替代模块。它验证 36 项正常/100 层边界、24 项攻击变体，并额外检查 101 层边界、fallback 深度继承和实际消费链。补丁应用后仍需 Web 单元测试、生产构建、bundle、附件和真实后端浏览器 E2E；Docker 镜像构建与公开验收由发布流程完成。

`pnpm audit --prod` 与包含构建依赖的 `pnpm audit` 分别报告。上游没有修复版本，后者仍会按 `braces@3.0.3` 报出这一 high advisory；本地源码修复不让版本匹配型扫描自动清零，不能声称 `audit-all=0`。保留审计输出、patch hash 和执行回归作为不同证据。展开结果数量仍遵循上游既有规则，本补丁不承诺解决其他资源耗尽类型。

来源：[GitHub advisory](https://github.com/advisories/GHSA-vfj7-8cjw-p6xm)、[上游问题 #70](https://github.com/micromatch/braces/issues/70)、[pnpm patch](https://pnpm.io/10.x/cli/patch)。
