#!/usr/bin/env bash
set -euo pipefail

TARGET_USER="${USER:-}"
VERIFY=0
SERVICES=(open-fprintd.service python3-validity.service)

usage() {
  cat <<'USAGE'
Usage: systemd-test.sh [--verify] [USER]

Restarts the project systemd services for a manual test, then runs fprintd-list.
With --verify it also runs fprintd-verify. This script does not change
PAM/authselect/GDM/sudo and does not enable services.

Options:
  --verify  Run fprintd-verify USER after fprintd-list USER.
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

run() {
  printf '$'
  printf ' %q' "$@"
  printf '\n'
  "$@"
}

is_systemd_service_pid() {
  local pid="$1"
  local service
  local service_pid

  for service in "${SERVICES[@]}"; do
    service_pid="$(systemctl show -p MainPID --value "$service" 2>/dev/null || true)"
    if [[ -n "$service_pid" && "$service_pid" != "0" && "$pid" == "$service_pid" ]]; then
      return 0
    fi
  done

  return 1
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

for cmd in pgrep sudo systemctl journalctl busctl fprintd-list fprintd-verify; do
  require_cmd "$cmd"
done

section "sudo authentication"
run sudo -v

section "foreground process check"
foreground_matches=()
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  pid="${line%% *}"
  if ! is_systemd_service_pid "$pid"; then
    foreground_matches+=("$line")
  fi
done < <(pgrep -fa '/opt/fedora-validity/venv/lib/open-fprintd/open-fprintd|/opt/fedora-validity/venv/lib/python-validity/dbus-service' || true)

if ((${#foreground_matches[@]} > 0)); then
  printf '[error] foreground open-fprintd/python-validity process appears to be running.\n' >&2
  printf '[hint] Stop foreground debug terminals with Ctrl-C, then rerun this script.\n' >&2
  printf '%s\n' "${foreground_matches[@]}" >&2
  exit 3
fi
printf '[info] no foreground project processes detected.\n'

section "restart project services"
run sudo systemctl stop python3-validity.service
run sudo systemctl stop open-fprintd.service
run sudo systemctl stop fprintd.service
run sudo systemctl start open-fprintd.service
run sudo systemctl start python3-validity.service

section "service status"
run systemctl status "${SERVICES[@]}" --no-pager || true

section "journal tail"
run journalctl -u open-fprintd.service -u python3-validity.service -n 120 --no-pager || true

section "wait for registered device"
for attempt in {1..20}; do
  devices="$(
    busctl --system call net.reactivated.Fprint /net/reactivated/Fprint/Manager net.reactivated.Fprint.Manager GetDevices 2>/dev/null || true
  )"
  printf '[info] GetDevices attempt %s/20: %s\n' "$attempt" "${devices:-no response}"
  if [[ "$devices" =~ ^ao[[:space:]]+[1-9] ]]; then
    break
  fi
  if [[ "$attempt" -eq 20 ]]; then
    printf '[error] no registered fingerprint devices appeared under open-fprintd.\n' >&2
    printf '[hint] Check: journalctl -u open-fprintd.service -u python3-validity.service -n 200 --no-pager\n' >&2
    exit 4
  fi
  sleep 1
done

section "fprintd-list"
run fprintd-list "$TARGET_USER"

if [[ "$VERIFY" == "1" ]]; then
  section "fprintd-verify"
  run fprintd-verify "$TARGET_USER"
else
  section "verify skipped"
  printf '[info] fprintd-verify was not run. Use --verify for the full systemd path check.\n'
fi

section "done"
printf 'Systemd test command sequence completed for user: %s\n' "$TARGET_USER"
