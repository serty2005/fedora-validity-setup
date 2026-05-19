#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="/opt/fedora-validity"
VENV="$PREFIX/venv"
DEST_DIR="/etc/dbus-1/system.d"
BACKUP_ROOT="$PREFIX/backups"
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage: install-dbus-policy.sh [--dry-run]

Installs only the D-Bus policy files required for foreground testing:
  - io.github.uunicorn.Fprint.conf
  - net.reactivated.Fprint.conf only if no system policy already exists

This does not enable or install systemd services and does not change PAM.
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

source_for() {
  local filename="$1"
  local repo_source="$PROJECT_ROOT/dbus/$filename"
  local venv_source="$VENV/share/dbus-1/system.d/$filename"
  local upstream_source=""

  case "$filename" in
    io.github.uunicorn.Fprint.conf)
      upstream_source="$PROJECT_ROOT/third_party/python-validity/dbus_service/$filename"
      ;;
    net.reactivated.Fprint.conf)
      upstream_source="$PROJECT_ROOT/third_party/open-fprintd/dbus_service/$filename"
      ;;
    *)
      printf '[error] unknown policy file: %s\n' "$filename" >&2
      exit 2
      ;;
  esac

  if [[ -f "$repo_source" ]]; then
    printf '%s\n' "$repo_source"
  elif [[ -f "$venv_source" ]]; then
    printf '%s\n' "$venv_source"
  elif [[ -f "$upstream_source" ]]; then
    printf '%s\n' "$upstream_source"
  else
    printf '[error] missing source policy for %s\n' "$filename" >&2
    exit 1
  fi
}

install_policy() {
  local filename="$1"
  local source="$2"
  local dest="$DEST_DIR/$filename"
  local backup_dir="$BACKUP_ROOT/dbus-policy-$(date +%Y%m%d-%H%M%S)"

  section "install $filename"
  printf 'source=%s\n' "$source"
  printf 'dest=%s\n' "$dest"

  if [[ -f "$dest" ]] && cmp -s "$source" "$dest"; then
    printf '[info] already installed and identical: %s\n' "$dest"
    return 0
  fi

  run sudo mkdir -p "$DEST_DIR"
  if [[ -f "$dest" ]]; then
    run sudo mkdir -p "$backup_dir"
    run sudo cp -a "$dest" "$backup_dir/$filename"
    printf '[info] backup: %s\n' "$backup_dir/$filename"
  fi
  run sudo install -m 0644 "$source" "$dest"
}

reload_dbus_policy() {
  section "reload dbus policy"
  run sudo systemctl reload dbus-broker.service || \
    run sudo systemctl reload dbus.service || \
    run sudo busctl call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus ReloadConfig || \
    printf '[warning] D-Bus reload command failed; restart foreground services and, if AccessDenied persists, reboot before retesting.\n'
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

section "policy sources"
BACKEND_POLICY="$(source_for io.github.uunicorn.Fprint.conf)"
OPEN_FPRINTD_POLICY="$(source_for net.reactivated.Fprint.conf)"
printf 'io.github.uunicorn.Fprint.conf -> %s\n' "$BACKEND_POLICY"
printf 'net.reactivated.Fprint.conf -> %s\n' "$OPEN_FPRINTD_POLICY"
printf 'destination directory -> %s\n' "$DEST_DIR"

install_policy io.github.uunicorn.Fprint.conf "$BACKEND_POLICY"

section "check net.reactivated.Fprint policy"
if [[ -f /etc/dbus-1/system.d/net.reactivated.Fprint.conf || -f /usr/share/dbus-1/system.d/net.reactivated.Fprint.conf ]]; then
  printf '[info] system policy already exists for net.reactivated.Fprint; leaving it untouched.\n'
else
  install_policy net.reactivated.Fprint.conf "$OPEN_FPRINTD_POLICY"
fi

reload_dbus_policy
