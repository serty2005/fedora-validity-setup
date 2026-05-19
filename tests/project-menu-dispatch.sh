#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/scripts"

make_helper() {
  local helper="$1"
  cat >"$TMPDIR/scripts/$helper" <<EOF
#!/usr/bin/env bash
printf '%s %s\n' "$helper" "\$*" >>"$TMPDIR/calls"
EOF
  chmod +x "$TMPDIR/scripts/$helper"
}

for helper in \
  check-dbus-chain.sh \
  stability-check.sh \
  systemd-test.sh \
  restart-project-services.sh \
  install-systemd.sh \
  check-pam-state.sh \
  enable-pam.sh \
  disable-pam.sh \
  enroll-test.sh \
  rollback.sh; do
  make_helper "$helper"
done

run_action() {
  PROJECT_ROOT="$TMPDIR" USER=testuser "$ROOT/scripts/project-menu.sh" --run "$@" >/tmp/project-menu-dispatch.out 2>&1
}

run_action check-dbus
run_action stability
run_action systemd-test
run_action restart-services
run_action install-systemd
run_action check-pam
run_action enable-pam
run_action disable-pam
run_action enroll
run_action rollback

cat >"$TMPDIR/expected" <<'EOF'
check-dbus-chain.sh --wait 20 testuser
stability-check.sh --iterations 2 --sleep 8 testuser
systemd-test.sh --verify testuser
restart-project-services.sh 
install-systemd.sh --enable
check-pam-state.sh --verify testuser
enable-pam.sh testuser
disable-pam.sh 
enroll-test.sh --finger right-index-finger testuser
rollback.sh 
EOF

if ! diff -u "$TMPDIR/expected" "$TMPDIR/calls"; then
  printf 'project-menu.sh dispatched unexpected commands\n' >&2
  cat /tmp/project-menu-dispatch.out >&2
  exit 1
fi
