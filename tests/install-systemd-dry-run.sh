#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin" "$TMPDIR/etc-systemd" "$TMPDIR/backups"

cat >"$TMPDIR/bin/systemctl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TMPDIR/systemctl-args"
exit 0
EOF

cat >"$TMPDIR/bin/sudo" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TMPDIR/sudo-args"
exit 0
EOF

cat >"$TMPDIR/install-dbus-policy.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TMPDIR/dbus-policy-args"
exit 0
EOF

chmod +x "$TMPDIR/bin/systemctl" "$TMPDIR/bin/sudo" "$TMPDIR/install-dbus-policy.sh"

OUTPUT="$(
  PATH="$TMPDIR/bin:$PATH" \
  SYSTEMD_DEST_DIR="$TMPDIR/etc-systemd" \
  SYSTEMD_BACKUP_ROOT="$TMPDIR/backups" \
  DBUS_POLICY_SCRIPT="$TMPDIR/install-dbus-policy.sh" \
  "$ROOT/scripts/install-systemd.sh" --dry-run
)"

grep -F 'open-fprintd.service' <<<"$OUTPUT" >/dev/null
grep -F 'python3-validity.service' <<<"$OUTPUT" >/dev/null
grep -F '/opt/fedora-validity/bin/ensure-firmware.sh' <<<"$OUTPUT" >/dev/null
grep -F 'enable requested: no' <<<"$OUTPUT" >/dev/null

grep -F -- '--dry-run' "$TMPDIR/dbus-policy-args" >/dev/null
grep -F 'systemctl daemon-reload' <<<"$OUTPUT" >/dev/null

if grep -F 'systemctl enable' <<<"$OUTPUT" >/dev/null; then
  printf 'install-systemd.sh must not enable services by default\n' >&2
  printf '%s\n' "$OUTPUT" >&2
  exit 1
fi

if grep -R -E 'authselect|pam_fprintd|gdm|/etc/pam\.d' "$TMPDIR" >/dev/null; then
  printf 'install-systemd dry-run must not touch PAM/authselect/GDM\n' >&2
  exit 1
fi
