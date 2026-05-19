#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-/opt/fedora-validity}"
VENV="$PREFIX/venv"
RUNTIME_DIR="${RUNTIME_DIR:-/var/run/python-validity}"
FIRMWARE_CACHE_DIR="${FIRMWARE_CACHE_DIR:-$PREFIX/firmware/python-validity}"
FIRMWARE_TOOL="$VENV/bin/validity-sensors-firmware"

section() {
  printf '\n===== %s =====\n' "$1"
}

require_file() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    printf '[error] missing expected path: %s\n' "$path" >&2
    printf '[hint] Run scripts/build-python-validity.sh first.\n' >&2
    exit 1
  fi
}

copy_firmware_files() {
  local source_dir="$1"
  local dest_dir="$2"

  install -d -m 0755 "$dest_dir"
  find "$source_dir" -maxdepth 1 -type f -name '*.xpfwext' -exec install -m 0644 {} "$dest_dir/" \;
}

has_firmware() {
  local dir="$1"
  compgen -G "$dir/*.xpfwext" >/dev/null
}

section "preflight"
require_file "$FIRMWARE_TOOL"

section "prepare firmware directories"
install -d -m 0755 "$RUNTIME_DIR"
install -d -m 0755 "$FIRMWARE_CACHE_DIR"
printf 'runtime directory: %s\n' "$RUNTIME_DIR"
printf 'persistent cache: %s\n' "$FIRMWARE_CACHE_DIR"

if has_firmware "$RUNTIME_DIR"; then
  section "runtime firmware already present"
  ls -lah "$RUNTIME_DIR"/*.xpfwext
  if ! has_firmware "$FIRMWARE_CACHE_DIR"; then
    section "populate persistent firmware cache"
    copy_firmware_files "$RUNTIME_DIR" "$FIRMWARE_CACHE_DIR"
  fi
  exit 0
fi

if has_firmware "$FIRMWARE_CACHE_DIR"; then
  section "copy cached firmware into runtime directory"
  copy_firmware_files "$FIRMWARE_CACHE_DIR" "$RUNTIME_DIR"
  ls -lah "$RUNTIME_DIR"/*.xpfwext
  exit 0
fi

section "download/extract firmware into runtime directory"
printf '$ %q\n' "$FIRMWARE_TOOL"
if ! "$FIRMWARE_TOOL"; then
  printf '[error] firmware runtime file is missing and persistent cache is empty.\n' >&2
  printf '[hint] Boot may be too early for DNS/network. After network is up, run: sudo %q\n' "$0" >&2
  exit 1
fi

if ! has_firmware "$RUNTIME_DIR"; then
  printf '[error] firmware tool completed but no .xpfwext appeared in %s\n' "$RUNTIME_DIR" >&2
  exit 1
fi

section "populate persistent firmware cache"
copy_firmware_files "$RUNTIME_DIR" "$FIRMWARE_CACHE_DIR"

section "firmware files"
ls -lah "$RUNTIME_DIR"/*.xpfwext
ls -lah "$FIRMWARE_CACHE_DIR"/*.xpfwext
