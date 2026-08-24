# Docker Release Evidence - historical baseline and 2026-08-24 update

## Conclusion

This file was created for the 2026-05 release rehearsal. Any Docker or Compose smoke result recorded
before the update below is historical evidence for that earlier tree, not evidence for the current
uncommitted worktree.

Current status on 2026-08-24: repository structure checks pass for the one-layout, two-architecture
scan contract. The build/scan job has no registry write permission or release environment; only its
dependent publisher receives those capabilities. Both Trivy inputs are scanned before login, and the
publisher verifies the sealed OCI archive checksum and digest before rejecting an existing tag and
pushing the unchanged layout. Current-worktree Docker image and Compose smokes also pass locally.

The already-published v1.0.8 baseline was read-only verified on 2026-08-24: its GitHub Release has no
assets, and `ghcr.io/sky121666/sky-personalledger:1.0.8` resolves to
`sha256:13e7d11085f58b4d7b73ebce604f92b705130a1fba4fae1b3cb2570c63d1a2a8` with
`linux/amd64` and `linux/arm64` image manifests. That observation does not prove a future tag run or
the current worktree's runtime behavior.

## Preflight

Run from the repository root:

```bash
./scripts/check-docker-release-preflight.sh
```

This verifies that the Docker workflow builds one OCI layout, uses digest-pinned Skopeo to export and
assert distinct amd64 and arm64 single-platform Docker archives, scans both archives before the only
registry login, checks that the immutable version tag is unused, publishes the original layout
without rebuilding, checks the remote digest, and generates a release-specific Compose asset. It
also verifies the Dockerfile runtime shape and Compose configuration contract. It does not execute
Trivy, push an image, or prove a container/Compose smoke run.

Before publishing, verify that the current worktree can build and boot as a Docker image:

```bash
./scripts/check-docker-local-smoke.sh
```

For a closer local compose rehearsal, including the `LEDGER_JWT_SECRET` and
`LEDGER_SETUP_TOKEN` guards:

```bash
./scripts/check-docker-compose-local-smoke.sh
```

After the real image is published, verify the manifest:

```bash
DOCKER_RELEASE_IMAGE=ghcr.io/<owner>/<repo>:X.Y.Z ./scripts/check-docker-release-evidence.sh
```

For strict release evidence, the image reference is required:

```bash
DOCKER_RELEASE_IMAGE=ghcr.io/<owner>/<repo>:X.Y.Z STRICT_DOCKER_RELEASE_EVIDENCE=1 RUN_DOCKER_RELEASE_SMOKE=1 ./scripts/check-docker-release-evidence.sh
```

Optionally run an isolated local smoke test:

```bash
DOCKER_RELEASE_IMAGE=ghcr.io/<owner>/<repo>:X.Y.Z RUN_DOCKER_RELEASE_SMOKE=1 ./scripts/check-docker-release-evidence.sh
```

## Image Evidence

| Item | Required Evidence | Status | Evidence |
| --- | --- | --- | --- |
| Current-worktree Docker build smoke | Current worktree builds and serves HTTP from a temporary container | PASS 2026-08-24 | Healthy; UID 10001; metrics authorization; database/uploads/backups persistence |
| Current-worktree Compose smoke | Current worktree starts through Compose with health and persistence checks | PASS 2026-08-24 | Bound to 127.0.0.1; JWT/setup guards, health, UID 10001, metrics authorization, persistence |
| Publish ordering contract | Both architecture scans precede the only GHCR login; unused-tag check precedes push | VERIFIED 2026-08-24 | `./scripts/check-docker-release-preflight.sh` |
| v1.0.8 historical GHCR baseline | Published index contains `linux/amd64` and `linux/arm64` | VERIFIED read-only 2026-08-24 | Digest `sha256:13e7d11085f58b4d7b73ebce604f92b705130a1fba4fae1b3cb2570c63d1a2a8` |
| Current release GHCR version tag | `ghcr.io/<owner>/<repo>:X.Y.Z` exists after the next tag release | PENDING | No new tag run was performed in this review |
| Current release Trivy scans | Both exported architecture archives pass HIGH/CRITICAL policy | PENDING | Workflow structure is verified; no current tag run was performed |
| Current release image digest | Published digest matches the scanned OCI layout and generated Compose asset | PENDING | No current tag run was performed |

## Deployment Smoke

Use a non-production test directory, a real random JWT secret, and a separate
random setup token. Do not paste either secret into this document.

```bash
mkdir -p /tmp/personal-ledger-release-smoke/data
cd /tmp/personal-ledger-release-smoke
gh release download vX.Y.Z --repo <owner>/<repo> --pattern 'docker-compose-vX.Y.Z.yml*'
sha256sum -c docker-compose-vX.Y.Z.yml.sha256
mv docker-compose-vX.Y.Z.yml docker-compose.yml
cp /secure/path/to/release-smoke.env .env
chmod 600 .env
docker compose pull
docker compose up -d
docker compose ps
curl -fsS http://127.0.0.1:8080/api/v1/health >/dev/null
docker compose down
```

| Check | Required Result | Status | Evidence |
| --- | --- | --- | --- |
| Compose pull | Versioned/digest-pinned image pulls successfully | PENDING |  |
| Container start | Container enters running/healthy state | PENDING |  |
| HTTP health | `curl -fsS http://127.0.0.1:8080/api/v1/health` succeeds | PENDING |  |
| Persistence | `/data` contains database/config/uploads/backups paths as expected | PENDING |  |
| Secret guards | Starting without `LEDGER_JWT_SECRET` or `LEDGER_SETUP_TOKEN` fails before container launch | PASS for current-worktree Compose smoke | Both guards verified by `./scripts/check-docker-compose-local-smoke.sh` |

## Release Decision

Do not mark Docker deployment complete until all rows above are changed from `PENDING` to `PASS` or a documented non-blocking exception, and `STRICT_DOCKER_RELEASE_EVIDENCE=1 ./scripts/check-docker-release-evidence.sh` passes.
