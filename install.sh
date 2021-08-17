#!/bin/sh
set -e

VERSION="1.12.3"
WORKDIR=`mktemp -d || exit 1`
trap "rm -rf ${WORKDIR}" EXIT
TAILSCALE_TGZ="${WORKDIR}/tailscale.tgz"

echo "Installing Tailscale in /mnt/data/tailscale"
curl -sSL -o "${TAILSCALE_TGZ}" https://pkgs.tailscale.com/stable/tailscale_${VERSION}_arm64.tgz
tar xzf "${TAILSCALE_TGZ}" -C "${WORKDIR}"
mkdir -p /mnt/data/tailscale
cp -R ${WORKDIR}/tailscale_${VERSION}_arm64/* /mnt/data/tailscale/

echo "Installing boot script for Tailscale"
curl -o /mnt/data/on_boot.d/10-tailscaled.sh -sSL https://raw.githubusercontent.com/pkwarren/tailscale-udm/main/on_boot.d/10-tailscaled.sh
chmod +x /mnt/data/on_boot.d/10-tailscaled.sh

echo "Starting tailscaled service"
/mnt/data/on_boot.d/10-tailscaled.sh
sleep 5

echo "Starting tailscale"
/mnt/data/tailscale/tailscale up
