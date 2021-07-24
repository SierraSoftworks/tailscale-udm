#!/bin/sh
set -e

VERSION="1.10.2"

echo "Installing Tailscale in /mnt/data/tailscale"
rm -f /tmp/tailscale.tgz
curl -o /tmp/tailscale.tgz https://pkgs.tailscale.com/stable/tailscale_${VERSION}_arm64.tgz
mkdir -p /tmp/tailscale
tar xzf /tmp/tailscale.tgz -C /tmp/tailscale
mkdir -p /mnt/data/tailscale
cp -R /tmp/tailscale/tailscale_${VERSION}_arm64/* /mnt/data/tailscale/

echo "Installing boot script for Tailscale"
curl -o /mnt/data/on_boot.d/10-tailscaled.sh -L https://raw.github.com/SierraSoftworks/tailscale-udm/master/on_boot.d/10-tailscaled.sh
chmod +x /mnt/data/on_boot.d/10-tailscaled.sh

echo "Starting tailscaled service"
/mnt/data/on_boot.d/10-tailscaled.sh
sleep 5

echo "Starting tailscale"
/mnt/data/tailscale/tailscale up
