#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin" "$TMPDIR/pam.d" "$TMPDIR/authselect" "$TMPDIR/backups" "$TMPDIR/state"
touch "$TMPDIR/pam.d/system-auth" "$TMPDIR/pam.d/password-auth" "$TMPDIR/authselect/authselect.conf"

cat >"$TMPDIR/bin/authselect" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "current" ]]; then
  printf 'Profile ID: local\n'
  printf 'Enabled features:\n'
  printf -- '- with-mdns4\n'
  exit 0
fi
printf 'unexpected direct authselect command: %s\n' "$*" >&2
exit 43
EOF

cat >"$TMPDIR/bin/fprintd-verify" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >"$TMPDIR/fprintd-verify-args"
exit 0
EOF

cat >"$TMPDIR/check-dbus-chain.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >"$TMPDIR/check-dbus-chain-args"
exit 0
EOF

cat >"$TMPDIR/bin/sudo" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TMPDIR/sudo-args"
if [[ "\${1:-}" == "authselect" ]]; then
  exit 0
fi
"\$@"
EOF

chmod +x "$TMPDIR/bin/"* "$TMPDIR/check-dbus-chain.sh"

OUTPUT="$(
  PATH="$TMPDIR/bin:$PATH" \
  CHECK_DBUS_CHAIN="$TMPDIR/check-dbus-chain.sh" \
  PAM_DIR="$TMPDIR/pam.d" \
  AUTHSELECT_DIR="$TMPDIR/authselect" \
  PAM_BACKUP_ROOT="$TMPDIR/backups" \
  FEDORA_VALIDITY_STATE_DIR="$TMPDIR/state" \
  USER=testuser \
  "$ROOT/scripts/enable-pam.sh"
)"

grep -F 'authselect enable-feature with-fingerprint' "$TMPDIR/sudo-args" >/dev/null
grep -F 'authselect apply-changes' "$TMPDIR/sudo-args" >/dev/null
grep -F 'project_changed_authselect=1' "$TMPDIR"/backups/pam-*/manifest.env >/dev/null
grep -F 'project_changed_authselect=1' "$TMPDIR/state/pam-authselect-with-fingerprint.env" >/dev/null
grep -F 'Rollback command: ./scripts/disable-pam.sh' <<<"$OUTPUT" >/dev/null

if [[ "$(cat "$TMPDIR/check-dbus-chain-args")" != "--wait 20" ]]; then
  printf 'expected check-dbus-chain --wait 20\n' >&2
  exit 1
fi

if [[ "$(cat "$TMPDIR/fprintd-verify-args")" != "testuser" ]]; then
  printf 'expected fprintd-verify testuser\n' >&2
  exit 1
fi
