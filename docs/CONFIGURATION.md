# Configuration guide

Main configuration file:

```text
shared/config.lua
```

## Admin access

Add trusted staff identifiers to `AdminIdentifiers`.

```lua
AdminIdentifiers = {
    'license:...',
    'discord:...',
}
```

## Discord logging

Set `Webhook` for general logs.

```lua
Webhook = ''
```

Optional routing can be configured in the `Webhooks` table.

## Screenshot capture

Important values:

```lua
AllowScreenshots = true
ScreenshotWebhook = ''
ScreenshotEncoding = 'jpg'
ScreenshotQuality = 70
ScreenshotTimeout = 15000
```

If `ScreenshotWebhook` is empty, the resource falls back to the main webhook when available, or local admin preview when upload is not configured.

## UI

Each admin can save layout preferences. To reset only your own UI:

```text
/zvs_resetui
```

## Performance

The default profile is tuned for low idle usage. Do not enable debug mode on public production servers unless you are actively diagnosing an issue.
