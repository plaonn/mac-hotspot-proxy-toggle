# mac-hotspot-proxy-toggle

[English](README.en.md) | [한국어](README.md)

<p>
  <img src="docs/assets/mhp-app-icon.svg" width="96" alt="Mac Hotspot Proxy Toggle app icon">
</p>

A small macOS utility that turns system proxy settings on only when the current Wi-Fi exactly matches a configured phone hotspot SSID and the proxy endpoint is available.

## Why

macOS proxy settings are scoped to a network service such as `Wi-Fi`, not to each Wi-Fi SSID. Phone hotspot router IPs can also change between connections.

Mac Hotspot Proxy Toggle reconciles the current state:

1. The default route is Wi-Fi.
2. The current Wi-Fi SSID exactly matches the configured `HOTSPOT_SSID`.
3. The proxy endpoint responds on `router:PROXY_PORT`.

If any condition does not match, Mac Hotspot Proxy Toggle disables the supported proxy backend. Current backends are `socks5` and `http`.

## Quick Install

### Homebrew

```bash
brew install plaonn/tap/hotspot-proxy-toggle
mkdir -p ~/.config
cp "$(brew --prefix)/etc/hotspot-proxy-toggle.conf.example" ~/.config/hotspot-proxy-toggle.conf
${EDITOR:-vi} ~/.config/hotspot-proxy-toggle.conf
brew services start plaonn/tap/hotspot-proxy-toggle
```

Run one reconciliation immediately:

```bash
hotspot-proxy-toggle run
```

### Source

```bash
git clone https://github.com/plaonn/mac-hotspot-proxy-toggle.git
cd mac-hotspot-proxy-toggle
PROXY_PORT=1080 HOTSPOT_SSID='My Phone Hotspot' ./install.sh
```

Source install also installs `~/Applications/MHP.app`. Launch `MHP.app`, then open `Settings...` from the menu bar to configure `Hotspot SSID`, `Proxy Type`, `Proxy Port`, `Language`, and `Start Automatically` in the GUI.

Start the menu bar icon automatically at login:

```bash
HOTSPOT_MENU_BAR=1 PROXY_PORT=1080 HOTSPOT_SSID='My Phone Hotspot' ./install.sh
```

See [docs/INSTALL.md](docs/INSTALL.md) for detailed install options.

## Configuration

Config file:

```text
~/.config/hotspot-proxy-toggle.conf
```

Core values:

```bash
PROXY_TYPE=socks5
PROXY_PORT=1080
HOTSPOT_SSID='My Phone'
REQUIRE_PROXY_CHECK=1
```

- `PROXY_TYPE=socks5`: configures the macOS SOCKS firewall proxy.
- `PROXY_TYPE=http`: configures HTTP/HTTPS Web Proxy by enabling Web Proxy and Secure Web Proxy on the same host/port.
- `HOTSPOT_SSID`: exact single phone hotspot SSID.
- `REQUIRE_PROXY_CHECK=1`: enables macOS proxy settings only when the proxy endpoint responds.

See [docs/CONFIG.md](docs/CONFIG.md) for all settings.

## Status Icons

![Mac Hotspot Proxy Toggle status icons](docs/assets/mhp-status-icons.svg)

The menu bar item is icon-only by default. It follows macOS template icon behavior, so state is expressed with alpha and knockout shapes instead of fixed colors.

| State | Meaning |
| --- | --- |
| Filled phone | Hotspot proxy is on |
| Outline phone | Non-hotspot or idle |
| Filled phone with slash | Hotspot detected, but proxy is unavailable |

See [docs/UI.md](docs/UI.md) for menu bar, `MHP.app`, notification, and Settings behavior.

## Check

```bash
hotspot-proxy-toggle status
/usr/sbin/networksetup -getsocksfirewallproxy Wi-Fi
```

Dry-run without changing macOS proxy settings:

```bash
PROXY_PORT=1080 DRY_RUN=1 ./bin/hotspot-proxy-toggle run
```

## Docs

- [docs/INSTALL.md](docs/INSTALL.md): install, LaunchAgent, source install, uninstall.
- [docs/CONFIG.md](docs/CONFIG.md): config file, backends, notifications.
- [docs/UI.md](docs/UI.md): menu bar, app icon, status icons.
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md): validation, build, release.
- [docs/SPEC.md](docs/SPEC.md): current implementation contract.
- [docs/ROADMAP.md](docs/ROADMAP.md): public future direction.

## Development

```bash
./scripts/validate.sh
```

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for the full development workflow.
