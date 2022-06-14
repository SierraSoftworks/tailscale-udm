#!/bin/sh
set -e

TAILSCALE_ROOT="${TAILSCALE_ROOT:-/mnt/data/tailscale}"
TAILSCALE="${TAILSCALE_ROOT}/tailscale"
TAILSCALED="${TAILSCALE_ROOT}/tailscaled"
TAILSCALED_SOCK="${TAILSCALED_SOCK:-/var/run/tailscale/tailscaled.sock}"

tailscale_start() {
  # shellcheck source=package/tailscale-env
  . "${TAILSCALE_ROOT}/tailscale-env"

  PORT="${PORT:-41641}"
  TAILSCALE_FLAGS="${TAILSCALE_FLAGS:-""}"
  TAILSCALED_FLAGS="${TAILSCALED_FLAGS:-"--tun userspace-networking"}"
  LOG_FILE="${TAILSCALE_ROOT}/tailscaled.log"

  if [ -e "${TAILSCALED_SOCK}" ]; then
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

    if [ -e "${TAILSCALED_SOCK}" ]; then
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

tailscale_stop() {
  echo "Stopping Tailscale..."
  $TAILSCALE down || true

  killall tailscaled 2>/dev/null || true

  $TAILSCALED --cleanup
}

tailscale_install() {
  VERSION="${1:-$(curl -sSLq 'https://pkgs.tailscale.com/stable/?mode=json' | jq -r '.Tarballs.arm64 | capture("tailscale_(?<version>[^_]+)_").version')}"
  WORKDIR="$(mktemp -d || exit 1)"
  trap 'rm -rf ${WORKDIR}' EXIT
  TAILSCALE_TGZ="${WORKDIR}/tailscale.tgz"

  echo "Installing Tailscale v${VERSION} in ${TAILSCALE_ROOT}..."
  curl -sSLf -o "${TAILSCALE_TGZ}" "https://pkgs.tailscale.com/stable/tailscale_${VERSION}_arm64.tgz" || {
    echo "Failed to download Tailscale v${VERSION} from https://pkgs.tailscale.com/stable/tailscale_${VERSION}_arm64.tgz"
    echo "Please make sure that you're using a valid version number and try again."
    exit 1
  }
  
  tar xzf "${TAILSCALE_TGZ}" -C "${WORKDIR}"
  mkdir -p "${TAILSCALE_ROOT}"
  cp -R "${WORKDIR}/tailscale_${VERSION}_arm64"/* "${TAILSCALE_ROOT}"
  
  echo "Installation complete, run '$0 start' to start Tailscale"
}

tailscale_uninstall() {
  echo "Removing Tailscale"
  $TAILSCALED --cleanup
  rm -rf /mnt/data/tailscale
  rm -f /mnt/data/on_boot.d/10-tailscaled.sh
}

tailscale_has_update() {
  CURRENT_VERSION="$($TAILSCALE --version | head -n 1)"
  TARGET_VERSION="${1:-$(curl -sSLq 'https://pkgs.tailscale.com/stable/?mode=json' | jq -r '.Tarballs.arm64 | capture("tailscale_(?<version>[^_]+)_").version')}"
  if [ "${CURRENT_VERSION}" != "${TARGET_VERSION}" ]; then
    return 0
  else
    return 1
  fi
}

case $1 in
  "status")
    if [ -e "${TAILSCALED_SOCK}" ]; then
      echo "Tailscaled is running"
      $TAILSCALE --version
    else
      echo "Tailscaled is not running"
    fi
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
    if [ -e "${TAILSCALE}" ]; then
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
      if [ -e "${TAILSCALED_SOCK}" ]; then
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
