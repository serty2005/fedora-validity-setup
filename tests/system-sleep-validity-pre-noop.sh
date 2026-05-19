#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cat >"$TMPDIR/restart-project-services.sh" <<'EOF'
#!/usr/bin/env bash
printf 'restart helper must not run for pre phase\n' >&2
exit 99
EOF
chmod +x "$TMPDIR/restart-project-services.sh"

FEDORA_VALIDITY_RESTART_HELPER="$TMPDIR/restart-project-services.sh" \
  "$ROOT/scripts/system-sleep-validity.sh" pre suspend >/tmp/system-sleep-validity-pre.out 2>&1

grep -F 'pre suspend' /tmp/system-sleep-validity-pre.out >/dev/null
