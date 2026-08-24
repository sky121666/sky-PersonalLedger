# Backup Operator Drill - 2026-05-27

## Conclusion

Automated backup/restore tests prove service behavior. This local operator drill additionally exercises the real export and restore HTTP workflow against isolated source and target deployments.

Evidence snapshot: the detailed local isolated API operator drill below passed on 2026-05-27 using
`./scripts/check-backup-operator-drill-local.sh`; its byte counts and seeded values are historical.
On 2026-08-24 the current tree separately passed the backup HTTP export/restore/restart rehearsal,
backup restore contracts, and the strict drill-document checker.

## Scope

The drill must verify that a human operator can export a backup, restore it into an isolated environment, and confirm the release-critical data set:

- family member records;
- member-linked transactions;
- account balances after restore;
- AI report history;
- absence of AI provider API keys and login credentials in the backup file.

## Required Environment

| Item | Value |
| --- | --- |
| Source deployment | Local isolated backend started by `./scripts/check-backup-operator-drill-local.sh` |
| Target isolated deployment | Local isolated backend started by `./scripts/check-backup-operator-drill-local.sh` |
| App version / build | Historical worktree on 2026-05-27 |
| Database engine | SQLite, temporary per-instance database |
| Operator | Codex local drill script |
| Drill date | 2026-05-27 |

## Drill Steps

| Step | Required Action | Expected Result | Status | Evidence |
| --- | --- | --- | --- | --- |
| 1 | Create or identify a family member | Member is visible in Family Hub / family API | PASS | Created `Operator Drill Member`; restored member ID matched |
| 2 | Create a transaction linked to that member | Transaction stores `member_id` and appears in family summary | PASS | Created expense `123.45` with `member_id` and `paid_by_member_id` |
| 3 | Generate or retain an AI report | AI report appears in AI Reports list | PASS | Local fake OpenAI-compatible provider generated completed weekly report |
| 4 | Export backup from the real app/API | Backup JSON downloads successfully | PASS | `GET /api/v1/backup` returned a 10036-byte backup payload |
| 5 | Inspect backup file locally | No password hash, refresh token, API token, or AI provider API key is present | PASS | Script scanned backup for credential markers and drill API key |
| 6 | Restore backup into isolated target | Restore finishes without error and creates pre-restore backup if scheduler is configured | PASS | `POST /api/v1/restore` succeeded on isolated target |
| 7 | Verify restored family member | Member name, default/enabled state, and relationship match source | PASS | Target `/api/v1/family/members` contained matching default member |
| 8 | Verify restored transaction | Member-linked transaction and account balance match source | PASS | Target `/api/v1/transactions` contained matching transaction and member link |
| 9 | Verify restored AI report history | Report period/status/content metadata is present | PASS | Target `/api/v1/ai/reports` contained completed report history |
| 10 | Verify excluded AI provider config | Provider secrets are not restored from normal backup | PASS | Target `/api/v1/ai/providers` returned an empty provider list |
| 11 | Run post-restore smoke | Login, Home, Family Hub, AI Reports, and transaction list are usable | PASS | Authenticated target API smoke covered family, transactions, AI reports, and summary |

## Suggested API Drill

Use an authenticated session against a test deployment. Do not paste tokens into this document.

```bash
curl -sS -H "Authorization: Bearer $SOURCE_TOKEN" \
  "$SOURCE_BASE_URL/api/v1/backup" \
  -o backup-release-drill.json

curl -sS -X POST -H "Authorization: Bearer $TARGET_TOKEN" \
  -F "file=@backup-release-drill.json" \
  "$TARGET_BASE_URL/api/v1/restore"
```

## Secret Inspection

Record only PASS/FAIL. Do not paste secret-like values.

| Check | Status | Notes |
| --- | --- | --- |
| Backup contains no password hash | PASS | Local script scanned exported backup |
| Backup contains no refresh token | PASS | Local script scanned exported backup |
| Backup contains no API token hash/prefix | PASS | Local script scanned exported backup |
| Backup contains no AI provider API key | PASS | Local script scanned exported backup and verified providers are not restored |
| Backup contains AI report history only | PASS | AI report history restored; provider config was excluded |

## Release Decision

The local isolated API operator drill is complete. A later release may still add production-environment operator evidence if the release process requires a non-local deployment rehearsal.
