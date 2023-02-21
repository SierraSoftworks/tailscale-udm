#!/bin/sh
set -e

OS_VERSION="${FW_VERSION:-$(ubnt-device-info firmware_detail | grep -oE '^[0-9]+')}"

if [ "$OS_VERSION" = '1' ]; then
  TAILSCALE_ROOT="/mnt/data/tailscale"
else
  TAILSCALE_ROOT="/data/tailscale"
fi

$TAILSCALE_ROOT/manage.sh on-boot