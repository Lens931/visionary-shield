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
    local heartbeatCfg = Config.Heartbeat or {}
    if heartbeatCfg.Enabled == false then
        return
    end
    local interval = heartbeatCfg.Interval or 15000
    local tolerance = heartbeatCfg.Tolerance or (interval * 3)

    local lastHeartbeat = {}

    local function resetPlayer(src)
        lastHeartbeat[src] = GetGameTimer()
    end

    RegisterNetEvent('zvs-ac:heartbeat', function(payload)
        local src = source
        if not src then return end
        resetPlayer(src)
    end)

    AddEventHandler('playerConnecting', function()
        local src = source
        resetPlayer(src)
    end)

    AddEventHandler('zvs-ac:internal:playerDropped', function(src)
        lastHeartbeat[src] = nil
    end)

    CreateThread(function()
        while true do
            Wait(math.max(interval, 1000))
            if zVS.adminTools and type(zVS.adminTools.isDefenseEnabled) == 'function' and not zVS.adminTools.isDefenseEnabled('heartbeat') then
                goto continue
            end
            local now = GetGameTimer()
            for _, player in ipairs(GetPlayers()) do
                local src = tonumber(player)
                if src then
                    if not lastHeartbeat[src] then
                        resetPlayer(src)
                    end
                    local delta = now - (lastHeartbeat[src] or 0)
                    if delta > tolerance and not utils.isAdmin(src) then
                        logger:flag('heartbeat_timeout', src, {
                            last_heartbeat_ms = delta,
                            tolerance_ms = tolerance,
                            ping = GetPlayerPing(src),
                        })
                        lastHeartbeat[src] = now
                    end
                end
            end
            ::continue::
        end
    end)
end

if zVS and type(zVS.registerModule) == 'function' then
    return zVS.registerModule('server.modules.heartbeat', module)
end

return module
