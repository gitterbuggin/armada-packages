#!/bin/bash
# Build U-Boot for the AYN Odin (SDM845) and wrap it as ABL-bootable Android
# boot images: out/uboot-ayn-odin.img (Odin / Odin Pro) and
# out/uboot-ayn-odin-m2.img (Odin M2). These get flashed to the inactive
# Android boot slot (see armada's Odin install docs); U-Boot then provides
# UEFI and loads Armada's ESP from the SD card.
#
# Recipe from https://sigmaris.info/blog/2025/01/ayn-odin-u-boot/
set -euxo pipefail
cd "$(dirname "$0")"; REPO=$PWD
source ./BASE.env
source ../toolchain.env

mkdir -p out; rm -f out/*

# Match the kernel package: aarch64 host builds natively; other hosts (x86_64)
# run a native container and cross-compile with the aarch64 toolchain rather
# than emulating the whole U-Boot build under qemu.
if [[ "$(uname -m)" == "aarch64" ]]; then
    PLATFORM="linux/arm64"
    TOOLCHAIN_PKGS="gcc binutils"
    CROSS=""
else
    PLATFORM="linux/amd64"
    TOOLCHAIN_PKGS="gcc binutils gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu"
    CROSS="aarch64-linux-gnu-"
fi

podman run --rm \
    -e REPO_URL="${REPO_URL}" -e COMMIT="${COMMIT}" -e VERSION="${VERSION}" \
    -e CROSS_COMPILE="${CROSS}" \
    -v "${REPO}:/work:Z" -w /work \
    --platform "${PLATFORM}" \
    "${BUILDER_IMAGE}" bash -euxc '
        dnf -y install '"${TOOLCHAIN_PKGS}"' make bc bison flex openssl-devel \
            gnutls-devel dtc swig python3-devel python3-setuptools \
            python3-pyelftools git-core gzip xz uboot-tools findutils \
            diffutils gawk grep sed coreutils hostname tar
        SRC=/tmp/u-boot-src
        rm -rf "${SRC}"
        git init -q "${SRC}"
        git -C "${SRC}" fetch --depth 1 "${REPO_URL}" "${COMMIT}"
        git -C "${SRC}" checkout -q FETCH_HEAD
        cd "${SRC}"
        for board in sdm845-ayn-odin sdm845-ayn-odin-m2; do
            rm -rf .output
            make O=.output CROSS_COMPILE="${CROSS_COMPILE}" qcom_defconfig
            make O=.output -j"$(nproc)" CROSS_COMPILE="${CROSS_COMPILE}" DEVICE_TREE="qcom/${board}"
            gzip -c .output/u-boot-nodtb.bin > .output/u-boot-nodtb.bin.gz
            cat .output/u-boot-nodtb.bin.gz \
                ".output/dts/upstream/src/arm64/qcom/${board}.dtb" \
                > ".output/uboot-with-dtb-${board}"
            python3 /work/vendor/mkbootimg/mkbootimg.py \
                --kernel_offset 0x00008000 --pagesize 4096 \
                --kernel ".output/uboot-with-dtb-${board}" \
                -o "/work/out/uboot-ayn-${board#sdm845-ayn-}.img"
        done
        printf "%s\n" "u-boot ${VERSION} (${COMMIT})" > /work/out/VERSION
    '

(
    cd out
    sha256sum uboot-ayn-odin.img uboot-ayn-odin-m2.img > SHA256SUMS
)
ls -lh out/
