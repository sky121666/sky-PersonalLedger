#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

LIST_MAX_NS="${BACKEND_PERF_LIST_MAX_NS:-50000000}"
LIST_MAX_BYTES="${BACKEND_PERF_LIST_MAX_BYTES:-1000000}"
LIST_MAX_ALLOCS="${BACKEND_PERF_LIST_MAX_ALLOCS:-10000}"
SUMMARY_MAX_NS="${BACKEND_PERF_SUMMARY_MAX_NS:-50000000}"
SUMMARY_MAX_BYTES="${BACKEND_PERF_SUMMARY_MAX_BYTES:-250000}"
SUMMARY_MAX_ALLOCS="${BACKEND_PERF_SUMMARY_MAX_ALLOCS:-1000}"

cd "$ROOT_DIR/backend"
go test ./internal/database -run '^TestOperationalQueryIndexesExistAndDriveSQLitePlans$' -count=1
go test ./internal/repository \
  -run '^$' \
  -bench '^BenchmarkTransactionRepository' \
  -benchmem \
  -benchtime=5x \
  -count=1 | tee "$TMP_DIR/benchmark.txt"

python3 - \
  "$TMP_DIR/benchmark.txt" \
  "$LIST_MAX_NS" "$LIST_MAX_BYTES" "$LIST_MAX_ALLOCS" \
  "$SUMMARY_MAX_NS" "$SUMMARY_MAX_BYTES" "$SUMMARY_MAX_ALLOCS" <<'PY'
import re
import sys

(
    path,
    list_max_ns,
    list_max_bytes,
    list_max_allocs,
    summary_max_ns,
    summary_max_bytes,
    summary_max_allocs,
) = sys.argv[1:]

limits = {
    "BenchmarkTransactionRepositoryListRecentPage": tuple(
        map(int, (list_max_ns, list_max_bytes, list_max_allocs))
    ),
    "BenchmarkTransactionRepositoryMonthlySummary": tuple(
        map(int, (summary_max_ns, summary_max_bytes, summary_max_allocs))
    ),
}
results = {}
pattern = re.compile(
    r"^(Benchmark\S+)-\d+\s+\d+\s+(\d+) ns/op\s+(\d+) B/op\s+(\d+) allocs/op$"
)

with open(path, encoding="utf-8") as handle:
    for raw_line in handle:
        match = pattern.match(raw_line.strip())
        if not match:
            continue
        name, ns_per_op, bytes_per_op, allocs_per_op = match.groups()
        results[name] = tuple(map(int, (ns_per_op, bytes_per_op, allocs_per_op)))

missing = sorted(set(limits) - set(results))
if missing:
    raise SystemExit(f"missing benchmark results: {', '.join(missing)}")

failures = []
for name, maximums in limits.items():
    actuals = results[name]
    labels = ("ns/op", "B/op", "allocs/op")
    print(
        f"{name}: {actuals[0]} ns/op, {actuals[1]} B/op, "
        f"{actuals[2]} allocs/op"
    )
    for label, actual, maximum in zip(labels, actuals, maximums):
        if actual > maximum:
            failures.append(f"{name} {label} {actual} exceeds budget {maximum}")

if failures:
    raise SystemExit("\n".join(failures))
PY

echo "Backend performance contract checks passed."
