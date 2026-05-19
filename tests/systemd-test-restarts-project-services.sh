#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin"

cat >"$TMPDIR/bin/pgrep" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF

cat >"$TMPDIR/bin/busctl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TMPDIR/busctl-args"
if [[ "\${1:-}" == "--system" && "\${2:-}" == "call" ]]; then
  printf 'ao 1 "/net/reactivated/Fprint/Device/0"\n'
  exit 0
fi
exit 1
EOF

cat >"$TMPDIR/bin/systemctl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TMPDIR/systemctl-args"
exit 0
EOF

cat >"$TMPDIR/bin/sudo" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TMPDIR/sudo-args"
if [[ "\${1:-}" == "-v" ]]; then
  exit 0
fi
"\$@"
EOF

cat >"$TMPDIR/bin/journalctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat >"$TMPDIR/bin/fprintd-list" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >"$TMPDIR/fprintd-list-args"
exit 0
EOF

cat >"$TMPDIR/bin/fprintd-verify" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

chmod +x "$TMPDIR/bin/"*

PATH="$TMPDIR/bin:$PATH" USER=testuser "$ROOT/scripts/systemd-test.sh" >/tmp/systemd-test-restarts-project-services.out 2>&1

grep -F 'stop python3-validity.service' "$TMPDIR/systemctl-args" >/dev/null
grep -F 'stop open-fprintd.service' "$TMPDIR/systemctl-args" >/dev/null
grep -F 'stop fprintd.service' "$TMPDIR/systemctl-args" >/dev/null
grep -F 'start open-fprintd.service' "$TMPDIR/systemctl-args" >/dev/null
grep -F 'start python3-validity.service' "$TMPDIR/systemctl-args" >/dev/null

python_stop_line="$(grep -n -F 'stop python3-validity.service' "$TMPDIR/systemctl-args" | head -n 1 | cut -d: -f1)"
open_stop_line="$(grep -n -F 'stop open-fprintd.service' "$TMPDIR/systemctl-args" | head -n 1 | cut -d: -f1)"
open_start_line="$(grep -n -F 'start open-fprintd.service' "$TMPDIR/systemctl-args" | head -n 1 | cut -d: -f1)"
python_start_line="$(grep -n -F 'start python3-validity.service' "$TMPDIR/systemctl-args" | head -n 1 | cut -d: -f1)"

if (( python_stop_line >= open_stop_line || open_stop_line >= open_start_line || open_start_line >= python_start_line )); then
  printf 'unexpected service restart order:\n' >&2
  cat "$TMPDIR/systemctl-args" >&2
  exit 1
fi
