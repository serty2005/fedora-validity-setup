#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="/opt/fedora-validity"
VENV="$PREFIX/venv"
REPO="$PROJECT_ROOT/third_party/open-fprintd"

section() {
  printf '\n===== %s =====\n' "$1"
}

require_file() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    printf '[error] missing expected path: %s\n' "$path" >&2
    exit 1
  fi
}

section "preflight"
require_file "$VENV/bin/python"
require_file "$REPO/setup.py"
"$VENV/bin/python" --version
git -C "$REPO" rev-parse HEAD

section "install open-fprintd into venv"
printf '$ sudo %q -m pip install --upgrade --no-deps %q\n' "$VENV/bin/python" "$REPO"
sudo "$VENV/bin/python" -m pip install --upgrade --no-deps "$REPO"

section "verify open-fprintd imports and files"
"$VENV/bin/python" -c "import dbus, gi, openfprintd; print('open-fprintd imports ok')"
require_file "$VENV/lib/open-fprintd/open-fprintd"
require_file "$VENV/share/dbus-1/system.d/net.reactivated.Fprint.conf"
require_file "$VENV/share/dbus-1/system-services/net.reactivated.Fprint.service"
printf 'open-fprintd executable: %s\n' "$VENV/lib/open-fprintd/open-fprintd"
