#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin" "$TMPDIR/etc-pam.d" "$TMPDIR/etc-authselect"

cat >"$TMPDIR/etc-pam.d/system-auth" <<'EOF'
auth        sufficient                                   pam_fprintd.so
EOF

cat >"$TMPDIR/etc-authselect/system-auth" <<'EOF'
auth        sufficient                                   pam_fprintd.so
EOF

cat >"$TMPDIR/bin/authselect" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "current" ]]; then
  printf 'Profile ID: local\n'
  printf 'Enabled features:\n'
  printf -- '- with-fingerprint\n'
  exit 0
fi
exit 1
EOF

cat >"$TMPDIR/bin/rpm" <<'EOF'
#!/usr/bin/env bash
printf 'fprintd-1.94.5-5.fc44.x86_64\n'
printf 'fprintd-pam-1.94.5-5.fc44.x86_64\n'
printf 'libfprint-1.94.10-1.fc44.x86_64\n'
EOF

cat >"$TMPDIR/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "is-enabled" ]]; then
  printf 'enabled\n'
  exit 0
fi
if [[ "${1:-}" == "is-active" ]]; then
  printf 'active\n'
  exit 0
fi
exit 0
EOF

cat >"$TMPDIR/bin/fprintd-list" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >"$TMPDIR/fprintd-list-args"
printf 'Fingerprints for user testuser on DBus driver (press):\n'
printf ' - #0: right-index-finger\n'
EOF

cat >"$TMPDIR/bin/fprintd-verify" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TMPDIR/fprintd-verify-args"
exit 0
EOF

cat >"$TMPDIR/check-dbus-chain.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >"$TMPDIR/check-dbus-chain-args"
printf '[ok] dbus chain\n'
EOF

chmod +x "$TMPDIR/bin/"* "$TMPDIR/check-dbus-chain.sh"

OUTPUT="$(
  PATH="$TMPDIR/bin:$PATH" \
  PAM_DIR="$TMPDIR/etc-pam.d" \
  AUTHSELECT_DIR="$TMPDIR/etc-authselect" \
  CHECK_DBUS_CHAIN="$TMPDIR/check-dbus-chain.sh" \
  USER=testuser \
  "$ROOT/scripts/check-pam-state.sh"
)"

grep -F 'Profile ID: local' <<<"$OUTPUT" >/dev/null
grep -F 'with-fingerprint' <<<"$OUTPUT" >/dev/null
grep -F 'pam_fprintd.so' <<<"$OUTPUT" >/dev/null
grep -F 'fprintd-pam-1.94.5-5.fc44.x86_64' <<<"$OUTPUT" >/dev/null
grep -F '[ok] dbus chain' <<<"$OUTPUT" >/dev/null
grep -F 'fprintd-verify skipped' <<<"$OUTPUT" >/dev/null

if [[ "$(cat "$TMPDIR/fprintd-list-args")" != "testuser" ]]; then
  printf 'expected fprintd-list to receive testuser\n' >&2
  exit 1
fi

if [[ -e "$TMPDIR/fprintd-verify-args" ]]; then
  printf 'check-pam-state.sh must not run fprintd-verify without --verify\n' >&2
  exit 1
fi

PATH="$TMPDIR/bin:$PATH" \
PAM_DIR="$TMPDIR/etc-pam.d" \
AUTHSELECT_DIR="$TMPDIR/etc-authselect" \
CHECK_DBUS_CHAIN="$TMPDIR/check-dbus-chain.sh" \
USER=testuser \
"$ROOT/scripts/check-pam-state.sh" --verify >/dev/null

if [[ "$(cat "$TMPDIR/fprintd-verify-args")" != "testuser" ]]; then
  printf 'expected --verify to call fprintd-verify testuser\n' >&2
  exit 1
fi
