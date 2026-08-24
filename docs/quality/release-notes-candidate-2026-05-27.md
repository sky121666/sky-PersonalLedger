# Release Notes - v1.0.9

## Personal Ledger v1.0.9

## Supported Platforms

| Platform | Status | Artifact |
| --- | --- | --- |
| Backend + Web | RELEASE SCOPE | Docker image `ghcr.io/sky121666/sky-personalledger:1.0.9` and the digest-pinned Release Compose pair |
| Android | DEVELOPMENT VERIFIED | Current source passed Android emulator real-backend E2E; no signed APK or AAB is published |
| iOS | DEVELOPMENT VERIFIED | Current source passed iOS Simulator real-backend E2E; no signed IPA or TestFlight build is published |
| macOS | NOT INCLUDED | Platform regression and signed distribution are outside this release |
| Windows | NOT INCLUDED | Platform regression and signed distribution are outside this release |

## Highlights

- Hardened transaction, reminder, lending, notification, and attachment mutations so clients refresh only after confirmed writes and surface partial attachment failures.
- Added attachment maintenance barriers, recoverable restore staging, reference validation, size limits, and integrity evidence for backup format 2.3.
- Added an independent credential-encryption keyring and transactional migration for AI Provider and notification credentials.
- Tightened setup, JSON body limits, trusted-proxy handling, CORS, health checks, private-network outbound policy, and error responses.
- Improved Web request-generation protection, responsive navigation, settings surfaces, and real-backend Playwright coverage.
- Improved Flutter server validation, secure local state, staged attachment sync, quick entry, reminders, lending, and consistent refresh behavior.
- Reworked Docker publication so one multi-architecture OCI layout is scanned before registry login, sealed, reverified, and then published without rebuilding.
- Split the README, feature documentation, deployment guide, release evidence, and Web/Android/iOS screenshots into focused documents.

## Security And Privacy

- AI analysis remains optional and disabled until an OpenAI-compatible AI provider is configured.
- API keys and notification credentials are protected at rest, omitted from API responses, excluded from normal backup export, and never required in repository configuration.
- A stable `LEDGER_CREDENTIAL_ENCRYPTION_KEY` separates credential encryption from JWT rotation; supported legacy values migrate transactionally at startup.
- Backup restore rejects credential-capable notification fields, invalid references, unsafe attachment paths, oversize data, and integrity mismatches before activation.
- Release mode rejects wildcard CORS and defaults to loopback binding plus private-network outbound blocking.

## Known Limitations

| Area | Status | Notes |
| --- | --- | --- |
| Android signed artifacts | OUT OF SCOPE | Signing material is optional and no APK or AAB is attached to v1.0.9 |
| iOS signed artifact | OUT OF SCOPE | No Apple certificate, provisioning profile, IPA, TestFlight build, or physical-device claim is included |
| iOS and Android device validation | DEVELOPMENT EVIDENCE ONLY | Android emulator and iOS Simulator real-backend E2E passed; this is not signed-install or physical-iPhone evidence |
| VoiceOver/TalkBack | OUT OF SCOPE | Automated semantics tests passed; no manual screen-reader claim is made |
| Attachment storage topology | SINGLE WRITER | The attachment maintenance barrier is process-local; a shared upload root does not support multiple write-capable replicas |
| Family authorization | PHASE 1+ | Member-linked accounting and budgets are supported; deeper member roles and permissions are reserved for later work |
| Source license | UNDECLARED | The repository contains public source but does not currently include a LICENSE file |

## Upgrade Notes

1. Back up the data directory and restricted local `.env` before upgrading.
2. Keep the previous digest and pre-upgrade backup until v1.0.9 health, login, transactions, attachments, notifications, family data, and AI reports are verified.
3. Configure and retain a stable `LEDGER_CREDENTIAL_ENCRYPTION_KEY`; do not discard the old key until startup migration and credential reads succeed.
4. Download `docker-compose-v1.0.9.yml` and its `.sha256` sidecar from the GitHub Release, verify the checksum, and deploy that digest-pinned Compose file.
5. Use one write-capable application instance for a shared attachment root.

## Rollback

1. Stop the v1.0.9 deployment and preserve its logs and data directory.
2. Redeploy the previously recorded immutable image or Compose asset.
3. Restore the pre-upgrade backup only after confirming the target version supports its backup format and credential-key state.
4. Re-run health, login, account balance, transaction create/edit/delete, attachment download, notification, Family Hub, and AI report checks.

## Verification Summary

| Gate | Evidence | Status |
| --- | --- | --- |
| Backend regression | `go test`, race tests, targeted soak, and `go vet` | PASS on 2026-08-24 |
| Web quality | 60 unit tests, production build, bundle and attachment checks, 2 real-backend Playwright flows | PASS on 2026-08-24 |
| Flutter quality | Analyzer, 404 passing tests with 1 designed skip, and 48 light/dark screen cases | PASS on 2026-08-24 |
| Mobile real-backend E2E | flutter-tester, Android emulator, and iOS Simulator | PASS on 2026-08-24 |
| Backup and security contracts | Restore, attachment integrity, credential migration, health, and privacy suites | PASS on 2026-08-24 |
| Local Docker | Current-worktree image and Compose health, persistence, non-root, and metrics checks | PASS on 2026-08-24 |
| Artifact preflight | `./scripts/check-release-artifacts-preflight.sh` | PASS for workflow structure; signed mobile output is not required |
| Optional signed artifact verifier | `RELEASE_ARTIFACT_DIR=artifacts RELEASE_VERSION=1.0.9 REQUIRE_IOS_ARTIFACT=1 VERIFY_ARTIFACT_SIGNATURES=1 ./scripts/check-release-artifact-files.sh` | NOT APPLICABLE to this Docker/Web release |
| Docker/Web publication | Tag workflow, GHCR multi-architecture manifest, Release Compose checksum, and published-image smoke | REQUIRED POST-TAG VERIFICATION |
| Full signed-mobile final gate | `STRICT_FINAL_RELEASE=1 ./scripts/check-final-release-gates.sh` | NOT APPLICABLE to this Docker/Web-only scope |

## Release Decision

v1.0.9 is approved for the Docker/Web tag workflow after its source commit is merged into `main`.
The release is complete only after the immutable tag, GHCR `linux/amd64` and `linux/arm64` image,
digest-pinned Compose attachment, checksum, and clean deployment smoke are verified. Signed mobile
artifacts, physical iPhone validation, and manual VoiceOver/TalkBack validation remain explicitly
outside this release and must not be inferred from simulator, emulator, widget, or screenshot evidence.
