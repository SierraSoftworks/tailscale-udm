#!/bin/sh
set -e

VERSION="${1:-1.12.3}"
WORKDIR="$(mktemp -d || exit 1)"
trap 'rm -rf ${WORKDIR}' EXIT
TAILSCALE_TGZ="${WORKDIR}/tailscale.tgz"

echo "Installing Tailscale in /mnt/data/tailscale"
curl -o "${TAILSCALE_TGZ}" "https://pkgs.tailscale.com/stable/tailscale_${VERSION}_arm64.tgz"
tar xzf "${TAILSCALE_TGZ}" -C "${WORKDIR}"
mkdir -p /mnt/data/tailscale
cp -R "${WORKDIR}/tailscale_${VERSION}_arm64"/* /mnt/data/tailscale/

echo "Shutting down tailscaled"
/mnt/data/tailscale/tailscale down
killall tailscaled

echo "Starting tailscaled service"
/mnt/data/on_boot.d/10-tailscaled.sh

sleep 5

echo "Starting tailscale"
/mnt/data/tailscale/tailscale up
