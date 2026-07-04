# Roadmap

This document keeps public future direction only. Active work tracking is not duplicated here.

## Near-Term

- Add a small shell-based test harness for parser and decision logic.
- Improve diagnostics for unsupported proxy types and unavailable dependencies.
- Add `shellcheck` validation once the project has a documented development setup.

## Later

- Add an event-driven macOS helper that triggers `hotspot-proxy-toggle run` on network state changes instead of relying on polling.
- Add additional proxy backends behind `PROXY_TYPE`, such as HTTP proxy or PAC configuration, if a real use case appears.
- Consider packaging options such as Homebrew formula support.

## Non-Goals

- Managing the phone-side proxy server.
- Supporting authenticated SOCKS proxies before a concrete requirement exists.
- Running a persistent shell loop.
- Storing private operator task state in public repository files.
