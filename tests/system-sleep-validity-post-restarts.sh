#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cat >"$TMPDIR/restart-project-services.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TMPDIR/restart-helper-args"
EOF
chmod +x "$TMPDIR/restart-project-services.sh"

FEDORA_VALIDITY_RESTART_HELPER="$TMPDIR/restart-project-services.sh" \
  "$ROOT/scripts/system-sleep-validity.sh" post suspend >/tmp/system-sleep-validity-post.out 2>&1

grep -F 'post suspend' /tmp/system-sleep-validity-post.out >/dev/null
if [[ ! -f "$TMPDIR/restart-helper-args" ]]; then
  printf 'expected post sleep hook to call restart helper\n' >&2
  cat /tmp/system-sleep-validity-post.out >&2
  exit 1
fi
grep -F -- '--no-status' "$TMPDIR/restart-helper-args" >/dev/null
