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

"${ROOT}/package/manage.sh" install; assert "Tailscale installer should run successfully"

[[ -f "${TAILSCALE_ROOT}/tailscale" ]]; assert "Tailscale should be installed"
[[ -x "${TAILSCALE_ROOT}/tailscale" ]]; assert "Tailscale should be executable"

[[ -f "${TAILSCALE_ROOT}/tailscaled" ]]; assert "Tailscaled should be installed"
[[ -x "${TAILSCALE_ROOT}/tailscaled" ]]; assert "Tailscaled should be executable"
