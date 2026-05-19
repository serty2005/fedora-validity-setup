#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-/opt/fedora-validity}"
VENV="$PREFIX/venv"
PYTHON_VALIDITY="$VENV/lib/python-validity/dbus-service"
CONFIG_DIR="$PREFIX/etc/python-validity"
DEVICE_ID="138a:0097"
RUNTIME_DIR="${RUNTIME_DIR:-/var/run/python-validity}"
DEVPATH_ARG=()
AUTO_DEVPATH=0
REBOOT_RETRIES=1

usage() {
  cat <<'USAGE'
Usage: run-python-validity-debug.sh [--auto-devpath] [--reboot-retries N]

Runs python-validity backend in the foreground on the system bus.

Options:
  --auto-devpath  Detect the 138a:0097 USB bus/device from lsusb and pass
                  --devpath usb-<bus>-<device> to python-validity.
  --reboot-retries N
                  When --auto-devpath is used, retry N times if the backend
                  exits normally after rebooting the sensor. Default: 1.
USAGE
}

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

refresh_devpath() {
  local lsusb_line
  local usb_bus
  local usb_device

  lsusb_line="$(lsusb -d "$DEVICE_ID" 2>/dev/null | head -n 1 || true)"
  if [[ -z "$lsusb_line" ]]; then
    printf '[error] USB device %s was not found by lsusb.\n' "$DEVICE_ID" >&2
    exit 4
  fi

  usb_bus="$(awk '{print $2}' <<<"$lsusb_line")"
  usb_device="$(awk '{gsub(":", "", $4); print $4}' <<<"$lsusb_line")"
  DEVPATH_ARG=(--devpath "usb-${usb_bus}-${usb_device}")
}

while (($# > 0)); do
  case "$1" in
    --auto-devpath)
      AUTO_DEVPATH=1
      refresh_devpath
      ;;
    --reboot-retries)
      if [[ -z "${2:-}" || ! "${2:-}" =~ ^[0-9]+$ ]]; then
        printf '[error] --reboot-retries requires a non-negative integer.\n' >&2
        exit 2
      fi
      REBOOT_RETRIES="$2"
      shift
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
require_file "$PYTHON_VALIDITY"
"$VENV/bin/python" -c "import dbus, gi, usb, yaml, cryptography, validitysensor; print('python-validity imports ok')"

if ! compgen -G "$RUNTIME_DIR/*.xpfwext" >/dev/null; then
  printf '[error] no firmware .xpfwext file found in %s.\n' "$RUNTIME_DIR" >&2
  printf '[hint] Run scripts/prepare-firmware.sh before starting python-validity.\n' >&2
  exit 5
fi

if ! busctl --system list | awk '$1 == "net.reactivated.Fprint" && $2 != "-" { found=1 } END { exit !found }'; then
  printf '[error] net.reactivated.Fprint is not currently owned. Start scripts/run-open-fprintd-debug.sh in another terminal first.\n' >&2
  exit 3
fi

if ! busctl --system introspect net.reactivated.Fprint /net/reactivated/Fprint/Manager net.reactivated.Fprint.Manager 2>/dev/null | awk '$1 == ".RegisterDevice" { found=1 } END { exit !found }'; then
  printf '[error] net.reactivated.Fprint owner does not expose RegisterDevice.\n' >&2
  printf '[hint] This is usually stock fprintd, not open-fprintd. Restart the first terminal with: scripts/run-open-fprintd-debug.sh --stop-stock-fprintd\n' >&2
  exit 6
fi

if [[ ! -f "$CONFIG_DIR/dbus-service.yaml" ]]; then
  section "create default config"
  printf '$ sudo mkdir -p %q\n' "$CONFIG_DIR"
  sudo mkdir -p "$CONFIG_DIR"
  printf '$ sudo tee %q\n' "$CONFIG_DIR/dbus-service.yaml"
  printf 'user_to_sid: {}\n' | sudo tee "$CONFIG_DIR/dbus-service.yaml" >/dev/null
fi

section "start python-validity foreground"
attempt=0
while true; do
  if [[ "$AUTO_DEVPATH" == "1" ]]; then
    refresh_devpath
  fi

  printf '$ sudo %q %q --debug --configpath %q' "$VENV/bin/python" "$PYTHON_VALIDITY" "$CONFIG_DIR"
  printf ' %q' "${DEVPATH_ARG[@]}"
  printf '\n'

  set +e
  sudo "$VENV/bin/python" "$PYTHON_VALIDITY" --debug --configpath "$CONFIG_DIR" "${DEVPATH_ARG[@]}"
  status=$?
  set -e

  if [[ "$status" -ne 0 ]]; then
    exit "$status"
  fi

  if [[ "$AUTO_DEVPATH" != "1" || "$attempt" -ge "$REBOOT_RETRIES" ]]; then
    exit 0
  fi

  attempt=$((attempt + 1))
  printf '[note] python-validity exited normally. The sensor may have rebooted; retrying with refreshed USB devpath (%s/%s).\n' "$attempt" "$REBOOT_RETRIES"
  sleep 2
done
