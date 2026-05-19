#!/usr/bin/env bash
set -euo pipefail

PREFIX="/opt/fedora-validity"
DBUS_DEST_DIR="/etc/dbus-1/system.d"
SYSTEMD_DEST_DIR="/etc/systemd/system"
HELPER_PATH="$PREFIX/bin/ensure-firmware.sh"
DRY_RUN=0
PROJECT_SERVICES=(open-fprintd.service python3-validity.service)

usage() {
  cat <<'USAGE'
Usage: rollback.sh [--dry-run]

Removes systemd and D-Bus artifacts installed by this project.
This does not change PAM/authselect/GDM/sudo.

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

section "stop project systemd services"
run_optional sudo systemctl stop "${PROJECT_SERVICES[@]}"

section "disable project systemd services"
run_optional sudo systemctl disable "${PROJECT_SERVICES[@]}"

section "remove project systemd unit files"
for service in "${PROJECT_SERVICES[@]}"; do
  run_optional sudo rm -f "$SYSTEMD_DEST_DIR/$service"
done

section "remove project-installed D-Bus policy files"
run_optional sudo rm -f "$DBUS_DEST_DIR/io.github.uunicorn.Fprint.conf"

if [[ -f "$DBUS_DEST_DIR/net.reactivated.Fprint.conf" ]]; then
  printf '[note] Leaving %s in place unless it was manually confirmed as project-installed.\n' "$DBUS_DEST_DIR/net.reactivated.Fprint.conf"
fi

section "remove project-installed helper files"
run_optional sudo rm -f "$HELPER_PATH"

section "available backups"
if [[ -d "$PREFIX/backups" ]]; then
  find "$PREFIX/backups" -maxdepth 3 -type f | sort
else
  printf '[info] no backups directory found: %s/backups\n' "$PREFIX"
fi

section "reload systemd"
run_optional sudo systemctl daemon-reload

section "reload dbus policy"
run_optional sudo systemctl reload dbus-broker.service
run_optional sudo systemctl reload dbus.service
run_optional sudo busctl call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus ReloadConfig

section "notes"
printf 'This rollback does not change PAM/authselect/GDM/sudo.\n'
printf 'Stop foreground debug services manually with Ctrl-C in their terminals if they are still running.\n'
