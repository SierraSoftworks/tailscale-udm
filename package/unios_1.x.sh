#!/bin/sh
export TAILSCALE_ROOT="${TAILSCALE_ROOT:-/mnt/data/tailscale}"
export TAILSCALE="${TAILSCALE_ROOT}/tailscale"
export TAILSCALED="${TAILSCALE_ROOT}/tailscaled"
export TAILSCALED_SOCK="${TAILSCALED_SOCK:-/var/run/tailscale/tailscaled.sock}"

_tailscale_is_running() {
  if [ -e "${TAILSCALED_SOCK}" ]; then
    return 0
  else
    return 1
  fi
}

_tailscale_is_installed() {
  if [ -e "${TAILSCALE}" ] && [ -e "${TAILSCALED}" ]; then
    return 0
  else
    return 1
  fi
}

_tailscale_start() {
  # shellcheck source=package/tailscale-env
  . "${TAILSCALE_ROOT}/tailscale-env"

  PORT="${PORT:-41641}"
  TAILSCALE_FLAGS="${TAILSCALE_FLAGS:-""}"
  TAILSCALED_FLAGS="${TAILSCALED_FLAGS:-"--tun userspace-networking"}"
  LOG_FILE="${TAILSCALE_ROOT}/tailscaled.log"

  if _tailscale_is_running; then
    echo "Tailscaled is already running"
  else
    echo "Starting Tailscaled..."
    $TAILSCALED --cleanup > "${LOG_FILE}" 2>&1

    # shellcheck disable=SC2086
    setsid $TAILSCALED \
      --state "${TAILSCALE_ROOT}/tailscaled.state" \
      --socket "${TAILSCALED_SOCK}" \
      --port "${PORT}" \
      ${TAILSCALED_FLAGS} >> "${LOG_FILE}" 2>&1 &

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
    timeout 5 $TAILSCALE up $TAILSCALE_FLAGS
  fi
}

_tailscale_stop() {
  $TAILSCALE down || true

  killall tailscaled 2>/dev/null || true

  $TAILSCALED --cleanup
}

_tailscale_install() {
  # Load the tailscale-env file to discover the flags which are required to be set
  # shellcheck source=package/tailscale-env
  . "${TAILSCALE_ROOT}/tailscale-env"

  VERSION="${1:-$(curl -sSLq --ipv4 "https://pkgs.tailscale.com/${TAILSCALE_CHANNEL}/?mode=json" | jq -r '.Tarballs.arm64 | capture("tailscale_(?<version>[^_]+)_").version')}"
  WORKDIR="$(mktemp -d || exit 1)"
  trap 'rm -rf ${WORKDIR}' EXIT
  TAILSCALE_TGZ="${WORKDIR}/tailscale.tgz"

  echo "Installing Tailscale v${VERSION} in ${TAILSCALE_ROOT}..."
  curl -sSLf --ipv4 -o "${TAILSCALE_TGZ}" "https://pkgs.tailscale.com/${TAILSCALE_CHANNEL}/tailscale_${VERSION}_arm64.tgz" || {
    echo "Failed to download Tailscale v${VERSION} from https://pkgs.tailscale.com/${TAILSCALE_CHANNEL}/tailscale_${VERSION}_arm64.tgz"
    echo "Please make sure that you're using a valid version number and try again."
    exit 1
  }
  
  tar xzf "${TAILSCALE_TGZ}" -C "${WORKDIR}"
  mkdir -p "${TAILSCALE_ROOT}"
  cp -R "${WORKDIR}/tailscale_${VERSION}_arm64"/* "${TAILSCALE_ROOT}"
  
  echo "Installation complete, run '$0 start' to start Tailscale"
}

_tailscale_uninstall() {
  $TAILSCALED --cleanup
  rm -rf /mnt/data/tailscale
  rm -f /mnt/data/on_boot.d/10-tailscaled.sh
}

_tailscale_cert() {
  action="${1:-help}"
  cert_dir="${TAILSCALE_ROOT}/certs"
  
  # Derive hostname from tailscale status (except for help and list commands)
  if [ "$action" != "help" ] && [ "$action" != "list" ]; then
    if ! _tailscale_is_running; then
      echo "Tailscale is not running. Please start Tailscale first."
      exit 1
    fi
    
    hostname=$($TAILSCALE status --json | jq -r '.Self.DNSName' | sed 's/\.$//')
    if [ -z "$hostname" ]; then
      echo "Failed to determine Tailscale hostname"
      exit 1
    fi
  fi
  
  case "$action" in
    generate)
      
      mkdir -p "$cert_dir"
      echo "Generating certificate for $hostname..."
      
      if $TAILSCALE cert --cert-file "$cert_dir/$hostname.crt" --key-file "$cert_dir/$hostname.key" "$hostname"; then
        chmod 644 "$cert_dir/$hostname.crt"
        chmod 600 "$cert_dir/$hostname.key"
        echo "Certificate generated successfully:"
        echo "  Certificate: $cert_dir/$hostname.crt"
        echo "  Private key: $cert_dir/$hostname.key"
        echo ""
        echo "Certificate expires in 90 days. Use '$0 cert renew' to renew."
      else
        echo "Failed to generate certificate. Ensure:"
        echo "  - MagicDNS is enabled in your Tailscale admin console"
        echo "  - HTTPS is enabled in your Tailscale admin console"
        exit 1
      fi
      ;;
      
    renew)
      if [ ! -f "$cert_dir/$hostname.crt" ] || [ ! -f "$cert_dir/$hostname.key" ]; then
        echo "Certificate not found for $hostname"
        echo "Use '$0 cert generate' to create a new certificate"
        exit 1
      fi
      
      echo "Renewing certificate for $hostname..."
      
      # Backup existing certificates
      cp "$cert_dir/$hostname.crt" "$cert_dir/$hostname.crt.bak"
      cp "$cert_dir/$hostname.key" "$cert_dir/$hostname.key.bak"
      
      if $TAILSCALE cert --cert-file "$cert_dir/$hostname.crt" --key-file "$cert_dir/$hostname.key" "$hostname"; then
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
      
    help|*)
      echo "Usage: $0 cert {generate|renew|list}"
      echo ""
      echo "Commands:"
      echo "  generate        - Generate new certificate for this device"
      echo "  renew           - Renew existing certificate"
      echo "  list            - List all stored certificates"
      echo ""
      echo "Examples:"
      echo "  $0 cert generate"
      echo "  $0 cert renew"
      echo ""
      echo "Note: Certificates expire after 90 days."
      echo "      MagicDNS and HTTPS must be enabled in your Tailscale admin console."
      echo "      Hostname is automatically determined from Tailscale status."
      ;;
  esac
}