# Visionary Shield

<p align="center">
  <strong>Open-source FiveM/QBCore admin and defensive security toolkit.</strong><br>
  Compact NUI, moderation workflows, runtime monitoring, screenshot evidence support and staff-friendly UX.
</p>

<p align="center">
  <img alt="License" src="https://img.shields.io/badge/license-GPL--3.0--or--later-blue.svg">
  <img alt="FiveM" src="https://img.shields.io/badge/FiveM-cerulean-7f8dff.svg">
  <img alt="Lua" src="https://img.shields.io/badge/Lua-5.4-2c2d72.svg">
  <img alt="QBCore" src="https://img.shields.io/badge/QBCore-friendly-65e4ff.svg">
  <img alt="Status" src="https://img.shields.io/badge/status-in%20development-orange.svg">
</p>

> Security should not be a luxury.
>
> Visionary Shield is released openly so server owners can audit, learn, improve and deploy stronger defensive tooling without relying only on opaque black boxes.

![Visionary Shield dashboard](assets/screenshots/dashboard.png)

---

## Project status

Visionary Shield is currently in **active development and polish**.

The project is usable as a base for testing, learning and server-side experimentation, but it should still be reviewed carefully before being used on a production server. Some parts may evolve quickly, especially spectate UX, webhook localization, false-positive handling, documentation and staff workflows.

Current polish focus:

- smoother camera-only spectate;
- cleaner English/French localization;
- professional Discord webhook formatting;
- lower idle overhead;
- safer moderation workflows;
- better documentation for small server owners.

This project is not presented as a magic anti-cheat. It is a transparent defensive layer made to improve visibility, help staff react faster and give communities a cleaner base to build on.

---

## Why this project exists

Many small FiveM communities need better moderation and visibility, but security tooling is often closed, expensive, hard to audit, or uncomfortable for staff to use.

Visionary Shield exists for a simple reason: give server owners a readable and configurable base that can help them understand what is happening on their server.

The goal is not to punish automatically or create fear. The goal is to provide useful signals, evidence, moderation tools and a cleaner decision process.

---

## Ethical approach

Visionary Shield is designed around **human review first**.

Anti-cheat and moderation tools can create false positives, especially in modded servers with custom resources, teleport systems, vehicles, lobbies, revive scripts and staff tools. For that reason, this project should be used responsibly.

Recommended principles:

- do not rely on one detection alone;
- review evidence before taking action;
- avoid automatic bans unless you fully understand your configuration;
- respect player privacy and keep evidence access limited to trusted staff;
- use Discord logs as moderation support, not public shaming;
- document your rules clearly for your community;
- keep the code auditable and configurable.

This project is shared to help server owners, not to encourage abusive moderation or surveillance.

---

## Highlights

- Compact ImGui-inspired NUI for administrators
- Player inspector and floating quick tools
- Runtime-aware interface: disabled backend features are not shown as active controls
- Staff actions: inspect, spectate, goto, bring, freeze, heal, warn, kick, ban
- NUI-native moderation dialogs, no browser prompt popups
- Screenshot evidence flow using standalone `screenshot-basic`
- Per-admin UI layout, opacity, scale and text scale settings
- Config-driven localization from `shared/config.lua`
- English by default, French available through configuration
- Camera-only spectate philosophy to avoid touching the admin ped
- `/zvs_resetui` resets only the current admin UI layout
- QBCore-friendly, Lua 5.4, `fx_version 'cerulean'`

---

## Spectate philosophy

Spectate should be safe and predictable.

The intended direction is **camera-only spectate by default**:

- no forced noclip;
- no admin ped teleport;
- no collision changes;
- no freeze on the admin ped;
- no invisibility changes unless explicitly configured;
- clean camera cleanup on stop/resource restart.

The staff camera should feel free and smooth, with orbit mode as the comfortable default and POV available when reliable target camera data is available.

---

## Localization philosophy

The public project should stay clean and accessible internationally.

Recommended default:

```lua
zVS.Config.Localization.DefaultLocale = 'en'
zVS.Config.DiscordLogging.Locale = 'en' -- or 'fr' / 'auto'
```

French should remain available through config, but webhook titles, field names and staff UI text should not be hardcoded in French.

---

## Requirements

- FXServer with `cerulean` resources
- Lua 5.4 enabled
- QBCore recommended
- [`screenshot-basic`](https://github.com/citizenfx/screenshot-basic) started before this resource

---

## Quick installation

Clone the repository into your resources folder with the resource name you want to ensure:

```bash
cd resources/[security]
git clone https://github.com/Lens931/visionary-shield.git zvs-ac
```

Then in `server.cfg`:

```cfg
ensure screenshot-basic
ensure zvs-ac
```

Then edit:

```text
shared/config.lua
```

Add your staff identifiers, language and optional Discord webhooks.

```lua
zVS.Config.AdminIdentifiers = {
    'license:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
    'discord:112233445566778899',
}

zVS.Config.Localization.DefaultLocale = 'en' -- or 'fr'
zVS.Config.DiscordLogging.Locale = 'en' -- 'en', 'fr', or 'auto'
zVS.Config.Webhook = '' -- optional Discord webhook
```

---

## Admin commands

```text
/zvsadmin      Open or close the admin dashboard
/zvs_resetui   Reset only the current admin UI layout
```

---

## Documentation

- [Development status](docs/DEVELOPMENT_STATUS.md)
- [Ethical use](docs/ETHICAL_USE.md)
- [Spectate and localization polish](docs/POLISH_SPECTATE_LOCALIZATION.md)
- [Deployment guide](docs/DEPLOYMENT.md)
- [Fast local deployment](docs/FAST_DEPLOYMENT.md)
- [Configuration guide](docs/CONFIGURATION.md)
- [Localization guide](docs/LOCALIZATION.md)
- [Screenshot-basic setup](docs/SCREENSHOTS.md)
- [Troubleshooting / repair guide](docs/TROUBLESHOOTING.md)
- [Architecture overview](docs/ARCHITECTURE.md)
- [Roadmap](ROADMAP.md)
- [Security policy](SECURITY.md)
- [Contributing](CONTRIBUTING.md)

---

## Community

Stars, issues, pull requests and real server feedback help the project improve.

Useful contributions include:

- translations;
- documentation fixes;
- reproducible bug reports;
- QBCore compatibility notes;
- performance testing;
- safer false-positive handling;
- cleaner webhook formatting.

Good first contributions:

- add or improve a locale in `shared/config.lua`;
- improve installation docs for your platform;
- report UI edge cases with screenshots;
- share safe performance findings from real servers;
- help polish spectate behavior without touching the admin ped.

---

## AI-assisted development note

This project is maintained by one independent developer, with AI assistance used to structure ideas, review code, improve documentation and speed up iteration.

AI helped me pass the step of releasing this project openly, but the goal remains human: build something useful, transparent and improvable for the community.

---

## License

This project is released under **GPL-3.0-or-later**.

You may use, study, modify and redistribute it under the license terms. Contributions are welcome.

