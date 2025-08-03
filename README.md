# Tailscale on Unifi Dream Machine

This repo contains the scripts necessary to install and run a [tailscale](https://tailscale.com)
instance on your [Unifi Dream Machine](https://unifi-network.ui.com/dreammachine) (UDM/UDM Pro/UDR/UDM-SE).
It does so by piggy-backing on the excellent [boostchicken/udm-utilities](https://github.com/boostchicken/udm-utilities)
to provide a persistent service and runs using Tailscale's usermode networking feature.

## Compatibility

**ⓘ You can confirm your OS version by running `/usr/bin/ubnt-device-info firmware_detail`**

This package is compatible with UniFi OS 2.x+ and is known to work on the following devices:

- UniFi Dream Machine (UDM)
- UniFi Dream Machine Pro (UDM Pro)
- UniFi Dream Router (UDR)
- UniFi Dream Machine Special Edition (UDM-SE)
- UniFi Cloud Key Gen 2 (UCK-G2)
- UniFi Cloud Key Gen 2 Plus (UCK-G2-PLUS)
- UniFi NAS Pro

We expect that it should function on most consumer-grade UniFi devices without issue, but if you
do run into any problems, please [open an issue](https://github.com/SierraSoftworks/tailscale-udm/issues)
and provide the following information:

- The device you are running on (e.g. UDM Pro)
- The UniFi OS version you are running (e.g. 2.4.8 - this can be found by running `/usr/bin/ubnt-device-info firmware_detail`)
- The steps you took to install Tailscale and any errors you encountered.

**WARNING:** This package is no longer compatible with UniFi OS 1.x (the legacy OS on UDM/UDM Pro). If you
are running UniFi OS 1.x and are unable to upgrade to the latest stable version of UniFi OS, you
should use the legacy version of this package, which is available in the `legacy` branch of
this repository. The legacy version is no longer maintained and may not work with the latest
version of Tailscale.

### Installation

1. Run the `install.sh` script to install the latest version of the
   Tailscale UDM package on your UDM.

   ```sh
   # Install the latest version of Tailscale UDM
   curl -sSLq https://raw.github.com/SierraSoftworks/tailscale-udm/main/install.sh | sh
   ```

2. Run `tailscale up` to start Tailscale.
3. Follow the on-screen steps to configure Tailscale and connect it to your network.
4. Confirm that Tailscale is working by running `tailscale status`

### Management

#### Configuring Tailscale

You can configure Tailscale using all the normal `tailscale up` options, you should be able to
find `tailscale` on your path after installation.

```sh
tailscale up --advertise-routes=10.0.0.0/24 --advertise-exit-node --advertise-tags=tag:it
```

#### Restarting Tailscale

On UniFi OS 2.x+, Tailscale is managed using `systemd` and the `tailscaled` service. You can
restart it using the following command.

```sh
systemctl restart tailscaled
```

#### Upgrading Tailscale

Upgrading Tailscale on UniFi OS 2.x+ can be done either using `apt` or by using the `manage.sh`
helper script.

##### Using `apt`

```sh
apt update && apt install -y tailscale
```

##### Using `manage.sh`

```sh
/data/tailscale/manage.sh update

# Or, if you are connected over Tailscale and want to run the update anyway
nohup /data/tailscale/manage.sh update!
```

#### Remove Tailscale

To remove Tailscale, you can run the following command, or run the steps below manually.

```sh
/data/tailscale/manage.sh uninstall
```

##### Manual Steps

1. Kill the `tailscaled` daemon with `systemctl stop tailscaled`.
2. Remove the `tailscale` package using `dpkg -P tailscale`.
3. Remove the management script and state using `rm -Rf /data/tailscale`.

## Contributing

There are clearly lots of folks who are interested in running Tailscale on their UDMs. If
you're one of those people and have an idea for how this can be improved, please create a
PR and we'll be more than happy to incorporate the changes.

## Frequently Asked Questions

### How do I advertise routes?

You do this by updating your Tailscale configuration as you would on any other machine,
just remember to provide the full path to the `tailscale` binary when doing so.

```sh
# Specify the routes you'd like to advertise using their CIDR notation

# UniFi OS 1.x
/mnt/data/tailscale/tailscale up --advertise-routes="10.0.0.0/24,192.168.0.0/24"

# UniFi OS 2.x/3.x
tailscale up --advertise-routes="10.0.0.0/24,192.168.0.0/24"
```

### Can I route traffic from machines on my local network to Tailscale endpoints automatically?

In theory, yes - however it does require manual changes to your routing rules and these will need
to be updated if you take advantage of WAN fail-over. This has been discussed in more detail on
[this GitHub discussion thread](https://github.com/SierraSoftworks/tailscale-udm/discussions/51).

*Note that we do not currently include this in `tailscale-udm` due to the risk of breaking conflicts in future.*

### Why can't I see a network interface for Tailscale?

Tailscale runs as a userspace networking component on the UDM rather than as a TUN
interface, which means you won't see it in the `ip addr` list.

### Does this support Tailscale SSH?

You bet, make sure you're running the latest version of Tailscale and then run `tailscale up --ssh`
to enable it. You'll need to setup SSH ACLs in your account by following
[this guide](https://tailscale.com/kb/1193/tailscale-ssh/).

```sh
# UniFi OS 1.x
# Update Tailscale to its latest version
/mnt/data/tailscale/manage.sh update!

# Enable SSH advertisment through Tailscale
/mnt/data/tailscale/tailscale up --ssh

# UniFi OS 2.x/3.x
# Update Tailscale to its latest version
/data/tailscale/manage.sh update!

# Enable SSH advertisment through Tailscale
tailscale up --ssh
```

### How do I generate HTTPS certificates with Tailscale?

Tailscale can generate valid HTTPS certificates for your UDM using Let's Encrypt. This requires:

- MagicDNS enabled in your Tailscale admin console
- HTTPS enabled in your Tailscale admin console

```sh
# Generate a certificate
/data/tailscale/manage.sh cert generate

# Install certificate into UniFi OS (2.x+)
/data/tailscale/manage.sh cert install-unifi

# Restart UniFi Core to apply
systemctl restart unifi-core
```

Certificates expire after 90 days. Use `cert renew` to renew them.
The hostname is automatically determined from your Tailscale configuration.

On UniFi OS 2.x+, a systemd timer is automatically installed when you generate
your first certificate. This timer runs weekly to check and renew certificates
before they expire.
