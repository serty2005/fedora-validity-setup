#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin" "$TMPDIR/runtime"

cat >"$TMPDIR/bin/busctl" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--system" && "${2:-}" == "list" ]]; then
  printf 'net.reactivated.Fprint 123 python root :1.1 session-c1.scope c1 -\n'
  exit 0
fi
if [[ "${1:-}" == "--system" && "${2:-}" == "introspect" ]]; then
  printf '.RegisterDevice method o - -\n'
  exit 0
fi
exit 1
EOF

cat >"$TMPDIR/bin/lsusb" <<'EOF'
#!/usr/bin/env bash
printf 'Bus 001 Device 006: ID 138a:0097 Validity Sensors, Inc. \n'
EOF

cat >"$TMPDIR/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo should not run when firmware is missing\n' >&2
exit 99
EOF

chmod +x "$TMPDIR/bin/busctl" "$TMPDIR/bin/lsusb" "$TMPDIR/bin/sudo"

set +e
PATH="$TMPDIR/bin:$PATH" RUNTIME_DIR="$TMPDIR/runtime" "$ROOT/scripts/run-python-validity-debug.sh" --auto-devpath >/tmp/run-python-validity-requires-firmware.out 2>&1
status=$?
set -e

if [[ "$status" -ne 5 ]]; then
  printf 'expected exit 5 for missing firmware, got %s\n' "$status" >&2
  cat /tmp/run-python-validity-requires-firmware.out >&2
  exit 1
fi

grep -F 'prepare-firmware.sh' /tmp/run-python-validity-requires-firmware.out >/dev/null
