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
local started = false
local playerRisk = {}

local function scoreEntry(src)
    local entry = playerRisk[src]
    if entry then
        return entry
    end
    entry = { score = 0, detections = 0, lastReason = nil, lastUpdate = utils.millis(), lastWebhook = 0 }
    playerRisk[src] = entry
    return entry
end

local function decayScore(entry, cfg, now)
    local decayMs = math.max(1000, tonumber(cfg.ScoreDecayMs) or 120000)
    local elapsed = math.max(0, now - (entry.lastUpdate or now))
    if elapsed <= 0 or entry.score <= 0 then
        entry.lastUpdate = now
        return
    end
    local decayRatio = math.min(1.0, elapsed / decayMs)
    entry.score = math.max(0, entry.score - (100 * decayRatio))
    entry.lastUpdate = now
end

local function getRiskList(limit)
    local rows = {}
    for src, entry in pairs(playerRisk) do
        if entry.score > 0 then
            rows[#rows + 1] = {
                src = src,
                player_name = GetPlayerName(src) or ('ID ' .. tostring(src)),
                score = utils.round(entry.score, 1),
                detections = entry.detections or 0,
                reason = entry.lastReason or 'unknown',
            }
        end
    end
    table.sort(rows, function(a, b)
        if a.score == b.score then
            return a.src < b.src
        end
        return a.score > b.score
    end)
    while #rows > limit do
        table.remove(rows)
    end
    return rows
end

function module:recordDetection(src, reason, score, payload)
    if not src or src == 0 then
        return
    end
    local cfg = Config.DamageMonitor or {}
    local monitoringCfg = Config.Monitoring or {}
    local entry = scoreEntry(src)
    local now = utils.millis()
    decayScore(entry, cfg, now)
    entry.score = math.min(100, entry.score + math.max(1, tonumber(score) or 10))
    entry.detections = (entry.detections or 0) + 1
    entry.lastReason = reason

    local cooldown = math.max(1000, tonumber(cfg.MonitoringCooldownMs) or 20000)
    if now - (entry.lastWebhook or 0) >= cooldown then
        entry.lastWebhook = now
        logger:flag('player_risk_profile', src, {
            detection = reason,
            risk_score = utils.round(entry.score, 1),
            detections = entry.detections,
            last_reason = reason,
            payload = payload,
        })
    end
end

function module:getRiskSnapshot(limit)
    return getRiskList(limit or 10)
end

function module:init()
    if started then
        return
    end
    started = true

    local monitoringCfg = Config.Monitoring or {}
    if monitoringCfg.Enabled == false then
        return
    end

    AddEventHandler('zvs-ac:internal:playerDropped', function(src)
        playerRisk[src] = nil
    end)

    local interval = math.max(10000, tonumber(monitoringCfg.SnapshotIntervalMs) or 60000)
    CreateThread(function()
        while true do
            Wait(interval)
            local queueStats = logger.getQueueStats and logger:getQueueStats() or {}
            local topRisk = monitoringCfg.IncludePlayerRisk == false and nil or getRiskList(math.max(1, tonumber(monitoringCfg.MaxTrackedPlayers) or 12))
            local highest = topRisk and topRisk[1] and tonumber(topRisk[1].score) or 0
            local active = (highest >= (tonumber(monitoringCfg.MinRiskToLog) or 35)) or ((queueStats.failed or 0) > 0) or ((queueStats.depth or 0) > 0)
            if monitoringCfg.OnlyWhenActive == false or active then
                local payload = {
                    description = 'Snapshot monitoring compact Visionary AC',
                    detection = 'monitoring_snapshot',
                    players = #GetPlayers(),
                    risk_score = highest,
                    webhook_queue_depth = queueStats.depth or 0,
                    webhook_sent = queueStats.sent or 0,
                    webhook_failed = queueStats.failed or 0,
                    webhook_dropped = queueStats.dropped or 0,
                    webhook_deduped = queueStats.deduped or 0,
                    top_risk = topRisk,
                }
                logger:send('monitoring_snapshot', payload)
            end
        end
    end)
end

if zVS and type(zVS.registerModule) == 'function' then
    return zVS.registerModule('server.modules.monitoring', module)
end

return module
