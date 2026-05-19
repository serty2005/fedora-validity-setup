#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin"

cat >"$TMPDIR/bin/busctl" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--system" && "${2:-}" == "list" ]]; then
  printf 'net.reactivated.Fprint 123 python root :1.1 session-c1.scope c1 -\n'
  exit 0
fi
exit 1
EOF

cat >"$TMPDIR/bin/fprintd-list" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >"$TMPDIR/fprintd-list-args"
exit 0
EOF

cat >"$TMPDIR/bin/fprintd-enroll" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >"$TMPDIR/fprintd-enroll-args"
exit 0
EOF

cat >"$TMPDIR/bin/fprintd-verify" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >"$TMPDIR/fprintd-verify-args"
exit 0
EOF

chmod +x "$TMPDIR/bin/busctl" "$TMPDIR/bin/fprintd-list" "$TMPDIR/bin/fprintd-enroll" "$TMPDIR/bin/fprintd-verify"

PATH="$TMPDIR/bin:$PATH" USER=testuser "$ROOT/scripts/enroll-test.sh" --finger right-index-finger >/tmp/enroll-test-finger.out 2>&1

if [[ "$(cat "$TMPDIR/fprintd-list-args")" != "testuser" ]]; then
  printf 'expected fprintd-list to receive USER, got: %s\n' "$(cat "$TMPDIR/fprintd-list-args")" >&2
  cat /tmp/enroll-test-finger.out >&2
  exit 1
fi

if [[ "$(cat "$TMPDIR/fprintd-enroll-args")" != "--finger right-index-finger testuser" ]]; then
  printf 'expected fprintd-enroll to receive --finger and USER, got: %s\n' "$(cat "$TMPDIR/fprintd-enroll-args")" >&2
  cat /tmp/enroll-test-finger.out >&2
  exit 1
fi

if [[ "$(cat "$TMPDIR/fprintd-verify-args")" != "testuser" ]]; then
  printf 'expected fprintd-verify to receive USER, got: %s\n' "$(cat "$TMPDIR/fprintd-verify-args")" >&2
  cat /tmp/enroll-test-finger.out >&2
  exit 1
fi
