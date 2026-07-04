# Requirements

This document is the RDD source of truth for the project.

## R0: Root Goal

- Requirement: Keep macOS proxy settings aligned with the current phone hotspot context without requiring a fixed hotspot router IP or manual proxy toggling.
- Rationale: macOS applies proxy settings per network service, while phone hotspots can change router IPs between connections.
- Failure prevented: Users should not have to leave a stale proxy enabled on normal Wi-Fi or manually edit the proxy host every time the phone hotspot changes router IP.
- Automation boundary: The utility may modify macOS proxy settings for the configured network service. It must not configure the phone, start a proxy server on the phone, or infer credentials.

## R1: Hotspot-Scoped Proxy Enablement

- Requirement: Enable macOS proxy settings only when the current default route is Wi-Fi and the Wi-Fi network matches the configured hotspot criteria.
- Rationale: macOS network services are broader than a single SSID, so the utility must avoid enabling proxy settings for unrelated networks.
- Failure prevented: Avoid routing normal Wi-Fi traffic through a phone-specific proxy configuration.
- Spec: Match the Wi-Fi interface through macOS hardware port discovery unless `WIFI_DEVICE` overrides it. Treat exact `HOTSPOT_SSIDS` matches as hotspot matches. When `STRICT_SSID=0`, allow DHCP marker matches such as `ANDROID_METERED`.
- Checks: `hotspot-proxy-toggle evaluate` reports `status=hotspot` only when the default route is the Wi-Fi device and hotspot criteria match.

## R2: Dynamic Router IP Resolution

- Requirement: Use the current Wi-Fi DHCP router IP as the proxy host instead of a fixed configured host.
- Rationale: Phone hotspot router IPs may change between connections.
- Failure prevented: Avoid stale proxy host settings after reconnecting to the same phone hotspot.
- Spec: Read `Router` from `ipconfig getsummary <wifi-device>` on each reconciliation.
- Checks: `hotspot-proxy-toggle status` includes the detected `router=<ip>` for hotspot candidates.

## R3: Endpoint-Gated Proxy State

- Requirement: Enable macOS proxy settings only when the configured proxy endpoint is actually available on the current hotspot router.
- Rationale: A hotspot may be connected while the proxy server on the phone is stopped.
- Failure prevented: Avoid enabling a broken system-wide proxy that prevents applications from reaching the network.
- Spec: With `PROXY_TYPE=socks5` and `REQUIRE_PROXY_CHECK=1`, send a SOCKS5 no-auth greeting to `router:PROXY_PORT` and require a `0500` response before enabling proxy settings.
- Checks: When the endpoint is unavailable, `run` reports `status=proxy-unavailable ... action=off` and disables the macOS proxy state.

## R4: Maintainable Automation Boundary

- Requirement: Keep the polling implementation compatible with a later event-driven network-change trigger.
- Rationale: Polling is simple and reliable for initial use, but an event-driven helper can reduce wakeups and improve reaction time later.
- Failure prevented: Avoid embedding install-time or daemon lifecycle assumptions into the runtime reconciliation logic.
- Spec: `bin/hotspot-proxy-toggle run` performs exactly one reconciliation and exits. LaunchAgent polling is configured outside the runtime command.
- Checks: LaunchAgent `ProgramArguments` call `hotspot-proxy-toggle run`; `bin/hotspot-proxy-toggle` has no persistent loop.

## R5: Public Utility Hygiene

- Requirement: Public repository files must not expose private operator state.
- Rationale: The utility is intended to be usable as a public macOS project.
- Failure prevented: Avoid leaking private Todoist IDs, Codex thread IDs, SSIDs, logs, local absolute paths, or personal runtime state.
- Spec: Public docs explain behavior and usage generically. Private planning and Todoist mapping live under `.private/`, which is ignored by Git.
- Checks: `git status --short` should not show `.private/` contents, logs, local config, or generated plist files.
