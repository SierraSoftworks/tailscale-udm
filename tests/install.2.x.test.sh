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
mock "${WORKDIR}/apt-key" "--## apt-key mock: \$* ##--"
mock "${WORKDIR}/tee" "--## tee mock: \$* ##--"
mock "${WORKDIR}/apt" "--## apt mock: \$* ##--"
mock "${WORKDIR}/sed" "--## sed mock: \$* ##--"
mock "${WORKDIR}/ln" "--## ln mock: \$* ##--"
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
        echo "--## systemctl enable \$2 ##--"
        touch "${WORKDIR}/\$2.enabled"
        ;;
    "daemon-reload")
        echo "--## systemctl daemon-reload ##--"
        touch "${WORKDIR}/systemctl.daemon-reload"
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

cp "${ROOT}/tests/os-release" "${WORKDIR}/os-release"
cp "${PACKAGE_ROOT}/tailscale-env" "${WORKDIR}/tailscale-env"

"${ROOT}/package/manage.sh" install; assert "Tailscale installer should run successfully"

cat "${WORKDIR}/apt.args"
cat "${WORKDIR}/sed.args"

assert_contains "$(head -n 1 "${WORKDIR}/apt.args")" "update" "The apt command should be called to update the package list"
assert_contains "$(head -n 2 "${WORKDIR}/apt.args" | tail -n 1)" "install -y tailscale" "The apt command should be called with the command to install tailscale file"
assert_contains "$(cat "${WORKDIR}/sed.args")" "--tun userspace-networking" "The defaults should be updated with userspace networking"
[[ -f "${WORKDIR}/tailscaled.restarted" ]]; assert "tailscaled should have been restarted"
[[ -f "${WORKDIR}/tailscaled.service.enabled" ]]; assert "tailscaled unit should be enabled"
[[ -f "${WORKDIR}/systemctl.daemon-reload" ]]; assert "systemctl should have been reloaded"
[[ -f "${WORKDIR}/tailscale-install.service.enabled" ]]; assert "tailscale-install unit should be enabled"
