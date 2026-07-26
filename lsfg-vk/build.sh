#!/usr/bin/bash

set -euxo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
PACKAGE_DIR="${PWD}"

source ./BASE.env
source ../toolchain.env

rm -rf out
mkdir -p out

podman run --rm \
  --volume "${PACKAGE_DIR}:/work:Z" \
  --workdir /work \
  --platform linux/aarch64 \
  "${BUILDER_IMAGE}" \
  bash -euxo pipefail -c '
    dnf -y install git clang cmake ninja-build vulkan-headers
    git clone https://github.com/PancakeTAS/lsfg-vk /tmp/lsfg-vk
    git -C /tmp/lsfg-vk checkout '"${COMMIT}"'
    git -C /tmp/lsfg-vk submodule update --init
    cmake \
      -S /tmp/lsfg-vk \
      -B /tmp/lsfg-vk/build \
      -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_COMPILER=clang \
      -DCMAKE_CXX_COMPILER=clang++ \
      -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF
    cmake --build /tmp/lsfg-vk/build --target lsfg-vk
    cp /tmp/lsfg-vk/build/liblsfg-vk.so /work/out/
    test "$(find /work/out -mindepth 1 -maxdepth 1 -type f -printf "%f\n")" = liblsfg-vk.so
    readelf -h /work/out/liblsfg-vk.so | grep -q "Machine:.*AArch64"
    readelf -p .comment /work/out/liblsfg-vk.so | grep -qi clang
'

echo "built: ${PACKAGE_DIR}/out"
