#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

OPEN_UNIT="$ROOT/systemd/open-fprintd.service"
PYTHON_UNIT="$ROOT/systemd/python3-validity.service"

[[ -f "$OPEN_UNIT" ]]
[[ -f "$PYTHON_UNIT" ]]

grep -F 'Type=simple' "$OPEN_UNIT" >/dev/null
grep -F 'Conflicts=fprintd.service' "$OPEN_UNIT" >/dev/null
grep -F 'ExecStart=/opt/fedora-validity/venv/bin/python /opt/fedora-validity/venv/lib/open-fprintd/open-fprintd --debug' "$OPEN_UNIT" >/dev/null
if grep -F 'BusName=net.reactivated.Fprint' "$OPEN_UNIT" >/dev/null; then
  printf 'open-fprintd.service must not claim BusName=net.reactivated.Fprint because stock fprintd.service already uses it\n' >&2
  exit 1
fi

grep -F 'After=open-fprintd.service' "$PYTHON_UNIT" >/dev/null
grep -F 'Requires=open-fprintd.service' "$PYTHON_UNIT" >/dev/null
grep -F 'busctl --system list' "$PYTHON_UNIT" >/dev/null
grep -F 'open-fprintd.service' "$PYTHON_UNIT" >/dev/null
if grep -F 'busctl --system introspect net.reactivated.Fprint' "$PYTHON_UNIT" >/dev/null; then
  printf 'python3-validity.service must not introspect net.reactivated.Fprint before backend start because that can activate stock fprintd.service\n' >&2
  exit 1
fi
grep -F 'ExecStartPre=/opt/fedora-validity/bin/ensure-firmware.sh' "$PYTHON_UNIT" >/dev/null
if grep -F 'ExecStartPre=/opt/fedora-validity/venv/bin/validity-sensors-firmware' "$PYTHON_UNIT" >/dev/null; then
  printf 'python3-validity.service must not call network-dependent validity-sensors-firmware directly during boot\n' >&2
  exit 1
fi
grep -F 'ExecStart=/opt/fedora-validity/venv/bin/python /opt/fedora-validity/venv/lib/python-validity/dbus-service --debug --configpath /opt/fedora-validity/etc/python-validity' "$PYTHON_UNIT" >/dev/null

if grep -R -E 'authselect|pam_fprintd|gdm|sudo pam|/etc/pam\.d' "$ROOT/systemd" >/dev/null; then
  printf 'systemd units must not change PAM/authselect/GDM/sudo\n' >&2
  exit 1
fi
