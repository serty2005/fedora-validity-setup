#!/usr/bin/env bash
set -euo pipefail

SYSTEMD_DEST_DIR="${SYSTEMD_DEST_DIR:-/etc/systemd/system}"
DRY_RUN=0
PROJECT_SERVICES=(open-fprintd.service python3-validity.service)

usage() {
  cat <<'USAGE'
Usage: clean-systemd-install.sh [--dry-run]

Stops and removes only the project systemd unit files, then reloads systemd.
This is meant for a clean reinstall through scripts/install-systemd.sh.
It does not remove D-Bus policy and does not change PAM/authselect/GDM/sudo.

Options:
  --dry-run  Print actions without changing files or systemd state.
USAGE
}

section() {
  printf '\n===== %s =====\n' "$1"
}

run_optional() {
  printf '$'
  printf ' %q' "$@"
  printf '\n'
  if [[ "$DRY_RUN" == "0" ]]; then
    "$@" || true
  fi
}

while (($# > 0)); do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf '[error] unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

section "sudo authentication"
run_optional sudo -v

section "stop project services"
run_optional sudo systemctl stop "${PROJECT_SERVICES[@]}"

section "disable project services"
run_optional sudo systemctl disable "${PROJECT_SERVICES[@]}"

section "remove project unit files"
for service in "${PROJECT_SERVICES[@]}"; do
  run_optional sudo rm -f "$SYSTEMD_DEST_DIR/$service"
done

section "reload systemd"
run_optional sudo systemctl daemon-reload

section "next step"
printf 'Clean systemd install state is ready. Reinstall with: ./scripts/install-systemd.sh\n'
printf 'This script did not remove D-Bus policy and did not change PAM/authselect/GDM/sudo.\n'
