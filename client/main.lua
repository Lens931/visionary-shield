zVS = zVS or {}
local utils = zVS and zVS.utils
if not utils then
    local ok, mod = pcall(require, 'shared.utils')
    if not ok then
        error(('zVS-AC: unable to load shared utils (%s)'):format(mod))
    end
    utils = mod
end

local resourceName = GetCurrentResourceName()

local function banner()
    if zVS.Config.EnableDebug then
        print(('^5[%s]^7 Visionary Anti-Cheat client initialised.'):format(resourceName))
    end
end

banner()

return {
    utils = utils,
}
