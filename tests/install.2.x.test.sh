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

# systemctl mock, used to ensure the installer doesn't block thinking that tailscale is running
cat > "${WORKDIR}/systemctl" <<EOF
#!/usr/bin/env bash

case "\$1" in
    "is-active")
        echo "--## systemctl is-active ##--"
        exit 1
        ;;
    "is-enabled")
        echo "--## systemctl is-enabled ##--"
        exit 1
        ;;
    "enable")
        echo "--## systemctl enable ##--"
        ;;
    "restart")
        echo "--## systemctl restart ##--"
        ;;
    *)
        echo "Unexpected command: \${1}"
        exit 1
        ;;
esac
EOF
chmod +x "${WORKDIR}/systemctl"

"${ROOT}/package/manage.sh" install; assert "Tailscale installer should run successfully"

assert_contains "$(cat "${WORKDIR}/dpkg.args")" "tailscale.deb" "The dpkg command should be called with the tailscale.deb file"
assert_contains "$(cat "${WORKDIR}/sed.args")" "--tun userspace-networking" "The defaults should be updated with userspace networking"
assert_contains "$(cat "${WORKDIR}/systemctl.args")" "enable tailscaled" "The systemd unit should be enabled"
