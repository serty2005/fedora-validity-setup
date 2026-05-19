#!/usr/bin/env bash
set -euo pipefail

PREFIX="/opt/fedora-validity"
VENV="$PREFIX/venv"
FIRMWARE_TOOL="$VENV/bin/validity-sensors-firmware"
ENSURE_FIRMWARE_SCRIPT="${ENSURE_FIRMWARE_SCRIPT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ensure-firmware.sh}"

section() {
  printf '\n===== %s =====\n' "$1"
}

require_file() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    printf '[error] missing expected path: %s\n' "$path" >&2
    printf '[hint] Run scripts/build-python-validity.sh first.\n' >&2
    exit 1
  fi
}

section "preflight"
require_file "$FIRMWARE_TOOL"
require_file "$ENSURE_FIRMWARE_SCRIPT"

section "ensure runtime firmware and persistent cache"
printf '$ sudo %q\n' "$ENSURE_FIRMWARE_SCRIPT"
sudo "$ENSURE_FIRMWARE_SCRIPT"
