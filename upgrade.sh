#!/bin/sh
set -e

VERSION="${TAILSCALE_VERSION:-$1}"
VERSION="${VERSION:-$(curl -sSLq 'https://api.github.com/repos/tailscale/tailscale/releases' | jq -r '.[0].tag_name | capture("v(?<version>.+)").version')}"
WORKDIR="$(mktemp -d || exit 1)"
trap 'rm -rf ${WORKDIR}' EXIT
TAILSCALE_TGZ="${WORKDIR}/tailscale.tgz"

echo "Installing Tailscale in /mnt/data/tailscale"
curl -sSLq -o "${TAILSCALE_TGZ}" "https://pkgs.tailscale.com/stable/tailscale_${VERSION}_arm64.tgz"
tar xzf "${TAILSCALE_TGZ}" -C "${WORKDIR}"
mkdir -p /mnt/data/tailscale

echo "Shutting down tailscaled"
/mnt/data/tailscale/tailscale down >/dev/null && echo "DONE" || echo "DONE"
killall tailscaled >/dev/null && echo "DONE" || echo "DONE"

cp -R "${WORKDIR}/tailscale_${VERSION}_arm64"/* /mnt/data/tailscale/

echo "Starting tailscaled service"
/mnt/data/on_boot.d/10-tailscaled.sh

sleep 5

echo "Starting tailscale"
/mnt/data/tailscale/tailscale up
