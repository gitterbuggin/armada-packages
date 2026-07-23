#!/bin/bash
set -euxo pipefail
cd "$(dirname "$0")"; REPO=$PWD
source ./BASE.env
source ../toolchain.env

CCACHE_DIR="${CCACHE_DIR:-${REPO}/.ccache}"; mkdir -p "${CCACHE_DIR}"
mkdir -p out; rm -f out/*

# On an aarch64 host, build in a native aarch64 container. On x86_64 (or any
# non-aarch64 host), run a NATIVE container and cross-compile with the aarch64
# toolchain instead of emulating the whole compile under qemu — the kernel is
# built for cross-compilation, so this is far faster and dodges qemu/seccomp
# ENOSYS gaps. build-kernel.sh keys off `uname -m` inside the container to pick
# native-vs-cross, so the container's arch must match the host's here.
if [[ "$(uname -m)" == "aarch64" ]]; then
    PLATFORM="linux/arm64"
    TOOLCHAIN_PKGS="gcc binutils"
else
    PLATFORM="linux/amd64"
    TOOLCHAIN_PKGS="gcc binutils gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu"
fi

podman run --rm \
    -e KERNEL_VERSION="${VERSION}" \
    -v "${REPO}:/work:Z" -w /work \
    -v "${CCACHE_DIR}:/ccache:Z" \
    -e CCACHE_DIR=/ccache -e CCACHE_MAXSIZE=2G \
    --platform "${PLATFORM}" \
    "${BUILDER_IMAGE}" bash -euxc '
        dnf -y install '"${TOOLCHAIN_PKGS}"' make bc bison flex openssl-devel \
            elfutils-libelf-devel zstd xz cpio patch curl perl-interpreter python3 \
            findutils diffutils gawk grep sed coreutils hostname gzip tar ccache
        WORK_DIR=/tmp/armada-kernel-build OUT_DIR=/work/out \
            bash scripts/build-kernel.sh
    '
