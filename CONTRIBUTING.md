# 参与贡献

感谢为 Personal Ledger 提交改进。项目优先接受范围明确、可验证并保持私有部署边界的变更。

## 开始之前

1. 从最新 `main` 创建短期分支；
2. 不提交 `.env`、数据库、备份、上传文件、签名材料或 API Key；
3. 涉及数据库迁移、认证、备份恢复、公共 API 或发布流程时，在 PR 中说明兼容性和回滚方式；
4. UI 变更需同时覆盖桌面与移动视口，Flutter 变更需说明验证平台。

## 本地验证

    ./scripts/check-public-git-safety.sh
    ./scripts/check-version-consistency.sh
    ./scripts/check-toolchain-consistency.sh
    git diff --check

    cd backend && go test ./... && go vet ./...
    cd ../web && pnpm install --frozen-lockfile && pnpm test && pnpm build && pnpm verify:bundle
    cd ../mobile && flutter pub get && flutter analyze && flutter test

Web 和移动端真实后端验证：

    ./scripts/verify-web-e2e.sh
    ./scripts/verify-mobile-e2e.sh

## Pull Request

PR 请保持单一目的，并写明：

- 问题和修复结果；
- 影响的客户端或接口；
- 已执行的验证；
- 数据迁移、隐私、安全或发布风险；
- 未覆盖的实体设备或外部服务边界。

所有 PR 必须通过项目质量总门禁、依赖审查和公共仓库安全检查。
