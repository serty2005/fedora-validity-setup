#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin" "$TMPDIR/etc-dbus" "$TMPDIR/usr-dbus" "$TMPDIR/runtime" "$TMPDIR/cache"
touch "$TMPDIR/etc-dbus/io.github.uunicorn.Fprint.conf"
touch "$TMPDIR/usr-dbus/net.reactivated.Fprint.conf"
touch "$TMPDIR/runtime/6_07f_lenovo_mis_qm.xpfwext"

cat >"$TMPDIR/bin/lsusb" <<'EOF'
#!/usr/bin/env bash
printf 'Bus 001 Device 011: ID 138a:0097 Validity Sensors, Inc.\n'
EOF

cat >"$TMPDIR/bin/busctl" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--system" && "${2:-}" == "list" ]]; then
  printf 'net.reactivated.Fprint 950 python root :1.19 open-fprintd.service - -\n'
  exit 0
fi
if [[ "${1:-}" == "--system" && "${2:-}" == "tree" ]]; then
  printf '/net/reactivated/Fprint/Device/0\n'
  exit 0
fi
if [[ "${1:-}" == "--system" && "${2:-}" == "introspect" ]]; then
  printf '.RegisterDevice method o - -\n'
  printf '.ListEnrolledFingers method s as -\n'
  exit 0
fi
if [[ "${1:-}" == "--system" && "${2:-}" == "call" ]]; then
  printf 'ao 1 "/net/reactivated/Fprint/Device/0"\n'
  exit 0
fi
exit 1
EOF

cat >"$TMPDIR/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "is-active" ]]; then
  case "${2:-}" in
    fprintd.service) printf 'inactive\n'; exit 3 ;;
    open-fprintd.service|python3-validity.service) printf 'active\n'; exit 0 ;;
  esac
fi
exit 0
EOF

cat >"$TMPDIR/bin/fprintd-list" <<'EOF'
#!/usr/bin/env bash
printf 'found 1 devices\n'
printf 'ListEnrolledFingers failed: GDBus.Error:org.freedesktop.DBus.Python.usb.core.USBError: usb.core.USBError: [Errno 19] No such device (it may have been disconnected)\n' >&2
exit 1
EOF

chmod +x "$TMPDIR/bin/lsusb" "$TMPDIR/bin/busctl" "$TMPDIR/bin/systemctl" "$TMPDIR/bin/fprintd-list"

set +e
OUTPUT="$(
  PATH="$TMPDIR/bin:$PATH" \
  DBUS_ETC_DIR="$TMPDIR/etc-dbus" \
  DBUS_USR_DIR="$TMPDIR/usr-dbus" \
  RUNTIME_DIR="$TMPDIR/runtime" \
  FIRMWARE_CACHE_DIR="$TMPDIR/cache" \
  USER=testuser \
  "$ROOT/scripts/check-dbus-chain.sh" 2>&1
)"
STATUS=$?
set -e

if [[ "$STATUS" -ne 21 ]]; then
  printf 'expected exit 21 for USB no-device, got %s\n%s\n' "$STATUS" "$OUTPUT" >&2
  exit 1
fi

grep -F '[diagnosis] python-validity reached the USB backend, but the device handle is stale or disconnected.' <<<"$OUTPUT" >/dev/null
grep -F './scripts/systemd-test.sh --verify' <<<"$OUTPUT" >/dev/null
