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
            python3-pyelftools git-core gzip xz xxd uboot-tools findutils \
            diffutils gawk grep sed coreutils hostname tar
        SRC=/tmp/u-boot-src
        rm -rf "${SRC}"
        git init -q "${SRC}"
        git -C "${SRC}" fetch --depth 1 "${REPO_URL}" "${COMMIT}"
        git -C "${SRC}" checkout -q FETCH_HEAD
        cd "${SRC}"
        # Quiet boot: log U-Boot to serial only, not the display (vidconsole),
        # so the screen stays blank from power-on until Plymouth takes over.
        # Serial still carries the full log for debugging. default.env is the
        # compiled-in env (CONFIG_USE_DEFAULT_ENV_FILE), shared by both boards.
        sed -i -e "s/^stdout=serial,vidconsole/stdout=serial/" \
               -e "s/^stderr=serial,vidconsole/stderr=serial/" \
               board/qualcomm/default.env
        grep -q "^stdout=serial$" board/qualcomm/default.env \
            && grep -q "^stderr=serial$" board/qualcomm/default.env \
            || { echo "ERROR: default.env console sed did not match"; exit 1; }
        for board in sdm845-ayn-odin sdm845-ayn-odin-m2; do
            rm -rf .output
            make O=.output CROSS_COMPILE="${CROSS_COMPILE}" qcom_defconfig
            # Fedora 44 OpenSSL dropped the deprecated <openssl/engine.h>, which
            # U-Boot 2024.10 still includes unconditionally in its libcrypto
            # host tools (rsa-sign.c/aes-encrypt.c). We do not use FIT/verified
            # boot (ABL loads a plain boot.img), so drop TOOLS_LIBCRYPTO. It is
            # default-y and select-ed by TOOLS_KWBIMAGE (Marvell-only), so both
            # that selector and the FIT-signature options must go too, or
            # olddefconfig turns it back on.
            #
            # Also select the board DT via CONFIG_DEFAULT_DEVICE_TREE rather
            # than the deprecated DEVICE_TREE= make var: with CONFIG_OF_UPSTREAM
            # the dtb that actually gets built comes from the config, while
            # DEVICE_TREE= only changes which .dtb the final existence check
            # looks for — so mixing them builds -m2 but checks for the non-m2
            # and fails. qcom_defconfig defaults this to the -m2 board.
            # BOOTDELAY=0: no autoboot countdown / "Press power button to stop
            # autoboot" prompt — boot straight through to the ESP bootflow.
            # VIDEO_LOGO off: no U-Boot submarine logo on the framebuffer, so the
            # screen stays blank from power-on until Plymouth (video is still
            # initialized for GRUB/Plymouth's EFI handoff, just nothing drawn).
            ./scripts/config --file .output/.config \
                -d TOOLS_KWBIMAGE -d TOOLS_LIBCRYPTO \
                -d FIT_SIGNATURE -d SPL_FIT_SIGNATURE -d VPL_FIT_SIGNATURE \
                -d VIDEO_LOGO \
                --set-val BOOTDELAY 0 \
                --set-str DEFAULT_DEVICE_TREE "qcom/${board}"
            make O=.output CROSS_COMPILE="${CROSS_COMPILE}" olddefconfig
            # Fail loudly if a board/def selector re-enabled it despite the above.
            grep -q "^CONFIG_TOOLS_LIBCRYPTO=y" .output/.config \
                && { echo "ERROR: TOOLS_LIBCRYPTO still on; another Kconfig selects it"; exit 1; } || true
            make O=.output -j"$(nproc)" CROSS_COMPILE="${CROSS_COMPILE}"
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
