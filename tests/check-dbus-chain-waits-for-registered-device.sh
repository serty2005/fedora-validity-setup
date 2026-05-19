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
printf 'Bus 001 Device 012: ID 138a:0097 Validity Sensors, Inc.\n'
EOF

cat >"$TMPDIR/bin/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat >"$TMPDIR/bin/busctl" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "--system" && "\${2:-}" == "list" ]]; then
  printf 'net.reactivated.Fprint 950 python root :1.19 open-fprintd.service - -\n'
  exit 0
fi
if [[ "\${1:-}" == "--system" && "\${2:-}" == "tree" ]]; then
  printf '/net/reactivated/Fprint/Device/0\n'
  exit 0
fi
if [[ "\${1:-}" == "--system" && "\${2:-}" == "introspect" ]]; then
  printf '.RegisterDevice method o - -\n'
  printf '.ListEnrolledFingers method s as -\n'
  exit 0
fi
if [[ "\${1:-}" == "--system" && "\${2:-}" == "call" ]]; then
  count_file="$TMPDIR/getdevices-count"
  count=0
  if [[ -f "\$count_file" ]]; then
    count="\$(cat "\$count_file")"
  fi
  count=\$((count + 1))
  printf '%s\n' "\$count" >"\$count_file"
  if [[ "\$count" -lt 3 ]]; then
    printf 'ao 0\n'
  else
    printf 'ao 1 "/net/reactivated/Fprint/Device/0"\n'
  fi
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
printf 'Device at /net/reactivated/Fprint/Device/0\n'
printf 'Fingerprints for user testuser on DBus driver (press):\n'
printf ' - #0: right-index-finger\n'
EOF

chmod +x "$TMPDIR/bin/"*

OUTPUT="$(
  PATH="$TMPDIR/bin:$PATH" \
  DBUS_ETC_DIR="$TMPDIR/etc-dbus" \
  DBUS_USR_DIR="$TMPDIR/usr-dbus" \
  RUNTIME_DIR="$TMPDIR/runtime" \
  FIRMWARE_CACHE_DIR="$TMPDIR/cache" \
  USER=testuser \
  "$ROOT/scripts/check-dbus-chain.sh" --wait 5
)"

if [[ "$(cat "$TMPDIR/getdevices-count")" != "3" ]]; then
  printf 'expected GetDevices to be retried until a device is registered\n' >&2
  exit 1
fi

grep -F 'ao 1 "/net/reactivated/Fprint/Device/0"' <<<"$OUTPUT" >/dev/null
