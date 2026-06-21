# Visionary Shield

**Visionary Shield** is an open-source FiveM/QBCore security and admin tooling resource built around a compact NUI, staff moderation workflows, runtime telemetry, screenshot evidence support, and low-idle overhead.

> Security should not be a luxury. This project is released openly so server owners can study, improve, audit, and deploy stronger defensive tooling without relying on opaque black boxes.

![Visionary Shield dashboard](assets/screenshots/dashboard.png)

## Features

- Compact ImGui-inspired NUI for administrators
- Player inspector and floating quick tools
- Runtime-aware UI: disabled backend features are not exposed as active buttons
- Staff actions: inspect, spectate, goto, bring, freeze, heal, warn, kick, ban
- Screenshot evidence flow using standalone `screenshot-basic`
- Discord logging support
- Admin UI settings per identifier
- `/zvs_resetui` to reset only the current admin layout
- Production-oriented focus handling for NUI text input and floating panels
- QBCore-friendly, Lua 5.4, `fx_version 'cerulean'`

## Screenshots

| Dashboard | Quick Tools | Player Inspector |
|---|---|---|
| ![Dashboard](assets/screenshots/dashboard.png) | ![Quick tools](assets/screenshots/quick-tools.png) | ![Inspector](assets/screenshots/inspector.png) |

## Requirements

- FXServer with `fx_version cerulean`
- Lua 5.4 enabled
- QBCore recommended
- [`screenshot-basic`](https://github.com/citizenfx/screenshot-basic) started before this resource

## Quick installation

```cfg
ensure screenshot-basic
ensure zvs-ac
```

Then edit:

```text
shared/config.lua
```

Add your staff identifiers and optional Discord webhooks.

## Admin commands

```text
/zvsadmin      Open or close the admin dashboard
/zvs_resetui   Reset only the current admin UI layout
```

## Documentation

- [Deployment guide](docs/DEPLOYMENT.md)
- [Configuration guide](docs/CONFIGURATION.md)
- [Screenshot-basic setup](docs/SCREENSHOTS.md)
- [Troubleshooting / repair guide](docs/TROUBLESHOOTING.md)
- [Security policy](SECURITY.md)
- [Contributing](CONTRIBUTING.md)

## Philosophy

Visionary Shield is not marketed as a magic anti-cheat. It is a practical defensive layer: telemetry, moderation ergonomics, logging, evidence capture, and server-side controls designed to help staff react faster and keep communities safer.

Open source means:
- code can be audited;
- fixes can be shared;
- server owners can adapt the system responsibly;
- security knowledge does not stay locked behind a paywall.

## License

This project is released under **GPL-3.0-or-later**.

You may use, study, modify, and redistribute it under the license terms. Contributions are welcome.
