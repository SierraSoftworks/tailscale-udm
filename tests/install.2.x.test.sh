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
mock "${WORKDIR}/apt" "--## apt mock: \$* ##--"
mock "${WORKDIR}/sed" "--## sed mock: \$* ##--"
mock "${WORKDIR}/ubnt-device-info" "2.0.0"

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
        touch "${WORKDIR}/tailscaled.enabled"
        ;;
    "restart")
        echo "--## systemctl restart ##--"
        touch "${WORKDIR}/tailscaled.restarted"
        ;;
    *)
        echo "Unexpected command: \${1}"
        exit 1
        ;;
esac
EOF
chmod +x "${WORKDIR}/systemctl"

"${ROOT}/package/manage.sh" install; assert "Tailscale installer should run successfully"

cat "${WORKDIR}/apt.args"

assert_contains "$(head -n 1 "${WORKDIR}/apt.args")" "update" "The apt command should be called to update the package list"
assert_contains "$(head -n 2 "${WORKDIR}/apt.args" | tail -n 1)" "install -y tailscale" "The apt command should be called with the command to install tailscale file"
assert_contains "$(cat "${WORKDIR}/sed.args")" "--tun userspace-networking" "The defaults should be updated with userspace networking"
[[ -f "${WORKDIR}/tailscaled.restarted" ]]; assert "tailscaled should have been restarted"
[[ -f "${WORKDIR}/tailscaled.enabled" ]]; assert "tailscaled unit should be enabled"
