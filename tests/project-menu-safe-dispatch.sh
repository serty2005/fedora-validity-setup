#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MENU="$ROOT/scripts/project-menu.sh"

if grep -E '\b(systemctl|authselect|busctl|dbus-send|gdbus|fprintd-(list|enroll|verify)|sudo)\b' "$MENU" >/dev/null; then
  printf 'project-menu.sh must delegate to project scripts instead of running system commands directly\n' >&2
  exit 1
fi

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
  if ! grep -F "$helper" "$MENU" >/dev/null; then
    printf 'project-menu.sh does not reference required helper: %s\n' "$helper" >&2
    exit 1
  fi
done
