#!/bin/sh

if [[ ! -f /mnt/data/tailscale/tailscale ]]; then
  echo "Tailscale is not installed on this device."
  exit 1
fi

echo "Shutting down tailscaled"
/mnt/data/tailscale/tailscale down
killall tailscaled

echo "Remove the boot script"
rm /mnt/data/on_boot.d/10-tailscaled.sh

echo "Have tailscale cleanup after itself"
/mnt/data/tailscale/tailscaled --cleanup

echo "Remove the tailscale binaries and state"
rm -Rf /mnt/data/tailscale