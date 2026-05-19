#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TARGET_USER="${USER:-}"
ITERATIONS=1
SLEEP_SECONDS=0
VERIFY=0

usage() {
  cat <<'USAGE'
Usage: stability-check.sh [--iterations N] [--sleep SECONDS] [--verify] [USER]

Runs repeated read-only fingerprint stack checks. By default this script runs
check-dbus-chain and enroll-test --list-only only. It does not enroll fingers,
does not restart services and does not change PAM/authselect/GDM/sudo.

Options:
  --iterations N   Number of check cycles. Default: 1.
  --sleep SECONDS  Delay between cycles. Default: 0.
  --verify         Also run fprintd-verify USER in each cycle.
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

resolve_helper() {
  local filename="$1"
  local repo_path="$PROJECT_ROOT/scripts/$filename"

  if [[ -x "$repo_path" ]]; then
    printf '%s\n' "$repo_path"
    return 0
  fi

  if command -v "$filename" >/dev/null 2>&1; then
    command -v "$filename"
    return 0
  fi

  printf '[error] missing helper: %s\n' "$repo_path" >&2
  exit 1
}

run_cmd() {
  printf '$'
  printf ' %q' "$@"
  printf '\n'
  "$@"
}

while (($# > 0)); do
  case "$1" in
    --iterations)
      if [[ -z "${2:-}" || ! "${2:-}" =~ ^[1-9][0-9]*$ ]]; then
        printf '[error] --iterations requires a positive integer.\n' >&2
        exit 2
      fi
      ITERATIONS="$2"
      shift
      ;;
    --sleep)
      if [[ -z "${2:-}" || ! "${2:-}" =~ ^[0-9]+$ ]]; then
        printf '[error] --sleep requires a non-negative integer.\n' >&2
        exit 2
      fi
      SLEEP_SECONDS="$2"
      shift
      ;;
    --verify)
      VERIFY=1
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

CHECK_DBUS_CHAIN="$(resolve_helper check-dbus-chain.sh)"
ENROLL_TEST="$(resolve_helper enroll-test.sh)"
require_cmd fprintd-verify

section "stability check config"
printf 'user=%s\n' "$TARGET_USER"
printf 'iterations=%s\n' "$ITERATIONS"
printf 'sleep_seconds=%s\n' "$SLEEP_SECONDS"
printf 'verify=%s\n' "$([[ "$VERIFY" == "1" ]] && printf yes || printf no)"
printf 'check_dbus_chain=%s\n' "$CHECK_DBUS_CHAIN"
printf 'enroll_test=%s\n' "$ENROLL_TEST"

for ((iteration = 1; iteration <= ITERATIONS; iteration++)); do
  section "iteration $iteration/$ITERATIONS: dbus chain"
  run_cmd "$CHECK_DBUS_CHAIN" "$TARGET_USER"

  section "iteration $iteration/$ITERATIONS: list-only"
  run_cmd "$ENROLL_TEST" --list-only "$TARGET_USER"

  if [[ "$VERIFY" == "1" ]]; then
    section "iteration $iteration/$ITERATIONS: verify"
    run_cmd fprintd-verify "$TARGET_USER"
  else
    section "iteration $iteration/$ITERATIONS: verify skipped"
    printf '[info] fprintd-verify was not run. Use --verify for physical verification.\n'
  fi

  if ((iteration < ITERATIONS && SLEEP_SECONDS > 0)); then
    section "sleep"
    printf '[info] sleeping %s seconds before next cycle.\n' "$SLEEP_SECONDS"
    sleep "$SLEEP_SECONDS"
  fi
done

section "done"
printf 'Stability check completed for user: %s\n' "$TARGET_USER"
