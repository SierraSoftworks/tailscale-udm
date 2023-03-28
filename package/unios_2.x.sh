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

    # Run tailscale up to configure
    echo "Running tailscale up to configure interface..."
    # shellcheck disable=SC2086
    timeout 5 tailscale up
}

_tailscale_stop() {
    systemctl stop tailscaled
}

_tailscale_install() {
    tailscale_version="${1:-$(curl -sSLq --ipv4 'https://pkgs.tailscale.com/stable/?mode=json' | jq -r '.Tarballs.arm64 | capture("tailscale_(?<version>[^_]+)_").version')}"

    if [ ! -f "/etc/apt/sources.list.d/tailscale.list" ]; then
        # shellcheck source=tests/os-release
        . /etc/os-release

        echo "Installing Tailscale package repository..."
        curl -fsSL --ipv4 "https://pkgs.tailscale.com/stable/${ID}/${VERSION_CODENAME}.gpg" | apt-key add -
        curl -fsSL --ipv4 "https://pkgs.tailscale.com/stable/${ID}/${VERSION_CODENAME}.list" | tee /etc/apt/sources.list.d/tailscale.list
    fi

    echo "Updating package lists..."
    apt update

    echo "Installing Tailscale ${tailscale_version}..."
    apt install -y tailscale="${tailscale_version}"

    echo "Configuring Tailscale to use userspace networking..."
    sed -i 's/FLAGS=""/FLAGS="--state \/data\/tailscale\/tailscaled.state --tun userspace-networking"/' /etc/default/tailscaled || {
        echo "Failed to configure Tailscale to use userspace networking"
        echo "Check that the file /etc/default/tailscaled exists and contains the line FLAGS=\"--state /data/tailscale/tailscale.state --tun userspace-networking\"."
        exit 1
    }

    echo "Restarting Tailscale daemon to detect new configuration..."
    systemctl restart tailscaled || {
        echo "Failed to restart Tailscale daemon"
        echo "The daemon might not be running with userspace networking enabled, you can restart it manually using 'systemctl restart tailscaled'."
        exit 1
    }

    echo "Enabling Tailscale to start on boot..."
    systemctl enable tailscaled || {
        echo "Failed to enable Tailscale to start on boot"
        echo "You can enable it manually using 'systemctl enable tailscaled'."
        exit 1
    }

    if [ ! -f "/lib/systemd/system/tailscale-install.service" ]; then
        echo "Installing pre-start script to install Tailscale on firmware updates."
        tee /lib/systemd/system/tailscale-install.service >/dev/null <<EOF
[Unit]
Description=Ensure that Tailscale is installed on your device
Before=tailscaled.service
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
Restart=no
ExecStart=/bin/bash /data/tailscale/manage.sh install

[Install]
WantedBy=tailscaled.service
EOF

        systemctl daemon-reload
        systemctl enable tailscale-install.service
    fi

    echo "Installation complete, run '$0 start' to start Tailscale"
}

_tailscale_uninstall() {
    apt remove tailscale
    rm -f /etc/apt/sources.list.d/tailscale.list || true
}
