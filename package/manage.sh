#!/bin/sh
set -e

PACKAGE_ROOT="${TAILSCALE_ROOT:-/mnt/data/tailscale}"
OS_VERSION="${OS_VERSION:-$(grep 'VERSION_ID=' /etc/os-release | grep -oE 'v[^.]+')}"

if [ "$OS_VERSION" = 'v1' ]; then
  # shellcheck source=package/unios_1.x.sh
  . "$PACKAGE_ROOT/unios_1.x.sh"
elif [ "$OS_VERSION" = 'v2' ]; then
  # shellcheck source=package/unios_2.x.sh
  . "$PACKAGE_ROOT/unios_2.x.sh"
else
  echo "Unsupported UniFi OS version ($OS_VERSION)."
  echo "Please provide the following information to us on GitHub:"
  echo "# /etc/os-release"
  cat /etc/os-release
  exit 1
fi

tailscale_status() {
  if _tailscale_is_running; then
    echo "Tailscaled is running"
    $TAILSCALE --version
  else
    echo "Tailscaled is not running"
  fi
}

tailscale_start() {
  _tailscale_start
}

tailscale_stop() {
  echo "Stopping Tailscale..."
  _tailscale_stop
}

tailscale_install() {
  _tailscale_install "$1"
  
  echo "Installation complete, run '$0 start' to start Tailscale"
}

tailscale_uninstall() {
  echo "Removing Tailscale"
  _tailscale_uninstall
}

tailscale_has_update() {
  CURRENT_VERSION="$($TAILSCALE --version | head -n 1)"
  TARGET_VERSION="${1:-$(curl --ipv4 -sSLq 'https://pkgs.tailscale.com/stable/?mode=json' | jq -r '.Tarballs.arm64 | capture("tailscale_(?<version>[^_]+)_").version')}"
  if [ "${CURRENT_VERSION}" != "${TARGET_VERSION}" ]; then
    return 0
  else
    return 1
  fi
}

case $1 in
  "status")
    tailscale_status
    ;;
  "start")
    tailscale_start
    ;;
  "stop")
    tailscale_stop
    ;;
  "restart")
    tailscale_stop
    tailscale_start
    ;;
  "install")
    if _tailscale_is_running; then
      echo "Tailscale is already installed, if you wish to update it, run '$0 update'"
      exit 0
    fi

    tailscale_install "$2"
    ;;
  "uninstall")
    tailscale_stop
    tailscale_uninstall
    ;;
  "update")
    if tailscale_has_update "$2"; then
      if _tailscale_is_running; then
        echo "Tailscaled is running, please stop it before updating"
        exit 1
      fi

      tailscale_install "$2"
    else
      echo "Tailscale is already up to date"
    fi
    ;;
  "update!")
    if tailscale_has_update "$2"; then
      tailscale_stop
      tailscale_install "$2"
      tailscale_start
    else
      echo "Tailscale is already up to date"
    fi
    ;;
  "on-boot")
    # shellcheck source=package/tailscale-env
    . "${TAILSCALE_ROOT}/tailscale-env"

    if [ "${TAILSCALE_AUTOUPDATE}" = "true" ]; then
      tailscale_has_update && tailscale_update || echo "Not updated"
    fi

    tailscale_start
    ;;
  *)
    echo "Usage: $0 {status|start|stop|restart|install|uninstall|update}"
    exit 1
    ;;
esac
