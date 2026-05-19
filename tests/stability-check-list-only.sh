#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin"

cat >"$TMPDIR/bin/check-dbus-chain.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TMPDIR/check-dbus-chain-args"
exit 0
EOF

cat >"$TMPDIR/bin/enroll-test.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TMPDIR/enroll-test-args"
exit 0
EOF

cat >"$TMPDIR/bin/fprintd-verify" <<'EOF'
#!/usr/bin/env bash
printf 'fprintd-verify should not run without --verify\n' >&2
exit 99
EOF

chmod +x "$TMPDIR/bin/"*

PATH="$TMPDIR/bin:$PATH" \
PROJECT_ROOT="$TMPDIR" \
USER=testuser \
"$ROOT/scripts/stability-check.sh" --iterations 2 >/tmp/stability-check-list-only.out 2>&1

if [[ "$(wc -l <"$TMPDIR/check-dbus-chain-args")" != "2" ]]; then
  printf 'expected two check-dbus-chain calls\n' >&2
  cat /tmp/stability-check-list-only.out >&2
  exit 1
fi

if [[ "$(wc -l <"$TMPDIR/enroll-test-args")" != "2" ]]; then
  printf 'expected two enroll-test calls\n' >&2
  cat /tmp/stability-check-list-only.out >&2
  exit 1
fi

if grep -v -F -- '--list-only testuser' "$TMPDIR/enroll-test-args" >/dev/null; then
  printf 'expected enroll-test to run only list-only checks for testuser\n' >&2
  cat "$TMPDIR/enroll-test-args" >&2
  exit 1
fi
