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

export PATH="${WORKDIR}:${PATH}"
mock "${WORKDIR}/ubnt-device-info" "1.0.0"

assert_eq "$("${ROOT}/package/manage.sh" status)" "Tailscale is not installed" "Tailscaled should be reported as not installed"

mock "${WORKDIR}/tailscale" "0.0.0"
mock "${WORKDIR}/tailscaled" "0.0.0"
assert_eq "$("${ROOT}/package/manage.sh" status)" "Tailscaled is not running" "Tailscaled should be reported as not running"

touch "${TAILSCALED_SOCK}"; assert "The tailscale socket should be created"
assert_eq "$("${ROOT}/package/manage.sh" status)" "Tailscaled is running
0.0.0" "Tailscaled should be reported as running with the version number"
rm "${TAILSCALED_SOCK}"; assert "The tailscale socket should be removed"