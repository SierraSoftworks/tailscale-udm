#!/bin/sh
export TAILSCALE_ROOT="${TAILSCALE_ROOT:-/mnt/data/tailscale}"
export TAILSCALE="${TAILSCALE_ROOT}/tailscale"
export TAILSCALED="${TAILSCALE_ROOT}/tailscaled"
export TAILSCALED_SOCK="${TAILSCALED_SOCK:-/var/run/tailscale/tailscaled.sock}"

# shellcheck source=package/tailscale-env
. "${TAILSCALE_ROOT}/tailscale-env"

_tailscale_is_running() {
  if [ -e "${TAILSCALED_SOCK}" ]; then
    return 0
  else
    return 1
  fi
}

_tailscale_start() {
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
  VERSION="${1:-$(curl -sSLq --ipv4 'https://pkgs.tailscale.com/stable/?mode=json' | jq -r '.Tarballs.arm64 | capture("tailscale_(?<version>[^_]+)_").version')}"
  WORKDIR="$(mktemp -d || exit 1)"
  trap 'rm -rf ${WORKDIR}' EXIT
  TAILSCALE_TGZ="${WORKDIR}/tailscale.tgz"

  echo "Installing Tailscale v${VERSION} in ${TAILSCALE_ROOT}..."
  curl -sSLf --ipv4 -o "${TAILSCALE_TGZ}" "https://pkgs.tailscale.com/stable/tailscale_${VERSION}_arm64.tgz" || {
    echo "Failed to download Tailscale v${VERSION} from https://pkgs.tailscale.com/stable/tailscale_${VERSION}_arm64.tgz"
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