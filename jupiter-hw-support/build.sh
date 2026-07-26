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
  --env PACKAGEVER="${PACKAGEVER}" \
  --env VERSION="${VERSION}" \
  "${BUILDER_IMAGE}" \
  bash -euxo pipefail -c '
    export HOME=/tmp
    dnf -y install rpm-build rpmdevtools spectool "dnf-command(builddep)"
    rpmdev-setuptree
    cat >/etc/rpm/macros.armada <<EOF
%_buildhost armada-builder
%packager Armada
%vendor Armada
EOF
    cp /work/jupiter-hw-support.spec ~/rpmbuild/SPECS/
    sed -i "s/^Version:.*/Version:        ${VERSION}/" ~/rpmbuild/SPECS/jupiter-hw-support.spec
    sed -i "s/^%global packagever .*/%global packagever ${PACKAGEVER}/" ~/rpmbuild/SPECS/jupiter-hw-support.spec
    cp /work/patches/*.patch ~/rpmbuild/SOURCES/
    cp /work/org.armada.jupiter-hw-support.policy ~/rpmbuild/SOURCES/
    cp /work/50-armada-jupiter-hw-support.rules ~/rpmbuild/SOURCES/
    spectool -g -R ~/rpmbuild/SPECS/jupiter-hw-support.spec
    dnf -y builddep ~/rpmbuild/SPECS/jupiter-hw-support.spec
    rpmbuild -bb ~/rpmbuild/SPECS/jupiter-hw-support.spec
    cp ~/rpmbuild/RPMS/noarch/armada-jupiter-hw-support-*.rpm /work/out/
'

echo "built: ${PACKAGE_DIR}/out"
