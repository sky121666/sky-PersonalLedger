#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

require_file() {
  local path="$1"
  [[ -f "$ROOT_DIR/$path" ]] || {
    echo "Missing required file: $path" >&2
    exit 1
  }
}

require_text() {
  local path="$1"
  local pattern="$2"
  grep -qE "$pattern" "$ROOT_DIR/$path" || {
    echo "Missing required pattern in $path: $pattern" >&2
    exit 1
  }
}

require_absent_text() {
  local path="$1"
  local pattern="$2"
  if grep -qE "$pattern" "$ROOT_DIR/$path"; then
    echo "Forbidden pattern in $path: $pattern" >&2
    exit 1
  fi
}

required_files=(.github/workflows/docker.yml .github/workflows/release-web.yml .github/workflows/release-web-recovery.yml .github/workflows/release.yml Dockerfile .dockerignore docker-entrypoint.sh docker-compose.yml docker-compose.debug.yml .env.example web/pnpm-workspace.yaml scripts/generate-release-compose.sh scripts/check-toolchain-consistency.sh scripts/release_contract.py scripts/test_release_contract.py)
for path in "${required_files[@]}"; do
  require_file "$path"
done

for tool in docker python3; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "$tool is required" >&2
    exit 1
  }
done

python3 - "$ROOT_DIR/.github/workflows/docker.yml" "$ROOT_DIR/.github/workflows/release-web.yml" "$ROOT_DIR/.github/workflows/release-web-recovery.yml" "$ROOT_DIR/.github/workflows/release.yml" <<'PY'
import re
import sys


docker = open(sys.argv[1], encoding="utf-8").read()
release = open(sys.argv[2], encoding="utf-8").read()
recovery = open(sys.argv[3], encoding="utf-8").read()
signed_release = open(sys.argv[4], encoding="utf-8").read()


def job_block(workflow, name):
    match = re.search(
        rf"(?ms)^  {re.escape(name)}:\n(?P<body>.*?)(?=^  [A-Za-z0-9_-]+:\n|\Z)",
        workflow,
    )
    if not match:
        raise SystemExit(f"Missing workflow job: {name}")
    return match.group(0)

expected_concurrency = "group: personal-ledger-release-publish"
if any(workflow.count(expected_concurrency) != 1 for workflow in (release, recovery, signed_release)):
    raise SystemExit("Docker/Web, recovery, and signed mobile workflows must share one global concurrency group")
if any("cancel-in-progress: false" not in workflow for workflow in (release, recovery, signed_release)):
    raise SystemExit("Release workflows must queue rather than cancel an in-progress publisher")
if release.count("uses: actions/checkout@") != release.count("persist-credentials: false"):
    raise SystemExit("Every Docker/Web release checkout must disable persisted credentials")
if recovery.count("uses: actions/checkout@") != recovery.count("persist-credentials: false"):
    raise SystemExit("Every recovery checkout must disable persisted credentials")
if "workflow_dispatch:" in docker:
    raise SystemExit("Docker publishing must only be callable by the gated tag workflow")
if docker.count("uses: docker/build-push-action@") != 1:
    raise SystemExit("Docker release must build exactly one OCI layout")
if re.search(r"^[ ]+push:[ ]+true[ ]*$", docker, re.MULTILINE):
    raise SystemExit("build-push-action must not publish before archive scans")

ordered_markers = [
    "Build one multi-arch OCI layout",
    "Export and verify architecture-specific scan archives",
    "Scan the verified amd64 docker archive",
    "Scan the verified arm64 docker archive",
    "Seal the scanned OCI layout for the publisher",
    "Upload the scanned OCI handoff",
    "Download the scanned OCI handoff",
    "Verify and restore the scanned OCI layout",
    "Login to GitHub Container Registry after both scans pass",
    "Reject an existing immutable image tag after both scans pass",
    "Push the scanned OCI layout without rebuilding",
]
positions = []
for marker in ordered_markers:
    if docker.count(marker) != 1:
        raise SystemExit(f"Expected exactly one Docker workflow marker: {marker}")
    positions.append(docker.index(marker))
if positions != sorted(positions):
    raise SystemExit("Docker build/scan/login/publish steps are out of order")

required_docker_contracts = [
    "platforms: linux/amd64,linux/arm64",
    "outputs: type=oci,dest=${{ runner.temp }}/personal-ledger-release.oci,tar=false",
    '--override-os linux',
    '--override-arch "$arch"',
    'docker-archive:${archive}:personal-ledger:scan-${arch}',
    'expected_platform="linux/${arch}"',
    'if [ "$actual_platform" != "$expected_platform" ]',
    "input: ${{ runner.temp }}/personal-ledger-amd64.tar",
    "input: ${{ runner.temp }}/personal-ledger-arm64.tar",
    "quay.io/skopeo/stable@sha256:",
    "docker.io/tonistiigi/binfmt@sha256:",
    "moby/buildkit:v0.32.2@sha256:",
    "docker.io/docker/buildkit-syft-scanner@sha256:",
    "copy --all --preserve-digests",
    "-e REGISTRY_AUTH_FILE=/tmp/auth.json",
    '-v "${HOME}/.docker/config.json:/tmp/auth.json:ro"',
    'if [ "$remote_digest" != "$local_digest" ]',
    'echo "image_digest=$local_digest" >> "$GITHUB_OUTPUT"',
    "personal-ledger-release.oci.tar.sha256",
    "sha256sum -c personal-ledger-release.oci.tar.sha256",
    "compression-level: 0",
    "needs: build_scan",
    "ref: ${{ inputs.source_ref || github.ref }}",
    "org.opencontainers.image.revision=${{ steps.source.outputs.sha }}",
    "source_ref and source_sha must be provided together",
    'PUBLISH_ENVIRONMENT" != "release"',
    'PUBLISH_ENVIRONMENT" != "release-recovery"',
]
for contract in required_docker_contracts:
    if contract not in docker:
        raise SystemExit(f"Missing Docker artifact identity contract: {contract}")
if '-v "${HOME}/.docker:/root/.docker:ro"' in docker:
    raise SystemExit("Skopeo must mount the Docker login file at its configured REGISTRY_AUTH_FILE")
if docker.count("uses: aquasecurity/trivy-action@") != 2:
    raise SystemExit("Docker release must run exactly two architecture-specific Trivy scans")
if docker.count("uses: docker/login-action@") != 1:
    raise SystemExit("Docker release must authenticate exactly once, after both Trivy scans")
if "TRIVY_PLATFORM" in docker or "input: ${{ runner.temp }}/personal-ledger-release.oci" in docker:
    raise SystemExit("Trivy must scan verified single-platform archives, not select from the OCI index")
if not re.search(r"SKOPEO_IMAGE:[ ]+quay[.]io/[^@]+@sha256:[0-9a-f]{64}", docker):
    raise SystemExit("Skopeo publisher image must be pinned by digest")
for moving_tag_contract in ("publish_latest", "value=latest", 'docker://${image}:latest'):
    if moving_tag_contract in docker:
        raise SystemExit("Docker tag workflow must publish only the immutable version tag, not latest")
build_scan = job_block(docker, "build_scan")
publish = job_block(docker, "publish")
push_step_match = re.search(
    r"(?ms)^      - name: Push the scanned OCI layout without rebuilding\n"
    r"(?P<body>.*?)(?=^      - name: |\Z)",
    publish,
)
if not push_step_match:
    raise SystemExit("Missing Docker publisher push step")
push_step = push_step_match.group("body")
for pattern in (
    r'(?m)^            -e REGISTRY_AUTH_FILE=/tmp/auth[.]json$',
    r'(?m)^            -v "[$][{]HOME[}]/[.]docker/config[.]json:/tmp/auth[.]json:ro"$',
):
    if not re.search(pattern, push_step):
        raise SystemExit("Skopeo publisher must use the Docker login file at /tmp/auth.json")
if "/root/.docker" in push_step:
    raise SystemExit("Skopeo publisher must not rely on its ignored /root/.docker path")
if re.search(r"(?m)^    environment:", build_scan) or "packages: write" in build_scan:
    raise SystemExit("Docker build/scan job must not have a release environment or package write access")
if "persist-credentials: false" not in build_scan:
    raise SystemExit("Docker build/scan checkout must not persist GitHub credentials")
if docker.count("uses: actions/checkout@") != docker.count("persist-credentials: false"):
    raise SystemExit("Every Docker workflow checkout must disable persisted credentials")
for contract in (
    "needs: build_scan",
    "environment: ${{ inputs.publish_environment }}",
    "actions: read",
    "packages: write",
):
    if contract not in publish:
        raise SystemExit(f"Docker publisher is missing protected handoff contract: {contract}")
if "actions/checkout@" in publish:
    raise SystemExit("Docker publisher must use the immutable artifact handoff, not a fresh checkout")
if docker.count("uses: actions/upload-artifact@") != 1 or docker.count("uses: actions/download-artifact@") != 1:
    raise SystemExit("Docker release must upload and download exactly one immutable OCI handoff")
if docker.count("packages: write") != 1:
    raise SystemExit("Only the protected Docker publisher may have package write access")
for forbidden_prepare_auth in ("packages: read", "docker login ghcr.io", "uses: docker/login-action@", "docker buildx imagetools inspect"):
    if forbidden_prepare_auth in release:
        raise SystemExit(
            "Docker/Web prepare must not authenticate to or inspect GHCR before both Trivy scans: "
            + forbidden_prepare_auth
        )

required_release_contracts = [
    "fetch-depth: 0",
    "git merge-base --is-ancestor",
    "releases/tags/",
    "Could not prove GitHub Release",
    "Refusing to overwrite",
    "scripts/release_contract.py verify-tag",
    "scripts/release_contract.py publish",
    "needs.prepare.outputs.tag_object",
    "environment: release",
]
for contract in required_release_contracts:
    if contract not in release:
        raise SystemExit(f"Missing tag release contract: {contract}")
required_post_scan_publish_contracts = [
    "docker buildx imagetools inspect",
    "Image tag already exists",
    "Could not prove ${image} is unused",
]
for contract in required_post_scan_publish_contracts:
    if contract not in docker:
        raise SystemExit(f"Missing post-scan immutable image tag contract: {contract}")
if not re.search(r"(?ms)^  release:\n(?:(?!^  [^ ]).)*^    environment: release$", release):
    raise SystemExit("GitHub Release writer must use the protected release environment")

release_docker = job_block(release, "docker")
for contract in (
    "source_ref: ${{ github.ref_name }}",
    "source_sha: ${{ github.sha }}",
    "publish_environment: release",
    "actions: read",
    "packages: write",
):
    if contract not in release_docker:
        raise SystemExit(f"Tag release Docker caller is missing nested permission or source contract: {contract}")

recovery_validate = job_block(recovery, "validate")
recovery_docker = job_block(recovery, "docker")
recovery_release = job_block(recovery, "release")
required_recovery_contracts = [
    "workflow_dispatch:",
    "failed_run_id:",
    "expected_digest:",
    "publisher_run_id:",
    "verify_only:",
    "mode_args+=(--verify-only)",
    "ref: refs/tags/${{ inputs.tag }}",
    "ref: ${{ github.sha }}",
    "path: tooling",
    "path: source",
    "working-directory: tooling",
    "scripts/release_contract.py recover-plan --source ../source",
    "scripts/release_contract.py publish --source ../source",
    "scripts/release_contract.py verify-image",
    "needs.validate.outputs.mode == 'build'",
    "needs.validate.outputs.mode != 'verify'",
    "needs.docker.result == 'skipped'",
    "needs.release.result == 'skipped'",
    "source_ref: ${{ needs.validate.outputs.release_sha }}",
    "source_sha: ${{ needs.validate.outputs.release_sha }}",
    "publish_environment: release-recovery",
    "environment: release-recovery",
    "RUNTIME_DOCKER_RELEASE_EVIDENCE: '1'",
    "RUN_DOCKER_RELEASE_SMOKE: '1'",
    "scripts/check-docker-release-evidence.sh",
    "needs.validate.outputs.tag_object",
]
for contract in required_recovery_contracts:
    if contract not in recovery:
        raise SystemExit(f"Missing immutable release recovery contract: {contract}")
for writer in (recovery_docker, recovery_release):
    if "!inputs.verify_only" not in writer:
        raise SystemExit("Read-only dispatch must explicitly disable each publisher")
for workflow in (release, recovery):
    if "target_commitish:" in workflow or "--target " in workflow or "softprops/action-gh-release@" in workflow:
        raise SystemExit("Docker/Web creation must use the verified existing tag, without target override or update actions")
    verifier = job_block(workflow, "verify-assets")
    if "environment:" in verifier or ": write" in verifier:
        raise SystemExit("Public asset verification must be read-only and outside deployment environments")
    for contract in ("scripts/release_contract.py verify-assets", "scripts/release_contract.py verify-tag",
                     "scripts/release_contract.py verify-image", "contents: read"):
        if contract not in verifier:
            raise SystemExit(f"Missing independent verification contract: {contract}")
    writer = job_block(workflow, "release")
    if "scripts/release_contract.py publish" not in writer or workflow.count("contents: write") != 1:
        raise SystemExit("Only the protected Release creator may have contents write access")
    if "scripts/release_contract.py verify-assets" in writer:
        raise SystemExit("Public verification must have a separate job, not redefine publication outcome")
if ": write" in recovery_validate or " publish " in recovery_validate:
    raise SystemExit("Recovery inspection cannot write remote state")
if "environment:" in recovery_validate or "packages: write" in recovery_validate:
    raise SystemExit("Recovery validation must remain read-only and outside a deployment environment")
for contract in ("actions: read", "packages: write", "publish_environment: release-recovery"):
    if contract not in recovery_docker:
        raise SystemExit(f"Recovery Docker caller is missing protected publisher contract: {contract}")
if "environment: release-recovery" not in recovery_release or "contents: write" not in recovery_release:
    raise SystemExit("Recovered GitHub Release writer must use the protected recovery environment")
if "softprops/action-gh-release@" in recovery:
    raise SystemExit("Recovery must use create-only gh release create instead of an action that can update a Release")

PY

require_text "Dockerfile" 'FROM node:[0-9]+[.][0-9]+[.][0-9]+-alpine[0-9.]+@sha256:[0-9a-f]{64} AS frontend-builder'
require_text "Dockerfile" 'COPY web/package[.]json web/pnpm-lock[.]yaml web/pnpm-workspace[.]yaml [.]/'
require_text "Dockerfile" 'FROM golang:[0-9]+[.][0-9]+[.][0-9]+-alpine[0-9.]+@sha256:[0-9a-f]{64} AS backend-builder'
require_text "Dockerfile" 'FROM alpine:[0-9]+[.][0-9]+[.][0-9]+@sha256:[0-9a-f]{64}'
require_text "Dockerfile" 'go build -mod=readonly'
require_text "Dockerfile" 'HEALTHCHECK'
require_text "Dockerfile" 'adduser -S -D -H -u 10001 -G ledger ledger'
require_text "Dockerfile" 'ENTRYPOINT \["/usr/local/bin/docker-entrypoint[.]sh"\]'
require_text "docker-entrypoint.sh" 'exec su-exec ledger:ledger'
require_text ".dockerignore" '^backend/[.]codex-go-cache$'
require_text ".dockerignore" '^output$'

require_text "docker-compose.yml" '127[.]0[.]0[.]1'
require_text "docker-compose.yml" 'LEDGER_CREDENTIAL_ENCRYPTION_KEY'
require_text "docker-compose.yml" 'LEDGER_CREDENTIAL_ENCRYPTION_PREVIOUS_KEY'
require_text ".env.example" '^LEDGER_BIND_ADDRESS=127[.]0[.]0[.]1$'
require_text ".env.example" '^LEDGER_CREDENTIAL_ENCRYPTION_KEY=$'
require_text ".env.example" '^LEDGER_CREDENTIAL_ENCRYPTION_PREVIOUS_KEY=$'
require_absent_text ".env.example" '^LEDGER_(DATABASE_PATH|STORAGE_UPLOAD_PATH|STORAGE_BACKUP_PATH|SETUP_CONFIG_PATH)=[.]/data'
require_absent_text ".env.example" '^[[:space:]]*LEDGER_CORS_ALLOWED_ORIGINS=[*][[:space:]]*$'

jwt_secret="docker-release-preflight-jwt-only"
setup_token="docker-release-preflight-setup-only"

env LEDGER_JWT_SECRET="$jwt_secret" LEDGER_SETUP_TOKEN="$setup_token" docker compose --env-file /dev/null -f "$ROOT_DIR/docker-compose.yml" config --format json >"$TMP_DIR/base.json"

env LEDGER_JWT_SECRET="$jwt_secret" LEDGER_SETUP_TOKEN="$setup_token" docker compose --env-file /dev/null -f "$ROOT_DIR/docker-compose.yml" -f "$ROOT_DIR/docker-compose.debug.yml" config --format json >"$TMP_DIR/debug.json"

env LEDGER_BIND_ADDRESS=0.0.0.0 LEDGER_SERVER_PORT=18080 LEDGER_SERVER_MODE=release LEDGER_SERVER_TRUSTED_PROXIES=10.0.0.0/8 LEDGER_SERVER_MAX_JSON_BODY_BYTES=2097152 LEDGER_DATABASE_DRIVER=postgres LEDGER_DATABASE_DSN='postgres://ledger@db:5432/ledger?sslmode=require' LEDGER_DATABASE_MAX_OPEN_CONNS=12 LEDGER_DATABASE_MAX_IDLE_CONNS=6 LEDGER_JWT_SECRET="$jwt_secret" LEDGER_JWT_ACCESS_EXPIRE=20 LEDGER_JWT_REFRESH_EXPIRE=50000 LEDGER_CREDENTIAL_ENCRYPTION_KEY=credential-primary-validation-only LEDGER_CREDENTIAL_ENCRYPTION_PREVIOUS_KEY=credential-previous-validation-only LEDGER_SETUP_TOKEN="$setup_token" LEDGER_SECURITY_BASE_PATH=/private LEDGER_SECURITY_ALLOW_PRIVATE_OUTBOUND=true LEDGER_CORS_ALLOWED_ORIGINS=https://ledger.example.test LEDGER_LOG_LEVEL=warn LEDGER_LOG_FORMAT=text LEDGER_STORAGE_MAX_FILE_SIZE=20 LEDGER_STORAGE_RESTORE_MAX_FILE_SIZE=96 LEDGER_STORAGE_ALLOWED_TYPES=png,pdf LEDGER_OBSERVABILITY_METRICS_ENABLED=true LEDGER_OBSERVABILITY_METRICS_TOKEN=metrics-validation-only LEDGER_RATE_LIMIT_MAX_REQUESTS=321 LEDGER_RATE_LIMIT_WINDOW_SECS=45 TZ=UTC docker compose --env-file /dev/null -f "$ROOT_DIR/docker-compose.yml" config --format json >"$TMP_DIR/override.json"

release_image='ghcr.io/example/personal-ledger@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
RELEASE_IMAGE="$release_image" bash "$ROOT_DIR/scripts/generate-release-compose.sh" "$TMP_DIR/docker-compose-v1.2.3.yml"
env LEDGER_JWT_SECRET="$jwt_secret" LEDGER_SETUP_TOKEN="$setup_token" docker compose --env-file /dev/null -f "$TMP_DIR/docker-compose-v1.2.3.yml" config --format json >"$TMP_DIR/release.json"

python3 - "$TMP_DIR/base.json" "$TMP_DIR/debug.json" "$TMP_DIR/override.json" "$TMP_DIR/release.json" "$release_image" <<'PY'
import json
import sys


def service(path):
    with open(path, encoding="utf-8") as handle:
        config = json.load(handle)
    try:
        return config["services"]["personal-ledger"]
    except (KeyError, TypeError) as error:
        raise SystemExit(f"Invalid personal-ledger Compose service in {path}: {error}")


base, debug, override, release = (service(path) for path in sys.argv[1:5])
release_image = sys.argv[5]

base_port = base["ports"][0]
if (base_port.get("host_ip"), base_port.get("published"), base_port.get("target")) != (
    "127.0.0.1",
    "8080",
    8080,
):
    raise SystemExit(f"Unexpected safe default port mapping: {base_port!r}")
override_port = override["ports"][0]
if (override_port.get("host_ip"), override_port.get("published"), override_port.get("target")) != (
    "0.0.0.0",
    "18080",
    8080,
):
    raise SystemExit(f"Compose host port override is not semantic: {override_port!r}")

if base["environment"].get("LEDGER_SERVER_MODE") != "release":
    raise SystemExit("Base Compose must resolve LEDGER_SERVER_MODE=release")
if debug["environment"].get("LEDGER_SERVER_MODE") != "debug":
    raise SystemExit("Debug override must resolve LEDGER_SERVER_MODE=debug")

expected_paths = {
    "LEDGER_SERVER_PORT": "8080",
    "LEDGER_SERVER_WEB_PATH": "/app/web/dist",
    "LEDGER_DATABASE_PATH": "/data/ledger.db",
    "LEDGER_SETUP_CONFIG_PATH": "/data/config.yaml",
    "LEDGER_STORAGE_UPLOAD_PATH": "/data/uploads",
    "LEDGER_STORAGE_BACKUP_PATH": "/data/backups",
}
for label, current in (("base", base), ("override", override), ("release", release)):
    environment = current["environment"]
    for name, expected in expected_paths.items():
        if environment.get(name) != expected:
            raise SystemExit(f"{label} Compose {name} must be {expected!r}")

expected_overrides = {
    "LEDGER_SERVER_TRUSTED_PROXIES": "10.0.0.0/8",
    "LEDGER_SERVER_MAX_JSON_BODY_BYTES": "2097152",
    "LEDGER_DATABASE_DRIVER": "postgres",
    "LEDGER_DATABASE_DSN": "postgres://ledger@db:5432/ledger?sslmode=require",
    "LEDGER_DATABASE_MAX_OPEN_CONNS": "12",
    "LEDGER_DATABASE_MAX_IDLE_CONNS": "6",
    "LEDGER_JWT_ACCESS_EXPIRE": "20",
    "LEDGER_JWT_REFRESH_EXPIRE": "50000",
    "LEDGER_CREDENTIAL_ENCRYPTION_KEY": "credential-primary-validation-only",
    "LEDGER_CREDENTIAL_ENCRYPTION_PREVIOUS_KEY": "credential-previous-validation-only",
    "LEDGER_SECURITY_BASE_PATH": "/private",
    "LEDGER_SECURITY_ALLOW_PRIVATE_OUTBOUND": "true",
    "LEDGER_CORS_ALLOWED_ORIGINS": "https://ledger.example.test",
    "LEDGER_LOG_LEVEL": "warn",
    "LEDGER_LOG_FORMAT": "text",
    "LEDGER_STORAGE_MAX_FILE_SIZE": "20",
    "LEDGER_STORAGE_RESTORE_MAX_FILE_SIZE": "96",
    "LEDGER_STORAGE_ALLOWED_TYPES": "png,pdf",
    "LEDGER_OBSERVABILITY_METRICS_ENABLED": "true",
    "LEDGER_OBSERVABILITY_METRICS_TOKEN": "metrics-validation-only",
    "LEDGER_RATE_LIMIT_MAX_REQUESTS": "321",
    "LEDGER_RATE_LIMIT_WINDOW_SECS": "45",
    "TZ": "UTC",
}
for name, expected in expected_overrides.items():
    if override["environment"].get(name) != expected:
        raise SystemExit(f"Compose override {name} did not resolve to {expected!r}")

if release.get("image") != release_image:
    raise SystemExit("Generated release Compose asset is not pinned to the requested digest")
PY

"$ROOT_DIR/scripts/check-toolchain-consistency.sh"

echo "Docker release preflight checks passed."
