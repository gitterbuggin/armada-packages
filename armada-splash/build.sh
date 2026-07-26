#!/usr/bin/bash

set -euxo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
PACKAGE_DIR="${PWD}"

source ../toolchain.env

rm -rf out
mkdir -p out

podman run --rm \
  --volume "${PACKAGE_DIR}:/work:Z" \
  --workdir /work \
  --platform linux/aarch64 \
  "${BUILDER_IMAGE}" \
  bash -euxo pipefail -c '
    dnf -y install gcc libX11-devel

    # stb_truetype in its own TU (third-party; warnings suppressed).
    gcc -O2 -w -c stb_impl.c -o stb_impl.o

    gcc -O2 -Wall -Wextra -DHAVE_X11 -o out/armada-splash \
        armada-splash.c stb_impl.o $(pkg-config --cflags --libs x11) -lm

    strip out/armada-splash
    rm -f stb_impl.o
  '

echo "built: ${PACKAGE_DIR}/out"
