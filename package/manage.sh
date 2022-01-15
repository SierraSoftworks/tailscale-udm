#!/bin/sh
set -e

TAILSCALE_ROOT="/mnt/data/tailscale"
TAILSCALE="${TAILSCALE_ROOT}/tailscale"
TAILSCALED="${TAILSCALE_ROOT}/tailscaled"
TAILSCALED_SOCK="/var/run/tailscale/tailscaled.sock"

case $1 in
  "status")
    if [ -f "${TAILSCALED_SOCK}" ]; then
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
    if [ -f "${TAILSCALE}" ]; then
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
    CURRENT_VERSION="$($TAILSCALE --version | head -n 1)"
    TARGET_VERSION="${2:-$(curl -sSLq 'https://api.github.com/repos/tailscale/tailscale/releases' | jq -r '.[0].tag_name | capture("v(?<version>.+)").version')}"
    if [ "${CURRENT_VERSION}" = "${TARGET_VERSION}" ]; then
      echo "Already up to date"
      exit 0
    fi

    tailscale_stop
    tailscale_install "$2"
    tailscale_start  
    ;;
  "on-boot")
    # shellcheck source=tailscale-env
    . "${TAILSCALE_ROOT}/tailscale-env"

    if [ "${TAILSCALE_AUTOUPDATE}" = "true" ]; then
      tailscale_update
    fi

    tailscale_start
    ;;
  *)
    echo "Usage: $0 {status|start|stop|restart|install|uninstall|update}"
    exit 1
    ;;
esac

tailscale_start() {
  # shellcheck source=tailscale-env
  . "${TAILSCALE_ROOT}/tailscale-env"

  PORT="${PORT:-41641}"
  TAILSCALE_FLAGS="${TAILSCALE_FLAGS:-""}"
  TAILSCALED_FLAGS="${TAILSCALED_FLAGS:-"--tun userspace-networking"}"
  LOG_FILE="${TAILSCALE_ROOT}/tailscaled.log"

  if [ -f "${TAILSCALED_SOCK}" ]; then
    echo "Tailscaled is already running"
  else
    echo "Starting Tailscaled..."
    $TAILSCALED --cleanup > "${LOG_FILE}" 2>&1

    # shellcheck disable=SC2086
    nohup $TAILSCALED \
      --state "${TAILSCALE_ROOT}/tailscaled.state" \
      --socket "${TAILSCALED_SOCK}" \
      --port "${PORT}" \
      ${TAILSCALED_FLAGS} >> "${LOG_FILE}" 2>&1 &

    # Wait a few seconds for the daemon to start
    sleep 5

    if [ -f "${TAILSCALED_SOCK}" ]; then
      echo "Tailscaled started successfully"
    else
      echo "Tailscaled failed to start"
      exit 1
    fi

    # Run tailscale up to configure
    # shellcheck disable=SC2086
    $TAILSCALE up $TAILSCALE_FLAGS
  fi
}

tailscale_stop() {
  echo "Stopping Tailscale..."
  $TAILSCALE down

  killall tailscaled

  $TAILSCALED --cleanup
}

tailscale_install() {
  VERSION="${1:-$(curl -sSLq 'https://api.github.com/repos/tailscale/tailscale/releases' | jq -r '.[0].tag_name | capture("v(?<version>.+)").version')}"
  WORKDIR="$(mktemp -d || exit 1)"
  trap 'rm -rf ${WORKDIR}' EXIT
  TAILSCALE_TGZ="${WORKDIR}/tailscale.tgz"

  echo "Installing Tailscale v${VERSION} in /mnt/data/tailscale"
  curl -sSL -o "${TAILSCALE_TGZ}" "https://pkgs.tailscale.com/stable/tailscale_${VERSION}_arm64.tgz"
  tar xzf "${TAILSCALE_TGZ}" -C "${WORKDIR}"
  mkdir -p /mnt/data/tailscale
  cp -R "${WORKDIR}/tailscale_${VERSION}_arm64"/* /mnt/data/tailscale/
  
  echo "Installation complete, run '$0 start' to start Tailscale"
}

tailscale_uninstall() {
  echo "Removing Tailscale"
  $TAILSCALED --cleanup
  rm -rf /mnt/data/tailscale
  rm -f /mnt/data/on_boot.d/10-tailscaled.sh
}