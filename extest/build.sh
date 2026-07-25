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
    dnf -y install git cargo rust gcc
    git clone https://github.com/Supreeeme/extest /tmp/extest
    git -C /tmp/extest checkout '"${COMMIT}"'
    # upstream forces x86
    rm -f /tmp/extest/.cargo/config.toml
    ( cd /tmp/extest && cargo build --release )
    cp /tmp/extest/target/release/libextest.so /work/out/
'

echo "built: ${PACKAGE_DIR}/out"
