#!/usr/bin/env bash
set -e

ROOT="$(dirname "$(dirname "$0")")"
WORKDIR="$(mktemp -d || exit 1)"
trap 'rm -rf ${WORKDIR}' EXIT

# shellcheck source=tests/helpers.sh
. "${ROOT}/tests/helpers.sh"

export TAILSCALE_ROOT="${WORKDIR}"
export TAILSCALED_SOCK="${WORKDIR}/tailscaled.sock"
export OS_VERSION="v1"

# Setup a mock tailscale binary which responds in a predictable way
tee "${WORKDIR}/tailscale" >/dev/null <<EOF
#!/usr/bin/env bash

case "\$1" in
    "down")
        exit 0
        ;;
    "--version")
        echo "0.0.0"
        exit 0
        ;;
    *)
        echo "Unexpected command: \${1}"
        exit 1
        ;;
esac
EOF
chmod +x "${WORKDIR}/tailscale"

mock "${WORKDIR}/tailscaled" "tailscaled \$1"

touch "${TAILSCALED_SOCK}"; assert "The tailscale socket should be created"
assert_eq "$("${ROOT}/package/manage.sh" update)" "Tailscaled is running, please stop it before updating" "The update command should exit with an error when Tailscale is running"

rm "${TAILSCALED_SOCK}"; assert "The tailscale socket should be removed"
"${ROOT}/package/manage.sh" update; assert "Tailscale should be updated"