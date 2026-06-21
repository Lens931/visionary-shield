# Architecture overview

This document gives contributors a high-level view of the resource.

```text
client/
  main.lua
  modules/
server/
  bootstrap.lua
  main.lua
  modules/
shared/
  config.lua
  utils.lua
ui/
  index.html
  style.css
  app.js
data/
  runtime JSON stores
```

## Design goals

- keep idle overhead low;
- prefer server-side authority for moderation decisions;
- avoid NUI polling when not required;
- keep UI state separate from saved layout state;
- avoid native browser prompts and use NUI dialogs instead.

## Notes for contributors

Keep changes small, testable, and documented. Avoid introducing permanent client threads unless they are strictly required.


## Localization flow

Localization is intentionally server-config driven:

1. Server reads `zVS.Config.Localization` from `shared/config.lua`.
2. Runtime config sends the selected locale and fallback strings to the NUI.
3. The NUI applies labels without requiring UI source edits.

This keeps translations friendly for server owners while preserving a compact frontend.
