#!/bin/bash
# Build tqftpserv (TFTP-over-QRTR firmware server) for SDM845 devices: the
# Odin's WLAN firmware runs on the modem DSP, which fetches wlanmdsp.mbn via
# this daemon. Direct gcc build (meson wants systemd vars; zstd-decompress.c
# conflicts with its own no-zstd header fallback — we ship uncompressed
# firmware, so build without zstd).
set -euxo pipefail
cd "$(dirname "$0")"; REPO=$PWD
source ./BASE.env
source ../toolchain.env

mkdir -p out; rm -f out/*

podman run --rm \
    -e REPO_URL="${REPO_URL}" -e COMMIT="${COMMIT}" \
    -v "${REPO}:/work:Z" -w /work \
    --platform linux/arm64 \
    "${BUILDER_IMAGE}" bash -euxc '
        dnf -y install gcc git-core qrtr-devel
        SRC=/tmp/tqftpserv-src
        rm -rf "${SRC}"
        git init -q "${SRC}"
        git -C "${SRC}" fetch --depth 1 "${REPO_URL}" "${COMMIT}"
        git -C "${SRC}" checkout -q FETCH_HEAD
        cd "${SRC}"
        SRCS=$(ls *.c | grep -v zstd)
        gcc -O2 -o /work/out/tqftpserv ${SRCS} -lqrtr
    '
ls -lh out/
