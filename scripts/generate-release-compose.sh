#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_FILE="${RELEASE_COMPOSE_SOURCE:-$ROOT_DIR/docker-compose.yml}"
OUTPUT_FILE="${1:-}"
RELEASE_IMAGE="${RELEASE_IMAGE:-}"

if [[ -z "$OUTPUT_FILE" || -z "$RELEASE_IMAGE" ]]; then
  echo "Usage: RELEASE_IMAGE=ghcr.io/owner/repo@sha256:<digest> $0 <output-file>" >&2
  exit 2
fi

python3 - "$SOURCE_FILE" "$OUTPUT_FILE" "$RELEASE_IMAGE" <<'PY'
import os
import pathlib
import re
import sys
import tempfile


source = pathlib.Path(sys.argv[1]).resolve()
output = pathlib.Path(sys.argv[2]).resolve()
image = sys.argv[3]

if not re.fullmatch(r"ghcr[.]io/[a-z0-9._-]+/[a-z0-9._-]+@sha256:[0-9a-f]{64}", image):
    raise SystemExit("RELEASE_IMAGE must be a lowercase GHCR reference pinned by sha256 digest")
if source == output:
    raise SystemExit("Refusing to overwrite the tracked Compose source")

text = source.read_text(encoding="utf-8")
pattern = re.compile(
    r"^(?P<indent>[ ]*)image:[ ]+[$][{]LEDGER_IMAGE:-[^}]+[}][ ]*$",
    re.MULTILINE,
)
text, replacements = pattern.subn(
    lambda match: f"{match.group('indent')}image: {image}",
    text,
)
if replacements != 1:
    raise SystemExit(f"Expected exactly one LEDGER_IMAGE service reference, found {replacements}")
if ":latest" in text:
    raise SystemExit("Generated release Compose asset must not contain a latest image reference")

output.parent.mkdir(parents=True, exist_ok=True)
with tempfile.NamedTemporaryFile(
    "w",
    encoding="utf-8",
    dir=output.parent,
    prefix=f".{output.name}.",
    delete=False,
) as handle:
    handle.write(f"# Immutable release image: {image}\n")
    handle.write(text)
    temporary = pathlib.Path(handle.name)
os.replace(temporary, output)
PY
