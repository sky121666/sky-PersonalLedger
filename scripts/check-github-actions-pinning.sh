#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

python3 - "$ROOT_DIR/.github/workflows" <<'PY'
import pathlib
import re
import sys


workflow_dir = pathlib.Path(sys.argv[1])
if not workflow_dir.is_dir():
    raise SystemExit(f"Workflow directory does not exist: {workflow_dir}")

uses_pattern = re.compile(r"^\s*(?:-\s*)?uses:\s*['\"]?([^'\"\s#]+)")
commit_pattern = re.compile(r"^[^@\s]+@[0-9a-f]{40}$")
docker_pattern = re.compile(r"^docker://[^@\s]+@sha256:[0-9a-f]{64}$")
failures = []

for path in sorted((*workflow_dir.glob("*.yml"), *workflow_dir.glob("*.yaml"))):
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        match = uses_pattern.match(line)
        if match is None:
            continue
        reference = match.group(1)
        if reference.startswith("./"):
            continue
        if reference.startswith("docker://"):
            valid = docker_pattern.fullmatch(reference) is not None
        else:
            valid = commit_pattern.fullmatch(reference) is not None
        if not valid:
            failures.append(f"{path.relative_to(workflow_dir.parent.parent)}:{line_number}: {reference}")

if failures:
    print("External GitHub Actions must use immutable commit SHAs:", file=sys.stderr)
    for failure in failures:
        print(f"  {failure}", file=sys.stderr)
    raise SystemExit(1)

print("GitHub Actions immutable pinning checks passed.")
PY
