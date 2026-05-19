#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin"

cat >"$TMPDIR/bin/busctl" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--system" && "${2:-}" == "list" ]]; then
  printf 'net.reactivated.Fprint - - - (activatable) - - -\n'
  exit 0
fi
exit 1
EOF

cat >"$TMPDIR/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "is-active" && "${2:-}" == "--quiet" && "${3:-}" == "fprintd.service" ]]; then
  exit 0
fi
exit 1
EOF

cat >"$TMPDIR/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo should not run when stock fprintd is active without explicit flag\n' >&2
exit 99
EOF

chmod +x "$TMPDIR/bin/busctl" "$TMPDIR/bin/systemctl" "$TMPDIR/bin/sudo"

set +e
PATH="$TMPDIR/bin:$PATH" "$ROOT/scripts/run-open-fprintd-debug.sh" >/tmp/run-open-fprintd-refuses-active-stock.out 2>&1
status=$?
set -e

if [[ "$status" -ne 4 ]]; then
  printf 'expected exit 4 for active stock fprintd, got %s\n' "$status" >&2
  cat /tmp/run-open-fprintd-refuses-active-stock.out >&2
  exit 1
fi

grep -F -- '--stop-stock-fprintd' /tmp/run-open-fprintd-refuses-active-stock.out >/dev/null
