#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-/opt/fedora-validity}"
VENV="$PREFIX/venv"
OPEN_FPRINTD="$VENV/lib/open-fprintd/open-fprintd"
STOP_STOCK_FPRINTD=0

usage() {
  cat <<'USAGE'
Usage: run-open-fprintd-debug.sh [--stop-stock-fprintd]

Runs open-fprintd in the foreground on the system bus.

Options:
  --stop-stock-fprintd  Temporarily stop Fedora's stock fprintd.service before
                        starting open-fprintd. This does not disable the unit.
USAGE
}

section() {
  printf '\n===== %s =====\n' "$1"
}

require_file() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    printf '[error] missing expected path: %s\n' "$path" >&2
    printf '[hint] Run scripts/build-open-fprintd.sh first.\n' >&2
    exit 1
  fi
}

while (($# > 0)); do
  case "$1" in
    --stop-stock-fprintd)
      STOP_STOCK_FPRINTD=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf '[error] unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

section "preflight"
require_file "$VENV/bin/python"
require_file "$OPEN_FPRINTD"
"$VENV/bin/python" -c "import dbus, gi, openfprintd; print('open-fprintd imports ok')"

if systemctl is-active --quiet fprintd.service; then
  section "stock fprintd service is active"
  if [[ "$STOP_STOCK_FPRINTD" == "1" ]]; then
    printf '$ sudo systemctl stop fprintd.service\n'
    sudo systemctl stop fprintd.service
  else
    printf '[error] stock fprintd.service is active and may own net.reactivated.Fprint during startup.\n' >&2
    printf '[hint] Stop it for this foreground test with: %s --stop-stock-fprintd\n' "$0" >&2
    exit 4
  fi
fi

if busctl --system list | awk '$1 == "net.reactivated.Fprint" && $2 != "-" { found=1 } END { exit !found }'; then
  section "existing net.reactivated.Fprint owner"
  busctl --system list | grep -F 'net.reactivated.Fprint' || true
  if [[ "$STOP_STOCK_FPRINTD" == "1" ]]; then
    printf '$ sudo systemctl stop fprintd.service\n'
    sudo systemctl stop fprintd.service
  else
    printf '[error] net.reactivated.Fprint is already owned. Re-run with --stop-stock-fprintd for a temporary foreground test.\n' >&2
    exit 3
  fi
fi

section "start open-fprintd foreground"
printf '$ sudo %q %q --debug\n' "$VENV/bin/python" "$OPEN_FPRINTD"
sudo "$VENV/bin/python" "$OPEN_FPRINTD" --debug
