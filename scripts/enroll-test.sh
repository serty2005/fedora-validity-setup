#!/usr/bin/env bash
set -euo pipefail

LIST_ONLY=0
TARGET_USER="${USER:-}"
FINGER=""

usage() {
  cat <<'USAGE'
Usage: enroll-test.sh [--list-only] [--finger FINGER] [USER]

Runs fprintd client checks against the currently running foreground services.

Options:
  --list-only  Run only fprintd-list USER; do not enroll or verify.
  --finger     Finger name passed to fprintd-enroll --finger.
USAGE
}

while (($# > 0)); do
  case "$1" in
    --list-only)
      LIST_ONLY=1
      ;;
    --finger)
      if [[ -z "${2:-}" ]]; then
        printf '[error] --finger requires a finger name.\n' >&2
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
      TARGET_USER="$1"
      ;;
  esac
  shift
done

if [[ -z "$TARGET_USER" ]]; then
  printf '[error] no target user specified and USER is empty.\n' >&2
  exit 2
fi

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

require_cmd fprintd-list
require_cmd fprintd-enroll
require_cmd fprintd-verify
require_cmd busctl

section "preflight"
if ! busctl --system list | awk '$1 == "net.reactivated.Fprint" && $2 != "-" { found=1 } END { exit !found }'; then
  printf '[error] net.reactivated.Fprint is not currently owned.\n' >&2
  printf '[hint] Run open-fprintd and python-validity debug services first.\n' >&2
  exit 3
fi
busctl --system list | grep -F 'net.reactivated.Fprint' || true

section "list devices and enrolled fingers"
printf '$ fprintd-list %q\n' "$TARGET_USER"
fprintd-list "$TARGET_USER"

if [[ "$LIST_ONLY" == "1" ]]; then
  section "done"
  printf 'List-only check completed for user: %s\n' "$TARGET_USER"
  exit 0
fi

section "enroll"
enroll_args=()
if [[ -n "$FINGER" ]]; then
  enroll_args+=(--finger "$FINGER")
fi
enroll_args+=("$TARGET_USER")
printf '$ fprintd-enroll'
printf ' %q' "${enroll_args[@]}"
printf '\n'
fprintd-enroll "${enroll_args[@]}"

section "verify"
printf '$ fprintd-verify %q\n' "$TARGET_USER"
fprintd-verify "$TARGET_USER"

section "done"
printf 'Enrollment and verification commands completed for user: %s\n' "$TARGET_USER"
