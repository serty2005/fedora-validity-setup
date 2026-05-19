#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin"

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

chmod +x "$TMPDIR/bin/"*

PATH="$TMPDIR/bin:$PATH" "$ROOT/scripts/restart-project-services.sh" >/tmp/restart-project-services-order.out 2>&1

grep -F 'stop python3-validity.service' "$TMPDIR/systemctl-args" >/dev/null
grep -F 'stop open-fprintd.service' "$TMPDIR/systemctl-args" >/dev/null
grep -F 'stop fprintd.service' "$TMPDIR/systemctl-args" >/dev/null
grep -F 'start open-fprintd.service' "$TMPDIR/systemctl-args" >/dev/null
grep -F 'start python3-validity.service' "$TMPDIR/systemctl-args" >/dev/null

python_stop_line="$(grep -n -F 'stop python3-validity.service' "$TMPDIR/systemctl-args" | head -n 1 | cut -d: -f1)"
open_stop_line="$(grep -n -F 'stop open-fprintd.service' "$TMPDIR/systemctl-args" | head -n 1 | cut -d: -f1)"
stock_stop_line="$(grep -n -F 'stop fprintd.service' "$TMPDIR/systemctl-args" | head -n 1 | cut -d: -f1)"
open_start_line="$(grep -n -F 'start open-fprintd.service' "$TMPDIR/systemctl-args" | head -n 1 | cut -d: -f1)"
python_start_line="$(grep -n -F 'start python3-validity.service' "$TMPDIR/systemctl-args" | head -n 1 | cut -d: -f1)"

if (( python_stop_line >= open_stop_line || open_stop_line >= stock_stop_line || stock_stop_line >= open_start_line || open_start_line >= python_start_line )); then
  printf 'unexpected restart order:\n' >&2
  cat "$TMPDIR/systemctl-args" >&2
  exit 1
fi
