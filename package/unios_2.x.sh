#!/bin/sh
export TAILSCALE_ROOT="${TAILSCALE_ROOT:-/data/tailscale}"
export TAILSCALE="tailscale"

_tailscale_is_running() {
    systemctl is-active --quiet tailscaled
}

_tailscale_is_installed() {
    command -v tailscale >/dev/null 2>&1
}

_tailscale_start() {
    systemctl start tailscaled

    # Wait a few seconds for the daemon to start
    sleep 5

    if _tailscale_is_running; then
      echo "Tailscaled started successfully"
    else
      echo "Tailscaled failed to start"
      exit 1
    fi

    echo "Run tailscale up to configure the interface."
}

_tailscale_stop() {
    systemctl stop tailscaled
}

_tailscale_install() {
    # shellcheck source=tests/os-release
    . /etc/os-release

    # Load the tailscale-env file to discover the flags which are required to be set
    # shellcheck source=package/tailscale-env
    . "${TAILSCALE_ROOT}/tailscale-env"

    tailscale_version="${1:-$(curl -sSLq --ipv4 "https://pkgs.tailscale.com/${TAILSCALE_CHANNEL}/?mode=json" | jq -r '.Tarballs.arm64 | capture("tailscale_(?<version>[^_]+)_").version')}"

    echo "Installing latest Tailscale package repository key..."
    curl -fsSL --ipv4 "https://pkgs.tailscale.com/${TAILSCALE_CHANNEL}/${ID}/${VERSION_CODENAME}.gpg" | apt-key add -

    if [ ! -f "/etc/apt/sources.list.d/tailscale.list" ]; then
        echo "Installing Tailscale package repository..."
        curl -fsSL --ipv4 "https://pkgs.tailscale.com/${TAILSCALE_CHANNEL}/${ID}/${VERSION_CODENAME}.list" | tee /etc/apt/sources.list.d/tailscale.list
    fi

    echo "Updating package lists..."
    apt update

    echo "Installing Tailscale ${tailscale_version}..."
    apt install -y tailscale="${tailscale_version}"

    echo "Configuring Tailscale port..."
    sed -i "s/PORT=\"[^\"]*\"/PORT=\"${PORT:-41641}\"/" /etc/default/tailscaled || {
        echo "Failed to configure Tailscale port"
        echo "Check that the file /etc/default/tailscaled exists and contains the line PORT=\"${PORT:-41641}\"."
        exit 1
    }

    echo "Configuring Tailscaled startup flags..."
    sed -i "s/FLAGS=\"[^\"]*\"/FLAGS=\"--state \/data\/tailscale\/tailscaled.state ${TAILSCALED_FLAGS}\"/" /etc/default/tailscaled || {
        echo "Failed to configure Tailscaled startup flags"
        echo "Check that the file /etc/default/tailscaled exists and contains the line FLAGS=\"--state /data/tailscale/tailscale.state ${TAILSCALED_FLAGS}\"."
        exit 1
    }

    echo "Restarting Tailscale daemon to detect new configuration..."
    systemctl restart tailscaled.service || {
        echo "Failed to restart Tailscale daemon"
        echo "The daemon might not be running with userspace networking enabled, you can restart it manually using 'systemctl restart tailscaled'."
        exit 1
    }

    echo "Enabling Tailscale to start on boot..."
    systemctl enable tailscaled.service || {
        echo "Failed to enable Tailscale to start on boot"
        echo "You can enable it manually using 'systemctl enable tailscaled'."
        exit 1
    }

    if [ ! -e "/etc/systemd/system/tailscale-install.service" ]; then
        echo "Installing pre-start script to install Tailscale on firmware updates."
        ln -s "${TAILSCALE_ROOT}/tailscale-install.service" /etc/systemd/system/tailscale-install.service

        systemctl daemon-reload
        systemctl enable tailscale-install.service
    fi

    if [ ! -e "/etc/systemd/system/tailscale-install.timer" ]; then
        echo "Installing auto-update timer to ensure that Tailscale is kept installed and up to date."
        ln -s "${TAILSCALE_ROOT}/tailscale-install.timer" /etc/systemd/system/tailscale-install.timer

        systemctl daemon-reload
        systemctl enable --now tailscale-install.timer
    fi

    echo "Installation complete, run '$0 start' to start Tailscale"
}

_tailscale_uninstall() {
    apt remove -y tailscale
    rm -f /etc/apt/sources.list.d/tailscale.list || true

    systemctl disable tailscale-install.service || true
    rm -f /lib/systemd/system/tailscale-install.service || true
}
