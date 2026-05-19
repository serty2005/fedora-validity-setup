#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/cache" "$TMPDIR/runtime" "$TMPDIR/venv/bin"
printf 'cached firmware\n' >"$TMPDIR/cache/6_07f_lenovo_mis_qm.xpfwext"

cat >"$TMPDIR/venv/bin/validity-sensors-firmware" <<'EOF'
#!/usr/bin/env bash
printf 'firmware tool should not run when cache exists\n' >&2
exit 99
EOF
chmod +x "$TMPDIR/venv/bin/validity-sensors-firmware"

PREFIX="$TMPDIR" \
RUNTIME_DIR="$TMPDIR/runtime" \
FIRMWARE_CACHE_DIR="$TMPDIR/cache" \
"$ROOT/scripts/ensure-firmware.sh" >/tmp/ensure-firmware-cache-first.out 2>&1

cmp "$TMPDIR/cache/6_07f_lenovo_mis_qm.xpfwext" "$TMPDIR/runtime/6_07f_lenovo_mis_qm.xpfwext"
grep -F 'copy cached firmware into runtime directory' /tmp/ensure-firmware-cache-first.out >/dev/null
