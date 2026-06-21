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
local joinGraceUntil = {}
local godmodeStrikeState = {}

local function nowMs()
    return GetGameTimer()
end

function module:init()
    local cfg = Config.GodmodeProbe or {}
    if not cfg.Enabled then
        return
    end

    local interval = tonumber(cfg.Interval) or 30000
    local damage = tonumber(cfg.Damage) or 1
    local allowedRecovery = tonumber(cfg.AllowedRecovery) or 0
    local joinGraceMs = tonumber(cfg.JoinGraceMs) or 90000
    local spawnGraceMs = tonumber(cfg.SpawnGraceMs) or 45000
    local consecutiveFlags = math.max(1, tonumber(cfg.ConsecutiveFlags) or 2)
    local probeCooldownMs = tonumber(cfg.ProbeCooldownMs) or 120000

    local function markGrace(src, ms)
        src = tonumber(src)
        if not src then return end
        joinGraceUntil[src] = nowMs() + (tonumber(ms) or joinGraceMs)
        godmodeStrikeState[src] = nil
    end

    AddEventHandler('playerJoining', function()
        markGrace(source, joinGraceMs)
    end)

    AddEventHandler('playerDropped', function()
        local src = tonumber(source)
        if not src then return end
        joinGraceUntil[src] = nil
        godmodeStrikeState[src] = nil
    end)

    RegisterNetEvent('zvs-ac:godmodeClientReady', function(data)
        local grace = spawnGraceMs
        if type(data) == 'table' and tonumber(data.grace) then
            grace = tonumber(data.grace)
        end
        markGrace(source, grace)
    end)

    CreateThread(function()
        Wait(500)
        for _, player in ipairs(GetPlayers()) do
            markGrace(tonumber(player), math.min(joinGraceMs, 45000))
        end
    end)

    RegisterNetEvent('zvs-ac:godmodeResult', function(data)
        local src = tonumber(source)
        if not src then return end
        if zVS.adminTools and type(zVS.adminTools.isDefenseEnabled) == 'function' and not zVS.adminTools.isDefenseEnabled('godmode_probe') then
            return
        end
        if utils.isAdmin(src) then return end
        if type(data) ~= 'table' then return end

        local now = nowMs()
        if joinGraceUntil[src] and now < joinGraceUntil[src] then
            return
        end

        if data.skipped then
            godmodeStrikeState[src] = nil
            return
        end

        local before = tonumber(data.before)
        local after = tonumber(data.after)
        local hpPos = data.pos
        if not before or not after then return end

        local expected = math.max(0, before - (tonumber(data.damage) or damage))
        if after > expected + allowedRecovery then
            local state = godmodeStrikeState[src] or { strikes = 0, last = 0, nextLog = 0 }
            state.strikes = (state.strikes or 0) + 1
            state.last = now
            godmodeStrikeState[src] = state

            if state.strikes < consecutiveFlags then
                return
            end

            if state.nextLog and now < state.nextLog then
                return
            end
            state.nextLog = now + probeCooldownMs

            logger:flag('godmode_suspect', src, {
                hp_before = before,
                hp_after = after,
                probe_damage = tonumber(data.damage) or damage,
                expected = expected,
                allowed_recovery = allowedRecovery,
                consecutive_flags = state.strikes,
                invincible = data.invincible and true or false,
                pos = hpPos,
                reason = 'post_spawn_confirmed_probe',
            })
        else
            godmodeStrikeState[src] = nil
        end
    end)

    CreateThread(function()
        while true do
            Wait(interval)
            if zVS.adminTools and type(zVS.adminTools.isDefenseEnabled) == 'function' and not zVS.adminTools.isDefenseEnabled('godmode_probe') then
                goto continue
            end
            local players = GetPlayers()
            local now = nowMs()
            for _, player in ipairs(players) do
                local src = tonumber(player)
                if src and not utils.isAdmin(src) and not (joinGraceUntil[src] and now < joinGraceUntil[src]) then
                    TriggerClientEvent('zvs-ac:probeGodmode', src, {
                        damage = damage,
                        minimum = cfg.MinimumHealth or 140,
                        restore = cfg.RestoreHealth ~= false,
                        restore_delay = cfg.RestoreDelay or 200,
                        allowed_recovery = allowedRecovery,
                    })
                end
            end
            ::continue::
        end
    end)
end

if zVS and type(zVS.registerModule) == 'function' then
    return zVS.registerModule('server.modules.godmode', module)
end

return module
