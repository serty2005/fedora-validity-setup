#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TARGET_USER="${USER:-}"
PAM_DIR="${PAM_DIR:-/etc/pam.d}"
AUTHSELECT_DIR="${AUTHSELECT_DIR:-/etc/authselect}"
CHECK_DBUS_CHAIN="${CHECK_DBUS_CHAIN:-$PROJECT_ROOT/scripts/check-dbus-chain.sh}"
PREFIX="${FEDORA_VALIDITY_PREFIX:-/opt/fedora-validity}"
PAM_BACKUP_ROOT="${PAM_BACKUP_ROOT:-$PREFIX/backups}"
STATE_DIR="${FEDORA_VALIDITY_STATE_DIR:-$PREFIX/state}"
STATE_FILE="$STATE_DIR/pam-authselect-with-fingerprint.env"
ASSUME_VERIFIED=0
WAIT_SECONDS=20
BACKUP_DIR="$PAM_BACKUP_ROOT/pam-$(date +%Y%m%d-%H%M%S)"

usage() {
  cat <<'USAGE'
Usage: enable-pam.sh [--assume-verified] [--wait SECONDS] [USER]

Safely enables Fedora authselect fingerprint integration after the project
service layer has been verified. It does not edit /etc/pam.d manually.

Behavior:
  - runs ./scripts/check-dbus-chain.sh --wait 20 before changes;
  - runs fprintd-verify USER unless --assume-verified is set;
  - backs up authselect current output and relevant PAM/authselect files;
  - if with-fingerprint is already enabled, records that fact and makes no
    authselect changes;
  - otherwise runs authselect enable-feature with-fingerprint and apply-changes.

Options:
  --assume-verified  Skip fprintd-verify only after manual verification.
  --wait SECONDS     Wait passed to check-dbus-chain.sh. Default: 20.
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

authselect_has_fingerprint() {
  grep -E '(^|[[:space:]])with-fingerprint($|[[:space:]])' >/dev/null
}

backup_file_if_exists() {
  local source="$1"
  local dest_dir="$2"

  if [[ -e "$source" ]]; then
    run sudo mkdir -p "$dest_dir"
    run sudo cp -a "$source" "$dest_dir/"
  fi
}

write_backup_text() {
  local name="$1"
  local content="$2"
  local tmp_file

  tmp_file="$(mktemp)"
  printf '%s\n' "$content" >"$tmp_file"
  run sudo install -m 0644 "$tmp_file" "$BACKUP_DIR/$name"
  rm -f "$tmp_file"
}

write_manifest() {
  local project_changed="$1"
  local pre_existing="$2"
  local tmp_file

  tmp_file="$(mktemp)"
  {
    printf 'project_changed_authselect=%s\n' "$project_changed"
    printf 'pre_existing_with_fingerprint=%s\n' "$pre_existing"
    printf 'backup_dir=%s\n' "$BACKUP_DIR"
    printf 'target_user=%s\n' "$TARGET_USER"
    printf 'created_at=%s\n' "$(date --iso-8601=seconds)"
  } >"$tmp_file"

  run sudo install -m 0644 "$tmp_file" "$BACKUP_DIR/manifest.env"
  if [[ "$project_changed" == "1" ]]; then
    run sudo mkdir -p "$STATE_DIR"
    run sudo install -m 0644 "$tmp_file" "$STATE_FILE"
  fi
  rm -f "$tmp_file"
}

create_backup() {
  local current_output="$1"
  local -a pam_files=(
    system-auth
    password-auth
    fingerprint-auth
    sudo
    sudo-i
    gdm-password
    gdm-fingerprint
    polkit-1
  )

  section "backup current PAM/authselect state"
  printf 'backup_dir=%s\n' "$BACKUP_DIR"
  run sudo mkdir -p "$BACKUP_DIR"
  write_backup_text authselect-current.txt "$current_output"

  for file in "${pam_files[@]}"; do
    backup_file_if_exists "$PAM_DIR/$file" "$BACKUP_DIR/pam.d"
  done

  if [[ -d "$PAM_DIR" ]]; then
    while IFS= read -r path; do
      backup_file_if_exists "$path" "$BACKUP_DIR/pam.d"
    done < <(grep -rl 'pam_fprintd' "$PAM_DIR" 2>/dev/null || true)
  fi

  backup_file_if_exists "$AUTHSELECT_DIR/authselect.conf" "$BACKUP_DIR/authselect"
  if [[ -d "$AUTHSELECT_DIR" ]]; then
    while IFS= read -r path; do
      backup_file_if_exists "$path" "$BACKUP_DIR/authselect"
    done < <(grep -rl 'pam_fprintd' "$AUTHSELECT_DIR" 2>/dev/null || true)
  fi
}

while (($# > 0)); do
  case "$1" in
    --assume-verified)
      ASSUME_VERIFIED=1
      ;;
    --wait)
      if [[ -z "${2:-}" || ! "${2:-}" =~ ^[0-9]+$ ]]; then
        printf '[error] --wait requires a non-negative integer.\n' >&2
        exit 2
      fi
      WAIT_SECONDS="$2"
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
      TARGET_USER="$1"
      ;;
  esac
  shift
done

if [[ -z "$TARGET_USER" ]]; then
  printf '[error] no target user specified and USER is empty.\n' >&2
  exit 2
fi

for cmd in authselect sudo; do
  require_cmd "$cmd"
done
if [[ "$ASSUME_VERIFIED" == "0" ]]; then
  require_cmd fprintd-verify
fi
if [[ ! -x "$CHECK_DBUS_CHAIN" ]]; then
  printf '[error] check-dbus-chain helper is not executable: %s\n' "$CHECK_DBUS_CHAIN" >&2
  exit 1
fi

section "service layer preflight"
run "$CHECK_DBUS_CHAIN" --wait "$WAIT_SECONDS"

section "fingerprint verification preflight"
if [[ "$ASSUME_VERIFIED" == "1" ]]; then
  printf '[warning] fprintd-verify skipped because --assume-verified was provided.\n'
else
  run fprintd-verify "$TARGET_USER"
fi

section "authselect current"
set +e
current_output="$(authselect current 2>&1)"
current_status=$?
set -e
printf '%s\n' "$current_output"
if [[ "$current_status" -ne 0 ]]; then
  printf '[error] authselect current failed; refusing to change PAM/authselect state.\n' >&2
  exit 10
fi
create_backup "$current_output"

if authselect_has_fingerprint <<<"$current_output"; then
  section "authselect feature"
  printf '[info] with-fingerprint is already enabled; no authselect changes made.\n'
  write_manifest 0 1
else
  section "enable authselect fingerprint feature"
  run sudo authselect enable-feature with-fingerprint
  run sudo authselect apply-changes
  write_manifest 1 0
fi

section "rollback"
printf 'Rollback command: ./scripts/disable-pam.sh\n'
printf 'Backup directory: %s\n' "$BACKUP_DIR"
