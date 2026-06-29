#!/usr/bin/env bash
#
# Summarize representative C userland ELF artifacts for Rust migration
# comparisons. Run after a source build has produced quser/build outputs.

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
raw_dir=
files=()

default_files=(
    quser/build/dev/virtio/devb-virtio.elf
    quser/build/fs/qrv/fs-qrv.elf
    quser/build/qsh/qsh.elf
    quser/build/sbin/login/login.elf
    quser/build/test/syncspace/test_syncspace.elf
    quser/build/test/suite/suite.elf
)

usage() {
    cat <<'EOF'
usage: scripts/capture-elf-baseline.sh [--raw-dir DIR] [elf ...]

Prints a Markdown summary table for representative QSOE C userland ELF files.
With --raw-dir, also writes full audit-elf.sh output for each artifact.

If no ELF files are provided, a migration-focused default set is used:
  devb-virtio, fs-qrv, qsh, login, syncspace, suite.
EOF
}

find_readelf() {
    local t
    for t in llvm-readelf readelf riscv64-linux-gnu-readelf greadelf; do
        if command -v "$t" >/dev/null 2>&1; then
            command -v "$t"
            return 0
        fi
    done
    return 1
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --raw-dir)
            [ "$#" -ge 2 ] || { echo "capture-elf-baseline.sh: --raw-dir needs a value" >&2; exit 2; }
            raw_dir=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            while [ "$#" -gt 0 ]; do
                files+=("$1")
                shift
            done
            ;;
        -*)
            echo "capture-elf-baseline.sh: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
        *)
            files+=("$1")
            shift
            ;;
    esac
done

if [ "${#files[@]}" -eq 0 ]; then
    files=("${default_files[@]}")
fi

READELF=$(find_readelf) || {
    echo "capture-elf-baseline.sh: no readelf tool found" >&2
    exit 127
}

if [ -n "$raw_dir" ]; then
    mkdir -p "$raw_dir"
fi

status=0

printf '| Artifact | Interpreter | Needed | Relocations | Undefined | TLS | Unwind |\n'
printf '| --- | --- | --- | --- | ---: | --- | --- |\n'

for rel in "${files[@]}"; do
    f=$rel
    if [ "${f#/}" = "$f" ]; then
        f="$ROOT/$f"
    fi

    if [ ! -f "$f" ]; then
        echo "capture-elf-baseline.sh: not a file: $rel" >&2
        status=1
        continue
    fi

    if [ -n "$raw_dir" ]; then
        raw_name=$(printf '%s' "$rel" | sed 's#[^A-Za-z0-9._-]#_#g')
        "$ROOT/scripts/audit-elf.sh" "$f" > "$raw_dir/$raw_name.audit.txt" || status=1
    fi

    interp=$("$READELF" -l "$f" 2>/dev/null |
        sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p' |
        head -1)
    needed=$("$READELF" -d "$f" 2>/dev/null |
        sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' |
        paste -sd, -)
    relocs=$("$READELF" -r "$f" 2>/dev/null |
        awk '/R_/ { for (i = 1; i <= NF; i++) if ($i ~ /^R_/) print $i }' |
        sort |
        uniq -c |
        awk '{ print $2 "=" $1 }' |
        paste -sd, -)
    undef=$("$READELF" -Ws "$f" 2>/dev/null |
        awk '$7 == "UND" && $4 != "SECTION" { n++ } END { print n + 0 }')

    tls=no
    if "$READELF" -S "$f" 2>/dev/null |
        grep -E '(\.(tdata|tbss)| TLS )' >/dev/null; then
        tls=yes
    fi

    unwind=no
    if "$READELF" -S "$f" 2>/dev/null |
        grep -E '\.(eh_frame|eh_frame_hdr|gcc_except_table|debug_frame)' >/dev/null; then
        unwind=yes
    fi

    printf '| `%s` | `%s` | `%s` | `%s` | %s | %s | %s |\n' \
        "$rel" \
        "${interp:-none}" \
        "${needed:-none}" \
        "${relocs:-none}" \
        "$undef" \
        "$tls" \
        "$unwind"
done

exit "$status"
