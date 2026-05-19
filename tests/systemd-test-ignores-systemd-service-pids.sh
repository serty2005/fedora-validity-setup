#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin"

cat >"$TMPDIR/bin/pgrep" <<'EOF'
#!/usr/bin/env bash
printf '10808 /opt/fedora-validity/venv/bin/python /opt/fedora-validity/venv/lib/open-fprintd/open-fprintd --debug\n'
printf '10864 /opt/fedora-validity/venv/bin/python /opt/fedora-validity/venv/lib/python-validity/dbus-service --debug --configpath /opt/fedora-validity/etc/python-validity\n'
exit 0
EOF

cat >"$TMPDIR/bin/systemctl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TMPDIR/systemctl-args"
if [[ "\${1:-}" == "show" && "\${2:-}" == "-p" && "\${3:-}" == "MainPID" && "\${4:-}" == "--value" ]]; then
  case "\${5:-}" in
    open-fprintd.service)
      printf '10808\n'
      ;;
    python3-validity.service)
      printf '10864\n'
      ;;
    *)
      printf '0\n'
      ;;
  esac
fi
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

cat >"$TMPDIR/bin/busctl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TMPDIR/busctl-args"
if [[ "\${1:-}" == "--system" && "\${2:-}" == "call" ]]; then
  printf 'ao 1 "/net/reactivated/Fprint/Device/0"\n'
  exit 0
fi
exit 1
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

chmod +x "$TMPDIR/bin/"*

PATH="$TMPDIR/bin:$PATH" USER=testuser "$ROOT/scripts/systemd-test.sh" >/tmp/systemd-test-ignores-systemd-service-pids.out 2>&1

grep -F 'no foreground project processes detected' /tmp/systemd-test-ignores-systemd-service-pids.out >/dev/null
grep -F 'start open-fprintd.service' "$TMPDIR/systemctl-args" >/dev/null

if [[ "$(cat "$TMPDIR/fprintd-list-args")" != "testuser" ]]; then
  printf 'expected fprintd-list to receive USER after ignoring systemd-owned pids\n' >&2
  cat /tmp/systemd-test-ignores-systemd-service-pids.out >&2
  exit 1
fi
