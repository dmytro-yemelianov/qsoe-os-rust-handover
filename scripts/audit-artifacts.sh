#!/usr/bin/env bash
#
# Audit installed QSOE userland ELF artifacts from the image staging roots.

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
strict_args=()
roots=()

default_roots=(
    quser/build/modpkg-root
    build/fsqrv-root
)

usage() {
    cat <<'EOF'
usage: scripts/audit-artifacts.sh [--strict-qsoe-user] [--root DIR]...

Find ELF files installed into the QSOE userland staging roots and run
scripts/audit-elf.sh on all of them.

Default roots:
  quser/build/modpkg-root   boot CPIO staging tree
  build/fsqrv-root          qrvfs /usr staging tree

Options:
  --strict-qsoe-user        pass the strict userland gate to audit-elf.sh
  --root DIR                add an explicit staging root to scan
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --strict-qsoe-user)
            strict_args+=(--strict-qsoe-user)
            shift
            ;;
        --root)
            [ "$#" -ge 2 ] || {
                echo "audit-artifacts.sh: --root needs a value" >&2
                exit 2
            }
            roots+=("$2")
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            while [ "$#" -gt 0 ]; do
                roots+=("$1")
                shift
            done
            ;;
        -*)
            echo "audit-artifacts.sh: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
        *)
            roots+=("$1")
            shift
            ;;
    esac
done

if [ "${#roots[@]}" -eq 0 ]; then
    roots=("${default_roots[@]}")
fi

elf_magic() {
    local f=$1
    dd if="$f" bs=4 count=1 2>/dev/null |
        od -An -tx1 |
        tr -d ' \n'
}

is_elf() {
    [ "$(elf_magic "$1")" = "7f454c46" ]
}

artifacts=()
missing=0

for root in "${roots[@]}"; do
    case "$root" in
        /*) abs_root=$root ;;
        *) abs_root=$ROOT/$root ;;
    esac

    if [ ! -d "$abs_root" ]; then
        echo "audit-artifacts.sh: missing staging root: $root" >&2
        missing=1
        continue
    fi

    while IFS= read -r f; do
        if is_elf "$f"; then
            case "$f" in
                "$ROOT"/*) artifacts+=("${f#$ROOT/}") ;;
                *) artifacts+=("$f") ;;
            esac
        fi
    done < <(find "$abs_root" -type f -print | LC_ALL=C sort)
done

if [ "$missing" -ne 0 ]; then
    echo "audit-artifacts.sh: build the source tree and qrvfs staging before auditing" >&2
    exit 1
fi

if [ "${#artifacts[@]}" -eq 0 ]; then
    echo "audit-artifacts.sh: no ELF artifacts found" >&2
    exit 1
fi

cd "$ROOT"

printf 'audit-artifacts.sh: auditing %u ELF artifacts\n' "${#artifacts[@]}"
for f in "${artifacts[@]}"; do
    printf '  %s\n' "$f"
done

"$ROOT/scripts/audit-elf.sh" "${strict_args[@]}" "${artifacts[@]}"
