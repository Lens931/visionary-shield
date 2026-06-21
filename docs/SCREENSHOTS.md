# Screenshot-basic setup

Visionary Shield uses the standalone `screenshot-basic` resource for capture and evidence workflows.

## Install

Place `screenshot-basic` in your resources folder and start it before `zvs-ac`.

```cfg
ensure screenshot-basic
ensure zvs-ac
```

## Validate

From the admin dashboard, select a player and press **Capture**.

Expected result:

- if a screenshot webhook is configured, the capture is uploaded;
- if no upload route is configured, the capture is shown in the admin NUI preview when available;
- if `screenshot-basic` is missing or stopped, the admin receives a clear error.

## Common issues

### Capture unavailable

Check:

```text
ensure screenshot-basic
```

Make sure the resource is not renamed.

### Upload fails

Check:

- webhook URL
- Discord rate limits
- server outbound network access
- image size / quality settings

### Blank image

Try lowering quality or switching encoding in `shared/config.lua`.
