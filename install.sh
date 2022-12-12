#!/bin/sh
set -e

# Determine the latest version of the Tailscale UDM package
VERSION="${1:-latest}"

if [ "${VERSION}" = "latest" ]; then
  # shellcheck disable=SC2034 # Disable incorrect unused variable warning
  PACKGE_URL="https://github.com/SierraSoftworks/tailscale-udm/releases/latest/download/tailscale-udm.tgz"
else
  PACKAGE_URL="https://github.com/SierraSoftworks/tailscale-udm/releases/download/${VERSION}/tailscale-udm.tgz"
fi

# Setup a temporary directory to download the package
WORKDIR="$(mktemp -d || exit 1)"
trap 'rm -rf ${WORKDIR}' EXIT

# Download the Tailscale-UDM package
curl -sSLf --ipv4 -o "${WORKDIR}/tailscale.tgz" "$PACKAGE_URL"

OS_VERSION="${FW_VERSION:-$(/usr/bin/ubnt-device-info firmware_detail | grep -oE '^[0-9]+')}"

if [ "$OS_VERSION" = '1' ]; then
  export PACKAGE_ROOT="/mnt/data/tailscale"
else
  export PACKAGE_ROOT="/data/tailscale"
fi

# Extract the package
tar xzf "${WORKDIR}/tailscale.tgz" -C "$(dirname -- "${PACKAGE_ROOT}")"

# Run the setup script to ensure that Tailscale is installed
# shellcheck source=package/manage.sh
"$PACKAGE_ROOT/manage.sh" install "${TAILSCALE_VERSION}"

# Start the tailscaled daemon
# shellcheck source=package/manage.sh
"$PACKAGE_ROOT/manage.sh" start
