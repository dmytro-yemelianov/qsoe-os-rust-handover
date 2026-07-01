#!/usr/bin/env bash
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAKE="${MAKE:-make}"
WORKDIR="${SPAWN_LOADER_C_STRESS_WORKDIR:-$ROOT/build/spawn-loader-c-stress-evidence}"
SPAWN_COUNT="${SPAWN_LOADER_C_STRESS_COUNT:-72}"
BOOT_LOG="$WORKDIR/boot-spawn-loader-c-stress.log"
SUMMARY="$WORKDIR/summary.txt"

fail() {
    printf 'spawn-loader-c-stress-evidence: %s\n' "$*" >&2
    exit 1
}

case "$SPAWN_COUNT" in
    ''|*[!0-9]*) fail "SPAWN_LOADER_C_STRESS_COUNT must be a positive integer" ;;
esac
if [ "$SPAWN_COUNT" -le 0 ]; then
    fail "SPAWN_LOADER_C_STRESS_COUNT must be greater than zero"
fi

require_log_fixed() {
    pattern="$1"
    label="$2"
    if ! grep -Fq "$pattern" "$BOOT_LOG"; then
        fail "missing boot evidence: $label ($pattern)"
    fi
}

reject_log_regex() {
    pattern="$1"
    label="$2"
    if grep -Eq "$pattern" "$BOOT_LOG"; then
        fail "unexpected boot evidence: $label ($pattern)"
    fi
}

source_conf="$ROOT/quser/conf"
source_sysinit="$source_conf/sysinit"
fragment=
lq_libc="$ROOT/lq/build/libc/libc.so"
sysinfo_staged="$ROOT/build/fsqrv-root/bin/sysinfo"

start_marker="spawn-loader-c-stress: starting repeated spawn/exit evidence"
failure_marker="spawn-loader-c-stress: missing executable failure ok"
cap_marker="spawn-loader-c-stress: repeated spawn/exit cap stability ok"

mkdir -p "$WORKDIR"

if [ ! -d "$source_conf" ]; then
    fail "missing quser/conf; run make prepare first"
fi

"$ROOT/scripts/apply-component-overrides.sh"

cleanup() {
    if [ -n "$fragment" ]; then
        rm -f "$fragment"
    fi
    rmdir "$source_sysinit" >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p "$source_sysinit"
fragment=$(mktemp "$source_sysinit/10-spawn-loader-c-stress.XXXXXX.sh")
{
    printf 'echo "%s"\n' "$start_marker"
    cat <<'EOF'
if /missing/spawn-loader-c-evidence >/dev/null 2>&1; then
    echo "spawn-loader-c-stress: missing executable unexpectedly succeeded"
    exit 1
else
    echo "spawn-loader-c-stress: missing executable failure ok"
fi
EOF

    i=1
    while [ "$i" -le "$SPAWN_COUNT" ]; do
        printf 'if /usr/bin/sysinfo >/dev/null 2>&1; then :; else rc=$?; echo "spawn-loader-c-stress: sysinfo spawn %03d failed $rc"; exit $rc; fi\n' "$i"
        i=$((i + 1))
    done

    printf 'echo "%s"\n' "$cap_marker"
} > "$fragment"
chmod 0644 "$fragment"

echo "spawn-loader-c-stress-evidence: building LQ runtime prerequisites"
"$MAKE" -C "$ROOT/lq" libc rtld libtaskman --no-print-directory

echo "spawn-loader-c-stress-evidence: rebuilding quser with LQ libc"
"$MAKE" -C "$ROOT/quser" LIBC_SO="$lq_libc" --no-print-directory

echo "spawn-loader-c-stress-evidence: rebuilding virtio qrvfs image"
rm -f "$ROOT/build/fsqrv.img" "$ROOT/build/virtio.img"
"$MAKE" -C "$ROOT" virtio --no-print-directory

if [ ! -x "$sysinfo_staged" ]; then
    fail "staged sysinfo is missing or not executable"
fi

echo "spawn-loader-c-stress-evidence: rebuilding QSOE/L image"
"$MAKE" -C "$ROOT/lq" --no-print-directory

boot_extra_patterns=$(printf '%s\n' \
    "$start_marker" \
    "$failure_marker" \
    "$cap_marker" \
    'dispatcher ready')

echo "spawn-loader-c-stress-evidence: booting repeated spawn/failure evidence"
QSOE_BOOT_VIRTIO_PATTERN="/dev/vblk0 ready" \
QSOE_BOOT_EXTRA_PATTERNS="$boot_extra_patterns" \
    "$ROOT/scripts/boot-smoke.sh" -k lq -t 180 -o "$BOOT_LOG" -- --debug=1

require_log_fixed "$start_marker" 'stress sysinit start'
require_log_fixed "$failure_marker" 'runtime missing-executable failure path'
require_log_fixed "$cap_marker" 'repeated spawn/exit cap stability'

reject_log_regex 'spawn-loader-c-stress: sysinfo spawn [0-9]+ failed' 'sysinfo spawn failure'
reject_log_regex 'spawn-loader-c-stress: missing executable unexpectedly succeeded' 'missing executable false positive'

dynamic_spawn_count=$(grep -E 'spawn: .*e_type=.*interp=yes' "$BOOT_LOG" | wc -l | tr -d '[:space:]')
if [ "$dynamic_spawn_count" -lt "$SPAWN_COUNT" ]; then
    fail "expected at least $SPAWN_COUNT dynamic spawn debug lines, saw $dynamic_spawn_count"
fi

{
    printf 'spawn/loader C stress evidence complete\n'
    printf 'boot_log=%s\n' "$BOOT_LOG"
    printf 'spawn_count=%s\n' "$SPAWN_COUNT"
    printf 'dynamic_spawn_debug_lines=%s\n' "$dynamic_spawn_count"
    printf 'observed=repeated dynamic sysinfo spawn/wait, missing-executable failure, final post-stress marker\n'
} > "$SUMMARY"

printf 'spawn-loader-c-stress-evidence: wrote %s\n' "$SUMMARY"
