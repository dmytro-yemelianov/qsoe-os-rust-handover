#!/usr/bin/env bash
#
# Build C source navigation and analysis indexes for the QSOE umbrella tree.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MODE=${1:-}
INDEX_DIR=${QSOE_INDEX_DIR:-"$ROOT/build/index/c"}
FILES="$INDEX_DIR/files.list"
DEFAULT_ROOTS="boot common host_tools libc libtaskman lq nq quser"

usage() {
    cat <<EOF
usage: scripts/c-index.sh <mode> [build command...]

modes:
  files        write the indexed source list
  tags         build Universal Ctags index
  cscope       build cscope index
  global       build GNU Global index
  static       build files, tags, cscope, and GNU Global indexes
  compile-db   capture compile_commands.json with Bear
  all          build static indexes and capture compile_commands.json

environment:
  QSOE_INDEX_DIR          output directory, default: build/index/c
  QSOE_INDEX_ROOTS        indexed roots, default: QSOE-owned C trees
  QSOE_INDEX_SEL4=1       include sel4-bootstrap/seL4 roots
  QSOE_INDEX_CLEAN=1      run make clean before compile-db capture
  QSOE_INDEX_DB_FLAVOR    current, host, or container
  QSOE_HOST_ROOT          host path for rewriting container compile DBs
EOF
}

need_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "c-index.sh: required tool not found: $1" >&2
        exit 127
    fi
}

index_roots() {
    roots=${QSOE_INDEX_ROOTS:-$DEFAULT_ROOTS}

    if [ "${QSOE_INDEX_SEL4:-0}" = "1" ]; then
        roots="$roots sel4-bootstrap/seL4 sel4-bootstrap/seL4_tools"
    fi

    for root in $roots; do
        if [ -d "$ROOT/$root" ] || [ -f "$ROOT/$root" ]; then
            printf '%s\n' "$root"
        fi
    done
}

write_files() {
    need_tool rg
    mkdir -p "$INDEX_DIR"

    (
        cd "$ROOT"
        index_roots | xargs rg --files \
            -g '*.c' \
            -g '*.h' \
            -g '*.S' \
            -g '*.s' \
            -g '*.ld' \
            -g '!**/.git/**' \
            -g '!**/build/**' \
            -g '!rust/target/**' \
            -g '!sel4-bootstrap/build-*' \
            2>/dev/null | LC_ALL=C sort -u
    ) > "$FILES"

    count=$(wc -l < "$FILES" | tr -d ' ')
    echo "c-index.sh: wrote $FILES ($count files)"
}

ensure_files() {
    if [ ! -f "$FILES" ]; then
        write_files
    fi
}

build_tags() {
    need_tool ctags
    ensure_files

    if ! ctags --version 2>/dev/null | grep -qi 'Universal Ctags'; then
        echo "c-index.sh: Universal Ctags is required for stable options" >&2
        exit 1
    fi

    ctags \
        -f "$INDEX_DIR/tags" \
        -L "$FILES" \
        --languages=C,Asm \
        --extras=+q \
        --fields=+iaS \
        --kinds-C=+p

    echo "c-index.sh: wrote $INDEX_DIR/tags"
}

build_cscope() {
    need_tool cscope
    ensure_files

    (
        cd "$ROOT"
        cscope -b -q -k -i "$FILES" -f "$INDEX_DIR/cscope.out"
    )

    echo "c-index.sh: wrote $INDEX_DIR/cscope.out"
}

build_global() {
    need_tool gtags
    ensure_files

    rm -rf "$INDEX_DIR/global"
    mkdir -p "$INDEX_DIR/global"

    (
        cd "$ROOT"
        gtags -f "$FILES" "$INDEX_DIR/global"
    )

    echo "c-index.sh: wrote $INDEX_DIR/global/{GTAGS,GRTAGS,GPATH}"
}

normalize_compile_db() {
    raw=$1
    out=$2

    if command -v jq >/dev/null 2>&1; then
        jq 'sort_by(.file // "", .directory // "", .command // "")' "$raw" > "$out"
    else
        cp "$raw" "$out"
    fi
}

rewrite_compile_db_for_host() {
    in_file=$1
    out_file=$2

    if [ -z "${QSOE_HOST_ROOT:-}" ]; then
        echo "c-index.sh: QSOE_HOST_ROOT is required for host compile DB rewrite" >&2
        exit 1
    fi
    need_tool jq

    jq --arg from "$ROOT" --arg to "$QSOE_HOST_ROOT" '
      def prefixed:
        if type == "string" and startswith($from) then
          $to + .[($from | length):]
        else
          .
        end;

      map(
        .directory |= prefixed
        | .file |= prefixed
        | if has("command") then
            .command |= gsub($from; $to)
          else
            .
          end
        | if has("arguments") then
            .arguments |= map(if type == "string" then gsub($from; $to) else . end)
          else
            .
          end
      )
    ' "$in_file" > "$out_file"
}

compile_db_flavor() {
    if [ -n "${QSOE_INDEX_DB_FLAVOR:-}" ]; then
        printf '%s\n' "$QSOE_INDEX_DB_FLAVOR"
    elif [ -n "${QSOE_HOST_ROOT:-}" ] && [ "$ROOT" != "$QSOE_HOST_ROOT" ]; then
        printf '%s\n' host
    else
        printf '%s\n' current
    fi
}

capture_compile_db() {
    need_tool bear
    mkdir -p "$INDEX_DIR"

    shift
    if [ "$#" -eq 0 ]; then
        set -- make
    fi

    if [ "${QSOE_INDEX_CLEAN:-0}" = "1" ]; then
        (cd "$ROOT" && make clean)
        mkdir -p "$INDEX_DIR"
    fi

    raw="$INDEX_DIR/compile_commands.raw.json"
    current="$INDEX_DIR/compile_commands.current.json"
    container="$INDEX_DIR/compile_commands.container.json"
    host="$INDEX_DIR/compile_commands.host.json"
    final="$INDEX_DIR/compile_commands.json"

    rm -f "$raw" "$current" "$container" "$host" "$final"

    (
        cd "$ROOT"
        bear --output "$raw" -- "$@"
    )

    normalize_compile_db "$raw" "$current"

    flavor=$(compile_db_flavor)
    case "$flavor" in
        current)
            cp "$current" "$final"
            ;;
        container)
            cp "$current" "$container"
            cp "$current" "$final"
            ;;
        host)
            cp "$current" "$container"
            rewrite_compile_db_for_host "$current" "$host"
            cp "$host" "$final"
            ;;
        *)
            echo "c-index.sh: invalid QSOE_INDEX_DB_FLAVOR: $flavor" >&2
            exit 2
            ;;
    esac

    count=$(jq 'length' "$final" 2>/dev/null || printf '?')
    echo "c-index.sh: wrote $final ($count commands, flavor=$flavor)"
    if [ "$count" = "0" ]; then
        echo "c-index.sh: compile DB is empty; use QSOE_INDEX_CLEAN=1 or capture a target that rebuilds" >&2
    fi
}

case "$MODE" in
    files)
        write_files
        ;;
    tags)
        build_tags
        ;;
    cscope)
        build_cscope
        ;;
    global)
        build_global
        ;;
    static)
        write_files
        build_tags
        build_cscope
        build_global
        ;;
    compile-db)
        capture_compile_db "$@"
        ;;
    all)
        write_files
        build_tags
        build_cscope
        build_global
        capture_compile_db compile-db
        ;;
    -h|--help|help|'')
        usage
        ;;
    *)
        echo "c-index.sh: unknown mode: $MODE" >&2
        usage >&2
        exit 2
        ;;
esac
