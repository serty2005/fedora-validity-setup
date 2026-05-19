#!/usr/bin/env bash
set -euo pipefail

section() {
  printf '\n===== %s =====\n' "$1"
}

run() {
  printf '$'
  printf ' %q' "$@"
  printf '\n'
  "$@"
}

run_optional() {
  printf '$'
  printf ' %q' "$@"
  printf '\n'
  "$@" || true
}

section "enabled repositories before cleanup"
run dnf repolist --enabled

section "validity/fprint related repositories"
dnf repolist --all | grep -i -E 'validity|fprint|pbo|taaem|r9ht|tigro|sneexy' || true

section "disable known stale python-validity COPR repositories"
run_optional sudo dnf copr disable pbo/python-validity -y
run_optional sudo dnf copr disable taaem/python-validity -y
run_optional sudo dnf copr disable r9ht/python-validitya -y
run_optional sudo dnf copr disable tigro/python-validity -y
run_optional sudo dnf copr disable sneexy/python-validity -y

section "remove only python-validity/python-validitya repo files"
run_optional sudo rm -f /etc/yum.repos.d/*python-validity*.repo
run_optional sudo rm -f /etc/yum.repos.d/*python-validitya*.repo

section "refresh dnf metadata"
run sudo dnf clean all
run sudo dnf makecache

section "enabled repositories after cleanup"
run dnf repolist --enabled

section "remaining validity/fprint related repositories"
dnf repolist --all | grep -i -E 'validity|fprint|pbo|taaem|r9ht|tigro|sneexy' || true
