#!/bin/sh

PORT="41641"
FLAGS="--tun userspace-networking"

## starts tailscaled

/mnt/data/tailscale/tailscaled --cleanup
nohup /mnt/data/tailscale/tailscaled \
    --state=/mnt/data/tailscale/tailscaled.state \
    --socket=/var/run/tailscale/tailscaled.sock \
    --port $PORT \
    $FLAGS > /dev/null 2>&1 &
