#!/usr/bin/env bash
# CI entry point, same on a GitHub runner and a local Ubuntu VM: install, build the case runner, then the gate.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v uv >/dev/null || { echo "FAIL setup: uv not installed"; exit 1; }
command -v python3 >/dev/null || { echo "FAIL setup: python3 (the oracle) not found"; exit 1; }
uv sync || { echo "FAIL setup: uv sync"; exit 1; }
mkdir -p .work
.venv/bin/mojo build -I src tests/cases.mojo -o .work/cases || { echo "FAIL build: tests/cases.mojo"; exit 1; }
CASES=.work/cases scripts/check.sh
