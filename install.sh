#!/bin/sh

VERSION="1.8.0"

echo "Installing Tailscale in /mnt/data/tailscale"
curl -o /tmp/tailscale.tgz https://pkgs.tailscale.com/stable/tailscale_${VERSION}_arm64.tgz
mkdir -p /mnt/data/tailscale
tar xzf /tmp/tailscale.tgz -C /mnt/data/tailscale

echo "Installing boot script for Tailscale"
curl -o /mnt/data/on_boot.d/10-tailscaled.sh https://raw.github.com/SierraSoftworks/tailscale-udm/master/on_boot.d/10-tailscaled.sh
chmod +x /mnt/data/on_boot.d/10-tailscaled.sh

echo "Starting tailscaled service"
/mnt/data/on_boot.d/10-tailscaled.sh

echo "Starting tailscale"
/mnt/data/tailscale/tailscale up