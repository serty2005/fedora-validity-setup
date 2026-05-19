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

cat >"$TMPDIR/bin/fprintd-verify" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TMPDIR/fprintd-verify-args"
exit 0
EOF

chmod +x "$TMPDIR/bin/"*

PATH="$TMPDIR/bin:$PATH" \
PROJECT_ROOT="$TMPDIR" \
USER=testuser \
"$ROOT/scripts/stability-check.sh" --iterations 2 --verify >/tmp/stability-check-verify.out 2>&1

if [[ "$(wc -l <"$TMPDIR/fprintd-verify-args")" != "2" ]]; then
  printf 'expected two fprintd-verify calls\n' >&2
  cat /tmp/stability-check-verify.out >&2
  exit 1
fi

if grep -v -F -- 'testuser' "$TMPDIR/fprintd-verify-args" >/dev/null; then
  printf 'expected fprintd-verify to receive testuser\n' >&2
  cat "$TMPDIR/fprintd-verify-args" >&2
  exit 1
fi
