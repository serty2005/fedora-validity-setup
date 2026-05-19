#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$PROJECT_ROOT/systemd"
DEST_DIR="${SYSTEMD_DEST_DIR:-/etc/systemd/system}"
SYSTEM_SLEEP_DIR="${SYSTEM_SLEEP_DIR:-/usr/lib/systemd/system-sleep}"
PREFIX="/opt/fedora-validity"
BIN_DIR="${FEDORA_VALIDITY_BIN_DIR:-$PREFIX/bin}"
BACKUP_ROOT="${SYSTEMD_BACKUP_ROOT:-$PREFIX/backups}"
DBUS_POLICY_SCRIPT="${DBUS_POLICY_SCRIPT:-$PROJECT_ROOT/scripts/install-dbus-policy.sh}"
ENSURE_FIRMWARE_SCRIPT="$PROJECT_ROOT/scripts/ensure-firmware.sh"
RESTART_SERVICES_SCRIPT="$PROJECT_ROOT/scripts/restart-project-services.sh"
SYSTEM_SLEEP_SCRIPT="$PROJECT_ROOT/scripts/system-sleep-validity.sh"
DRY_RUN=0
ENABLE=0
BACKUP_DIR="$BACKUP_ROOT/systemd-$(date +%Y%m%d-%H%M%S)"
UNITS=(open-fprintd.service python3-validity.service)

usage() {
  cat <<'USAGE'
Usage: install-systemd.sh [--dry-run] [--enable]

Installs local systemd units for open-fprintd and python-validity.
By default it installs unit files and reloads systemd, but does not enable
autostart. This script does not change PAM/authselect/GDM/sudo.

Options:
  --dry-run  Print actions without changing files or systemd state.
  --enable   Enable the project services after installation.
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

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    printf '[error] missing expected file: %s\n' "$path" >&2
    exit 1
  fi
}

install_unit() {
  local unit="$1"
  local source="$SOURCE_DIR/$unit"
  local dest="$DEST_DIR/$unit"

  section "install $unit"
  require_file "$source"
  printf 'source=%s\n' "$source"
  printf 'dest=%s\n' "$dest"

  if [[ -f "$dest" ]] && cmp -s "$source" "$dest"; then
    printf '[info] already installed and identical: %s\n' "$dest"
    return 0
  fi

  run sudo mkdir -p "$DEST_DIR"
  if [[ -f "$dest" ]]; then
    run sudo mkdir -p "$BACKUP_DIR"
    run sudo cp -a "$dest" "$BACKUP_DIR/$unit"
    printf '[info] backup: %s\n' "$BACKUP_DIR/$unit"
  fi
  run sudo install -m 0644 "$source" "$dest"
}

install_helper() {
  local source="$1"
  local dest="$BIN_DIR/$(basename "$source")"

  section "install helper $(basename "$source")"
  require_file "$source"
  printf 'source=%s\n' "$source"
  printf 'dest=%s\n' "$dest"

  if [[ -f "$dest" ]] && cmp -s "$source" "$dest"; then
    printf '[info] already installed and identical: %s\n' "$dest"
    return 0
  fi

  run sudo mkdir -p "$BIN_DIR"
  run sudo install -m 0755 "$source" "$dest"
}

install_system_sleep_hook() {
  local source="$1"
  local dest="$SYSTEM_SLEEP_DIR/fedora-validity-setup"

  section "install system-sleep hook"
  require_file "$source"
  printf 'source=%s\n' "$source"
  printf 'dest=%s\n' "$dest"

  if [[ -f "$dest" ]] && cmp -s "$source" "$dest"; then
    printf '[info] already installed and identical: %s\n' "$dest"
    return 0
  fi

  run sudo mkdir -p "$SYSTEM_SLEEP_DIR"
  run sudo install -m 0755 "$source" "$dest"
}

while (($# > 0)); do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    --enable)
      ENABLE=1
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
printf 'project root: %s\n' "$PROJECT_ROOT"
printf 'systemd source dir: %s\n' "$SOURCE_DIR"
printf 'systemd destination dir: %s\n' "$DEST_DIR"
printf 'system-sleep destination dir: %s\n' "$SYSTEM_SLEEP_DIR"
printf 'helper destination dir: %s\n' "$BIN_DIR"
printf 'backup root: %s\n' "$BACKUP_ROOT"
printf 'dry run: %s\n' "$([[ "$DRY_RUN" == "1" ]] && printf yes || printf no)"
printf 'enable requested: %s\n' "$([[ "$ENABLE" == "1" ]] && printf yes || printf no)"
require_file "$DBUS_POLICY_SCRIPT"
require_file "$ENSURE_FIRMWARE_SCRIPT"
require_file "$RESTART_SERVICES_SCRIPT"
require_file "$SYSTEM_SLEEP_SCRIPT"
for unit in "${UNITS[@]}"; do
  require_file "$SOURCE_DIR/$unit"
done

section "sudo authentication"
run sudo -v

section "install dbus policy"
if [[ "$DRY_RUN" == "1" ]]; then
  printf '$'
  printf ' %q' "$DBUS_POLICY_SCRIPT" --dry-run
  printf '\n'
  "$DBUS_POLICY_SCRIPT" --dry-run
else
  run "$DBUS_POLICY_SCRIPT"
fi

install_helper "$ENSURE_FIRMWARE_SCRIPT"
install_helper "$RESTART_SERVICES_SCRIPT"
install_system_sleep_hook "$SYSTEM_SLEEP_SCRIPT"

for unit in "${UNITS[@]}"; do
  install_unit "$unit"
done

section "reload systemd"
run sudo systemctl daemon-reload

if [[ "$ENABLE" == "1" ]]; then
  section "enable services"
  run sudo systemctl enable "${UNITS[@]}"
else
  section "autostart"
  printf '[info] services were not enabled. Use --enable only after manual systemd verification.\n'
fi

section "notes"
printf 'This script does not install udev rules and does not change PAM/authselect/GDM/sudo.\n'
printf 'Manual test command: ./scripts/systemd-test.sh --verify\n'
