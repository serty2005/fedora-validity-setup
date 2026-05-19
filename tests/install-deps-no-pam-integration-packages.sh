#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/install-deps.sh"

if grep -E '^[[:space:]]*(authselect|fprintd-pam)[[:space:]]*$' "$SCRIPT" >/dev/null; then
  printf 'install-deps.sh must not install PAM/authselect integration packages in iteration 005\n' >&2
  exit 1
fi
