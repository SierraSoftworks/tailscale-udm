#!/bin/sh
set -e

VERSION="${1:-1.12.3}"
WORKDIR="$(mktemp -d || exit 1)"
trap 'rm -rf ${WORKDIR}' EXIT
TAILSCALE_TGZ="${WORKDIR}/tailscale.tgz"

echo "Installing Tailscale in /mnt/data/tailscale"
curl -sSL -o "${TAILSCALE_TGZ}" "https://pkgs.tailscale.com/stable/tailscale_${VERSION}_arm64.tgz"
tar xzf "${TAILSCALE_TGZ}" -C "${WORKDIR}"
mkdir -p /mnt/data/tailscale
cp -R "${WORKDIR}/tailscale_${VERSION}_arm64"/* /mnt/data/tailscale/

echo "Installing Tailscale upgrade script in /mnt/data/tailscale/upgrade.sh"
curl -o /mnt/data/tailscale/upgrade.sh -sSL https://raw.githubusercontent.com/SierraSoftworks/tailscale-udm/main/upgrade.sh
chmod +x /mnt/data/tailscale/upgrade.sh

echo "Installing boot script for Tailscale"
curl -o /mnt/data/on_boot.d/10-tailscaled.sh -sSL https://raw.githubusercontent.com/SierraSoftworks/tailscale-udm/main/on_boot.d/10-tailscaled.sh
chmod +x /mnt/data/on_boot.d/10-tailscaled.sh

echo "Installing tailscale env script"
curl -o /mnt/data/tailscale/tailscale-env -sSL https://raw.githubusercontent.com/SierraSoftworks/tailscale-udm/main/tailscale-env

echo "Starting tailscaled service"
/mnt/data/on_boot.d/10-tailscaled.sh
