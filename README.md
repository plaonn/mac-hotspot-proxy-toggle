# mac-hotspot-proxy-toggle

A small macOS utility that enables proxy settings only when a matching hotspot and proxy endpoint are available.

The current release supports SOCKS5 on the current hotspot router IP. The project name and configuration are intentionally proxy-generic so other macOS proxy types can be added later.

## Why

macOS proxy settings are attached to a network service such as `Wi-Fi`, not to each Wi-Fi SSID. Phone hotspots can also change their router IP between connections.

This utility reconciles that state:

1. Check whether the default route is Wi-Fi.
2. Read the current Wi-Fi router IP from DHCP state.
3. Decide whether the Wi-Fi looks like the configured phone hotspot.
4. Verify the proxy endpoint on `router:PROXY_PORT`.
5. Enable macOS proxy settings only when the endpoint is available; otherwise disable them.

## Install

```bash
git clone https://github.com/plaonn/mac-hotspot-proxy-toggle.git
cd mac-hotspot-proxy-toggle
PROXY_PORT=1080 ./install.sh
```

Optional exact SSID match:

```bash
PROXY_PORT=1080 HOTSPOT_SSIDS='My Phone Hotspot' ./install.sh
```

The installer writes:

```text
~/.local/share/hotspot-proxy-toggle/
~/.local/bin/hotspot-proxy-toggle
~/.config/hotspot-proxy-toggle.conf
~/Library/LaunchAgents/com.github.plaonn.hotspot-proxy-toggle.plist
```

The LaunchAgent runs every 60 seconds by default:

```bash
CHECK_INTERVAL_SECONDS=30 PROXY_PORT=1080 ./install.sh
```

## Check

```bash
~/.local/bin/hotspot-proxy-toggle status
/usr/sbin/networksetup -getsocksfirewallproxy Wi-Fi
```

Run one reconciliation immediately:

```bash
~/.local/bin/hotspot-proxy-toggle run
```

Dry-run without changing macOS proxy settings:

```bash
PROXY_PORT=1080 DRY_RUN=1 ./bin/hotspot-proxy-toggle run
```

## Configuration

Edit:

```text
~/.config/hotspot-proxy-toggle.conf
```

Example:

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
```

`PROXY_TYPE=socks5` is the only supported backend in the current release.

`REQUIRE_PROXY_CHECK=1` means macOS proxy settings are enabled only if the hotspot router answers a SOCKS5 no-auth greeting on `PROXY_PORT`.

## Uninstall

```bash
./uninstall.sh
```

The config file is kept intentionally:

```text
~/.config/hotspot-proxy-toggle.conf
```

## Development

Project requirements and current behavior are documented in:

- [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md)
- [docs/SPEC.md](docs/SPEC.md)
- [docs/ROADMAP.md](docs/ROADMAP.md)

Validate shell syntax:

```bash
bash -n bin/hotspot-proxy-toggle install.sh uninstall.sh
```
