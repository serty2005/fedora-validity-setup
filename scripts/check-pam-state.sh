#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TARGET_USER="${USER:-}"
PAM_DIR="${PAM_DIR:-/etc/pam.d}"
AUTHSELECT_DIR="${AUTHSELECT_DIR:-/etc/authselect}"
CHECK_DBUS_CHAIN="${CHECK_DBUS_CHAIN:-$PROJECT_ROOT/scripts/check-dbus-chain.sh}"
VERIFY=0

usage() {
  cat <<'USAGE'
Usage: check-pam-state.sh [--verify] [USER]

Shows current PAM/authselect/fingerprint state without changing the system.
By default it runs fprintd-list only. fprintd-verify runs only when --verify is
explicitly requested.

Options:
  --verify  Also run fprintd-verify USER.
USAGE
}

section() {
  printf '\n===== %s =====\n' "$1"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf '[error] missing command: %s\n' "$cmd" >&2
    exit 1
  fi
}

run_optional() {
  printf '$'
  printf ' %q' "$@"
  printf '\n'
  "$@" || true
}

while (($# > 0)); do
  case "$1" in
    --verify)
      VERIFY=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      printf '[error] unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      TARGET_USER="$1"
      ;;
  esac
  shift
done

if [[ -z "$TARGET_USER" ]]; then
  printf '[error] no target user specified and USER is empty.\n' >&2
  exit 2
fi

for cmd in authselect fprintd-list rpm systemctl; do
  require_cmd "$cmd"
done
if [[ "$VERIFY" == "1" ]]; then
  require_cmd fprintd-verify
fi
if [[ ! -x "$CHECK_DBUS_CHAIN" ]]; then
  printf '[error] check-dbus-chain helper is not executable: %s\n' "$CHECK_DBUS_CHAIN" >&2
  exit 1
fi

section "authselect current"
run_optional authselect current

section "pam_fprintd references"
printf '$ grep -R %q %q %q\n' pam_fprintd "$PAM_DIR" "$AUTHSELECT_DIR"
grep -R 'pam_fprintd' "$PAM_DIR" "$AUTHSELECT_DIR" 2>/dev/null || true

section "installed packages"
run_optional rpm -q fprintd fprintd-pam libfprint

section "service layer status"
run_optional systemctl is-enabled open-fprintd.service python3-validity.service
run_optional systemctl is-active open-fprintd.service python3-validity.service
run_optional "$CHECK_DBUS_CHAIN" --wait 20 "$TARGET_USER"

section "fprintd-list"
run_optional fprintd-list "$TARGET_USER"

section "fprintd-verify"
if [[ "$VERIFY" == "1" ]]; then
  run_optional fprintd-verify "$TARGET_USER"
else
  printf '[info] fprintd-verify skipped. Use --verify for physical verification.\n'
fi

section "notes"
printf 'check-pam-state.sh is read-only and does not change PAM/authselect/GDM/sudo.\n'
