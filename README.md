# Tailscale on Unifi Dream Machine
This repo contains the scripts necessary to install and run a [tailscale](https://tailscale.com)
instance on your [Unifi Dream Machine](https://unifi-network.ui.com/dreammachine) (UDM/UDM Pro).
It does so by piggy-backing on the excellent [boostchicken/udm-utilities](https://github.com/boostchicken/udm-utilities)
to provide a persistent service and runs using Tailscale's usermode networking feature.

## Instructions
### Install Tailscale
1. Follow the steps to install the boostchicken `on-boot-script` [here](https://github.com/boostchicken-dev/udm-utilities/tree/master/on-boot-script).

   ⚠ Make sure that you exit the `unifi-os` shell before moving onto step 2 (or you won't be able to find the `/mnt/data` directory).
2. Run the `install.sh` script to install `tailscale` and the startup script on your UDM.
   
   ```sh
   # Install the latest version of Tailscale
   curl -sSLq https://raw.github.com/SierraSoftworks/tailscale-udm/master/install.sh | sh

   # Install a specific version of Tailscale
   curl -sSLq https://raw.github.com/SierraSoftworks/tailscale-udm/master/install.sh | TAILSCALE_VERSION=1.20.0 sh

   # Install Tailscale and start it with some custom flags
   curl -sSLq https://raw.github.com/SierraSoftworks/tailscale-udm/master/install.sh | TAILSCALE_FLAGS="--authkey XXXXXXX" sh
   ```
3. Follow the on-screen steps to configure `tailscale` and connect it to your network.
4. Confirm that `tailscale` is working by running `/mnt/data/tailscale/tailscale status`

### Upgrade Tailscale
Upgrading can be done by running the upgrade script below.

```sh
# Upgrade to the latest version of Tailscale
curl -sSLq https://raw.github.com/SierraSoftworks/tailscale-udm/master/upgrade.sh | sh

# Upgrade to a specific version of Tailscale using your local script
/mnt/data/tailscale/upgrade.sh 1.20.0
```

### Remove Tailscale
To remove Tailscale, you can run the following command, or run the steps below manually.
   
```sh
# Remove Tailscale from your UDM using the automated script
curl -sSLq https://raw.githubusercontent.com/SierraSoftworks/tailscale-udm/main/uninstall.sh | sh
```

#### Manual Steps
1. Kill the `tailscaled` daemon.
   
   ```sh
   ps | grep tailscaled
   kill <PID>
   ```
2. Remove the boot script using `rm /mnt/data/on_boot.d/10-tailscaled.sh`
3. Have tailscale cleanup after itself using `/mnt/data/tailscale/tailscaled --cleanup`.
4. Remove the tailscale binaries and state using `rm -Rf /mnt/data/tailscale`.

## Contributing
There are clearly lots of folks who are interested in running Tailscale on their UDMs. If
you're one of those people and have an idea for how this can be improved, please create a
PR and we'll be more than happy to incorporate the changes.
