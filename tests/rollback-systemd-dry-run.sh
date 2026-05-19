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
exit 0
EOF

cat >"$TMPDIR/bin/busctl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TMPDIR/busctl-args"
exit 0
EOF

chmod +x "$TMPDIR/bin/systemctl" "$TMPDIR/bin/sudo" "$TMPDIR/bin/busctl"

OUTPUT="$(PATH="$TMPDIR/bin:$PATH" "$ROOT/scripts/rollback.sh" --dry-run 2>&1)"
touch "$TMPDIR/systemctl-args" "$TMPDIR/sudo-args" "$TMPDIR/busctl-args"

grep -F 'systemctl stop open-fprintd.service python3-validity.service' <<<"$OUTPUT" >/dev/null
grep -F 'systemctl disable open-fprintd.service python3-validity.service' <<<"$OUTPUT" >/dev/null
grep -F 'systemctl daemon-reload' <<<"$OUTPUT" >/dev/null
grep -F '/etc/systemd/system/open-fprintd.service' <<<"$OUTPUT" >/dev/null
grep -F '/etc/systemd/system/python3-validity.service' <<<"$OUTPUT" >/dev/null
grep -F '/etc/dbus-1/system.d/io.github.uunicorn.Fprint.conf' <<<"$OUTPUT" >/dev/null
grep -F '/opt/fedora-validity/bin/ensure-firmware.sh' <<<"$OUTPUT" >/dev/null
grep -F '/opt/fedora-validity/bin/restart-project-services.sh' <<<"$OUTPUT" >/dev/null
grep -F '/usr/lib/systemd/system-sleep/fedora-validity-setup' <<<"$OUTPUT" >/dev/null

if grep -E 'authselect|pam_fprintd|gdm|/etc/pam\.d' "$TMPDIR/systemctl-args" "$TMPDIR/sudo-args" "$TMPDIR/busctl-args" >/dev/null; then
  printf 'rollback must not run commands that touch PAM/authselect/GDM\n' >&2
  exit 1
fi
