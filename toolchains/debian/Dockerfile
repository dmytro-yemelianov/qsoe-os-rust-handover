FROM debian:trixie

ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TOOLCHAIN=1.95.0
ARG RUST_TARGET=riscv64gc-unknown-none-elf
ARG RUST_TASKMAN_TARGET=riscv64imac-unknown-none-elf

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bash \
        bear \
        bc \
        binutils-riscv64-linux-gnu \
        bison \
        build-essential \
        ca-certificates \
        clang-tidy \
        clang-tools \
        clangd \
        cmake \
        cpio \
        curl \
        device-tree-compiler \
        file \
        flex \
        gcc-riscv64-linux-gnu \
        git \
        global \
        jq \
        libxml2-utils \
        make \
        ninja-build \
        opensbi \
        patch \
        pkg-config \
        python3 \
        python3-autopep8 \
        python3-bs4 \
        python3-dev \
        python3-jinja2 \
        python3-jsonschema \
        python3-kconfiglib \
        python3-libarchive-c \
        python3-lxml \
        python3-pexpect \
        python3-ply \
        python3-psutil \
        python3-pyelftools \
        python3-setuptools \
        python3-sh \
        python3-six \
        python3-yaml \
        qemu-system-misc \
        ripgrep \
        rsync \
        sccache \
        universal-ctags \
        cscope \
        xz-utils && \
    rm -rf /var/lib/apt/lists/*

ARG PYFDT_VERSION=0.3

RUN curl --proto '=https' --tlsv1.2 -fsSL \
        "https://files.pythonhosted.org/packages/source/p/pyfdt/pyfdt-${PYFDT_VERSION}.tar.gz" \
        | tar -xz -C /tmp && \
    cd "/tmp/pyfdt-${PYFDT_VERSION}" && \
    python3 setup.py install --prefix=/usr/local && \
    rm -rf "/tmp/pyfdt-${PYFDT_VERSION}"

ENV RUSTUP_HOME=/opt/rust/rustup
ENV CARGO_HOME=/cargo-cache
ENV PATH=/opt/rust/cargo/bin:${PATH}

RUN curl --proto '=https' --tlsv1.2 -fsSLo /tmp/rustup-init https://sh.rustup.rs && \
    chmod +x /tmp/rustup-init && \
    CARGO_HOME=/opt/rust/cargo /tmp/rustup-init -y \
        --profile minimal \
        --default-toolchain "${RUST_TOOLCHAIN}" \
        --component clippy \
        --component rust-analyzer \
        --component rustfmt \
        --target "${RUST_TARGET}" && \
    /opt/rust/cargo/bin/rustup target add "${RUST_TASKMAN_TARGET}" \
        --toolchain "${RUST_TOOLCHAIN}" && \
    rm -f /tmp/rustup-init && \
    mkdir -p "${CARGO_HOME}" && \
    chmod -R a+rwX /opt/rust "${CARGO_HOME}"

RUN printf '%s\n' \
        'export RUSTUP_HOME=${RUSTUP_HOME:-/opt/rust/rustup}' \
        'export CARGO_HOME=${CARGO_HOME:-/cargo-cache}' \
        'export PATH=/opt/rust/cargo/bin:$PATH' \
        'if [ -n "${QSOE_SCCACHE_WRAPPER_DIR:-}" ]; then export PATH="${QSOE_SCCACHE_WRAPPER_DIR}:$PATH"; fi' \
        > /etc/profile.d/qsoe-rust.sh

WORKDIR /work/qsoe/os

CMD ["/bin/bash"]
