#!/bin/bash
set -euxo pipefail
cd "$(dirname "$0")"; REPO=$PWD

source ./BASE.env
source ../toolchain.env

REST="${SRPM#NetworkManager-}"
NM_VER="${REST%%-*}"
NM_REL="${REST#*-}"; NM_REL="${NM_REL%.fc*}"
DIST=".fc44.armada"   # sorts above stock .fc44 so dnf upgrades to the armada build

# Every NM subpackage the image installs must ship at one EVR: they cross-require
# each other by exact version-release.
SUBPKGS="NetworkManager NetworkManager-libnm NetworkManager-wifi NetworkManager-tui NetworkManager-cloud-setup"

mkdir -p out; rm -f out/*
podman run --rm \
    -e SRPM="${SRPM}" -e NM_VER="${NM_VER}" -e NM_REL="${NM_REL}" -e DIST="${DIST}" -e SUBPKGS="${SUBPKGS}" \
    -v "${REPO}:/work:Z" -w /work --platform linux/arm64 \
    "${BUILDER_IMAGE}" bash -euxc '
    export HOME=/tmp
    dnf -y install rpm-build rpmdevtools koji "dnf-command(builddep)" git-core
    rpmdev-setuptree
    cat >/etc/rpm/macros.armada <<EOF
%_buildhost armada-builder
%packager Armada
%vendor Armada
EOF

    cd /tmp
    koji download-build --arch=src "${SRPM}"
    rpm -i "${SRPM}.src.rpm"
    SPEC="$HOME/rpmbuild/SPECS/NetworkManager.spec"

    # Force the stock numeric release so .fc44.armada sorts just above the base
    # build, whatever release macro the spec uses.
    sed -i "s/^Release:.*/Release:        ${NM_REL}%{?dist}/" "$SPEC"
    sed -i "/^%autochangelog/d" "$SPEC"

    cp /work/patches/*.patch "$HOME/rpmbuild/SOURCES/"
    LAST=$(grep -nE "^(Patch|Source)[0-9]*:" "$SPEC" | tail -1 | cut -d: -f1)
    [ -n "$LAST" ] || { echo "ERROR: no Source/Patch line to anchor on"; exit 1; }
    sed -i "${LAST}a Patch9001:       0001-armada-keep-devices-active-on-suspend.patch" "$SPEC"

    # The patch lands only if the spec auto-applies patches; assert it so a spec
    # change cannot silently drop it (a non-matching patch fails rpmbuild itself).
    grep -qE "^[[:space:]]*%(autosetup|autopatch)" "$SPEC" \
        || { echo "ERROR: NetworkManager.spec does not auto-apply patches; adjust build.sh"; exit 1; }

    dnf -y builddep "$SPEC"
    rpmbuild -bb --define "dist ${DIST}" "$SPEC"

    for p in ${SUBPKGS}; do
        cp "$HOME"/rpmbuild/RPMS/*/"${p}-${NM_VER}-${NM_REL}${DIST}".*.rpm /work/out/
    done
'
ls -l out/
