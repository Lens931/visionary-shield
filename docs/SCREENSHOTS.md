# Screenshots and evidence capture

Visionary Shield supports two kinds of screenshots:

1. Repository screenshots used for GitHub presentation.
2. Runtime evidence screenshots requested by staff through `screenshot-basic`.

## Repository screenshots

The README uses these files:

```text
assets/screenshots/dashboard.png
assets/screenshots/inspector.png
assets/screenshots/settings.png
assets/screenshots/quick-tools.png
```

Replace them when the interface changes significantly. Keep images clean, readable and free of private player data when possible.

## Runtime screenshots

Start `screenshot-basic` before Visionary Shield:

```cfg
ensure screenshot-basic
ensure zvs-ac
```

If a screenshot webhook is configured, evidence can be uploaded. If not, the admin still receives a local NUI preview when possible.

## Troubleshooting

If screenshots do not appear:

- confirm `screenshot-basic` is started;
- confirm no resource renamed its exports;
- check server console for screenshot-related warnings;
- test without Discord upload first;
- verify that the target player is fully loaded.
