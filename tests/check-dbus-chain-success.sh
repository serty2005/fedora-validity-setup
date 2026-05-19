#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin" "$TMPDIR/etc-dbus" "$TMPDIR/usr-dbus" "$TMPDIR/runtime" "$TMPDIR/cache"
touch "$TMPDIR/etc-dbus/io.github.uunicorn.Fprint.conf"
touch "$TMPDIR/usr-dbus/net.reactivated.Fprint.conf"
touch "$TMPDIR/runtime/6_07f_lenovo_mis_qm.xpfwext"
touch "$TMPDIR/cache/6_07f_lenovo_mis_qm.xpfwext"

cat >"$TMPDIR/bin/lsusb" <<'EOF'
#!/usr/bin/env bash
printf 'Bus 001 Device 010: ID 138a:0097 Validity Sensors, Inc.\n'
EOF

cat >"$TMPDIR/bin/busctl" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--system" && "${2:-}" == "list" ]]; then
  printf ':1.19 950 python root :1.19 open-fprintd.service - -\n'
  printf ':1.31 1144 python root :1.31 python3-validity.service - -\n'
  printf 'net.reactivated.Fprint 950 python root :1.19 open-fprintd.service - -\n'
  exit 0
fi
if [[ "${1:-}" == "--system" && "${2:-}" == "tree" ]]; then
  printf '/net/reactivated/Fprint/Manager\n'
  printf '/net/reactivated/Fprint/Device/0\n'
  exit 0
fi
if [[ "${1:-}" == "--system" && "${2:-}" == "introspect" ]]; then
  if [[ "${4:-}" == "/net/reactivated/Fprint/Manager" ]]; then
    printf '.GetDevices method - ao -\n'
    printf '.RegisterDevice method o - -\n'
    exit 0
  fi
  if [[ "${4:-}" == "/net/reactivated/Fprint/Device/0" ]]; then
    printf '.ListEnrolledFingers method s as -\n'
    exit 0
  fi
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
if [[ "${1:-}" == "status" || "${1:-}" == "show" ]]; then
  exit 0
fi
exit 0
EOF

cat >"$TMPDIR/bin/fprintd-list" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >"$TMPDIR/fprintd-list-args"
printf 'found 1 devices\n'
printf 'Device at /net/reactivated/Fprint/Device/0\n'
printf 'Fingerprints for user testuser on DBus driver (press):\n'
printf ' - #0: right-index-finger\n'
EOF

chmod +x "$TMPDIR/bin/lsusb" "$TMPDIR/bin/busctl" "$TMPDIR/bin/systemctl" "$TMPDIR/bin/fprintd-list"

OUTPUT="$(
  PATH="$TMPDIR/bin:$PATH" \
  DBUS_ETC_DIR="$TMPDIR/etc-dbus" \
  DBUS_USR_DIR="$TMPDIR/usr-dbus" \
  RUNTIME_DIR="$TMPDIR/runtime" \
  FIRMWARE_CACHE_DIR="$TMPDIR/cache" \
  USER=testuser \
  "$ROOT/scripts/check-dbus-chain.sh"
)"

grep -F '[ok] fprintd-list completed without D-Bus/USB error.' <<<"$OUTPUT" >/dev/null

if [[ "$(cat "$TMPDIR/fprintd-list-args")" != "testuser" ]]; then
  printf 'expected fprintd-list to receive USER, got: %s\n' "$(cat "$TMPDIR/fprintd-list-args")" >&2
  exit 1
fi
