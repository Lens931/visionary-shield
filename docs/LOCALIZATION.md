# Localization

Visionary Shield uses a config-driven localization layer. Server owners can translate the admin NUI from `shared/config.lua` without editing the JavaScript UI.

## Select a language

Open:

```text
shared/config.lua
```

Then set:

```lua
Localization = {
    Enabled = true,
    DefaultLocale = 'en',
    FallbackLocale = 'en',
    Locales = {
        en = { ... },
        fr = { ... },
    }
}
```

Available default locales:

- `en`
- `fr`

## Add a new language

Copy an existing locale table and rename the key:

```lua
Locales = {
    en = { ... },
    fr = { ... },
    es = {
        app = {
            players = 'jugadores',
            risk = 'riesgo',
        },
        -- Continue translating the same structure.
    }
}
```

Then set:

```lua
DefaultLocale = 'es'
```

## Fallback behavior

If a translation key is missing, the UI falls back to `FallbackLocale`. If the key is still missing, the interface uses a built-in safe label.

## Contribution tip

Translation pull requests are welcome. Please keep labels short: the UI is intentionally compact.
