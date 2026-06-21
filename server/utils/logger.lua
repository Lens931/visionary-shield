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

local Logger = {}
Logger.__index = Logger

local identifierOrder = { 'license', 'fivem', 'discord', 'steam', 'xbl', 'live', 'ip' }
local severityPalette = {
    critical = 15158332, -- rouge
    warning = 16098851, -- orange
    info = 3447003, -- bleu
    success = 5763719, -- vert
    review = 10181046, -- violet Visionary
}

local detectionVisuals = {
    teleport = { emoji = '🛰️', severity = 'critical', label = 'Téléportation suspecte' },
    airwalk = { emoji = '🪽', severity = 'critical', label = 'Airwalk suspect' },
    sudden_ascent = { emoji = '📈', severity = 'warning', label = 'Ascension brutale' },
    high_speed = { emoji = '⚡', severity = 'warning', label = 'Vitesse anormale' },
    speed_burst = { emoji = '🏎️', severity = 'warning', label = 'Accélération extrême' },
    vehicle_speed = { emoji = '🚗', severity = 'warning', label = 'Vitesse véhicule anormale' },
    invincible = { emoji = '🛡️', severity = 'critical', label = 'Invincibilité détectée' },
    godmode_pattern = { emoji = '♾️', severity = 'critical', label = 'Pattern godmode' },
    excess_health = { emoji = '❤️', severity = 'warning', label = 'Santé excessive' },
    excess_armor = { emoji = '🦺', severity = 'warning', label = 'Armure excessive' },
    invisible = { emoji = '👻', severity = 'warning', label = 'Invisibilité suspecte' },
    noclip_v2 = { emoji = '🧭', severity = 'critical', label = 'NoClip V2' },
    silent_aim = { emoji = '🎯', severity = 'critical', label = 'Silent Aim' },
    triggerbot = { emoji = '⚙️', severity = 'critical', label = 'TriggerBot' },
    aim_assist = { emoji = '🧲', severity = 'warning', label = 'Aim Assist heuristics' },
    spectator_abuse = { emoji = '📡', severity = 'warning', label = 'Spectator abuse' },
    entity_spam = { emoji = '📦', severity = 'warning', label = 'Entity spam analysis' },
    event_flood = { emoji = '🌊', severity = 'critical', label = 'Event flood analysis' },
    network_anomaly = { emoji = '🕸️', severity = 'warning', label = 'Network anomaly' },
    resource_tampering = { emoji = '🧬', severity = 'critical', label = 'Resource tampering' },
    vehicle_spawn_abuse_v2 = { emoji = '🚨', severity = 'critical', label = 'Vehicle spawn abuse V2' },
    behaviour_profile = { emoji = '🧠', severity = 'warning', label = 'AI-like behaviour profile' },
    server_movement_signature = { emoji = '🛰️', severity = 'critical', label = 'Signature mouvement serveur' },
    stealth_state_mismatch = { emoji = '👻', severity = 'critical', label = 'État joueur incohérent' },
    combat_without_lineage = { emoji = '🎯', severity = 'critical', label = 'Dégâts sans lignée combat' },
    camera_desync_pattern = { emoji = '🎥', severity = 'warning', label = 'Pattern caméra désynchronisé' },
    freecam_pov_mismatch = { emoji = '📹', severity = 'critical', label = 'Freecam / POV mismatch' },
    damage_rate_signature = { emoji = '💥', severity = 'critical', label = 'Signature dégâts anormale' },
    aim_entropy_signature = { emoji = '🧬', severity = 'critical', label = 'Signature aim non humaine' },
    health_rollback_signature = { emoji = '❤️‍🩹', severity = 'warning', label = 'Rollback santé suspect' },
}

local metricDescriptors = {
    { key = 'speed', label = 'Vitesse', format = '%.1f km/h' },
    { key = 'current_speed', label = 'Vitesse actuelle', format = '%.1f km/h' },
    { key = 'previous_speed', label = 'Vitesse précédente', format = '%.1f km/h' },
    { key = 'delta_speed', label = 'Variation de vitesse', format = '%.1f km/h' },
    { key = 'distance', label = 'Distance', format = '%.1f m' },
    { key = 'deltaMs', label = 'Fenêtre', format = '%.0f ms' },
    { key = 'elapsed_ms', label = 'Fenêtre', format = '%.0f ms' },
    { key = 'height', label = 'Hauteur', format = '%.1f m' },
    { key = 'horizontalSpeed', label = 'Vitesse horizontale', format = '%.1f km/h' },
    { key = 'horizontal_speed', label = 'Vitesse horizontale', format = '%.1f km/h' },
    { key = 'vertical_speed', label = 'Vitesse verticale', format = '%.2f m/s' },
    { key = 'armour', label = 'Armure', format = '%.0f' },
    { key = 'health', label = 'Santé', format = '%.0f' },
    { key = 'maxHealth', label = 'Santé max', format = '%.0f' },
    { key = 'alpha', label = 'Alpha', format = '%.0f' },
    { key = 'risk_score', label = 'Risk score', format = '%.1f' },
    { key = 'increment', label = 'Risk delta', format = '%.1f' },
    { key = 'confidence', label = 'Confidence', format = '%.2f' },
    { key = 'count', label = 'Count', format = '%.0f' },
    { key = 'ping', label = 'Ping', format = '%.0f ms' },
    { key = 'strikes', label = 'Strikes', format = '%.0f' },
    { key = 'hits', label = 'Hits', format = '%.0f' },
    { key = 'total_damage', label = 'Dégâts totaux', format = '%.0f' },
    { key = 'camera_distance', label = 'Distance caméra', format = '%.1f m' },
    { key = 'ray_distance', label = 'Écart rayon caméra', format = '%.2f m' },
    { key = 'reaction_variance', label = 'Variance réaction', format = '%.2f ms' },
    { key = 'snap_variance', label = 'Variance snap', format = '%.2f°' },
}


local function ensurePayload(typeName, payload)
    local data = utils.copyTable(payload or {})
    data.t = data.t or typeName
    data.ts = data.ts or utils.iso8601()
    return data
end

local function formatIdentifierSummary(payload)
    if type(payload.identifier_summary) == 'string' and payload.identifier_summary ~= '' then
        return payload.identifier_summary
    end

    local entries = {}
    local primary = payload.identifier_map
    if type(primary) == 'table' then
        for _, key in ipairs(identifierOrder) do
            local value = primary[key]
            if value then
                entries[#entries + 1] = ('%s: `%s`'):format(key, value)
            end
        end
        for key, value in pairs(primary) do
            local known = false
            for _, ordered in ipairs(identifierOrder) do
                if ordered == key then
                    known = true
                    break
                end
            end
            if not known then
                entries[#entries + 1] = ('%s: `%s`'):format(key, value)
            end
        end
    end

    if #entries == 0 then
        local identifiers = payload.identifiers
        if type(identifiers) == 'table' then
            for _, identifier in ipairs(identifiers) do
                if type(identifier) == 'string' and identifier ~= '' then
                    entries[#entries + 1] = ('`%s`'):format(identifier)
                end
            end
        end
    end

    if #entries == 0 then
        return nil
    end

    return table.concat(entries, '\n')
end

local function formatCoords(coords)
    if type(coords) ~= 'table' then
        return nil
    end
    local x = tonumber(coords.x or coords[1])
    local y = tonumber(coords.y or coords[2])
    local z = tonumber(coords.z or coords[3])
    if not x or not y or not z then
        return nil
    end
    return ('x=%.2f, y=%.2f, z=%.2f'):format(x, y, z)
end

local function gatherMetrics(payload)
    local lines = {}
    local seen = {}
    for _, descriptor in ipairs(metricDescriptors) do
        local value = payload[descriptor.key]
        if value ~= nil and not seen[descriptor.label] then
            local formatted = nil
            local numberValue = tonumber(value)
            if descriptor.format and numberValue then
                formatted = descriptor.format:format(numberValue)
            elseif type(value) == 'string' and value ~= '' then
                formatted = value
            elseif type(value) == 'number' then
                formatted = tostring(value)
            end
            if formatted then
                lines[#lines + 1] = ('%s: %s'):format(descriptor.label, formatted)
                seen[descriptor.label] = true
            end
        end
    end
    return lines
end

local function resolveSuggestedAction(score, escalation)
    score = tonumber(score) or 0
    escalation = tostring(escalation or '')
    if escalation == 'ban' or score >= 94 then
        return 'Suggestion staff: ban après vérification complète des preuves'
    elseif escalation == 'kick' or score >= 78 then
        return 'Suggestion staff: kick si les preuves concordent'
    elseif escalation == 'freeze' or score >= 55 then
        return 'Suggestion staff: freeze + spectate + capture écran'
    elseif escalation == 'staff_review' or score >= 35 then
        return 'Suggestion staff: surveiller passivement et confirmer le contexte'
    end
    return 'Observation passive — aucune action recommandée'
end

local function summarizeRiskList(list, limit)
    if type(list) ~= 'table' then return nil end
    local rows = {}
    local maxRows = math.max(1, math.floor(tonumber(limit) or 5))
    for index, entry in ipairs(list) do
        if index > maxRows then break end
        if type(entry) == 'table' then
            rows[#rows + 1] = ('#%s • %s • score %s • %s'):format(
                tostring(entry.src or entry.target or '?'),
                tostring(entry.name or entry.player_name or entry.targetName or 'Inconnu'),
                tostring(entry.score or entry.risk_score or 0),
                tostring(entry.lastDetection or entry.reason or entry.escalation or 'telemetry')
            )
        end
    end
    if #rows == 0 then return nil end
    return table.concat(rows, '\n')
end

local function summarizeApprovals(list, limit)
    if type(list) ~= 'table' then return nil end
    local rows = {}
    local maxRows = math.max(1, math.floor(tonumber(limit) or 5))
    for index, entry in ipairs(list) do
        if index > maxRows then break end
        if type(entry) == 'table' then
            rows[#rows + 1] = ('%s • #%s • score %s • %s'):format(
                tostring(entry.action or 'review'),
                tostring(entry.src or entry.target or '?'),
                tostring(entry.score or 0),
                tostring(entry.detection or entry.recommendation or 'pending')
            )
        end
    end
    if #rows == 0 then return nil end
    return table.concat(rows, '\n')
end

local function encodeRawPayload(payload)
    local ok, encoded = pcall(json.encode, payload)
    if not ok or type(encoded) ~= 'string' then
        return nil
    end
    if #encoded > 900 then
        encoded = encoded:sub(1, 900) .. '…'
    end
    return ('```json\n%s\n```'):format(encoded)
end

function Logger:new()
    local instance = setmetatable({}, Logger)
    return instance
end

local function buildEmbed(typeName, payload)
    local detectionKey = nil
    if type(typeName) == 'string' and typeName:find('auto_detection_', 1, true) == 1 then
        detectionKey = typeName:gsub('^auto_detection_', '')
    elseif type(payload.detection) == 'string' and payload.detection ~= '' then
        detectionKey = payload.detection
    end

    local visuals = detectionKey and detectionVisuals[detectionKey] or nil
    local severity = payload.severity or (visuals and visuals.severity) or 'info'
    if typeName and (typeName:find('risk_', 1, true) == 1 or typeName:find('player_risk_', 1, true) == 1) then
        severity = payload.severity or 'review'
    end
    local color = severityPalette[severity] or severityPalette.info
    local titlePrefix = visuals and visuals.emoji or '🛰️'
    local titleLabel = visuals and visuals.label or typeName

    local embed = {
        title = ('%s %s'):format(titlePrefix, titleLabel),
        color = color,
        timestamp = payload.ts,
        fields = {},
        footer = {
            text = ('Visionary SOC • %s'):format(typeName),
        },
    }
    if payload.target_name or payload.player_name then
        embed.author = {
            name = tostring(payload.target_name or payload.player_name),
        }
    end

    local description = payload.description or payload.message
    if type(description) == 'string' and description ~= '' then
        embed.description = description
    end

    local function addField(name, value, inline)
        if not value then return end
        if type(value) ~= 'string' then
            value = tostring(value)
        end
        if value == '' then return end
        if #value > 1024 then
            value = value:sub(1, 1019) .. '...'
        end
        embed.fields[#embed.fields + 1] = { name = name, value = value, inline = inline or false }
    end

    local sourceLabel = nil
    if payload.src then
        if payload.admin_name or payload.source_name then
            sourceLabel = ('%s (#%s)'):format(payload.admin_name or payload.source_name, payload.src)
        else
            sourceLabel = ('ID #%s'):format(payload.src)
        end
    elseif payload.admin_name or payload.source_name then
        sourceLabel = payload.admin_name or payload.source_name
    end
    addField('Source', sourceLabel, true)

    local targetLabel = nil
    if payload.target then
        if payload.target_name or payload.player_name then
            targetLabel = ('%s (#%s)'):format(payload.target_name or payload.player_name, payload.target)
        else
            targetLabel = ('ID #%s'):format(payload.target)
        end
    elseif payload.target_name or payload.player_name then
        targetLabel = payload.target_name or payload.player_name
    end
    addField('Cible', targetLabel, true)

    if payload.detection then
        addField('Détection', tostring(payload.detection), true)
    end

    local riskScore = tonumber(payload.risk_score or payload.score)
    if riskScore then
        addField('Score de risque', ('%.1f / 100'):format(riskScore), true)
        addField('Décision', 'Avis humain requis — aucune sanction automatique', true)
        addField('Recommandation', resolveSuggestedAction(riskScore, payload.escalation or payload.requestedAction or payload.action), false)
    end

    if payload.confidence then
        local confidence = tonumber(payload.confidence)
        if confidence then
            addField('Confiance', ('%.0f%%'):format(confidence * 100), true)
        end
    end

    if payload.recommendation then
        addField('Suggestion', tostring(payload.recommendation), false)
    end

    if payload.reason then
        addField('Raison', tostring(payload.reason), false)
    end

    local identifiersField = formatIdentifierSummary(payload)
    if identifiersField then
        addField('Identifiants', identifiersField, false)
    end

    local coordsField = formatCoords(payload.coords)
    if coordsField then
        addField('Position', coordsField, true)
    end

    local fromField = formatCoords(payload.from_coords)
    if fromField then
        addField('Origine', fromField, true)
    end

    local toField = formatCoords(payload.to_coords)
    if toField then
        addField('Destination', toField, true)
    end

    local metrics = gatherMetrics(payload)
    if #metrics > 0 then
        addField('Paramètres', table.concat(metrics, '\n'), false)
    end

    local topRiskSummary = summarizeRiskList(payload.top_risk, 6)
    if topRiskSummary then
        addField('Top profils à surveiller', topRiskSummary, false)
    end

    local approvalsSummary = summarizeApprovals(payload.approvals, 6)
    if approvalsSummary then
        addField('Décisions en attente', approvalsSummary, false)
    end

    local rawPayload = encodeRawPayload(payload)
    if #embed.fields == 0 then
        if rawPayload then
            embed.description = rawPayload
        end
    else
        if rawPayload then
            addField('Données', rawPayload, false)
        end
    end

    if not embed.description or embed.description == '' then
        embed.description = 'Événement Visionary AC'
    end

    return {
        username = 'Visionary AC',
        embeds = { embed },
    }
end

local webhookQueue = {}
local isProcessing = false
local maxAttempts = 3
local queueStats = { enqueued = 0, sent = 0, failed = 0, dropped = 0, deduped = 0 }
local recentLogKeys = {}

local function loggerCfg()
    return Config.DiscordLogging or Config.Logger or {}
end

local function makeDedupeKey(typeName, payload)
    payload = payload or {}
    return table.concat({
        tostring(typeName or 'event'),
        tostring(payload.target or payload.src or ''),
        tostring(payload.detection or payload.reason or payload.message or ''),
    }, '|')
end

local function cleanupDedupe(now, windowMs)
    for key, expires in pairs(recentLogKeys) do
        if expires <= now then
            recentLogKeys[key] = nil
        end
    end
end

local function firstWebhook(...)
    for index = 1, select('#', ...) do
        local candidate = select(index, ...)
        if type(candidate) == 'string' and candidate ~= '' then
            return candidate
        end
    end
    return nil
end

local function resolveWebhook(typeName)
    local monitoringCfg = Config.Monitoring or {}
    local webhookCfg = Config.Webhooks or {}
    local detectionWebhooks = webhookCfg.Detections or {}
    local routing = {
        monitoring_snapshot = firstWebhook(webhookCfg.Monitoring, monitoringCfg.Webhook),
    }

    local defaultWebhook = firstWebhook(webhookCfg.Default, Config.Webhook)

    if typeName and typeName:find('damage_', 1, true) == 1 then
        return firstWebhook(monitoringCfg.DetectionWebhook, defaultWebhook)
    end

    if typeName and (typeName:find('auto_detection_', 1, true) == 1 or typeName:find('player_risk_', 1, true) == 1) then
        local byExact = detectionWebhooks[typeName]
        local suffix = typeName:gsub('^auto_detection_', '')
        local bySuffix = detectionWebhooks[suffix]
        local detectionDefault = detectionWebhooks.auto_detection_default
        return firstWebhook(byExact, bySuffix, detectionDefault, monitoringCfg.DetectionWebhook, defaultWebhook)
    end

    local target = routing[typeName]
    if type(target) == 'string' and target ~= '' then
        return target
    end

    return firstWebhook(defaultWebhook)
end

local function processQueue()
    if isProcessing then return end
    local item = webhookQueue[1]
    if not item then return end
    local webhook = resolveWebhook(item.typeName)
    maxAttempts = math.max(1, math.floor(tonumber(loggerCfg().RetryAttempts) or maxAttempts or 3))
    if (webhook or '') == '' then
        utils.debugLog('Webhook not configured. Skipping queued log for', item.typeName)
        queueStats.dropped = queueStats.dropped + 1
        table.remove(webhookQueue, 1)
        processQueue()
        return
    end

    isProcessing = true
    local bodyPayload = ensurePayload(item.typeName, item.payload)
    local body = buildEmbed(item.typeName, bodyPayload)

    PerformHttpRequest(webhook, function(status, text)
        local success = status == 204 or status == 200
        if not success then
            item.attempts = item.attempts + 1
            if item.attempts < maxAttempts then
                utils.debugLog(('Webhook attempt %s/%s failed for %s (status: %s)'):format(item.attempts, maxAttempts, item.typeName, status or 'n/a'))
                SetTimeout(math.min(10000, 2000 * item.attempts), function()
                    isProcessing = false
                    processQueue()
                end)
                return
            else
                queueStats.failed = queueStats.failed + 1
                utils.debugLog(('Webhook permanently failed for %s (status: %s, body: %s)'):format(item.typeName, status or 'n/a', text or ''))
            end
        end

        table.remove(webhookQueue, 1)
        if success then
            queueStats.sent = queueStats.sent + 1
        end
        isProcessing = false
        processQueue()
    end, 'POST', json.encode(body), { ['Content-Type'] = 'application/json' })
end

function Logger:send(typeName, payload)
    local settings = loggerCfg()
    local now = utils.millis()
    local dedupeWindow = math.max(0, tonumber(settings.DedupeWindowMs) or 6500)
    if dedupeWindow > 0 then
        cleanupDedupe(now, dedupeWindow)
        local dedupeKey = makeDedupeKey(typeName, payload)
        local expires = recentLogKeys[dedupeKey]
        if expires and expires > now then
            queueStats.deduped = (queueStats.deduped or 0) + 1
            return
        end
        recentLogKeys[dedupeKey] = now + dedupeWindow
    end

    local maxQueue = math.max(10, math.floor(tonumber(settings.QueueMax) or 90))
    while #webhookQueue >= maxQueue do
        table.remove(webhookQueue, 1)
        queueStats.dropped = queueStats.dropped + 1
    end

    queueStats.enqueued = queueStats.enqueued + 1
    webhookQueue[#webhookQueue + 1] = {
        typeName = typeName,
        payload = payload,
        attempts = 0,
    }
    processQueue()
end

function Logger:getQueueStats()
    return {
        depth = #webhookQueue,
        processing = isProcessing,
        enqueued = queueStats.enqueued,
        sent = queueStats.sent,
        failed = queueStats.failed,
        dropped = queueStats.dropped,
        deduped = queueStats.deduped or 0,
    }
end

function Logger:flag(typeName, src, payload)
    payload = payload or {}
    payload.src = src
    self:send(typeName, payload)
end

zVS.logger = Logger:new()

if type(package) == 'table' and type(package.loaded) == 'table' then
    package.loaded['server.utils.logger'] = zVS.logger
    package.loaded['server/utils/logger'] = zVS.logger
end

return zVS.logger
