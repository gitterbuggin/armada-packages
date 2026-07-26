#!/usr/bin/bash

set -euxo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
PACKAGE_DIR="${PWD}"

source ./BASE.env
source ../toolchain.env

SYSROOT_VERSION="${SYSROOT_VERSION:-fc44-armada}"
SYSROOT_TARBALL="fex-sysroot-${SYSROOT_VERSION}.tar.gz"

# Build and cache the FEX sysroot when it is not already available.
if [ ! -f "${SYSROOT_TARBALL}" ]; then
  podman run --rm \
    --volume "${PACKAGE_DIR}:/work:Z" \
    --workdir /work \
    --env SYSROOT_TARBALL="${SYSROOT_TARBALL}" \
    --platform linux/aarch64 \
    "${BUILDER_IMAGE}" \
    bash -euxo pipefail -c '
        dnf -y install dnf-plugins-core rpmdevtools

        bash build-fex-sysroot.sh 44
        mv fex-sysroot-fc44-*.tar.gz "${SYSROOT_TARBALL}"
    '
fi

rm -rf out
mkdir -p out

podman run --rm \
  --env COMMIT="${COMMIT}" \
  --env DATE="${DATE}" \
  --env BASE_VERSION="${BASE_VERSION}" \
  --env ARMADA_MARCH="${ARMADA_MARCH}" \
  --env SYSROOT_TARBALL="${SYSROOT_TARBALL}" \
  --volume "${PACKAGE_DIR}:/work:Z" \
  --workdir /work \
  --platform linux/aarch64 \
  "${BUILDER_IMAGE}" \
  bash -euxc '
        dnf -y install --skip-unavailable rpm-build rpmdevtools \
            dnf-plugins-core spectool cmake clang lld llvm ninja-build \
            python3 python3-setuptools systemd-rpm-macros catch-devel \
            fmt-devel libepoxy-devel SDL2-devel xxhash-devel git-core \
            cmake-rpm-macros qt6-qtdeclarative-devel \
            alsa-lib-devel libdrm-devel libglvnd-devel libX11-devel \
            libXrandr-devel openssl-devel wayland-devel zlib-devel \
            clang-devel llvm-devel
        rpmdev-setuptree
        cat >/etc/rpm/macros.armada <<EOF
%_buildhost armada-builder
%packager Armada
%vendor Armada
EOF
        cp fex-emu.spec ~/rpmbuild/SPECS/
        sed -i "/^%build$/i %global build_cflags %{build_cflags} ${ARMADA_MARCH}" ~/rpmbuild/SPECS/fex-emu.spec
        sed -i "/^%build$/i %global build_cxxflags %{build_cxxflags} ${ARMADA_MARCH}" ~/rpmbuild/SPECS/fex-emu.spec
        cp patches/*.patch ~/rpmbuild/SOURCES/
        cp toolchain_x86_32.cmake toolchain_x86_64.cmake \
           build-fex-sysroot.sh '"${SYSROOT_TARBALL}"' ~/rpmbuild/SOURCES/
        spectool -g -R --define "commit ${COMMIT}" --define "date ${DATE}" --define "base_version ${BASE_VERSION}" ~/rpmbuild/SPECS/fex-emu.spec
        rpmbuild -bb --define "commit ${COMMIT}" --define "date ${DATE}" --define "base_version ${BASE_VERSION}" ~/rpmbuild/SPECS/fex-emu.spec
        cp ~/rpmbuild/RPMS/aarch64/*.rpm /work/out/
        cp ~/rpmbuild/RPMS/noarch/*.rpm /work/out/ 2>/dev/null || true
    '

echo "built: ${PACKAGE_DIR}/out"
