#!/usr/bin/env bash
# The gate: every fixture tree through the Python oracle (tools/oracle.py) and through CASES
# (the Mojo runner built from tests/cases.mojo), outputs identical, each side twice; then the API test
# and the example, both on the fixture. Never touches the real /sys.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${CASES:?FAIL setup: set CASES to the built case runner}"
mkdir -p .work
M=.venv/bin/mojo
n=0
for root in tests/fixtures/*/; do
  root=${root%/}
  python3 -I tools/oracle.py "$root" > .work/exp.txt
  for run in 1 2; do
    timeout 30 "$CASES" "$root" > .work/got.txt || { echo "FAIL run: runner exited non-zero on $root"; exit 1; }
    diff .work/exp.txt .work/got.txt > .work/diff.txt || { echo "FAIL oracle: $root differs from Python (run $run)"; head -20 .work/diff.txt; exit 1; }
  done
  echo "oracle: $root identical ($(wc -l < .work/exp.txt) lines, 2 runs)"
  n=$((n+1))
done
rm -rf .work/api; cp -r tests/fixtures/edge .work/api
$M run -I src tests/api.mojo || { echo "FAIL api: tests/api.mojo"; exit 1; }
$M run -I src examples/quickstart.mojo > /dev/null || { echo "FAIL example: examples/quickstart.mojo"; exit 1; }
echo "fixtures: $n"
echo "PASS all"
