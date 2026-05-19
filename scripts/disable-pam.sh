#!/usr/bin/env bash
set -euo pipefail

PREFIX="${FEDORA_VALIDITY_PREFIX:-/opt/fedora-validity}"
STATE_DIR="${FEDORA_VALIDITY_STATE_DIR:-$PREFIX/state}"
STATE_FILE="$STATE_DIR/pam-authselect-with-fingerprint.env"
FORCE=0

usage() {
  cat <<'USAGE'
Usage: disable-pam.sh [--force]

Rolls back only the authselect fingerprint feature enabled by this project.
Without a project marker, it refuses to disable with-fingerprint because the
feature may have been enabled before this project.

Options:
  --force  Disable authselect with-fingerprint even without a project marker.
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

project_marker_exists() {
  [[ -f "$STATE_FILE" ]] && grep -Fx 'project_changed_authselect=1' "$STATE_FILE" >/dev/null
}

while (($# > 0)); do
  case "$1" in
    --force)
      FORCE=1
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
      printf '[error] unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

for cmd in authselect sudo; do
  require_cmd "$cmd"
done

section "planned change"
printf 'This script changes only authselect feature with-fingerprint.\n'
printf 'It does not edit /etc/pam.d manually and does not change passwords, users, GDM config or sudoers.\n'

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

if ! authselect_has_fingerprint <<<"$current_output"; then
  printf '[info] with-fingerprint is already disabled; no authselect changes needed.\n'
  if project_marker_exists; then
    run sudo rm -f "$STATE_FILE"
  fi
  exit 0
fi

if ! project_marker_exists && [[ "$FORCE" == "0" ]]; then
  section "guard"
  printf '[info] No project marker found at %s.\n' "$STATE_FILE"
  printf '[info] Refusing to disable with-fingerprint because it may predate this project.\n'
  printf '[info] Re-run with --force only if you intentionally want to disable fingerprint auth globally.\n'
  exit 0
fi

if [[ "$FORCE" == "1" && ! -f "$STATE_FILE" ]]; then
  section "force"
  printf '[warning] --force provided without project marker; disabling system fingerprint auth anyway.\n'
fi

section "disable authselect fingerprint feature"
run sudo authselect disable-feature with-fingerprint
run sudo authselect apply-changes

if [[ -f "$STATE_FILE" ]]; then
  section "remove project marker"
  run sudo rm -f "$STATE_FILE"
fi

section "done"
printf 'with-fingerprint rollback command completed. Password authentication should remain available through Fedora PAM fallback.\n'
