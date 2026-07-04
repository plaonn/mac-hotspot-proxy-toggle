# Project Instructions

This is a public macOS utility repository. Keep public files free of personal Todoist IDs, Codex thread IDs, private absolute paths, local router addresses, SSIDs, logs, and operator-only notes.

## Source Of Truth

- `docs/REQUIREMENTS.md`: RDD root goal, requirements, rationale, failure-prevented statements, and loop boundaries.
- `docs/SPEC.md`: current public behavior and implementation contract.
- `docs/ROADMAP.md`: public future direction and non-goals.
- `README.md`: user-facing install and usage guide.

## Implementation Rules

- Keep the runtime command a single-shot reconciler. It should inspect current network/proxy state, apply the minimal required macOS proxy change, and exit.
- Keep installation, LaunchAgent templating, and uninstall logic outside `bin/hotspot-proxy-toggle`.
- Preserve the generic proxy project naming. The current implementation may support only SOCKS5, but new proxy types should be added as explicit `PROXY_TYPE` backends.
- Do not add long-running daemons unless an event-driven helper is intentionally introduced and documented.
- Do not commit generated local config, logs, LaunchAgent outputs, or `.private/` files.

## Validation

For script-only changes, run:

```bash
bash -n bin/hotspot-proxy-toggle install.sh uninstall.sh
```

When behavior changes, also run dry-run or status checks appropriate to the host macOS environment and document any checks that could not be performed.
