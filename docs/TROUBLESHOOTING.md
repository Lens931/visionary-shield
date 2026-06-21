# Troubleshooting / repair guide

## UI is off-screen or broken

Use:

```text
/zvs_resetui
```

This resets only your admin UI layout.

## Dashboard bind opens but does not close

Check for other resources using the same keybind. You can rebind it in FiveM key settings.

## Typing in NUI opens chat or phone

Make sure you are running the latest version. The current build guards NUI text input and releases focus when the dashboard is closed.

## Screenshot capture does not work

See [Screenshot-basic setup](SCREENSHOTS.md).

## Logs do not appear in Discord

Check `Webhook` in `shared/config.lua`. Do not leave placeholder values.

## NoClip issues on custom maps

NoClip is sensitive to streaming/collision on heavily modified map stacks. Test on your production map set before giving it to all staff.
