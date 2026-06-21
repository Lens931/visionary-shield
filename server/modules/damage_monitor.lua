local utils = zVS and zVS.utils
if not utils then
    local ok, mod = pcall(require, 'shared.utils')
    if not ok then
        error(('zVS-AC: unable to load shared utils (%s)'):format(mod))
    end
    utils = mod
end
zVS = zVS or {}
local Config = zVS.Config or {}

local module = {}

local cfg = nil
local damageLimit = 50
local blacklist = {}
local playerState = {}
local recentDamage = {}
local flagCooldown = 15000
local scorePerFlag = {}
local monitoring = nil

local function initConfig()
    cfg = Config.DamageMonitor or {}
    if not cfg.Enabled then
        return false
    end

    damageLimit = cfg.MaxLogEntries or damageLimit
    flagCooldown = cfg.FlagCooldown or flagCooldown

    blacklist = utils.buildLookup(cfg.BlacklistedWeapons, function(value)
        if type(value) == 'string' then
            local hash = GetHashKey(value)
            if hash and hash ~= 0 then
                return hash
            end
        end
        return tonumber(value)
    end)

    scorePerFlag = cfg.ScorePerFlag or {}
    monitoring = type(zVS.getModule) == 'function' and zVS.getModule('server.modules.monitoring') or zVS.monitoring

    return true
end

local function getState(src)
    local state = playerState[src]
    if not state then
        state = {
            shots = {},
            kills = {},
            headshots = {},
            lastFlags = {},
        }
        playerState[src] = state
    end
    return state
end

local function prune(list, now, window)
    if window <= 0 then return end
    for i = #list, 1, -1 do
        if now - list[i] > window then
            table.remove(list, i)
        end
    end
end

local function flagThrottle(state, key, now)
    local last = state.lastFlags[key] or 0
    if now - last < flagCooldown then
        return false
    end
    state.lastFlags[key] = now
    return true
end

local function pushDamageLog(entry)
    entry.id = utils.randomId('dmg-')
    entry.ts = utils.iso8601()
    table.insert(recentDamage, 1, entry)
    while #recentDamage > damageLimit do
        table.remove(recentDamage)
    end
end

local function appendFlag(entry, flag)
    entry.flags = entry.flags or {}
    entry.flags[#entry.flags + 1] = flag
end

local function buildMessage(reason, src, report)
    local attacker = GetPlayerName(src) or ('ID ' .. tostring(src))
    local target
    if report and report.target then
        target = GetPlayerName(report.target) or report.victimName
    end
    target = target or report and report.victimName or 'unknown target'
    local weapon = report and report.weapon and utils.hex(report.weapon) or 'unknown weapon'
    return ('%s suspect %s against %s (%s)'):format(attacker, reason, target, weapon)
end

local function flagPlayer(src, reason, report, extraPayload)
    local payload = utils.copyTable(extraPayload or {})
    payload.reason = reason
    if report then
        for key, value in pairs(report) do
            if payload[key] == nil then
                payload[key] = value
            end
        end
    end
    payload.attacker = GetPlayerName(src)
    payload.target = report and (report.victimName or GetPlayerName(report.target or 0))

    TriggerEvent('zvs-ac:adminTools:flag', {
        type = 'damage_' .. reason,
        src = src,
        message = buildMessage(reason, src, report),
        payload = payload,
        logType = 'damage_monitor',
        notify = cfg.NotifyOnSuspicion ~= false,
        notifyMessage = buildMessage(reason, src, report),
    })
end

local function getFlagScore(reason)
    local configured = tonumber(scorePerFlag[reason])
    if configured and configured > 0 then
        return configured
    end
    return 15
end

local function handleSuspicion(state, src, reason, report, entry)
    if not monitoring and type(zVS.getModule) == 'function' then
        monitoring = zVS.getModule('server.modules.monitoring') or zVS.monitoring
    end
    if not flagThrottle(state, reason, utils.millis()) then
        return
    end
    appendFlag(entry, reason)
    flagPlayer(src, reason, report, entry)
    if monitoring and type(monitoring.recordDetection) == 'function' then
        monitoring:recordDetection(src, reason, getFlagScore(reason), entry)
    end
end

local function onDamageReport(src, report)
    if type(report) ~= 'table' then return end
    if zVS.adminTools and type(zVS.adminTools.isDefenseEnabled) == 'function' and not zVS.adminTools.isDefenseEnabled('damage_monitor') then
        return
    end
    if cfg.IgnoreAdmins and utils.isAdmin(src) then return end

    local target = tonumber(report.target) or 0
    local now = utils.millis()
    local state = getState(src)

    prune(state.shots, now, cfg.ShotWindow or 0)
    prune(state.kills, now, cfg.KillWindow or 0)
    prune(state.headshots, now, cfg.HeadshotWindow or 0)

    state.shots[#state.shots + 1] = now

    if report.fatal then
        state.kills[#state.kills + 1] = now
    end

    if report.headshot then
        state.headshots[#state.headshots + 1] = now
    end

    local entry = {
        src = src,
        srcName = GetPlayerName(src),
        target = target,
        targetName = report.victimName or (target ~= 0 and GetPlayerName(target)) or 'Unknown',
        weapon = report.weapon,
        headshot = report.headshot or false,
        fatal = report.fatal or false,
        damage = tonumber(report.damage) or nil,
        distance = report.distance and utils.round(report.distance, 2) or nil,
        bone = report.bone,
        pos = report.pos,
    }

    if entry.damage and (cfg.MaxDamagePerHit or 0) > 0 and entry.damage >= cfg.MaxDamagePerHit then
        handleSuspicion(state, src, 'excessive_damage', report, entry)
    end

    if report.weapon and blacklist[report.weapon] then
        handleSuspicion(state, src, 'blacklisted_weapon', report, entry)
    end

    local maxShots = cfg.MaxShotsPerWindow or math.huge
    if maxShots > 0 and #state.shots >= maxShots then
        handleSuspicion(state, src, 'rapid_fire', report, entry)
    end

    local killThreshold = cfg.KillThreshold or math.huge
    if killThreshold > 0 and #state.kills >= killThreshold then
        handleSuspicion(state, src, 'kill_streak', report, entry)
    end

    local headshotThreshold = cfg.HeadshotThreshold or math.huge
    if headshotThreshold > 0 and #state.headshots >= headshotThreshold then
        handleSuspicion(state, src, 'headshot_streak', report, entry)
    end

    pushDamageLog(entry)
end

RegisterNetEvent('zvs-ac:damageReport', function(report)
    local src = source
    if not cfg or not cfg.Enabled then return end
    onDamageReport(src, report)
end)

AddEventHandler('playerDropped', function()
    playerState[source] = nil
end)

function module:init()
    if not initConfig() then
        utils.debugLog('Damage monitor disabled by configuration')
        return
    end

    zVS.damageMonitor = zVS.damageMonitor or {}
    zVS.damageMonitor.getRecentDamage = function(_, copy)
        if copy == false then
            return recentDamage
        end
        return utils.copyTable(recentDamage)
    end

    zVS.damageMonitor.pushManualFlag = function(reason, src, report, payload)
        flagPlayer(src, reason, report, payload)
    end

    utils.debugLog('Damage monitor module initialised')
end

if zVS and type(zVS.registerModule) == 'function' then
    return zVS.registerModule('server.modules.damage_monitor', module)
end

return module
