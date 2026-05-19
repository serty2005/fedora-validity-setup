#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="/opt/fedora-validity"
VENV="$PREFIX/venv"
NOTES="$PROJECT_ROOT/docs/fedora44-python314-notes.md"

section() {
  printf '\n===== %s =====\n' "$1"
}

append_note() {
  {
    printf '\n## prepare-venv note %s\n\n' "$(date --iso-8601=seconds)"
    printf '%s\n' "$1"
  } >> "$NOTES"
}

section "sudo authentication"
printf '$ sudo -v\n'
sudo -v

section "create prefix"
printf '$ sudo mkdir -p %q\n' "$PREFIX"
sudo mkdir -p "$PREFIX"

section "create venv"
if [[ ! -x "$VENV/bin/python" ]]; then
  printf '$ sudo python3 -m venv --system-site-packages %q\n' "$VENV"
  sudo python3 -m venv --system-site-packages "$VENV"
else
  printf '[info] venv already exists: %s\n' "$VENV"
fi

section "upgrade packaging tools"
printf '$ sudo %q -m pip install --upgrade pip setuptools wheel\n' "$VENV/bin/python"
sudo "$VENV/bin/python" -m pip install --upgrade pip setuptools wheel

section "install upstream Python dependencies in venv"
printf '$ sudo %q -m pip install --upgrade cryptography pyusb pyyaml\n' "$VENV/bin/python"
sudo "$VENV/bin/python" -m pip install --upgrade cryptography pyusb pyyaml

section "check core imports"
printf '$ %q -c %q\n' "$VENV/bin/python" "import usb, cryptography, yaml; print('ok')"
"$VENV/bin/python" -c "import usb, cryptography, yaml; print('ok')"

section "check Fedora-provided runtime imports"
MISSING_SYSTEM_IMPORTS=()
for module in dbus gi; do
  printf '$ %q -c %q\n' "$VENV/bin/python" "import ${module}; print('${module}: ok')"
  if ! "$VENV/bin/python" -c "import ${module}; print('${module}: ok')"; then
    MISSING_SYSTEM_IMPORTS+=("$module")
  fi
done

printf '$ %q -c %q\n' "$VENV/bin/python" "import systemd; print('systemd: ok')"
if ! "$VENV/bin/python" -c "import systemd; print('systemd: ok')"; then
  append_note "Модуль \`systemd\` не импортируется из venv. Для этого проекта он пока не найден в runtime imports upstream; если позже понадобится \`systemd-python\`, использовать Fedora RPM, а не глобальный \`sudo pip\`."
fi

if ((${#MISSING_SYSTEM_IMPORTS[@]} > 0)); then
  append_note "Следующие Fedora-provided imports не доступны из \`$VENV\`: \`${MISSING_SYSTEM_IMPORTS[*]}\`. Установить соответствующие RPM через \`scripts/install-deps.sh\` после очистки старого COPR."
  printf '[warning] missing system imports: %s\n' "${MISSING_SYSTEM_IMPORTS[*]}" >&2
else
  append_note "Venv \`$VENV\` создан с \`--system-site-packages\`; \`dbus\` и \`gi\` доступны из Fedora RPM/system site-packages."
fi
