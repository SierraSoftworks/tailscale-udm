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
    WORKDIR="$(mktemp -d || exit 1)"
    trap 'rm -rf ${WORKDIR}' EXIT
    TAILSCALE_DEB="${WORKDIR}/tailscale.deb"

    echo "Downloading Tailscale ${VERSION}..."
    curl -sSLf --ipv4 -o "${TAILSCALE_DEB}" "https://pkgs.tailscale.com/stable/debian/pool/tailscale_${VERSION}_arm64.deb" || {
        echo "Failed to download Tailscale v${VERSION} from https://pkgs.tailscale.com/stable/debian/pool/tailscale_${VERSION}_arm64.deb"
        echo "Please make sure that you're using a valid version number and try again."
        exit 1
    }

    echo "Installing Tailscale ${VERSION}..."
    dpkg -i "${TAILSCALE_DEB}" || {
        echo "Failed to install Tailscale v${VERSION} from ${TAILSCALE_DEB}"
        echo "Please make sure that you're using a valid version number and try again."
        exit 1
    }

    echo "Configuring Tailscale to use userspace networking..."
    sed -i 's/FLAGS=""/FLAGS="--tun userspace-networking/"/' /etc/default/tailscaled || {
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
    dpkg -P tailscale
}