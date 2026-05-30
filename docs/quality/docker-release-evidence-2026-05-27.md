# Docker Release Evidence - 2026-05-27

## Conclusion

Docker is the primary "one place deploy, others can use it" distribution path for Personal Ledger. The source-level workflow is prepared, but a release is not fully proven until the versioned GHCR image is pushed, pulled, started with persistent `/data`, and health-checked.

Current status: Docker release structure is prepared, the current worktree has passed a local Docker build/run smoke, and local compose deployment smoke has passed. Real GHCR image publication and release deployment smoke evidence are still pending.

## Preflight

Run from the repository root:

```bash
./scripts/check-docker-release-preflight.sh
```

This verifies the Docker workflow, tag release integration, multi-architecture build target, Dockerfile runtime shape, healthcheck, persistent `/data`, and docker-compose secret guard.

Before publishing, verify that the current worktree can build and boot as a Docker image:

```bash
./scripts/check-docker-local-smoke.sh
```

For a closer local compose rehearsal, including the `LEDGER_JWT_SECRET` guard:

```bash
./scripts/check-docker-compose-local-smoke.sh
```

After the real image is published, verify the manifest:

```bash
DOCKER_RELEASE_IMAGE=ghcr.io/<owner>/<repo>:X.Y.Z ./scripts/check-docker-release-evidence.sh
```

For strict release evidence, the image reference is required:

```bash
DOCKER_RELEASE_IMAGE=ghcr.io/<owner>/<repo>:X.Y.Z STRICT_DOCKER_RELEASE_EVIDENCE=1 ./scripts/check-docker-release-evidence.sh
```

Optionally run an isolated local smoke test:

```bash
DOCKER_RELEASE_IMAGE=ghcr.io/<owner>/<repo>:X.Y.Z RUN_DOCKER_RELEASE_SMOKE=1 ./scripts/check-docker-release-evidence.sh
```

## Image Evidence

| Item | Required Evidence | Status | Evidence |
| --- | --- | --- | --- |
| Local Docker build smoke | Current worktree builds and serves HTTP from a temporary container | PASS | `./scripts/check-docker-local-smoke.sh`, image `personal-ledger:local-smoke`, HTTP served on temporary localhost port |
| Local compose smoke | Current worktree image starts through Docker Compose with a persistent `/data` mount, image healthcheck, and JWT secret guard | PASS | `./scripts/check-docker-compose-local-smoke.sh`, image `personal-ledger:local-smoke`, HTTP served on temporary localhost port, container healthcheck became healthy, `ledger.db`, `uploads`, and `backups` created |
| GHCR version tag | `ghcr.io/<owner>/<repo>:X.Y.Z` exists after tag release | PENDING |  |
| Multi-arch manifest | Image includes `linux/amd64` and `linux/arm64` | PENDING |  |
| Latest tag policy | `latest` is published only by intended release workflow | PENDING |  |
| Image digest | Immutable digest is recorded | PENDING |  |

## Deployment Smoke

Use a non-production test directory and a real random JWT secret. Do not paste the secret into this document.

```bash
mkdir -p /tmp/personal-ledger-release-smoke/data
cd /tmp/personal-ledger-release-smoke
printf 'LEDGER_JWT_SECRET=%s\n' '<random-secret>' > .env
curl -fsSLO https://raw.githubusercontent.com/<owner>/<repo>/refs/tags/vX.Y.Z/docker-compose.yml
export LEDGER_IMAGE=ghcr.io/<owner>/<repo>:X.Y.Z
export LEDGER_SERVER_MODE=release
docker compose pull
docker compose up -d
docker compose ps
curl -fsS http://127.0.0.1:8080/api/v1/health >/dev/null
docker compose down
```

| Check | Required Result | Status | Evidence |
| --- | --- | --- | --- |
| Compose pull | Versioned or latest image pulls successfully | PENDING |  |
| Container start | Container enters running/healthy state | PENDING |  |
| HTTP health | `curl -fsS http://127.0.0.1:8080/api/v1/health` succeeds | PENDING |  |
| Persistence | `/data` contains database/config/uploads/backups paths as expected | PENDING |  |
| JWT guard | Starting without `LEDGER_JWT_SECRET` fails before container launch | PASS local, PENDING release image | Local compose config guard passed; repeat against published release compose/image |

## Release Decision

Do not mark Docker deployment complete until all rows above are changed from `PENDING` to `PASS` or a documented non-blocking exception, and `STRICT_DOCKER_RELEASE_EVIDENCE=1 ./scripts/check-docker-release-evidence.sh` passes.
