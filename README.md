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
   curl -sSL https://raw.github.com/SierraSoftworks/tailscale-udm/master/install.sh | TAILSCALE_VERSION=1.18.2 sh
   ```
3. Follow the on-screen steps to configure `tailscale` and connect it to your network.
4. Confirm that `tailscale` is working by running `/mnt/data/tailscale/tailscale status`

### Upgrade Tailscale
Upgrading can be done by running the upgrade script below (replace `1.12.3` with the version you want to upgrade to).

```sh
/mnt/data/tailscale/upgrade.sh 1.12.3
```

### Remove Tailscale
To remove Tailscale, you can run the following command, or run the steps below manually.
   
```sh
curl -sSL https://raw.githubusercontent.com/SierraSoftworks/tailscale-udm/main/uninstall.sh | sh
```

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
