#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RULE="$ROOT/udev/99-validity-138a0097.rules"

[[ -f "$RULE" ]]

grep -F 'ATTR{idVendor}=="138a"' "$RULE" >/dev/null
grep -F 'ATTR{idProduct}=="0097"' "$RULE" >/dev/null
grep -F 'TAG+="systemd"' "$RULE" >/dev/null
grep -F 'ENV{SYSTEMD_WANTS}+="python3-validity.service"' "$RULE" >/dev/null

if grep -F 'MODE="0666"' "$RULE" >/dev/null; then
  printf 'udev rule must not make the USB device world-writable\n' >&2
  exit 1
fi
