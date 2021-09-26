#!/bin/sh
set -xe

# source environment variables such as PORT, TAILSCALE_FLAGS, etc.
TAILSCALE_ENV="/mnt/data/tailscale/tailscale-env"
# shellcheck source=tailscale-env
. "${TAILSCALE_ENV}"

PORT="${PORT:-41641}"
TAILSCALE_FLAGS="${TAILSCALE_FLAGS:-""}"
TAILSCALED_FLAGS="${TAILSCALED_FLAGS:-"--tun userspace-networking"}"
LOG_FILE="/mnt/data/tailscale/tailscaled.log"

## starts tailscaled
/mnt/data/tailscale/tailscaled --cleanup

# shellcheck disable=SC2086
nohup /mnt/data/tailscale/tailscaled \
    --state=/mnt/data/tailscale/tailscaled.state \
    --socket=/var/run/tailscale/tailscaled.sock \
    --port ${PORT} \
    ${TAILSCALED_FLAGS} > ${LOG_FILE} 2>&1 &

# Wait 5s for the daemon to start and then run tailscale up to configure
/bin/sh -c "sleep 5; /mnt/data/tailscale/tailscale up ${TAILSCALE_FLAGS}" &
