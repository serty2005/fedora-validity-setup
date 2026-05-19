#!/usr/bin/env bash
set -euo pipefail

DEVICE_ID="${DEVICE_ID:-138a:0097}"
TARGET_USER="${USER:-}"
DBUS_ETC_DIR="${DBUS_ETC_DIR:-/etc/dbus-1/system.d}"
DBUS_USR_DIR="${DBUS_USR_DIR:-/usr/share/dbus-1/system.d}"
RUNTIME_DIR="${RUNTIME_DIR:-/var/run/python-validity}"
FIRMWARE_CACHE_DIR="${FIRMWARE_CACHE_DIR:-/opt/fedora-validity/firmware/python-validity}"

usage() {
  cat <<'USAGE'
Usage: check-dbus-chain.sh [USER]

Checks the current fprintd/open-fprintd/python-validity chain without changing
system state. It does not restart services, does not install policy files and
does not change PAM/authselect/GDM/sudo.
USAGE
}

section() {
  printf '\n===== %s =====\n' "$1"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf '[error] missing command: %s\n' "$cmd" >&2
    exit 1
  fi
}

run_optional() {
  printf '$'
  printf ' %q' "$@"
  printf '\n'
  "$@" || true
}

require_policy() {
  local filename="$1"
  if [[ -f "$DBUS_ETC_DIR/$filename" ]]; then
    printf '[ok] %s found in %s\n' "$filename" "$DBUS_ETC_DIR"
    return 0
  fi
  if [[ -f "$DBUS_USR_DIR/$filename" ]]; then
    printf '[ok] %s found in %s\n' "$filename" "$DBUS_USR_DIR"
    return 0
  fi
  printf '[warning] %s not found in %s or %s\n' "$filename" "$DBUS_ETC_DIR" "$DBUS_USR_DIR"
  return 1
}

service_is_active() {
  local service="$1"
  systemctl is-active "$service" >/dev/null 2>&1
}

classify_fprintd_list_failure() {
  local output="$1"

  if grep -F 'org.freedesktop.DBus.Error.AccessDenied' <<<"$output" >/dev/null; then
    printf '[diagnosis] D-Bus policy denial while listing enrolled fingers.\n' >&2
    printf '[hint] Run ./scripts/install-dbus-policy.sh, then restart the project debug/systemd services before retesting.\n' >&2
    exit 20
  fi

  if grep -F 'usb.core.USBError' <<<"$output" >/dev/null && grep -F 'No such device' <<<"$output" >/dev/null; then
    printf '[diagnosis] python-validity reached the USB backend, but the device handle is stale or disconnected.\n' >&2
    printf '[hint] The registered D-Bus device is stale. Restart through ./scripts/systemd-test.sh --verify or restart open-fprintd.service and python3-validity.service from a local terminal.\n' >&2
    exit 21
  fi

  if grep -F 'No devices available' <<<"$output" >/dev/null; then
    printf '[diagnosis] fprintd client path is alive, but no backend device is registered.\n' >&2
    printf '[hint] Check python-validity registration and GetDevices output above.\n' >&2
    exit 22
  fi

  printf '[diagnosis] fprintd-list failed with an unclassified error.\n' >&2
  printf '[hint] Inspect the fprintd-list output above and service journals.\n' >&2
  exit 23
}

while (($# > 0)); do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      TARGET_USER="$1"
      ;;
  esac
  shift
done

if [[ -z "$TARGET_USER" ]]; then
  printf '[error] no target user specified and USER is empty.\n' >&2
  exit 2
fi

for cmd in busctl fprintd-list lsusb systemctl; do
  require_cmd "$cmd"
done

section "USB sensor"
if lsusb_line="$(lsusb -d "$DEVICE_ID" 2>/dev/null | head -n 1)" && [[ -n "$lsusb_line" ]]; then
  printf '[ok] %s\n' "$lsusb_line"
else
  printf '[error] USB device %s was not found by lsusb.\n' "$DEVICE_ID" >&2
  exit 10
fi

section "firmware files"
if compgen -G "$RUNTIME_DIR/*.xpfwext" >/dev/null; then
  printf '[ok] runtime firmware exists in %s\n' "$RUNTIME_DIR"
else
  printf '[warning] no runtime .xpfwext file found in %s\n' "$RUNTIME_DIR"
fi
if compgen -G "$FIRMWARE_CACHE_DIR/*.xpfwext" >/dev/null; then
  printf '[ok] firmware cache exists in %s\n' "$FIRMWARE_CACHE_DIR"
else
  printf '[warning] no cached .xpfwext file found in %s\n' "$FIRMWARE_CACHE_DIR"
fi

section "D-Bus ownership"
bus_list="$(busctl --system list)"
printf '%s\n' "$bus_list" | grep -i -E 'fprint|validity|uunicorn' || true

if ! awk '$1 == "net.reactivated.Fprint" && $2 != "-" { found=1 } END { exit !found }' <<<"$bus_list"; then
  printf '[error] net.reactivated.Fprint is not currently owned.\n' >&2
  exit 11
fi

if awk '$1 == "net.reactivated.Fprint" && $6 == "open-fprintd.service" { found=1 } END { exit !found }' <<<"$bus_list"; then
  printf '[ok] net.reactivated.Fprint is owned by open-fprintd.service.\n'
else
  printf '[warning] net.reactivated.Fprint is owned, but not by open-fprintd.service.\n'
fi

section "stock fprintd conflict"
if service_is_active fprintd.service; then
  printf '[warning] stock fprintd.service is active and may conflict with open-fprintd.\n'
else
  printf '[ok] stock fprintd.service is not active.\n'
fi
if service_is_active open-fprintd.service; then
  printf '[ok] open-fprintd.service is active.\n'
else
  printf '[warning] open-fprintd.service is not active.\n'
fi
if service_is_active python3-validity.service; then
  printf '[ok] python3-validity.service is active.\n'
else
  printf '[warning] python3-validity.service is not active.\n'
fi

section "D-Bus object tree"
run_optional busctl --system tree net.reactivated.Fprint

section "D-Bus introspection"
manager_introspection="$(busctl --system introspect net.reactivated.Fprint /net/reactivated/Fprint/Manager 2>&1 || true)"
printf '%s\n' "$manager_introspection"
if grep -F '.RegisterDevice' <<<"$manager_introspection" >/dev/null; then
  printf '[ok] manager exposes RegisterDevice; owner looks like open-fprintd.\n'
else
  printf '[error] manager does not expose RegisterDevice; current owner may be stock fprintd.\n' >&2
  exit 12
fi

device_introspection="$(busctl --system introspect net.reactivated.Fprint /net/reactivated/Fprint/Device/0 2>&1 || true)"
printf '%s\n' "$device_introspection"
if grep -F '.ListEnrolledFingers' <<<"$device_introspection" >/dev/null; then
  printf '[ok] device exposes ListEnrolledFingers.\n'
else
  printf '[warning] /net/reactivated/Fprint/Device/0 does not expose ListEnrolledFingers or is absent.\n'
fi

section "D-Bus policy files"
require_policy net.reactivated.Fprint.conf || true
require_policy io.github.uunicorn.Fprint.conf || true

section "polkit actions"
printf '$ grep -R %q %q %q\n' 'fprint\|validity\|uunicorn' /usr/share/polkit-1/actions /etc/polkit-1
grep -R 'fprint\|validity\|uunicorn' /usr/share/polkit-1/actions /etc/polkit-1 2>/dev/null || true

section "registered devices"
devices="$(
  busctl --system call net.reactivated.Fprint /net/reactivated/Fprint/Manager net.reactivated.Fprint.Manager GetDevices 2>/dev/null || true
)"
printf '%s\n' "${devices:-no response}"
if [[ ! "$devices" =~ ^ao[[:space:]]+[1-9] ]]; then
  printf '[error] GetDevices did not report a registered fingerprint device.\n' >&2
  exit 13
fi

section "fprintd-list"
printf '$ fprintd-list %q\n' "$TARGET_USER"
set +e
list_output="$(fprintd-list "$TARGET_USER" 2>&1)"
list_status=$?
set -e
printf '%s\n' "$list_output"

if [[ "$list_status" -ne 0 ]]; then
  classify_fprintd_list_failure "$list_output"
fi

printf '[ok] fprintd-list completed without D-Bus/USB error.\n'
