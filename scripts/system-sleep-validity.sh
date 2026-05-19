#!/usr/bin/env bash
set -euo pipefail

PHASE="${1:-}"
ACTION="${2:-}"
RESTART_HELPER="${FEDORA_VALIDITY_RESTART_HELPER:-/opt/fedora-validity/bin/restart-project-services.sh}"

printf 'fedora-validity system-sleep hook: %s %s\n' "${PHASE:-unknown}" "${ACTION:-unknown}"

case "$PHASE" in
  pre)
    printf 'fedora-validity: pre-sleep phase, no action.\n'
    exit 0
    ;;
  post)
    if [[ ! -x "$RESTART_HELPER" ]]; then
      printf 'fedora-validity: missing restart helper: %s\n' "$RESTART_HELPER" >&2
      exit 1
    fi
    printf 'fedora-validity: restarting project services after resume.\n'
    "$RESTART_HELPER" --no-status
    ;;
  *)
    printf 'fedora-validity: unknown system-sleep phase, no action.\n'
    ;;
esac
