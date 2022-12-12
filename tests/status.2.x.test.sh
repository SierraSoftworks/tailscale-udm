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

mock "/usr/bin/ubnt-device-info" "1.0.0"

export PATH="${WORKDIR}:${PATH}"
mock "${WORKDIR}/tailscale" "0.0.0"

mock "${WORKDIR}/systemctl" "" 1
assert_eq "$("${ROOT}/package/manage.sh" status)" "Tailscaled is not running" "Tailscaled should be reported as not running"

mock "${WORKDIR}/systemctl" "" 0
assert_eq "$("${ROOT}/package/manage.sh" status)" "Tailscaled is running
0.0.0" "Tailscaled should be reported as running with the version number"