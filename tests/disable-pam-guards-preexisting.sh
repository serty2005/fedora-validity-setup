#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin" "$TMPDIR/state"

cat >"$TMPDIR/bin/authselect" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "current" ]]; then
  printf 'Profile ID: local\n'
  printf 'Enabled features:\n'
  printf -- '- with-fingerprint\n'
  exit 0
fi
printf 'unexpected direct authselect command: %s\n' "$*" >&2
exit 44
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

OUTPUT="$(
  PATH="$TMPDIR/bin:$PATH" \
  FEDORA_VALIDITY_STATE_DIR="$TMPDIR/state" \
  "$ROOT/scripts/disable-pam.sh"
)"

grep -F 'No project marker found' <<<"$OUTPUT" >/dev/null

if [[ -e "$TMPDIR/sudo-args" ]]; then
  printf 'disable-pam.sh must not call sudo authselect without project marker or --force\n' >&2
  cat "$TMPDIR/sudo-args" >&2
  exit 1
fi

PATH="$TMPDIR/bin:$PATH" \
FEDORA_VALIDITY_STATE_DIR="$TMPDIR/state" \
"$ROOT/scripts/disable-pam.sh" --force >/dev/null

grep -F 'authselect disable-feature with-fingerprint' "$TMPDIR/sudo-args" >/dev/null
grep -F 'authselect apply-changes' "$TMPDIR/sudo-args" >/dev/null
