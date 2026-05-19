#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/cache" "$TMPDIR/runtime" "$TMPDIR/venv/bin"

cat >"$TMPDIR/venv/bin/validity-sensors-firmware" <<EOF
#!/usr/bin/env bash
printf 'downloaded firmware\n' >"$TMPDIR/runtime/6_07f_lenovo_mis_qm.xpfwext"
EOF
chmod +x "$TMPDIR/venv/bin/validity-sensors-firmware"

PREFIX="$TMPDIR" \
RUNTIME_DIR="$TMPDIR/runtime" \
FIRMWARE_CACHE_DIR="$TMPDIR/cache" \
"$ROOT/scripts/ensure-firmware.sh" >/tmp/ensure-firmware-populates-cache.out 2>&1

cmp "$TMPDIR/runtime/6_07f_lenovo_mis_qm.xpfwext" "$TMPDIR/cache/6_07f_lenovo_mis_qm.xpfwext"
grep -F 'populate persistent firmware cache' /tmp/ensure-firmware-populates-cache.out >/dev/null
