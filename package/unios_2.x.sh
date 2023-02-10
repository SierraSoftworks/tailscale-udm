#!/bin/sh

export TAILSCALE="tailscale"

_tailscale_is_running() {
    systemctl is-active --quiet tailscaled
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
    VERSION="${1:-$(curl -sSLq --ipv4 'https://pkgs.tailscale.com/stable/?mode=json' | jq -r '.Tarballs.arm64 | capture("tailscale_(?<version>[^_]+)_").version')}"

    if [ ! -f "/etc/apt/sources.list.d/tailscale.list" ]; then
        # shellcheck source=tests/os-release
        . /etc/os-release

        echo "Installing Tailscale package repository..."
        curl -fsSL --ipv4 "https://pkgs.tailscale.com/stable/${ID}/${VERSION_CODENAME}.gpg" | sudo apt-key add -
        curl -fsSL --ipv4 "https://pkgs.tailscale.com/stable/${ID}/${VERSION_CODENAME}.list" | sudo tee /etc/apt/sources.list.d/tailscale.list
    fi

    echo "Updating package lists..."
    apt update

    echo "Installing Tailscale ${VERSION}..."
    apt install -y tailscale="${VERSION}"

    echo "Configuring Tailscale to use userspace networking..."
    sed -i 's/FLAGS=""/FLAGS="--tun userspace-networking"/' /etc/default/tailscaled || {
        echo "Failed to configure Tailscale to use userspace networking"
        echo "Check that the file /etc/default/tailscaled exists and contains the line FLAGS=\"--tun userspace-networking\"."
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
  
    echo "Installation complete, run '$0 start' to start Tailscale"
}

_tailscale_uninstall() {
    apt remove tailscale
    rm -f /etc/apt/sources.list.d/tailscale.list || true
}
