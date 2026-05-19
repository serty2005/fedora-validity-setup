#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
SHOW_STATUS=1
SERVICES=(open-fprintd.service python3-validity.service)

usage() {
  cat <<'USAGE'
Usage: restart-project-services.sh [--dry-run] [--no-status]

Restarts the project fingerprint services in the order needed to drop stale
python-validity USB handles. This script does not change PAM/authselect/GDM/sudo.

Options:
  --dry-run  Print actions without changing systemd state.
  --no-status
             Do not print final systemctl status.
USAGE
}

section() {
  printf '\n===== %s =====\n' "$1"
}

run() {
  printf '$'
  printf ' %q' "$@"
  printf '\n'
  if [[ "$DRY_RUN" == "0" ]]; then
    "$@"
  fi
}

systemctl_cmd() {
  if [[ "${EUID:-$(id -u)}" == "0" ]]; then
    run systemctl "$@"
  else
    run sudo systemctl "$@"
  fi
}

while (($# > 0)); do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    --no-status)
      SHOW_STATUS=0
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

section "preflight"
printf 'dry_run=%s\n' "$([[ "$DRY_RUN" == "1" ]] && printf yes || printf no)"
if [[ "${EUID:-$(id -u)}" != "0" && "$DRY_RUN" == "0" ]]; then
  run sudo -v
fi

section "restart project services"
systemctl_cmd stop python3-validity.service
systemctl_cmd stop open-fprintd.service
systemctl_cmd stop fprintd.service
systemctl_cmd start open-fprintd.service
systemctl_cmd start python3-validity.service

if [[ "$SHOW_STATUS" == "1" ]]; then
  section "status"
  systemctl_cmd status "${SERVICES[@]}" --no-pager || true
fi

section "done"
printf 'Project fingerprint services were restarted.\n'
