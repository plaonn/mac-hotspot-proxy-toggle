# Specification

This document describes current behavior. Future ideas belong in `docs/ROADMAP.md`.

## Scope

`hotspot-proxy-toggle` is a macOS utility for reconciling system proxy settings against the current phone hotspot context.

Current backend support:

- `PROXY_TYPE=socks5`

Current network service support:

- macOS `networksetup` SOCKS firewall proxy settings for one configured network service, default `Wi-Fi`.

## Runtime Command

`bin/hotspot-proxy-toggle` supports:

- `evaluate`: print hotspot detection result only.
- `status`: print hotspot detection result, optional proxy endpoint check, and current macOS SOCKS proxy state.
- `run`: perform one reconciliation and exit.

The runtime command does not install files, create LaunchAgents, or run a persistent loop.

## Configuration

Default config path:

```text
~/.config/hotspot-proxy-toggle.conf
```

Supported keys:

```bash
NETWORK_SERVICE='Wi-Fi'
WIFI_DEVICE=''
PROXY_TYPE=socks5
PROXY_PORT=1080
HOTSPOT_SSIDS=''
HOTSPOT_DHCP_MARKERS='ANDROID_METERED'
STRICT_SSID=0
REQUIRE_PROXY_CHECK=1
PROXY_CHECK_TIMEOUT=1
DRY_RUN=0
```

`PROXY_TYPE` values other than `socks5` are rejected.

## Detection

The utility:

1. Discovers the Wi-Fi device from `networksetup -listallhardwareports` unless `WIFI_DEVICE` is set.
2. Reads the default route interface from `route -n get default`.
3. Exits the hotspot path if the default interface is not the Wi-Fi device.
4. Reads DHCP summary from `ipconfig getsummary <wifi-device>`.
5. Extracts `Router` and `SSID`.
6. Matches hotspot status by exact SSID allow-list or DHCP marker, depending on config.

`STRICT_SSID=1` disables DHCP marker fallback.

## Proxy Check

When `REQUIRE_PROXY_CHECK=1`, the `socks5` backend sends this SOCKS5 no-auth greeting:

```text
05 01 00
```

It requires this response before enabling macOS proxy settings:

```text
05 00
```

This verifies that the port is a SOCKS5 no-auth proxy rather than merely an open TCP port.

## Reconciliation

`run` applies these rules:

- Not Wi-Fi, no router, or not hotspot: disable the configured network service's SOCKS proxy state.
- Hotspot candidate with unavailable proxy endpoint: disable the SOCKS proxy state.
- Hotspot candidate with available SOCKS5 endpoint: set SOCKS host to the current router IP, set port to `PROXY_PORT`, and enable SOCKS proxy state.
- If the current macOS proxy state already matches the desired state, avoid redundant `networksetup` writes where practical.

## Installation

`install.sh` installs:

```text
~/.local/share/hotspot-proxy-toggle/
~/.local/bin/hotspot-proxy-toggle
~/.config/hotspot-proxy-toggle.conf
~/Library/LaunchAgents/com.github.plaonn.hotspot-proxy-toggle.plist
```

The LaunchAgent calls:

```text
hotspot-proxy-toggle run
```

The default polling interval is 60 seconds.

## Uninstall

`uninstall.sh` unloads the LaunchAgent, removes the installed binary tree and command symlink, and keeps the config file.
