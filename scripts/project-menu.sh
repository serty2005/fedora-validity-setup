#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TARGET_USER="${USER:-}"
FINGER="right-index-finger"
ACTION=""

usage() {
  cat <<'USAGE'
Usage: project-menu.sh [--run ACTION] [--user USER] [--finger FINGER]

Small dispatcher menu for the project service, enrollment, PAM and rollback
checks. This script delegates all system changes to existing project scripts.

Actions:
  check-dbus        Run check-dbus-chain.sh --wait 20 USER.
  stability         Run stability-check.sh --iterations 2 --sleep 8 USER.
  systemd-test      Run systemd-test.sh --verify USER.
  restart-services  Run restart-project-services.sh.
  install-systemd   Run install-systemd.sh --enable.
  check-pam         Run check-pam-state.sh --verify USER.
  enable-pam        Run enable-pam.sh USER.
  disable-pam       Run disable-pam.sh.
  enroll            Run enroll-test.sh --finger FINGER USER.
  rollback          Run rollback.sh.
USAGE
}

section() {
  printf '\n===== %s =====\n' "$1"
}

resolve_helper() {
  local filename="$1"
  local path="$PROJECT_ROOT/scripts/$filename"

  if [[ -x "$path" ]]; then
    printf '%s\n' "$path"
    return 0
  fi

  printf '[error] missing helper: %s\n' "$path" >&2
  exit 1
}

run_helper() {
  local helper="$1"
  shift

  local path
  path="$(resolve_helper "$helper")"

  printf '$'
  printf ' %q' "$path" "$@"
  printf '\n'
  "$path" "$@"
}

require_user() {
  if [[ -z "$TARGET_USER" ]]; then
    printf '[error] no target user specified and USER is empty.\n' >&2
    exit 2
  fi
}

run_action() {
  local action="$1"

  case "$action" in
    check-dbus)
      require_user
      section "check dbus chain"
      run_helper check-dbus-chain.sh --wait 20 "$TARGET_USER"
      ;;
    stability)
      require_user
      section "stability check"
      run_helper stability-check.sh --iterations 2 --sleep 8 "$TARGET_USER"
      ;;
    systemd-test)
      require_user
      section "systemd test"
      run_helper systemd-test.sh --verify "$TARGET_USER"
      ;;
    restart-services)
      section "restart project services"
      run_helper restart-project-services.sh
      ;;
    install-systemd)
      section "install and enable project services"
      run_helper install-systemd.sh --enable
      ;;
    check-pam)
      require_user
      section "check pam state"
      run_helper check-pam-state.sh --verify "$TARGET_USER"
      ;;
    enable-pam)
      require_user
      section "enable pam"
      run_helper enable-pam.sh "$TARGET_USER"
      ;;
    disable-pam)
      section "disable pam"
      run_helper disable-pam.sh
      ;;
    enroll)
      require_user
      section "enroll fingerprint"
      run_helper enroll-test.sh --finger "$FINGER" "$TARGET_USER"
      ;;
    rollback)
      section "rollback"
      run_helper rollback.sh
      ;;
    *)
      printf '[error] unknown action: %s\n' "$action" >&2
      usage >&2
      exit 2
      ;;
  esac
}

print_menu() {
  cat <<EOF

fedora-validity-setup menu

Target user: ${TARGET_USER:-not set}
Enroll finger: $FINGER

  1) check-dbus
  2) stability
  3) systemd-test
  4) restart-services
  5) install-systemd
  6) check-pam
  7) enable-pam
  8) disable-pam
  9) enroll
 10) rollback
  q) quit
EOF
}

while (($# > 0)); do
  case "$1" in
    --run)
      if [[ -z "${2:-}" ]]; then
        printf '[error] --run requires an action.\n' >&2
        exit 2
      fi
      ACTION="$2"
      shift
      ;;
    --user)
      if [[ -z "${2:-}" ]]; then
        printf '[error] --user requires a value.\n' >&2
        exit 2
      fi
      TARGET_USER="$2"
      shift
      ;;
    --finger)
      if [[ -z "${2:-}" ]]; then
        printf '[error] --finger requires a value.\n' >&2
        exit 2
      fi
      FINGER="$2"
      shift
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
      ACTION="$1"
      ;;
  esac
  shift
done

if [[ -n "$ACTION" ]]; then
  run_action "$ACTION"
  exit 0
fi

while true; do
  print_menu
  printf '\nSelect action: '
  IFS= read -r choice

  case "$choice" in
    1) run_action check-dbus ;;
    2) run_action stability ;;
    3) run_action systemd-test ;;
    4) run_action restart-services ;;
    5) run_action install-systemd ;;
    6) run_action check-pam ;;
    7) run_action enable-pam ;;
    8) run_action disable-pam ;;
    9) run_action enroll ;;
    10) run_action rollback ;;
    q|Q|quit|exit)
      exit 0
      ;;
    *)
      printf '[error] unknown selection: %s\n' "$choice" >&2
      ;;
  esac
done
