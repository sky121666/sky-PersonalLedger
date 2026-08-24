# Docker Release Evidence - v1.0.9

## Conclusion

v1.0.9 separates evidence that can exist before a tag from evidence that only exists after
publication. Source, Compose, build/scan ordering, immutable-version, and local runtime contracts are
checked before publication. After GHCR publication, the tag workflow runs the real manifest and
container smoke against the exact OCI digest before it is allowed to create the GitHub Release.

This tracked document deliberately does not guess the future OCI digest. The successful non-draft
v1.0.9 GitHub Release is the durable signal that the published-image gate passed; the exact digest is
recorded in the Release Compose asset and the workflow output. Independent verification still reads
that live digest and runs the same smoke instead of trusting prose.

## Preflight

Run from the repository root:

```bash
./scripts/check-docker-release-preflight.sh
./scripts/check-docker-local-smoke.sh
./scripts/check-docker-compose-local-smoke.sh
```

The preflight proves that one multi-architecture OCI layout is built; digest-pinned Skopeo exports
and checks distinct amd64 and arm64 scan archives; both Trivy scans precede the only registry login;
the sealed OCI archive checksum and digest are rechecked by a separate publisher; an existing version
tag is rejected; and the unchanged layout is pushed without rebuilding.

The source-level Docker/Web release gate is:

```bash
RELEASE_SCOPE=docker-web RELEASE_PHASE=source STRICT_FINAL_RELEASE=1 ./scripts/check-final-release-gates.sh
```

It validates a clean versioned source tree, repository safety, version consistency, strict release
notes/runbook/inventory, backup operator evidence, and the Docker release workflow contract. It does
not ask for a GHCR digest before that digest exists.

## Image Evidence

| Item | Required Evidence | v1.0.9 Contract |
| --- | --- | --- |
| Local Docker build | Current source serves HTTP from a temporary container | PASS 2026-08-24; healthy, UID 10001, authenticated metrics, persistent database/uploads/backups |
| Local Compose | Current source starts through Compose with safe defaults and secret guards | PASS 2026-08-24; loopback bind, `LEDGER_JWT_SECRET` and `LEDGER_SETUP_TOKEN` guards, persistence |
| Publish ordering | Both architecture scans precede login and immutable tag creation | PASS in `./scripts/check-docker-release-preflight.sh` |
| GHCR version | `ghcr.io/sky121666/sky-personalledger:1.0.9` resolves after publication | REQUIRED BY TAG WORKFLOW before GitHub Release creation |
| Platforms | Manifest contains `linux/amd64` and `linux/arm64` | REQUIRED BY PUBLISHED-IMAGE GATE |
| Trivy | Both verified architecture archives satisfy the HIGH/CRITICAL policy | REQUIRED BEFORE THE PUBLISH JOB CAN RUN |
| OCI identity | Remote digest equals the sealed scanned layout digest | REQUIRED BY THE PUBLISH JOB |
| Compose identity | Release Compose uses the same immutable digest | GENERATED ONLY AFTER THE PUBLISHED-IMAGE GATE PASSES |

The tag workflow invokes the strict runtime path with the exact digest:

```bash
DOCKER_RELEASE_IMAGE=ghcr.io/sky121666/sky-personalledger@sha256:runtime-digest-from-workflow \
RUNTIME_DOCKER_RELEASE_EVIDENCE=1 \
RUN_DOCKER_RELEASE_SMOKE=1 \
./scripts/check-docker-release-evidence.sh
```

`runtime-digest-from-workflow` is explanatory text, not a value to copy. Always read the real digest
from the release workflow or digest-pinned Compose asset.

## Deployment Smoke

The automated published-image gate checks:

- the live manifest includes both supported Linux architectures;
- the exact digest pulls successfully;
- `/api/v1/health` becomes healthy;
- unauthenticated metrics return 401 and a dedicated token succeeds;
- PID 1 runs as UID 10001;
- `ledger.db`, `uploads`, and `backups` persist under `/data`.

Independent post-release verification:

```bash
mkdir -p /tmp/personal-ledger-v1.0.9-verification
gh release download v1.0.9 --repo sky121666/sky-PersonalLedger \
  --dir /tmp/personal-ledger-v1.0.9-verification \
  --pattern 'docker-compose-v1.0.9.yml*'
(cd /tmp/personal-ledger-v1.0.9-verification && sha256sum -c docker-compose-v1.0.9.yml.sha256)
DOCKER_RELEASE_IMAGE=ghcr.io/sky121666/sky-personalledger:1.0.9 \
STRICT_DOCKER_RELEASE_EVIDENCE=1 \
RUN_DOCKER_RELEASE_SMOKE=1 \
./scripts/check-docker-release-evidence.sh
```

The `.env` used for an operator deployment must contain real random `LEDGER_JWT_SECRET` and
`LEDGER_SETUP_TOKEN` values and remain outside the repository and evidence logs.

## Release Decision

Do not describe v1.0.9 as published merely because its local checks pass. It is a completed
Docker/Web release only when the immutable tag exists, the automated workflow is successful, the
GitHub Release is non-draft, the Compose checksum verifies, GHCR reports both architectures, the
Compose digest equals the GHCR digest, and an independent runtime smoke succeeds. A failed run never
authorizes moving or recreating `v1.0.9`; source corrections require a new reviewed version.
