# Deployment guide

## 1. Download

Clone the repository or copy the `zvs-ac` folder into your FiveM resources directory.

Recommended path:

```text
resources/[security]/zvs-ac
```

## 2. Dependencies

Start `screenshot-basic` before Visionary Shield:

```cfg
ensure screenshot-basic
ensure zvs-ac
```

`screenshot-basic` is required for capture/evidence features.

## 3. Configure admins

Open:

```text
shared/config.lua
```

Set your trusted staff identifiers:

```lua
AdminIdentifiers = {
    'license:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
    'discord:112233445566778899',
}
```

Use identifiers returned by FiveM, not display names.

## 4. Configure logging

Set a Discord webhook if you want remote logs:

```lua
Webhook = 'https://discord.com/api/webhooks/...'
```

For public repositories, never commit real webhook URLs.

## 5. Start the resource

Restart the server or run:

```text
refresh
ensure screenshot-basic
ensure zvs-ac
```

## 6. First validation

In game, as an authorized admin:

```text
/zvsadmin
```

Then test:

- dashboard open/close bind
- player list refresh
- player inspector
- quick tools
- warn modal
- screenshot capture
- `/zvs_resetui`

## 7. Production notes

- Keep webhooks private.
- Keep admin identifiers minimal.
- Test on a staging server before production.
- Do not rely on a single anti-cheat layer.
- Review changes before pulling updates.
