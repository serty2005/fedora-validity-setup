#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin"

cat >"$TMPDIR/bin/pgrep" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF

cat >"$TMPDIR/bin/busctl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TMPDIR/busctl-args"
if [[ "\${1:-}" == "--system" && "\${2:-}" == "call" ]]; then
  count_file="$TMPDIR/busctl-call-count"
  count=0
  if [[ -f "\$count_file" ]]; then
    count="\$(cat "\$count_file")"
  fi
  count=\$((count + 1))
  printf '%s\n' "\$count" >"\$count_file"
  if [[ "\$count" -eq 1 ]]; then
    printf 'ao 0\n'
  else
    printf 'ao 1 "/net/reactivated/Fprint/Device/0"\n'
  fi
  exit 0
fi
exit 1
EOF

cat >"$TMPDIR/bin/systemctl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TMPDIR/systemctl-args"
exit 0
EOF

cat >"$TMPDIR/bin/sudo" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TMPDIR/sudo-args"
if [[ "\${1:-}" == "-v" ]]; then
  exit 0
fi
"\$@"
EOF

cat >"$TMPDIR/bin/journalctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat >"$TMPDIR/bin/fprintd-list" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >"$TMPDIR/fprintd-list-args"
exit 0
EOF

cat >"$TMPDIR/bin/fprintd-verify" <<'EOF'
#!/usr/bin/env bash
printf 'fprintd-verify should not run without --verify\n' >&2
exit 99
EOF

chmod +x "$TMPDIR/bin/pgrep" "$TMPDIR/bin/busctl" "$TMPDIR/bin/systemctl" "$TMPDIR/bin/sudo" "$TMPDIR/bin/journalctl" "$TMPDIR/bin/fprintd-list" "$TMPDIR/bin/fprintd-verify"

PATH="$TMPDIR/bin:$PATH" USER=testuser "$ROOT/scripts/systemd-test.sh" >/tmp/systemd-test-list-only.out 2>&1

grep -F 'stop fprintd.service' "$TMPDIR/systemctl-args" >/dev/null
grep -F 'start open-fprintd.service' "$TMPDIR/systemctl-args" >/dev/null
grep -F 'start python3-validity.service' "$TMPDIR/systemctl-args" >/dev/null
grep -F 'status open-fprintd.service python3-validity.service --no-pager' "$TMPDIR/systemctl-args" >/dev/null
if grep -F 'reset-failed open-fprintd.service python3-validity.service' "$TMPDIR/systemctl-args" >/dev/null; then
  printf 'systemd-test must not require reset-failed for project units; Fedora may report them as not loaded\n' >&2
  cat "$TMPDIR/systemctl-args" >&2
  exit 1
fi
grep -F 'net.reactivated.Fprint /net/reactivated/Fprint/Manager net.reactivated.Fprint.Manager GetDevices' "$TMPDIR/busctl-args" >/dev/null

if [[ "$(cat "$TMPDIR/busctl-call-count")" -lt 2 ]]; then
  printf 'expected systemd-test to wait until GetDevices reports a registered device\n' >&2
  cat /tmp/systemd-test-list-only.out >&2
  exit 1
fi

if [[ "$(cat "$TMPDIR/fprintd-list-args")" != "testuser" ]]; then
  printf 'expected fprintd-list to receive USER, got: %s\n' "$(cat "$TMPDIR/fprintd-list-args")" >&2
  cat /tmp/systemd-test-list-only.out >&2
  exit 1
fi
