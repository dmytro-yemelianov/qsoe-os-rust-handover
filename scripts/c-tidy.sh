#!/usr/bin/env bash
#
# Run a bounded clang-tidy pass over the active QSOE C compile database.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DB=${QSOE_TIDY_DB:-"$ROOT/build/index/c/compile_commands.json"}
LIMIT=${QSOE_TIDY_LIMIT:-25}
ROOTS=${QSOE_TIDY_ROOTS:-"boot common host_tools libc libtaskman lq nq quser"}
CLANG_TIDY=${CLANG_TIDY:-clang-tidy}
CONFIG=${QSOE_TIDY_CONFIG:-"$ROOT/.clang-tidy"}
HEADER_FILTER=${QSOE_TIDY_HEADER_FILTER:-"^$ROOT/(boot|common|host_tools|libc|libtaskman|lq|nq|quser)/"}
CHECKS=${QSOE_TIDY_CHECKS:-}

usage() {
    cat <<EOF
usage: scripts/c-tidy.sh [options] [--] [file...]

options:
  --all             run every matching compile database entry
  --limit N         run at most N files, default: $LIMIT; 0 means all
  --roots "R..."    space-separated source roots, default: $ROOTS
  --checks CHECKS   override .clang-tidy Checks for this run

environment:
  QSOE_TIDY_DB             compile database, default: build/index/c/compile_commands.json
  QSOE_TIDY_LIMIT          default file limit
  QSOE_TIDY_ROOTS          default source roots
  QSOE_TIDY_CHECKS         override repo .clang-tidy checks
  QSOE_TIDY_CONFIG         clang-tidy config file, default: .clang-tidy
  QSOE_TIDY_HEADER_FILTER  override header filter
  CLANG_TIDY               clang-tidy binary, default: clang-tidy
EOF
}

need_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "c-tidy.sh: required tool not found: $1" >&2
        exit 127
    fi
}

abs_path() {
    case "$1" in
        /*)
            realpath -m "$1"
            ;;
        *)
            realpath -m "$ROOT/$1"
            ;;
    esac
}

root_allowed() {
    rel=${1#"$ROOT"/}
    for root in $ROOTS; do
        case "$rel" in
            "$root"|"$root"/*)
                return 0
                ;;
        esac
    done
    return 1
}

parse_limit() {
    case "$1" in
        ''|*[!0-9]*)
            echo "c-tidy.sh: limit must be a non-negative integer: $1" >&2
            exit 2
            ;;
    esac
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --all)
            LIMIT=0
            ;;
        --limit)
            shift
            [ "$#" -gt 0 ] || {
                echo "c-tidy.sh: --limit requires a value" >&2
                exit 2
            }
            LIMIT=$1
            ;;
        --roots)
            shift
            [ "$#" -gt 0 ] || {
                echo "c-tidy.sh: --roots requires a value" >&2
                exit 2
            }
            ROOTS=$1
            ;;
        --checks)
            shift
            [ "$#" -gt 0 ] || {
                echo "c-tidy.sh: --checks requires a value" >&2
                exit 2
            }
            CHECKS=$1
            ;;
        -h|--help|help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "c-tidy.sh: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
        *)
            break
            ;;
    esac
    shift
done

parse_limit "$LIMIT"
need_tool jq
need_tool realpath
need_tool "$CLANG_TIDY"

if [ ! -f "$DB" ]; then
    echo "c-tidy.sh: missing compile database: $DB" >&2
    echo "Generate it with: QSOE_INDEX_CLEAN=1 make index-c-compile-db" >&2
    exit 1
fi

if [ ! -f "$CONFIG" ] && [ -z "$CHECKS" ]; then
    echo "c-tidy.sh: missing clang-tidy config: $CONFIG" >&2
    exit 1
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

candidates="$tmpdir/candidates"
selected="$tmpdir/selected"
requested="$tmpdir/requested"
run_files="$tmpdir/run-files"
db_dir=$(dirname "$DB")
clang_db_dir=$db_dir

if [ "$(basename "$DB")" != "compile_commands.json" ]; then
    clang_db_dir="$tmpdir/clang-db"
    mkdir -p "$clang_db_dir"
    cp "$DB" "$clang_db_dir/compile_commands.json"
fi

jq -r '.[].file // empty' "$DB" | while IFS= read -r file; do
    case "$file" in
        /*)
            abs=$(realpath -m "$file")
            ;;
        *)
            abs=$(realpath -m "$db_dir/$file")
            ;;
    esac

    [ -f "$abs" ] || continue
    case "$abs" in
        "$ROOT"/build/*|"$ROOT"/sel4-bootstrap/*)
            continue
            ;;
    esac
    root_allowed "$abs" || continue
    printf '%s\n' "$abs"
done | LC_ALL=C sort -u > "$candidates"

if [ "$#" -gt 0 ]; then
    : > "$requested"
    for file in "$@"; do
        abs_path "$file" >> "$requested"
    done
    LC_ALL=C sort -u "$requested" -o "$requested"
    grep -Fxf "$requested" "$candidates" > "$selected" || true
else
    cp "$candidates" "$selected"
fi

if [ ! -s "$selected" ]; then
    echo "c-tidy.sh: no matching source files in compile database" >&2
    exit 1
fi

if [ "$LIMIT" = "0" ]; then
    cp "$selected" "$run_files"
else
    sed -n "1,${LIMIT}p" "$selected" > "$run_files"
fi

count=$(wc -l < "$run_files" | tr -d ' ')
total=$(wc -l < "$selected" | tr -d ' ')

echo "c-tidy.sh: database: $DB"
echo "c-tidy.sh: files: $count/$total"
echo "c-tidy.sh: roots: $ROOTS"
if [ -n "$CHECKS" ]; then
    echo "c-tidy.sh: checks: $CHECKS"
else
    echo "c-tidy.sh: config: $CONFIG"
fi

status=0
while IFS= read -r file; do
    echo "c-tidy.sh: $file"
    args=(--quiet -p "$clang_db_dir" --header-filter "$HEADER_FILTER")
    if [ -n "$CHECKS" ]; then
        args+=(--checks "$CHECKS")
    else
        args+=(--config-file "$CONFIG")
    fi
    "$CLANG_TIDY" "${args[@]}" "$file" || status=$?
done < "$run_files"

exit "$status"
