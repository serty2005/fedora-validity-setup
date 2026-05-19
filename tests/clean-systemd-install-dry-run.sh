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

chmod +x "$TMPDIR/bin/systemctl" "$TMPDIR/bin/sudo"

OUTPUT="$(PATH="$TMPDIR/bin:$PATH" "$ROOT/scripts/clean-systemd-install.sh" --dry-run 2>&1)"
touch "$TMPDIR/systemctl-args" "$TMPDIR/sudo-args"

grep -F 'systemctl stop open-fprintd.service python3-validity.service' <<<"$OUTPUT" >/dev/null
grep -F 'systemctl disable open-fprintd.service python3-validity.service' <<<"$OUTPUT" >/dev/null
grep -F '/etc/systemd/system/open-fprintd.service' <<<"$OUTPUT" >/dev/null
grep -F '/etc/systemd/system/python3-validity.service' <<<"$OUTPUT" >/dev/null
grep -F 'systemctl daemon-reload' <<<"$OUTPUT" >/dev/null
grep -F 'install-systemd.sh' <<<"$OUTPUT" >/dev/null

if grep -F 'reset-failed open-fprintd.service python3-validity.service' <<<"$OUTPUT" >/dev/null; then
  printf 'clean-systemd-install must not call reset-failed for project units; Fedora may report them as not loaded\n' >&2
  printf '%s\n' "$OUTPUT" >&2
  exit 1
fi

if grep -E 'authselect|pam_fprintd|gdm|/etc/pam\.d|/etc/dbus-1/system.d/io.github.uunicorn.Fprint.conf' "$TMPDIR/systemctl-args" "$TMPDIR/sudo-args" >/dev/null; then
  printf 'clean-systemd-install must not touch PAM/authselect/GDM or D-Bus policy\n' >&2
  exit 1
fi
