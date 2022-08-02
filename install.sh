#!/bin/sh
set -e

# Determine the latest version of the Tailscale UDM package
VERSION="${1:-$(curl -sSLq --ipv4 'https://api.github.com/repos/SierraSoftworks/tailscale-udm/releases' | jq -r '.[0].tag_name')}"

# Setup a temporary directory to download the package
WORKDIR="$(mktemp -d || exit 1)"
trap 'rm -rf ${WORKDIR}' EXIT

# Download the Tailscale-UDM package
curl -sSLf --ipv4 -o "${WORKDIR}/tailscale.tgz" "https://github.com/SierraSoftworks/tailscale-udm/releases/download/${VERSION}/tailscale-udm.tgz"

# Extract the package
tar xzf "${WORKDIR}/tailscale.tgz" -C "/mnt/data/"

# Run the setup script to ensure that Tailscale is installed
# shellcheck source=package/manage.sh
/mnt/data/tailscale/manage.sh install "${TAILSCALE_VERSION}"

# Start the tailscaled daemon
# shellcheck source=package/manage.sh
/mnt/data/tailscale/manage.sh start
