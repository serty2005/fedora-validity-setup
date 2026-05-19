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
  printf 'net.reactivated.Fprint 123 python root :1.1 session-c1.scope c1 -\n'
  exit 0
fi
if [[ "${1:-}" == "--system" && "${2:-}" == "introspect" ]]; then
  printf '.RegisterDevice method o - -\n'
  exit 0
fi
exit 1
EOF

cat >"$TMPDIR/bin/lsusb" <<EOF
#!/usr/bin/env bash
count_file="$TMPDIR/lsusb-count"
count=0
if [[ -f "\$count_file" ]]; then
  count="\$(cat "\$count_file")"
fi
count=\$((count + 1))
printf '%s\n' "\$count" >"\$count_file"
if [[ "\$count" -eq 1 ]]; then
  printf 'Bus 001 Device 006: ID 138a:0097 Validity Sensors, Inc. \n'
else
  printf 'Bus 001 Device 008: ID 138a:0097 Validity Sensors, Inc. \n'
fi
EOF

cat >"$TMPDIR/bin/sudo" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TMPDIR/sudo-args"
exit 0
EOF

chmod +x "$TMPDIR/bin/busctl" "$TMPDIR/bin/lsusb" "$TMPDIR/bin/sudo"

PATH="$TMPDIR/bin:$PATH" RUNTIME_DIR="$TMPDIR/runtime" "$ROOT/scripts/run-python-validity-debug.sh" --auto-devpath >/tmp/run-python-validity-debug-test.out 2>&1

run_count="$(wc -l <"$TMPDIR/sudo-args")"
if [[ "$run_count" -ne 2 ]]; then
  printf 'expected 2 python-validity launch attempts after first normal exit, got %s\n' "$run_count" >&2
  cat /tmp/run-python-validity-debug-test.out >&2
  exit 1
fi

if ! tail -n 1 "$TMPDIR/sudo-args" | grep -F -- '--devpath usb-001-008' >/dev/null; then
  printf 'expected second launch to refresh devpath to usb-001-008\n' >&2
  cat "$TMPDIR/sudo-args" >&2
  exit 1
fi
