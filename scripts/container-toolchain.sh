#!/usr/bin/env bash
#
# Build and run the Debian QSOE toolchain container.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
RUNTIME=${CONTAINER_RUNTIME:-docker}
IMAGE=${QSOE_TOOLCHAIN_IMAGE:-qsoe-toolchain:debian}
DOCKERFILE="$ROOT/toolchains/debian/Dockerfile"
CONTEXT="$ROOT/toolchains/debian"

usage() {
    cat <<EOF
usage: scripts/container-toolchain.sh <command> [args...]

commands:
  build              build the Debian toolchain image
  shell              open an interactive shell in the mounted repository
  run <cmd...>       run a command in /work/qsoe/os
  check              run host fixtures and Rust checks
  index-c-static     build C tags, cscope, and GNU Global indexes
  index-c-compile-db capture C compile_commands.json with Bear
  tidy-c             run bounded clang-tidy over the active compile DB
  rust-fast          run the fast Rust edit-loop checks
  rust-quality       run the normal Rust quality gate
  rust-abi           run the QSOE Rust ABI/link-smoke gate
  rust-deep          run optional deeper Rust checks
  rust-link-smoke    run make rust-qsoe-link-smoke
  source-build       run make prepare if needed, then make

environment:
  CONTAINER_RUNTIME      container runtime, default: docker
  QSOE_TOOLCHAIN_IMAGE   image tag, default: qsoe-toolchain:debian
  QSOE_CONTAINER_ROOT=1  run container as root instead of host uid/gid
EOF
}

need_runtime() {
    if ! command -v "$RUNTIME" >/dev/null 2>&1; then
        echo "container-toolchain.sh: runtime not found: $RUNTIME" >&2
        exit 127
    fi
}

run_container() {
    need_runtime

    docker_args=(run --rm)
    if [ -t 0 ] && [ -t 1 ]; then
        docker_args+=(-it)
    fi

    if [ "${QSOE_CONTAINER_ROOT:-0}" != "1" ]; then
        docker_args+=(--user "$(id -u):$(id -g)" -e HOME=/tmp/qsoe-home)
    fi

    "$RUNTIME" "${docker_args[@]}" \
        -e GIT_CONFIG_COUNT=1 \
        -e GIT_CONFIG_KEY_0=safe.directory \
        -e GIT_CONFIG_VALUE_0='*' \
        -e QSOE_HOST_ROOT="$ROOT" \
        -v "$ROOT:/work/qsoe/os" \
        -w /work/qsoe/os \
        "$IMAGE" \
        bash -c 'mkdir -p "$HOME"; exec "$@"' qsoe-container "$@"
}

cmd=${1:-}
case "$cmd" in
    build)
        need_runtime
        "$RUNTIME" build -f "$DOCKERFILE" -t "$IMAGE" "$CONTEXT"
        ;;
    shell)
        run_container bash
        ;;
    run)
        shift
        if [ "$#" -eq 0 ]; then
            usage >&2
            exit 2
        fi
        run_container "$@"
        ;;
    check)
        run_container bash -c 'make check-host-tools && make rust-quality && make check-qrvfs-rust-fixture && make check-elf-reloc-fixture'
        ;;
    index-c-static)
        run_container make index-c-static
        ;;
    index-c-compile-db)
        run_container make index-c-compile-db
        ;;
    tidy-c)
        run_container bash -c '
            if [ -f build/index/c/compile_commands.container.json ]; then
                QSOE_TIDY_DB="$PWD/build/index/c/compile_commands.container.json" make tidy-c
            else
                make tidy-c
            fi
        '
        ;;
    rust-fast)
        run_container make rust-fast
        ;;
    rust-quality)
        run_container make rust-quality
        ;;
    rust-abi)
        run_container make rust-abi
        ;;
    rust-deep)
        run_container make rust-deep
        ;;
    rust-link-smoke)
        run_container bash -c 'make rust-qsoe-link-smoke'
        ;;
    source-build)
        run_container bash -c '
            set -eu
            missing=0
            for d in lq nq libc quser; do
                [ -d "$d" ] || missing=1
            done
            if [ "$missing" -eq 1 ]; then
                make prepare
            fi
            scripts/apply-component-overrides.sh
            make
        '
        ;;
    -h|--help|help|'')
        usage
        ;;
    *)
        echo "container-toolchain.sh: unknown command: $cmd" >&2
        usage >&2
        exit 2
        ;;
esac
