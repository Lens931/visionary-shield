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
local profiles = {}
local staffApprovals = {}
local auditTrail = {}
local actionCooldowns = {}
local escalationOrder = { 'staff_review', 'freeze', 'kick', 'ban' }

local defaultWeights = {
    high_speed = 14,
    speed_burst = 18,
    teleport = 38,
    airwalk = 28,
    sudden_ascent = 22,
    vehicle_speed = 20,
    invincible = 40,
    godmode_pattern = 42,
    excess_health = 24,
    excess_armor = 18,
    invisible = 24,
    damage_excessive_damage = 35,
    damage_blacklisted_weapon = 55,
    damage_rapid_fire = 30,
    damage_kill_streak = 25,
    damage_headshot_streak = 25,
    noclip_v2 = 48,
    silent_aim = 58,
    triggerbot = 45,
    aim_assist = 32,
    spectator_abuse = 30,
    entity_spam = 34,
    event_flood = 36,
    network_anomaly = 30,
    resource_tampering = 65,
    vehicle_spawn_abuse_v2 = 38,
    behaviour_profile = 26,
}

local function cfg()
    return Config.RiskEngine or {}
end

local function clamp(value, minValue, maxValue)
    value = tonumber(value) or 0
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function trim(list, limit)
    limit = math.max(0, math.floor(tonumber(limit) or 0))
    if limit <= 0 then
        for index = #list, 1, -1 do
            list[index] = nil
        end
        return
    end
    while #list > limit do
        table.remove(list)
    end
end

local function getProfile(src)
    local numeric = tonumber(src)
    if not numeric then return nil end
    local profile = profiles[numeric]
    if profile then
        return profile
    end
    profile = {
        src = numeric,
        score = 0,
        peak = 0,
        confidence = 0,
        detections = {},
        timeline = {},
        firstSeen = utils.iso8601(),
        lastSeen = utils.iso8601(),
        lastUpdate = utils.millis(),
        lastDetection = nil,
        escalation = 'none',
        pendingApproval = nil,
        actions = {},
        heat = {},
    }
    profiles[numeric] = profile
    return profile
end

local function decay(profile, now)
    local settings = cfg()
    local decayMs = math.max(1000, tonumber(settings.DecayMs) or 180000)
    local elapsed = math.max(0, now - (profile.lastUpdate or now))
    if elapsed <= 0 or profile.score <= 0 then
        profile.lastUpdate = now
        return
    end
    local decayPerWindow = tonumber(settings.DecayPerWindow) or 18
    profile.score = clamp(profile.score - (decayPerWindow * (elapsed / decayMs)), 0, 100)
    profile.lastUpdate = now
end

local function resolveWeight(detection, explicitWeight)
    if explicitWeight ~= nil then
        local numeric = tonumber(explicitWeight)
        if numeric and numeric > 0 then
            return numeric
        end
    end
    local weights = cfg().Weights or {}
    local configured = tonumber(weights[detection])
    if configured and configured > 0 then
        return configured
    end
    return defaultWeights[detection] or tonumber(weights.default) or 15
end

local function getThreshold(action)
    local thresholds = cfg().Thresholds or {}
    local defaults = { staff_review = 35, freeze = 55, kick = 78, ban = 94 }
    return tonumber(thresholds[action]) or defaults[action] or 100
end

local function recommendationFor(action, score)
    score = tonumber(score) or 0
    if action == 'ban' then
        return 'Ban conseillé uniquement si plusieurs preuves concordent et après validation staff.'
    elseif action == 'kick' then
        return 'Kick conseillé si le comportement est confirmé en spectate/capture.'
    elseif action == 'freeze' then
        return 'Freeze conseillé pour figer la situation, spectate et collecter une preuve.'
    elseif action == 'staff_review' then
        return 'Surveillance passive conseillée : confirmer le contexte avant toute action.'
    end
    return 'Aucune sanction recommandée, continuer la surveillance passive.'
end

local function resolveEscalation(score)
    local selected = 'none'
    for _, action in ipairs(escalationOrder) do
        if score >= getThreshold(action) then
            selected = action
        end
    end
    return selected
end

local function getActionCooldown(action)
    local cooldowns = cfg().ActionCooldownMs or {}
    return math.max(1000, tonumber(cooldowns[action]) or 60000)
end

local function canExecuteAction(src, action, now)
    actionCooldowns[src] = actionCooldowns[src] or {}
    local expires = actionCooldowns[src][action]
    if expires and expires > now then
        return false
    end
    actionCooldowns[src][action] = now + getActionCooldown(action)
    return true
end

local function addAudit(entry)
    entry.id = entry.id or utils.randomId('audit-')
    entry.ts = entry.ts or utils.iso8601()
    table.insert(auditTrail, 1, entry)
    trim(auditTrail, cfg().AuditLimit or 120)
end

local function staffApprovalRequired(action)
    if cfg().HumanReviewOnly ~= false and (action == 'freeze' or action == 'kick' or action == 'ban') then
        return true
    end
    local workflow = cfg().StaffApproval or {}
    if workflow.Enabled == false then
        return false
    end
    local required = workflow.RequireFor or { freeze = true, kick = true, ban = true }
    return required[action] == true
end

local function executeEscalation(profile, action, payload)
    if action == 'none' or action == 'staff_review' then
        return
    end

    local settings = cfg()
    local approvedByStaff = payload and payload.approved == true

    if staffApprovalRequired(action) and not approvedByStaff then
        local existing = profile.pendingApproval and staffApprovals[profile.pendingApproval] or nil
        if existing and existing.status == 'pending' then
            existing.action = action
            existing.score = utils.round(profile.score, 1)
            existing.detection = profile.lastDetection
            existing.payload = payload
            existing.recommendation = recommendationFor(action, profile.score)
            existing.updatedAt = os.time()
            addAudit({ action = 'approval_updated', target = profile.src, requestedAction = action, score = existing.score, recommendation = existing.recommendation })
            TriggerEvent('zvs-ac:risk:approvalRequested', existing)
            return
        end

        local approval = {
            id = utils.randomId('approval-'),
            src = profile.src,
            targetName = GetPlayerName(profile.src),
            action = action,
            score = utils.round(profile.score, 1),
            detection = profile.lastDetection,
            recommendation = recommendationFor(action, profile.score),
            payload = payload,
            createdAt = os.time(),
            status = 'pending',
        }
        staffApprovals[approval.id] = approval
        profile.pendingApproval = approval.id
        addAudit({ action = 'approval_requested', target = profile.src, requestedAction = action, score = approval.score, recommendation = approval.recommendation })
        logger:flag('risk_manual_review_required', profile.src, {
            detection = profile.lastDetection,
            risk_score = approval.score,
            requestedAction = action,
            recommendation = approval.recommendation,
            human_review_only = true,
        })
        TriggerEvent('zvs-ac:risk:approvalRequested', approval)
        return
    end

    if not approvedByStaff and (settings.AutomationEnabled == false or settings.HumanReviewOnly ~= false) then
        addAudit({
            action = 'manual_review_required',
            target = profile.src,
            requestedAction = action,
            score = utils.round(profile.score, 1),
            recommendation = recommendationFor(action, profile.score),
        })
        return
    end

    local now = utils.millis()
    if not canExecuteAction(profile.src, action, now) then
        return
    end

    local reason = ('Visionary Risk Engine staff decision: %s (score %.1f)'):format(profile.lastDetection or 'risk', profile.score)
    if action == 'freeze' then
        TriggerEvent('zvs-ac:risk:autoFreeze', profile.src, reason, payload)
    elseif action == 'kick' then
        DropPlayer(profile.src, reason)
    elseif action == 'ban' then
        TriggerEvent('zvs-ac:risk:autoBan', profile.src, reason, payload)
    end

    profile.actions[#profile.actions + 1] = { action = action, ts = utils.iso8601(), reason = reason }
    trim(profile.actions, 20)
    addAudit({ action = (approvedByStaff and 'staff_' or 'review_') .. action, target = profile.src, score = utils.round(profile.score, 1), reason = reason })
    logger:flag((approvedByStaff and 'risk_staff_' or 'risk_review_') .. action, profile.src, {
        risk_score = utils.round(profile.score, 1),
        detection = profile.lastDetection,
        reason = reason,
    })
end

function module:record(src, detection, payload)
    if not src or src == 0 then return nil end
    detection = tostring(detection or 'unknown')
    payload = payload or {}
    if cfg().Enabled == false then return nil end
    if zVS.adminTools and type(zVS.adminTools.isDefenseEnabled) == 'function' and not zVS.adminTools.isDefenseEnabled('risk_engine') then return nil end
    if cfg().IgnoreAdmins ~= false and utils.isAdmin(src) then return nil end

    local profile = getProfile(src)
    local now = utils.millis()
    decay(profile, now)

    local weight = resolveWeight(detection, payload.weight or payload.score)
    local confidence = clamp(payload.confidence or 0.65, 0, 1)
    local increment = weight * confidence
    profile.score = clamp(profile.score + increment, 0, 100)
    profile.peak = math.max(profile.peak or 0, profile.score)
    profile.confidence = clamp(((profile.confidence or 0) * 0.7) + (confidence * 0.3), 0, 1)
    profile.lastSeen = utils.iso8601()
    profile.lastUpdate = now
    profile.lastDetection = detection

    local count = profile.detections[detection] or 0
    profile.detections[detection] = count + 1

    local nextEscalationPreview = resolveEscalation(profile.score)
    local event = {
        ts = profile.lastSeen,
        detection = detection,
        score = utils.round(profile.score, 1),
        delta = utils.round(increment, 1),
        weight = weight,
        confidence = utils.round(confidence, 2),
        escalation = nextEscalationPreview,
        recommendation = recommendationFor(nextEscalationPreview, profile.score),
        payload = payload,
    }
    table.insert(profile.timeline, 1, event)
    trim(profile.timeline, cfg().TimelineLimit or 40)

    local nextEscalation = nextEscalationPreview
    if nextEscalation ~= profile.escalation then
        profile.escalation = nextEscalation
        addAudit({ action = 'escalation_change', target = profile.src, escalation = nextEscalation, score = event.score, detection = detection })
        logger:flag('risk_escalation_' .. nextEscalation, profile.src, {
            detection = detection,
            risk_score = event.score,
            increment = event.delta,
            escalation = nextEscalation,
            recommendation = event.recommendation,
            human_review_only = cfg().HumanReviewOnly ~= false,
        })
        executeEscalation(profile, nextEscalation, payload)
    end

    TriggerEvent('zvs-ac:risk:updated', profile.src, self:getProfile(profile.src))
    return profile
end

function module:getProfile(src)
    local profile = profiles[tonumber(src)]
    if not profile then return nil end
    local clone = utils.copyTable(profile)
    clone.name = GetPlayerName(profile.src)
    clone.score = utils.round(clone.score or 0, 1)
    clone.peak = utils.round(clone.peak or 0, 1)
    clone.confidence = utils.round(clone.confidence or 0, 2)
    clone.recommendation = recommendationFor(clone.escalation, clone.score)
    clone.humanReviewOnly = cfg().HumanReviewOnly ~= false
    return clone
end

function module:getSnapshot(limit)
    local rows = {}
    local now = utils.millis()
    for src, profile in pairs(profiles) do
        decay(profile, now)
        if profile.score > 0.1 or #(profile.timeline or {}) > 0 then
            rows[#rows + 1] = self:getProfile(src)
        end
    end
    table.sort(rows, function(a, b)
        if a.score == b.score then return a.src < b.src end
        return a.score > b.score
    end)
    trim(rows, limit or cfg().SnapshotLimit or 30)
    return rows
end

function module:getAudit(limit)
    local output = {}
    for index, entry in ipairs(auditTrail) do
        if index > (limit or 40) then break end
        output[#output + 1] = utils.copyTable(entry)
    end
    return output
end

function module:getApprovals()
    local output = {}
    for _, approval in pairs(staffApprovals) do
        if approval.status == 'pending' then
            output[#output + 1] = utils.copyTable(approval)
        end
    end
    table.sort(output, function(a, b) return (a.createdAt or 0) > (b.createdAt or 0) end)
    return output
end

function module:resolveApproval(id, admin, approved)
    local approval = staffApprovals[id]
    if not approval or approval.status ~= 'pending' then
        return false, 'not_found'
    end
    approval.status = approved and 'approved' or 'rejected'
    approval.resolvedAt = os.time()
    approval.resolvedBy = admin
    addAudit({ action = 'approval_' .. approval.status, target = approval.src, admin = admin, requestedAction = approval.action })
    if approved then
        local payload = approval.payload or {}
        payload.approved = true
        executeEscalation(getProfile(approval.src), approval.action, payload)
    end
    return true
end

function module:init()
    if started then return end
    started = true
    zVS.riskEngine = module

    AddEventHandler('zvs-ac:risk:record', function(src, detection, payload)
        module:record(src, detection, payload)
    end)

    AddEventHandler('zvs-ac:internal:playerDropped', function(src)
        profiles[src] = nil
        actionCooldowns[src] = nil
    end)

    -- ZeroFootprint: when passive Discord snapshots are disabled, the Risk Engine stays fully event-driven.
    -- Detections still call module:record() instantly via zvs-ac:risk:record, but no idle server thread is created.
    if (cfg().SnapshotToDiscord == false) then
        return
    end

    CreateThread(function()
        while true do
            local settings = cfg()
            local interval = math.max(30000, tonumber(settings.SnapshotIntervalMs) or 90000)
            Wait(interval)
            if settings.Enabled ~= false and settings.SnapshotToDiscord ~= false then
                local top = module:getSnapshot(10)
                local approvals = module:getApprovals()
                local highest = top[1] and tonumber(top[1].score) or 0
                local minScore = tonumber(settings.SnapshotMinScore) or getThreshold('staff_review')
                if #approvals > 0 or highest >= minScore then
                    logger:send('risk_snapshot', {
                        description = 'Snapshot compact du Risk Engine — surveillance passive, décisions humaines uniquement.',
                        detection = 'risk_snapshot',
                        risk_score = highest,
                        human_review_only = settings.HumanReviewOnly ~= false,
                        top_risk = top,
                        approvals = approvals,
                    })
                end
            end
        end
    end)
end

if zVS and type(zVS.registerModule) == 'function' then
    return zVS.registerModule('server.modules.risk_engine', module)
end

return module
