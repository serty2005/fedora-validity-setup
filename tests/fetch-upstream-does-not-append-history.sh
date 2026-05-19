#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/fetch-upstream.sh"

if grep -F '>> "$ITERATION_DOC"' "$SCRIPT" >/dev/null; then
  printf 'fetch-upstream.sh must not append generated upstream hashes to historical iteration docs\n' >&2
  exit 1
fi

grep -F 'docs/upstream-commits.md' "$SCRIPT" >/dev/null
