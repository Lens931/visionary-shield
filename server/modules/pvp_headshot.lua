local utils = zVS and zVS.utils
if not utils then
    local ok, mod = pcall(require, 'shared.utils')
    if not ok then
        error(('zVS-AC: unable to load shared utils (%s)'):format(mod))
    end
    utils = mod
end
local logger = zVS and zVS.logger
if not logger then
    local ok, mod = pcall(require, 'server.utils.logger')
    if not ok then
        error(('zVS-AC: unable to load server logger (%s)'):format(mod))
    end
    logger = mod
end
zVS = zVS or {}
local Config = zVS.Config or {}

local module = {}

function module:init()
    local cfg = Config.HeadshotLog or {}
    if not cfg.Enabled then
        return
    end

    RegisterNetEvent('zvs-ac:headshotLog', function(data)
        local src = source
        if utils.isAdmin(src) then return end
        if type(data) ~= 'table' then return end
        if not data.target or not tonumber(data.target) then return end

        logger:flag('pvp_headshot', src, {
            target = tonumber(data.target),
            weapon = data.weapon,
            bone = data.bone,
            distance = utils.round(tonumber(data.distance) or 0.0, cfg.DistancePrecision or 2),
            fatal = data.fatal and true or false,
            pos = data.pos,
        })
    end)
end

if zVS and type(zVS.registerModule) == 'function' then
    return zVS.registerModule('server.modules.pvp_headshot', module)
end

return module
