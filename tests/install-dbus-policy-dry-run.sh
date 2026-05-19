#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="$(PATH="/nonexistent:$PATH" "$ROOT/scripts/install-dbus-policy.sh" --dry-run)"

grep -F 'io.github.uunicorn.Fprint.conf' <<<"$OUTPUT" >/dev/null
grep -F 'net.reactivated.Fprint.conf' <<<"$OUTPUT" >/dev/null
grep -F '/etc/dbus-1/system.d/' <<<"$OUTPUT" >/dev/null
grep -F "$ROOT/dbus/io.github.uunicorn.Fprint.conf" <<<"$OUTPUT" >/dev/null
grep -F "$ROOT/dbus/net.reactivated.Fprint.conf" <<<"$OUTPUT" >/dev/null
