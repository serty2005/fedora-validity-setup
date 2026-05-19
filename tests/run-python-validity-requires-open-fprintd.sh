#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin" "$TMPDIR/runtime"
touch "$TMPDIR/runtime/fake.xpfwext"

cat >"$TMPDIR/bin/busctl" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--system" && "${2:-}" == "list" ]]; then
  printf 'net.reactivated.Fprint 123 fprintd root :1.1 fprintd.service - -\n'
  exit 0
fi
if [[ "${1:-}" == "--system" && "${2:-}" == "introspect" ]]; then
  printf '.GetDevices method - ao -\n'
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
printf 'sudo should not run when RegisterDevice is missing\n' >&2
exit 99
EOF

chmod +x "$TMPDIR/bin/busctl" "$TMPDIR/bin/lsusb" "$TMPDIR/bin/sudo"

set +e
PATH="$TMPDIR/bin:$PATH" RUNTIME_DIR="$TMPDIR/runtime" "$ROOT/scripts/run-python-validity-debug.sh" --auto-devpath >/tmp/run-python-validity-requires-open-fprintd.out 2>&1
status=$?
set -e

if [[ "$status" -ne 6 ]]; then
  printf 'expected exit 6 when RegisterDevice is missing, got %s\n' "$status" >&2
  cat /tmp/run-python-validity-requires-open-fprintd.out >&2
  exit 1
fi

grep -F 'RegisterDevice' /tmp/run-python-validity-requires-open-fprintd.out >/dev/null
