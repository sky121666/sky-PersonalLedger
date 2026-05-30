# Release Notes Candidate - 2026-05-27

## Personal Ledger vX.Y.Z

## Supported Platforms

| Platform | Status | Artifact |
| --- | --- | --- |
| Backend + Web | READY AFTER RELEASE WORKFLOW | Docker image `ghcr.io/<owner>/<repo>:X.Y.Z` |
| Android | READY AFTER SIGNED ARTIFACT | `personal-ledger-X.Y.Z-android.apk`, `personal-ledger-X.Y.Z-android.aab`, and `.sha256` files |
| iOS | PENDING SIGNED ARTIFACT | `personal-ledger-X.Y.Z-ios.ipa` from tag release or manual workflow, TestFlight build, or Xcode archive evidence |
| macOS | NOT INCLUDED | Platform regression is not part of this release candidate |
| Windows | NOT INCLUDED | Platform regression is not part of this release candidate |

## Highlights

- Family member management with member-linked transactions.
- Family monthly summary and premium mobile Family Hub.
- Member-level total and category budget foundation.
- OpenAI-compatible AI provider setup and weekly/monthly AI reports across Web and native mobile.
- Non-secret AI provider presets for DeepSeek, OpenAI, SiliconFlow, and custom gateways.
- AI report snapshots include aggregate budget and member-budget context without raw transaction remarks.
- Web AI report detail renders aggregate snapshot metrics, risk cards, and family member snapshots.
- Native mobile AI reports can select report type, enabled Provider, period, and member/account masking before generation.
- Aggregated AI snapshots that exclude raw transaction remarks by default.
- Premium mobile Home, Quick Transaction, AI Reports, Family Hub, member-budget budget screen surfaces, and Family Hub budget strip.

## Security And Privacy

- AI analysis is optional and disabled until a provider is configured.
- New AI provider API keys are protected at rest and are not returned by list/detail APIs.
- AI provider secrets are excluded from normal backup export.
- Backup/restore rehearsal covers family members, member-linked transactions, and AI report history.
- Before upgrading, existing AI providers should be re-saved to protect any legacy plaintext key values.

## Known Limitations

| Area | Status | Notes |
| --- | --- | --- |
| Android signed artifacts | PENDING | Requires real signing secrets or local release keystore evidence |
| iOS signed artifact | PENDING | Requires Apple certificate, provisioning profile, and IPA/TestFlight/archive evidence |
| Physical iPhone validation | PENDING | Requires USB-connected iPhone E2E or signed-install manual checklist |
| VoiceOver/TalkBack | PENDING | Requires manual assistive-technology pass on release candidate |
| Family features | PHASE 1+ | Member-level budgets are supported; roles and deeper permissions are reserved for later |

## Upgrade Notes

1. Take a backup before upgrading.
2. Keep the previous Docker image tag available until the new version is verified.
3. Re-save existing AI providers after upgrade so legacy stored keys are protected by the new secret protection path.
4. Verify family members, member-linked transactions, member-level budgets, and AI report history after restore or upgrade.
5. Run `RUN_EXPENSIVE=1 ./scripts/check-production-readiness.sh` before tagging a release candidate.

## Rollback

1. Stop the new deployment.
2. Redeploy the previous Docker image tag.
3. Restore the pre-upgrade backup only after confirming the target version supports the backup format.
4. Keep the failed release artifacts and logs for diagnosis.
5. Re-run login, account balance, transaction create/edit/delete, Family Hub, and AI report smoke checks.

## Verification Summary

| Gate | Evidence | Status |
| --- | --- | --- |
| Source-level local rehearsal | `RUN_EXPENSIVE=1 ./scripts/check-production-readiness.sh` | PASS, 2026-05-27 local run |
| Artifact preflight | `./scripts/check-release-artifacts-preflight.sh` | PASS REQUIRED |
| Artifact file evidence | `./scripts/check-release-artifact-files.sh` | PENDING REAL ARTIFACTS |
| Final release gate | `STRICT_FINAL_RELEASE=1 ./scripts/check-final-release-gates.sh` | PENDING REAL EVIDENCE |

## Release Decision

Do not publish this release candidate as fully complete until:

- Android signed APK/AAB and checksums are recorded.
- iOS signed IPA, TestFlight build, or archive evidence is recorded if iOS distribution is in scope.
- Physical iPhone validation is recorded.
- VoiceOver/TalkBack evidence is recorded or explicitly scoped out.
- This file has no unresolved `PENDING` rows for in-scope release gates.
