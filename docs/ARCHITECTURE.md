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
