#!/usr/bin/env bash
set -e

ROOT="$(dirname "$(dirname "$0")")"
WORKDIR="$(mktemp -d || exit 1)"
trap 'rm -rf ${WORKDIR}' EXIT

# shellcheck source=tests/helpers.sh
. "${ROOT}/tests/helpers.sh"

export TAILSCALE_ROOT="${WORKDIR}"
export TAILSCALED_SOCK="${WORKDIR}/tailscaled.sock"

echo '#!/usr/bin/env bash' > "${WORKDIR}/tailscale"
echo 'echo "0.0.0"' >> "${WORKDIR}/tailscale"
chmod +x "${WORKDIR}/tailscale"

assert_eq "$("${ROOT}/package/manage.sh" status)" "Tailscaled is not running" "Tailscaled should be reported as not running"

touch "${TAILSCALED_SOCK}"; assert "The tailscale socket should be created"
assert_eq "$("${ROOT}/package/manage.sh" status)" "Tailscaled is running
0.0.0" "Tailscaled should be reported as running with the version number"
rm "${TAILSCALED_SOCK}"; assert "The tailscale socket should be removed"