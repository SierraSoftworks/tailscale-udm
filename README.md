# Tailscale on Unifi Dream Machine
This repo contains the scripts necessary to install and run a [tailscale](https://tailscale.com)
instance on your [Unifi Dream Machine](https://unifi-network.ui.com/dreammachine) (UDM/UDM Pro).
It does so by piggy-backing on the excellent [boostchicken/udm-utilities](https://github.com/boostchicken/udm-utilities)
to provide a persistent service and runs using Tailscale's usermode networking feature.

## Installation
1. Follow the steps to install the boostchicken `on-boot-script` [here](https://github.com/boostchicken/udm-utilities/tree/master/on-boot-script).
2. Run the `install.sh` script to install `tailscale` and the startup script on your UDM.
   
   ```sh
   curl -L https://raw.github.com/SierraSoftworks/tailscale-udm/master/install.sh | sh
   ```
3. Follow the on-screen steps to configure `tailscale` and connect it to your network.
4. Confirm that `tailscale` is working by running `/mnt/data/tailscale/tailscale status`

## Uninstallation
1. Kill the `tailscaled` daemon.
   
   ```sh
   ps | grep tailscaled
   kill <PID>
   ```
2. Remove the boot script using `rm /mnt/data/on_boot.d/10-tailscaled.sh`
3. Have tailscale cleanup after itself using `/mnt/data/tailscale/tailscaled --cleanup`.
4. Remove the tailscale binaries and state using `rm -Rf /mnt/data/tailscale`.
