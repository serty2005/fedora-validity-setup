#!/usr/bin/env bash
set -euo pipefail

PACKAGES=(
  git
  gcc
  gcc-c++
  make
  cmake
  meson
  ninja-build
  pkgconf-pkg-config
  python3
  python3-devel
  python3-pip
  python3-virtualenv
  python3-setuptools
  python3-wheel
  python3-dbus
  python3-gobject
  python3-cryptography
  python3-pyusb
  python3-pyyaml
  dbus-devel
  glib2-devel
  systemd-devel
  libusb1-devel
  libgusb-devel
  pam-devel
  polkit-devel
  openssl-devel
  xmlto
  gtk-doc
  gettext
  fprintd
  libfprint
  usbutils
)

section() {
  printf '\n===== %s =====\n' "$1"
}

section "check enabled repositories"
dnf repolist --enabled

if dnf repolist --enabled | grep -i -E 'python-validity|python-validitya' >/dev/null; then
  printf '\n[error] stale python-validity COPR repository is still enabled.\n' >&2
  printf '[error] Run scripts/clean-old-copr.sh first, then rerun this script.\n' >&2
  exit 2
fi

section "sudo authentication"
printf '$ sudo -v\n'
sudo -v

FAILED_PACKAGES=()

section "install Fedora/RPM Fusion dependencies"
for package in "${PACKAGES[@]}"; do
  printf '\n$ sudo dnf install -y %q\n' "$package"
  if ! sudo dnf install -y "$package"; then
    FAILED_PACKAGES+=("$package")
    printf '[warning] package was not installed: %s\n' "$package" >&2
  fi
done

section "dependency installation summary"
if ((${#FAILED_PACKAGES[@]} == 0)); then
  printf 'All requested packages were installed or already present.\n'
else
  printf 'Packages not installed:\n'
  printf '  - %s\n' "${FAILED_PACKAGES[@]}"
  printf '\nRecord these missing packages in docs/iteration-002.md before continuing.\n'
fi
