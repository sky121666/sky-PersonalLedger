#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/web/dist"

if [[ ! -f "$DIST_DIR/index.html" ]]; then
  echo "web/dist/index.html is missing; run the production build first" >&2
  exit 1
fi

python3 - \
  "$DIST_DIR" \
  "${WEB_BUNDLE_MAX_TOTAL_BYTES:-1000000}" \
  "${WEB_BUNDLE_MAX_GZIP_BYTES:-400000}" \
  "${WEB_BUNDLE_MAX_JS_CHUNK_BYTES:-200000}" \
  "${WEB_BUNDLE_MAX_CSS_CHUNK_BYTES:-120000}" \
  "${WEB_BUNDLE_MAX_INDEX_BYTES:-20000}" <<'PY'
import gzip
import pathlib
import sys

(
    dist_text,
    max_total_text,
    max_gzip_text,
    max_js_text,
    max_css_text,
    max_index_text,
) = sys.argv[1:]

dist = pathlib.Path(dist_text)
limits = {
    "total": int(max_total_text),
    "gzip": int(max_gzip_text),
    "js": int(max_js_text),
    "css": int(max_css_text),
    "index": int(max_index_text),
}
files = sorted(path for path in dist.rglob("*") if path.is_file())
if not files:
    raise SystemExit("web production output is empty")

sizes = {path: path.stat().st_size for path in files}
total = sum(sizes.values())
gzip_total = sum(len(gzip.compress(path.read_bytes(), compresslevel=9)) for path in files)
largest_js = max((size for path, size in sizes.items() if path.suffix == ".js"), default=0)
largest_css = max((size for path, size in sizes.items() if path.suffix == ".css"), default=0)
index_size = sizes[dist / "index.html"]

measurements = {
    "total": total,
    "gzip": gzip_total,
    "js": largest_js,
    "css": largest_css,
    "index": index_size,
}
labels = {
    "total": "total raw bytes",
    "gzip": "total gzip bytes",
    "js": "largest JavaScript chunk bytes",
    "css": "largest CSS chunk bytes",
    "index": "index.html bytes",
}

failures = []
for key, actual in measurements.items():
    maximum = limits[key]
    print(f"Web bundle {labels[key]}: {actual} (budget {maximum})")
    if actual > maximum:
        failures.append(f"{labels[key]} {actual} exceeds budget {maximum}")

if failures:
    raise SystemExit("\n".join(failures))
PY

echo "Web performance budget checks passed."
