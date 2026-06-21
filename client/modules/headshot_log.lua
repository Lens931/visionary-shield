zVS = zVS or {}
local cfg = zVS.Config.HeadshotLog or {}

if not cfg.Enabled then
    return
end

-- Headshot logging is forwarded by damage_reporter.lua to avoid duplicating
-- another gameEventTriggered listener and to keep client resmon lower.
return true
