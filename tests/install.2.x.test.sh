#!/usr/bin/env bash
set -e

ROOT="$(dirname "$(dirname "$0")")"
WORKDIR="$(mktemp -d || exit 1)"
trap 'rm -rf ${WORKDIR}' EXIT

# shellcheck source=tests/helpers.sh
. "${ROOT}/tests/helpers.sh"

export PACKAGE_ROOT="${ROOT}/package"
export TAILSCALE_ROOT="${WORKDIR}"
export TAILSCALED_SOCK="${WORKDIR}/tailscaled.sock"
export OS_VERSION="v2"

export PATH="${WORKDIR}:${PATH}"
mock "${WORKDIR}/dpkg" "--## dpkg mock: \$* ##--"
mock "${WORKDIR}/sed" "--## sed mock: \$* ##--"
mock "${WORKDIR}/systemctl" "--## systemctl mock: \$* ##--"

"${ROOT}/package/manage.sh" install; assert "Tailscale installer should run successfully"

assert_eq "$(cat ${WORKDIR}/dpkg.args)" "-i ${WORKDIR}/tailscale.deb" "The dpkg command should be called with the correct arguments"
assert_contains "$(cat ${WORKDIR}/sed.args)" "--tun userspace-networking" "The defaults should be updated with userspace networking"
assert_contains "$(cat ${WORKDIR}/systemctl.args)" "enable tailscaled" "The systemd unit should be enabled"
