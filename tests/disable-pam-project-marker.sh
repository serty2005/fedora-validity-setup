#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin" "$TMPDIR/state"

cat >"$TMPDIR/state/pam-authselect-with-fingerprint.env" <<'EOF'
project_changed_authselect=1
backup_dir=/tmp/example-backup
EOF

cat >"$TMPDIR/bin/authselect" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "current" ]]; then
  printf 'Profile ID: local\n'
  printf 'Enabled features:\n'
  printf -- '- with-fingerprint\n'
  exit 0
fi
printf 'unexpected direct authselect command: %s\n' "$*" >&2
exit 45
EOF

cat >"$TMPDIR/bin/sudo" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TMPDIR/sudo-args"
if [[ "\${1:-}" == "authselect" ]]; then
  exit 0
fi
"\$@"
EOF

chmod +x "$TMPDIR/bin/"*

PATH="$TMPDIR/bin:$PATH" \
FEDORA_VALIDITY_STATE_DIR="$TMPDIR/state" \
"$ROOT/scripts/disable-pam.sh" >/dev/null

grep -F 'authselect disable-feature with-fingerprint' "$TMPDIR/sudo-args" >/dev/null
grep -F 'authselect apply-changes' "$TMPDIR/sudo-args" >/dev/null

if [[ -e "$TMPDIR/state/pam-authselect-with-fingerprint.env" ]]; then
  printf 'disable-pam.sh must remove project marker after rollback\n' >&2
  exit 1
fi
