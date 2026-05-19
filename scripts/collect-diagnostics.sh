#!/usr/bin/env bash
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE_ID="138a:0097"
WITH_SUDO=0

usage() {
  cat <<'USAGE'
Usage: collect-diagnostics.sh [--with-sudo]

Options:
  --with-sudo  Use regular sudo for privileged diagnostics. This may prompt
               for the user's password.
USAGE
}

while (($# > 0)); do
  case "$1" in
    --with-sudo)
      WITH_SUDO=1
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

LSUSB_LINE="$(lsusb -d "$DEVICE_ID" 2>/dev/null | head -n 1 || true)"
USB_BUS=""
USB_DEVICE=""
if [[ -n "$LSUSB_LINE" ]]; then
  USB_BUS="$(awk '{print $2}' <<<"$LSUSB_LINE")"
  USB_DEVICE="$(awk '{gsub(":", "", $4); print $4}' <<<"$LSUSB_LINE")"
fi
USB_DEV_PATH=""
if [[ -n "$USB_BUS" && -n "$USB_DEVICE" ]]; then
  USB_DEV_PATH="/dev/bus/usb/${USB_BUS}/${USB_DEVICE}"
fi

section() {
  printf '\n===== %s =====\n' "$1"
}

run_cmd() {
  local title="$1"
  shift

  section "$title"
  printf '$'
  printf ' %q' "$@"
  printf '\n'

  "$@"
  local status=$?
  printf '[exit:%s]\n' "$status"
  return 0
}

run_shell() {
  local title="$1"
  local cmd="$2"

  section "$title"
  printf '$ %s\n' "$cmd"
  bash -o pipefail -c "$cmd"
  local status=$?
  printf '[exit:%s]\n' "$status"
  return 0
}

run_sudo_shell() {
  local title="$1"
  local cmd="$2"
  local sudo_args=()

  section "$title"
  if [[ "$WITH_SUDO" == "1" ]]; then
    printf '$ sudo bash -o pipefail -c %q\n' "$cmd"
  else
    sudo_args=(-n)
    printf '$ sudo -n bash -o pipefail -c %q\n' "$cmd"
  fi
  sudo "${sudo_args[@]}" bash -o pipefail -c "$cmd"
  local status=$?
  if [[ $status -ne 0 ]]; then
    if [[ "$WITH_SUDO" == "1" ]]; then
      printf '[note] sudo command failed even though --with-sudo was used. Check password, sudo policy, or command availability.\n'
    else
      printf '[note] sudo command failed. If this is a password prompt issue, rerun the script with --with-sudo.\n'
    fi
  fi
  printf '[exit:%s]\n' "$status"
  return 0
}

section "diagnostics metadata"
printf 'timestamp=%s\n' "$(date --iso-8601=seconds)"
printf 'project_root=%s\n' "$PROJECT_ROOT"
printf 'user=%s\n' "${USER:-unknown}"
printf 'device_id=%s\n' "$DEVICE_ID"
printf 'with_sudo=%s\n' "$WITH_SUDO"
printf 'lsusb_line=%s\n' "${LSUSB_LINE:-not-found}"
printf 'usb_bus=%s\n' "${USB_BUS:-not-found}"
printf 'usb_device=%s\n' "${USB_DEVICE:-not-found}"
printf 'usb_dev_path=%s\n' "${USB_DEV_PATH:-not-found}"

run_cmd "fedora release" cat /etc/fedora-release
run_cmd "kernel" uname -a
run_cmd "python version" python3 --version
run_cmd "python rpm" rpm -q python3
run_cmd "usb devices" lsusb
run_cmd "validity usb verbose" lsusb -d "$DEVICE_ID" -v
run_sudo_shell "validity usb verbose with sudo" "lsusb -d '$DEVICE_ID' -v"
run_shell "usb device node permissions" "ls -l /dev/bus/usb/*/*"
if [[ -n "$USB_DEV_PATH" ]]; then
  run_shell "udevadm info for validity device" "udevadm info --query=all --name='$USB_DEV_PATH'"
else
  section "udevadm info for validity device"
  printf '[note] device %s was not found by lsusb; skipping udevadm info.\n' "$DEVICE_ID"
  printf '[exit:0]\n'
fi
run_sudo_shell "kernel messages for fingerprint/usb" "dmesg | grep -i -E '138a|0097|validity|finger|usb' | tail -n 300"
run_shell "installed rpm packages matching fprint/validity/pam" "rpm -qa | grep -i -E 'fprint|validity|pam'"
run_shell "dnf installed fprint/validity packages" "dnf list installed '*fprint*' '*validity*'"
run_shell "enabled dnf repositories" "dnf repolist --enabled"
run_shell "yum repository files" "ls -1 /etc/yum.repos.d"
run_shell "systemd unit files matching fprint/validity" "systemctl list-unit-files | grep -i -E 'fprint|validity'"
run_shell "fprintd status" "systemctl status fprintd --no-pager || true"
run_shell "fprintd list current user" "fprintd-list \"\${USER}\" || true"
run_shell "system bus services matching fprint/validity" "busctl --system list | grep -i -E 'fprint|validity' || true"
run_shell "authselect current" "authselect current || true"
run_shell "pam fprintd references" "grep -R \"pam_fprintd\" /etc/pam.d /etc/authselect 2>/dev/null || true"
run_cmd "selinux mode" getenforce
run_sudo_shell "recent selinux avc events" "ausearch -m avc -ts recent 2>/dev/null | tail -n 200 || true"
run_shell "journal fingerprint/selinux messages" "journalctl -b | grep -i -E 'selinux|avc|denied|fprint|validity' | tail -n 200 || true"
