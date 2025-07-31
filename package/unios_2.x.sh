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
    . "${OS_RELEASE_FILE:-/etc/os-release}"

    # Load the tailscale-env file to discover the flags which are required to be set
    # shellcheck source=package/tailscale-env
    . "${TAILSCALE_ROOT}/tailscale-env"

    tailscale_version="${1:-$(curl -sSLq --ipv4 "https://pkgs.tailscale.com/${TAILSCALE_CHANNEL}/?mode=json" | jq -r '.Tarballs.arm64 | capture("tailscale_(?<version>[^_]+)_").version')}"

    echo "Installing latest Tailscale package repository..."
    if [ "${VERSION_CODENAME}" = "stretch" ]; then
        curl -fsSL --ipv4 "https://pkgs.tailscale.com/${TAILSCALE_CHANNEL}/${ID}/${VERSION_CODENAME}.gpg" | apt-key add -
        curl -fsSL --ipv4 "https://pkgs.tailscale.com/${TAILSCALE_CHANNEL}/${ID}/${VERSION_CODENAME}.list" | tee /etc/apt/sources.list.d/tailscale.list
    else
        curl -fsSL --ipv4 "https://pkgs.tailscale.com/${TAILSCALE_CHANNEL}/${ID}/${VERSION_CODENAME}.noarmor.gpg" | tee /usr/share/keyrings/tailscale-archive-keyring.gpg > /dev/null
        curl -fsSL --ipv4 "https://pkgs.tailscale.com/${TAILSCALE_CHANNEL}/${ID}/${VERSION_CODENAME}.tailscale-keyring.list" | tee /etc/apt/sources.list.d/tailscale.list > /dev/null
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
    sed -i "s@FLAGS=\"[^\"]*\"@FLAGS=\"--state /data/tailscale/tailscaled.state ${TAILSCALED_FLAGS}\"@" /etc/default/tailscaled || {
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

    if [ ! -L "/etc/systemd/system/tailscale-install.service" ]; then
        if [ ! -e "${TAILSCALE_ROOT}/tailscale-install.service" ]; then
            rm -f /etc/systemd/system/tailscale-install.service
        fi

        echo "Installing pre-start script to install Tailscale on firmware updates."
        ln -s "${TAILSCALE_ROOT}/tailscale-install.service" /etc/systemd/system/tailscale-install.service
    fi

    if [ ! -L "/etc/systemd/system/tailscale-install.timer" ]; then
        if [ ! -e "${TAILSCALE_ROOT}/tailscale-install.timer" ]; then
            rm -f /etc/systemd/system/tailscale-install.timer
        fi

        echo "Installing auto-update timer to ensure that Tailscale is kept installed and up to date."
        ln -s "${TAILSCALE_ROOT}/tailscale-install.timer" /etc/systemd/system/tailscale-install.timer
    fi

    systemctl daemon-reload
    systemctl enable tailscale-install.service
    systemctl enable --now tailscale-install.timer

    echo "Installation complete, run '$0 start' to start Tailscale"
}

_tailscale_uninstall() {
    apt remove -y tailscale
    rm -f /etc/apt/sources.list.d/tailscale.list || true

    systemctl disable tailscale-install.service || true
    rm -f /lib/systemd/system/tailscale-install.service || true

    systemctl disable tailscale-install.timer || true
    rm -f /lib/systemd/system/tailscale-install.timer || true
    
    systemctl disable tailscale-cert-renewal.timer || true
    systemctl stop tailscale-cert-renewal.timer || true
    rm -f /lib/systemd/system/tailscale-cert-renewal.service || true
    rm -f /lib/systemd/system/tailscale-cert-renewal.timer || true
}

_tailscale_cert() {
    action="${1:-help}"
    hostname="${2:-$(hostname)}"
    cert_dir="${TAILSCALE_ROOT}/certs"
    
    case "$action" in
        generate)
            if ! _tailscale_is_running; then
                echo "Tailscale is not running. Please start Tailscale first."
                exit 1
            fi
            
            mkdir -p "$cert_dir"
            echo "Generating certificate for $hostname..."
            
            if tailscale cert --cert-file "$cert_dir/$hostname.crt" --key-file "$cert_dir/$hostname.key" "$hostname"; then
                chmod 644 "$cert_dir/$hostname.crt"
                chmod 600 "$cert_dir/$hostname.key"
                echo "Certificate generated successfully:"
                echo "  Certificate: $cert_dir/$hostname.crt"
                echo "  Private key: $cert_dir/$hostname.key"
                echo ""
                echo "Certificate expires in 90 days. Use '$0 cert renew $hostname' to renew."
                
                # Install auto-renewal timer if not already installed
                if [ ! -L "/etc/systemd/system/tailscale-cert-renewal.service" ]; then
                    if [ -f "${TAILSCALE_ROOT}/tailscale-cert-renewal.service" ] && [ -f "${TAILSCALE_ROOT}/tailscale-cert-renewal.timer" ]; then
                        echo "Installing certificate auto-renewal timer..."
                        ln -s "${TAILSCALE_ROOT}/tailscale-cert-renewal.service" /etc/systemd/system/
                        ln -s "${TAILSCALE_ROOT}/tailscale-cert-renewal.timer" /etc/systemd/system/
                        systemctl daemon-reload
                        systemctl enable tailscale-cert-renewal.timer
                        systemctl start tailscale-cert-renewal.timer
                        echo "Certificate will be automatically renewed weekly"
                    fi
                fi
            else
                echo "Failed to generate certificate. Ensure:"
                echo "  - MagicDNS is enabled in your Tailscale admin console"
                echo "  - HTTPS is enabled in your Tailscale admin console"
                echo "  - The hostname '$hostname' matches your Tailscale machine name"
                exit 1
            fi
            ;;
            
        renew)
            if ! _tailscale_is_running; then
                echo "Tailscale is not running. Please start Tailscale first."
                exit 1
            fi
            
            if [ ! -f "$cert_dir/$hostname.crt" ] || [ ! -f "$cert_dir/$hostname.key" ]; then
                echo "Certificate not found for $hostname"
                echo "Use '$0 cert generate $hostname' to create a new certificate"
                exit 1
            fi
            
            echo "Renewing certificate for $hostname..."
            
            # Backup existing certificates
            cp "$cert_dir/$hostname.crt" "$cert_dir/$hostname.crt.bak"
            cp "$cert_dir/$hostname.key" "$cert_dir/$hostname.key.bak"
            
            if tailscale cert --cert-file "$cert_dir/$hostname.crt" --key-file "$cert_dir/$hostname.key" "$hostname"; then
                chmod 644 "$cert_dir/$hostname.crt"
                chmod 600 "$cert_dir/$hostname.key"
                rm -f "$cert_dir/$hostname.crt.bak" "$cert_dir/$hostname.key.bak"
                echo "Certificate renewed successfully"
            else
                # Restore backups on failure
                mv "$cert_dir/$hostname.crt.bak" "$cert_dir/$hostname.crt"
                mv "$cert_dir/$hostname.key.bak" "$cert_dir/$hostname.key"
                echo "Failed to renew certificate"
                exit 1
            fi
            ;;
            
        list)
            if [ -d "$cert_dir" ]; then
                echo "Certificates stored in $cert_dir:"
                echo ""
                for cert in "$cert_dir"/*.crt; do
                    if [ -f "$cert" ]; then
                        basename="${cert##*/}"
                        hostname="${basename%.crt}"
                        echo "  $hostname:"
                        echo "    Certificate: $cert"
                        echo "    Private key: $cert_dir/$hostname.key"
                        if command -v openssl >/dev/null 2>&1; then
                            expiry=$(openssl x509 -enddate -noout -in "$cert" | cut -d= -f2)
                            echo "    Expires: $expiry"
                        fi
                        echo ""
                    fi
                done
                if [ ! -f "$cert_dir"/*.crt ]; then
                    echo "  No certificates found"
                fi
            else
                echo "No certificates directory found"
            fi
            ;;
            
        install-unifi)
            if [ ! -f "$cert_dir/$hostname.crt" ] || [ ! -f "$cert_dir/$hostname.key" ]; then
                echo "Certificate not found for $hostname"
                echo "Use '$0 cert generate $hostname' to create a certificate first"
                exit 1
            fi
            
            echo "Installing certificate for UniFi controller..."
            
            # Install for UniFi OS (nginx)
            if [ -d "/data/unifi-core/config" ]; then
                echo "Installing certificate for UniFi OS web interface..."
                
                # Generate a UUID for the certificate
                cert_uuid=$(cat /proc/sys/kernel/random/uuid)
                
                # Copy certificates with UUID names
                cp "$cert_dir/$hostname.crt" "/data/unifi-core/config/$cert_uuid.crt"
                cp "$cert_dir/$hostname.key" "/data/unifi-core/config/$cert_uuid.key"
                
                # Set proper permissions
                chmod 644 "/data/unifi-core/config/$cert_uuid.crt"
                chmod 600 "/data/unifi-core/config/$cert_uuid.key"
                
                # Register certificate in PostgreSQL database for persistence
                if [ -f "${TAILSCALE_ROOT}/cert-db-register.sh" ]; then
                    echo "Registering certificate in database..."
                    sh "${TAILSCALE_ROOT}/cert-db-register.sh" "$cert_uuid" "/data/unifi-core/config/$cert_uuid.crt" "/data/unifi-core/config/$cert_uuid.key" "$hostname"
                else
                    echo "Warning: Database registration script not found. Certificate may not persist across restarts."
                fi
                
                # Update nginx configuration
                cat > /data/unifi-core/config/http/local-certs.conf <<EOF
ssl_certificate     /data/unifi-core/config/$cert_uuid.crt;
ssl_certificate_key /data/unifi-core/config/$cert_uuid.key;
EOF
                
                # Update settings.yaml to activate the certificate
                if grep -q "activeCertId:" /data/unifi-core/config/settings.yaml 2>/dev/null; then
                    # Update existing activeCertId
                    sed -i "s/activeCertId: .*/activeCertId: $cert_uuid/" /data/unifi-core/config/settings.yaml
                else
                    # Add activeCertId if it doesn't exist
                    echo "activeCertId: $cert_uuid" >> /data/unifi-core/config/settings.yaml
                fi
                
                echo "UniFi OS certificate installed with ID: $cert_uuid"
                echo "Note: Restart unifi-core for the certificate to take effect:"
                echo "  systemctl restart unifi-core"
            fi
            ;;
            
        help|*)
            echo "Usage: $0 cert {generate|renew|list|install-unifi} [hostname]"
            echo ""
            echo "Commands:"
            echo "  generate [hostname]     - Generate new certificate for hostname (default: system hostname)"
            echo "  renew [hostname]        - Renew existing certificate"
            echo "  list                    - List all stored certificates"
            echo "  install-unifi [hostname] - Install certificate into UniFi controller"
            echo ""
            echo "Examples:"
            echo "  $0 cert generate"
            echo "  $0 cert generate myudm"
            echo "  $0 cert renew myudm"
            echo "  $0 cert install-unifi myudm"
            echo ""
            echo "Note: Certificates expire after 90 days and must be renewed manually."
            echo "      MagicDNS and HTTPS must be enabled in your Tailscale admin console."
            ;;
    esac
}
