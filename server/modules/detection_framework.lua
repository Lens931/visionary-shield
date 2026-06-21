local utils = zVS and zVS.utils
if not utils then
    local ok, mod = pcall(require, 'shared.utils')
    if not ok then error(('zVS-AC: unable to load shared utils (%s)'):format(mod)) end
    utils = mod
end

local logger = zVS and zVS.logger
if not logger then
    local ok, mod = pcall(require, 'server.utils.logger')
    if not ok then error(('zVS-AC: unable to load server logger (%s)'):format(mod)) end
    logger = mod
end

zVS = zVS or {}
local Config = zVS.Config or {}
local module = {}
local started = false
local state = {}
local globalCounters = { events = {}, entities = {}, vehicles = {} }

local detectorMeta = {
    noclip_v2 = { label = 'NoClip V2', weight = 48 },
    silent_aim = { label = 'Silent Aim', weight = 58 },
    triggerbot = { label = 'TriggerBot', weight = 45 },
    aim_assist = { label = 'Aim Assist Heuristics', weight = 32 },
    spectator_abuse = { label = 'Spectator Abuse', weight = 30 },
    entity_spam = { label = 'Entity Spam Analysis', weight = 34 },
    event_flood = { label = 'Event Flood Analysis', weight = 36 },
    network_anomaly = { label = 'Network Anomaly', weight = 30 },
    resource_tampering = { label = 'Resource Tampering', weight = 65 },
    vehicle_spawn_abuse_v2 = { label = 'Advanced Vehicle Spawn Abuse', weight = 38 },
    behaviour_profile = { label = 'AI-like Behaviour Profile', weight = 26 },
    server_movement_signature = { label = 'Server Movement Signature', weight = 42 },
    stealth_state_mismatch = { label = 'Stealth State Mismatch', weight = 44 },
    combat_without_lineage = { label = 'Combat Without Client Lineage', weight = 52 },
    camera_desync_pattern = { label = 'Camera Desync Pattern', weight = 28 },
    freecam_pov_mismatch = { label = 'Freecam / POV Mismatch', weight = 38 },
    damage_rate_signature = { label = 'Damage Rate Signature', weight = 46 },
    aim_entropy_signature = { label = 'Aim Entropy Signature', weight = 40 },
    health_rollback_signature = { label = 'Health Rollback Signature', weight = 30 },
}

local debugOnceCache = {}

local function debugOnce(key, ...)
    if debugOnceCache[key] then return end
    debugOnceCache[key] = true
    if utils and type(utils.debugLog) == 'function' then
        utils.debugLog(...)
    end
end

local function cfg()
    local enhanced = Config.EnhancedDetections
    if type(enhanced) ~= 'table' then
        return {}
    end
    return enhanced
end

local function detectorCfg(key)
    local detectors = cfg().Detectors
    if type(detectors) ~= 'table' then
        return {}
    end

    local settings = detectors[key]
    if type(settings) == 'table' then
        return settings
    end

    -- Backward compatibility: older or manually edited configs may use
    -- detectorName = 45 or detectorName = false instead of a sub-table.
    if type(settings) == 'number' then
        debugOnce('detector-number-' .. tostring(key), 'EnhancedDetections detector normalized from number:', key, settings)
        return { Weight = settings, Severity = settings, severity = settings }
    end

    if type(settings) == 'boolean' then
        debugOnce('detector-boolean-' .. tostring(key), 'EnhancedDetections detector normalized from boolean:', key, settings)
        return { Enabled = settings }
    end

    if settings ~= nil then
        debugOnce('detector-invalid-' .. tostring(key), 'EnhancedDetections detector ignored because it is not a table/number/boolean:', key, type(settings))
    end

    return {}
end

local function enabled(key)
    if cfg().Enabled == false then return false end
    if zVS.adminTools and type(zVS.adminTools.isDefenseEnabled) == 'function' and not zVS.adminTools.isDefenseEnabled('enhanced_detections') then return false end
    local settings = detectorCfg(key)
    return settings.Enabled ~= false
end

local function getState(src)
    state[src] = state[src] or {
        events = {},
        telemetry = {},
        lastFlags = {},
        shots = {},
        resources = {},
        serverSamples = {},
        strikes = {},
        damageEvents = {},
        lastCombatTelemetryAt = 0,
        joinedAt = utils.millis(),
        cameraProbeStrikes = {},
    }
    return state[src]
end

local function prune(list, now, window)
    if type(list) ~= 'table' then
        return
    end

    local maxAge = tonumber(window) or 0
    if maxAge <= 0 then
        return
    end

    local currentTime = tonumber(now) or utils.millis()
    for index = #list, 1, -1 do
        local entry = list[index]
        local ts = nil

        if type(entry) == 'table' then
            ts = tonumber(entry.ts or entry.time or entry.timestamp or entry[1])
        else
            ts = tonumber(entry)
        end

        if not ts or currentTime - ts > maxAge then
            table.remove(list, index)
        end
    end
end


local function addStrike(player, key, now, window)
    if type(player) ~= 'table' then return 0 end
    player.strikes = type(player.strikes) == 'table' and player.strikes or {}
    local list = player.strikes[key]
    if type(list) ~= 'table' then
        list = {}
        player.strikes[key] = list
    end
    list[#list + 1] = tonumber(now) or utils.millis()
    prune(list, now, window or 15000)
    return #list
end

local function safeCall(fnName, ...)
    local fn = _G[fnName]
    if type(fn) ~= 'function' then return nil end
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil
end

local function safeEntityCoords(entity)
    local coords = safeCall('GetEntityCoords', entity)
    if not coords then return nil end
    return { x = (coords.x or 0.0) + 0.0, y = (coords.y or 0.0) + 0.0, z = (coords.z or 0.0) + 0.0 }
end

local function safeEntitySpeedKmh(entity)
    local speed = tonumber(safeCall('GetEntitySpeed', entity))
    if not speed then return nil end
    return speed * 3.6
end

local function safeVehicleForPed(ped)
    return tonumber(safeCall('GetVehiclePedIsIn', ped, false)) or 0
end

local function safeRoutingBucket(src)
    return tonumber(safeCall('GetPlayerRoutingBucket', src)) or 0
end

local function throttle(bucket, key, cooldown)
    if type(bucket) ~= 'table' then
        return true
    end

    local now = utils.millis()
    local nextAllowed = tonumber(bucket[key])
    if nextAllowed and nextAllowed > now then
        return false
    end
    bucket[key] = now + math.max(1000, tonumber(cooldown) or 15000)
    return true
end

local function record(src, detection, payload)
    if not src or src == 0 or not enabled(detection) then return end
    if cfg().IgnoreAdmins ~= false and utils.isAdmin(src) then return end
    local meta = detectorMeta[detection] or { label = detection, weight = 15 }
    payload = type(payload) == 'table' and payload or {}
    local settings = detectorCfg(detection)
    payload.detection = detection
    payload.detector_label = meta.label
    payload.weight = payload.weight or settings.Weight or settings.weight or meta.weight
    payload.confidence = payload.confidence or settings.Confidence or settings.confidence or 0.72
    payload.target = payload.target or src
    payload.target_name = payload.target_name or GetPlayerName(src)

    TriggerEvent('zvs-ac:risk:record', src, detection, payload)
    TriggerEvent('zvs-ac:adminTools:flag', {
        type = detection,
        src = src,
        message = ('%s: %s (#%s)'):format(meta.label, GetPlayerName(src) or 'Unknown', src),
        payload = payload,
        logType = 'enhanced_detection_' .. detection,
        notify = settings.Notify == true,
    })
    logger:flag('enhanced_detection_' .. detection, src, payload)
end

function module:record(src, detection, payload)
    return record(tonumber(src), detection, payload)
end

local function distance(a, b)
    if not a or not b then return 0.0 end
    local dx = (a.x or 0.0) - (b.x or 0.0)
    local dy = (a.y or 0.0) - (b.y or 0.0)
    local dz = (a.z or 0.0) - (b.z or 0.0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function variance(values)
    if type(values) ~= 'table' or #values <= 1 then return math.huge end
    local sum = 0.0
    local count = 0
    for _, value in ipairs(values) do
        local n = tonumber(value)
        if n then
            sum = sum + n
            count = count + 1
        end
    end
    if count <= 1 then return math.huge end
    local mean = sum / count
    local total = 0.0
    for _, value in ipairs(values) do
        local n = tonumber(value)
        if n then
            local delta = n - mean
            total = total + (delta * delta)
        end
    end
    return math.sqrt(total / count)
end

local function analyzeTelemetry(src, sample)
    local player = getState(src)
    local now = utils.millis()
    sample.ts = now
    table.insert(player.telemetry, 1, sample)
    while #player.telemetry > 12 do table.remove(player.telemetry) end

    local current = player.telemetry[1]
    local previous = player.telemetry[2]

    if enabled('stealth_state_mismatch') and not utils.isAdmin(src) then
        local stealth = detectorCfg('stealth_state_mismatch')
        local alpha = tonumber(current.alpha)
        local visible = current.visible
        local invincible = current.invincible == true
        local health = tonumber(current.health) or 0
        local armor = tonumber(current.armor) or 0
        local suspicious = false
        local reasons = {}

        if visible == false then
            suspicious = true
            reasons[#reasons + 1] = 'not_visible'
        end
        if alpha and alpha < (tonumber(stealth.AlphaThreshold) or 180) then
            suspicious = true
            reasons[#reasons + 1] = 'low_alpha'
        end
        if invincible then
            suspicious = true
            reasons[#reasons + 1] = 'client_invincible'
        end
        if health > (tonumber(stealth.MaxHealth) or 250) then
            suspicious = true
            reasons[#reasons + 1] = 'excess_health'
        end
        if armor > (tonumber(stealth.MaxArmor) or 100) then
            suspicious = true
            reasons[#reasons + 1] = 'excess_armor'
        end

        if suspicious then
            local strikes = addStrike(player, 'stealth_state_mismatch', now, stealth.StrikeWindowMs or 12000)
            if strikes >= (stealth.StrikeThreshold or 2) and throttle(player.lastFlags, 'stealth_state_mismatch', stealth.CooldownMs or 45000) then
                record(src, 'stealth_state_mismatch', {
                    reasons = reasons,
                    strikes = strikes,
                    alpha = alpha,
                    visible = visible,
                    invincible = invincible,
                    health = health,
                    armor = armor,
                    coords = current.coords,
                    confidence = invincible and 0.84 or 0.68,
                })
            end
        end
    end

    if not previous then return end

    if enabled('health_rollback_signature') then
        local rollback = detectorCfg('health_rollback_signature')
        local currentHealth = tonumber(current.health) or 0
        local previousHealth = tonumber(previous.health) or 0
        local delta = currentHealth - previousHealth
        local minPrevious = tonumber(rollback.MinPreviousHealth) or 101
        local healDelta = tonumber(rollback.HealDelta) or 45
        local maxAllowed = tonumber(rollback.MaxAllowedHealth) or 220
        if previousHealth >= minPrevious and delta >= healDelta and currentHealth > maxAllowed and not current.inVehicle then
            local strikes = addStrike(player, 'health_rollback_signature', now, rollback.StrikeWindowMs or 18000)
            if strikes >= (tonumber(rollback.StrikeThreshold) or 2) and throttle(player.lastFlags, 'health_rollback_signature', rollback.CooldownMs or 45000) then
                record(src, 'health_rollback_signature', {
                    strikes = strikes,
                    previous_health = previousHealth,
                    health = currentHealth,
                    delta_health = delta,
                    coords = current.coords,
                    confidence = strikes >= 3 and 0.76 or 0.64,
                })
            end
        end
    end

    if enabled('noclip_v2') and current.coords and previous.coords and not current.inVehicle then
        local dz = math.abs((current.coords.z or 0) - (previous.coords.z or 0))
        local dist = distance(current.coords, previous.coords)
        local timeSeconds = math.max(0.1, (now - (previous.ts or now)) / 1000)
        local speed = (dist / timeSeconds) * 3.6
        local noclip = detectorCfg('noclip_v2')
        if dz >= (noclip.VerticalDelta or 7.5) and speed >= (noclip.MinSpeedKmh or 35) and current.heightAboveGround >= (noclip.MinHeight or 5.0) and not current.falling and not current.parachuting and not current.swimming then
            if throttle(player.lastFlags, 'noclip_v2', noclip.CooldownMs or 30000) then
                record(src, 'noclip_v2', { coords = current.coords, delta_z = dz, speed = speed, height = current.heightAboveGround, confidence = 0.82 })
            end
        end
    end

    if enabled('network_anomaly') then
        local network = detectorCfg('network_anomaly')
        local ping = tonumber(current.ping) or GetPlayerPing(src) or 0
        if ping >= (network.PingThreshold or 450) or math.abs((current.speed or 0) - (previous.speed or 0)) >= (network.SpeedDeltaKmh or 180) then
            if throttle(player.lastFlags, 'network_anomaly', network.CooldownMs or 45000) then
                record(src, 'network_anomaly', { ping = ping, speed = current.speed, previous_speed = previous.speed, confidence = 0.55 })
            end
        end
    end

    if enabled('behaviour_profile') then
        local behaviour = detectorCfg('behaviour_profile')
        local sampleCount = math.min(#player.telemetry, behaviour.SampleSize or 8)
        local erratic = 0
        for index = 1, sampleCount - 1 do
            local a = player.telemetry[index]
            local b = player.telemetry[index + 1]
            if a and b and math.abs((a.heading or 0) - (b.heading or 0)) >= (behaviour.HeadingSnapDegrees or 135) and (a.speed or 0) >= (behaviour.MinSpeedKmh or 18) then
                erratic = erratic + 1
            end
        end
        if erratic >= (behaviour.ErraticThreshold or 4) and throttle(player.lastFlags, 'behaviour_profile', behaviour.CooldownMs or 60000) then
            record(src, 'behaviour_profile', { erratic_samples = erratic, sample_count = sampleCount, confidence = 0.62 })
        end
    end
end

local function analyzeCombat(src, sample)
    local player = getState(src)
    local now = utils.millis()
    player.lastCombatTelemetryAt = now
    table.insert(player.shots, 1, { ts = now, data = sample })
    prune(player.shots, now, detectorCfg('triggerbot').WindowMs or 5000)
    while #player.shots > 24 do table.remove(player.shots) end

    if enabled('triggerbot') then
        local trigger = detectorCfg('triggerbot')
        local fastLocks = 0
        for _, shot in ipairs(player.shots) do
            local reaction = tonumber(shot.data and shot.data.reactionMs)
            if reaction and reaction <= (trigger.ReactionMs or 90) then
                fastLocks = fastLocks + 1
            end
        end
        if fastLocks >= (trigger.FastLockThreshold or 4) and throttle(player.lastFlags, 'triggerbot', trigger.CooldownMs or 45000) then
            record(src, 'triggerbot', { fast_locks = fastLocks, window = #player.shots, confidence = 0.78 })
        end
    end

    if enabled('aim_entropy_signature') then
        local entropy = detectorCfg('aim_entropy_signature')
        local reactions = {}
        local snaps = {}
        local eligible = 0
        for _, shot in ipairs(player.shots) do
            local data = shot.data or {}
            local reaction = tonumber(data.reactionMs)
            local snap = tonumber(data.snapAngle)
            if reaction and reaction <= (tonumber(entropy.MaxReactionMs) or 115) and snap then
                reactions[#reactions + 1] = reaction
                snaps[#snaps + 1] = snap
                eligible = eligible + 1
            end
        end
        local sampleThreshold = tonumber(entropy.SampleThreshold) or 7
        if eligible >= sampleThreshold then
            local reactionVariance = variance(reactions)
            local snapVariance = variance(snaps)
            if reactionVariance <= (tonumber(entropy.ReactionVarianceMs) or 18) and snapVariance <= (tonumber(entropy.SnapVarianceDegrees) or 2.4) then
                if throttle(player.lastFlags, 'aim_entropy_signature', entropy.CooldownMs or 45000) then
                    record(src, 'aim_entropy_signature', {
                        samples = eligible,
                        reaction_variance = utils.round(reactionVariance, 2),
                        snap_variance = utils.round(snapVariance, 2),
                        confidence = eligible >= sampleThreshold + 2 and 0.84 or 0.72,
                    })
                end
            end
        end
    end

    if enabled('silent_aim') and sample.headshot and sample.visible == false and sample.distance and sample.distance >= (detectorCfg('silent_aim').MinDistance or 70.0) then
        if throttle(player.lastFlags, 'silent_aim', detectorCfg('silent_aim').CooldownMs or 45000) then
            record(src, 'silent_aim', { distance = sample.distance, weapon = sample.weapon, confidence = 0.76 })
        end
    end

    if enabled('aim_assist') and sample.snapAngle and sample.snapAngle >= (detectorCfg('aim_assist').SnapAngle or 42) and sample.lockTimeMs and sample.lockTimeMs <= (detectorCfg('aim_assist').LockTimeMs or 160) then
        if throttle(player.lastFlags, 'aim_assist', detectorCfg('aim_assist').CooldownMs or 45000) then
            record(src, 'aim_assist', { snap_angle = sample.snapAngle, lock_time_ms = sample.lockTimeMs, confidence = 0.68 })
        end
    end
end


local function analyzeServerMovementSample(src, now)
    if not enabled('server_movement_signature') then return end
    if cfg().IgnoreAdmins ~= false and utils.isAdmin(src) then return end

    local movement = detectorCfg('server_movement_signature')
    local player = getState(src)
    if (now - (player.joinedAt or now)) < (tonumber(movement.IgnoreAfterJoinMs) or 25000) then
        return
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end

    local coords = safeEntityCoords(ped)
    if not coords then return end

    local sample = {
        ts = now,
        coords = coords,
        speed = safeEntitySpeedKmh(ped),
        vehicle = safeVehicleForPed(ped),
        bucket = safeRoutingBucket(src),
    }

    table.insert(player.serverSamples, 1, sample)
    while #player.serverSamples > 6 do table.remove(player.serverSamples) end

    local previous = player.serverSamples[2]
    if not previous or not previous.coords then return end
    if previous.bucket ~= sample.bucket then return end

    local elapsed = math.max(0.25, (now - (previous.ts or now)) / 1000)
    local travelled = distance(sample.coords, previous.coords)
    local computedSpeed = (travelled / elapsed) * 3.6
    local nativeSpeed = tonumber(sample.speed) or computedSpeed
    local speed = math.max(computedSpeed, nativeSpeed)
    local dz = math.abs((sample.coords.z or 0.0) - (previous.coords.z or 0.0))
    local inVehicle = sample.vehicle and sample.vehicle ~= 0

    local maxSpeed = inVehicle and (tonumber(movement.MaxVehicleKmh) or 520.0) or (tonumber(movement.MaxOnFootKmh) or 135.0)
    local teleportDistance = tonumber(movement.TeleportDistance) or 180.0
    local verticalDelta = tonumber(movement.VerticalDelta) or 18.0
    local suspicious = false
    local reason = nil

    if travelled >= teleportDistance and computedSpeed >= maxSpeed then
        suspicious = true
        reason = 'teleport_distance'
    elseif speed >= maxSpeed and travelled >= (inVehicle and 80.0 or 28.0) then
        suspicious = true
        reason = 'impossible_speed'
    elseif not inVehicle and dz >= verticalDelta and travelled >= 12.0 and computedSpeed >= 45.0 then
        suspicious = true
        reason = 'vertical_clip'
    end

    if not suspicious then return end

    local strikes = addStrike(player, 'server_movement_signature', now, movement.StrikeWindowMs or 18000)
    if strikes >= (tonumber(movement.StrikeThreshold) or 2) and throttle(player.lastFlags, 'server_movement_signature', movement.CooldownMs or 35000) then
        record(src, 'server_movement_signature', {
            reason = reason,
            strikes = strikes,
            distance = utils.round(travelled, 2),
            speed = utils.round(speed, 1),
            computed_speed = utils.round(computedSpeed, 1),
            native_speed = sample.speed and utils.round(sample.speed, 1) or nil,
            vertical_delta = utils.round(dz, 2),
            in_vehicle = inVehicle,
            bucket = sample.bucket,
            coords = sample.coords,
            previous_coords = previous.coords,
            confidence = strikes >= 3 and 0.86 or 0.74,
        })
    end
end

local function ensureServerMovementThread()
    if not enabled('server_movement_signature') then return end
    local movement = detectorCfg('server_movement_signature')
    local perf = Config.Performance or {}
    local defaultInterval = perf.ZeroFootprint ~= false and 15000 or 2500
    local interval = math.max(defaultInterval, tonumber(movement.IntervalMs) or defaultInterval)
    CreateThread(function()
        while true do
            Wait(interval)
            if enabled('server_movement_signature') then
                local now = utils.millis()
                for _, player in ipairs(GetPlayers()) do
                    local src = tonumber(player)
                    if src then
                        analyzeServerMovementSample(src, now)
                    end
                end
            end
        end
    end)
end

local function handleWeaponDamageEvent(sender, data)
    local src = tonumber(sender)
    if not src or src <= 0 or (not enabled('combat_without_lineage') and not enabled('damage_rate_signature')) then return end
    if cfg().IgnoreAdmins ~= false and utils.isAdmin(src) then return end

    local player = getState(src)
    local now = utils.millis()
    local lineage = detectorCfg('combat_without_lineage')
    local missingMs = tonumber(lineage.MissingCombatTelemetryMs) or 2200
    local lastCombat = tonumber(player.lastCombatTelemetryAt) or 0

    if enabled('damage_rate_signature') then
        local rate = detectorCfg('damage_rate_signature')
        player.damageEvents = type(player.damageEvents) == 'table' and player.damageEvents or {}
        local payload = type(data) == 'table' and data or {}
        local damage = tonumber(payload.weaponDamage or payload.damage or payload.damageAmount) or 0
        local event = {
            ts = now,
            damage = damage,
            weapon = payload.weaponType,
            willKill = payload.willKill == true,
            victim = payload.hitGlobalId or payload.hitEntity or payload.victim,
        }
        player.damageEvents[#player.damageEvents + 1] = event
        prune(player.damageEvents, now, rate.WindowMs or 2200)
        local hits = #player.damageEvents
        local totalDamage = 0
        local kills = 0
        for _, item in ipairs(player.damageEvents) do
            totalDamage = totalDamage + (tonumber(item.damage) or 0)
            if item.willKill then kills = kills + 1 end
        end
        local hitThreshold = tonumber(rate.HitThreshold) or 7
        local damageThreshold = tonumber(rate.DamageThreshold) or 520
        local killThreshold = tonumber(rate.KillThreshold) or 3
        if hits >= hitThreshold or totalDamage >= damageThreshold or kills >= killThreshold then
            if throttle(player.lastFlags, 'damage_rate_signature', rate.CooldownMs or 35000) then
                record(src, 'damage_rate_signature', {
                    hits = hits,
                    total_damage = totalDamage,
                    kills = kills,
                    window_ms = rate.WindowMs or 2200,
                    weapon_type = payload.weaponType,
                    confidence = (hits >= hitThreshold and totalDamage >= damageThreshold) and 0.86 or 0.72,
                })
            end
        end
    end

    if not enabled('combat_without_lineage') then
        return
    end

    if lastCombat > 0 and (now - lastCombat) <= missingMs then
        return
    end

    local strikes = addStrike(player, 'combat_without_lineage', now, lineage.WindowMs or 6500)
    if strikes >= (tonumber(lineage.StrikeThreshold) or 3) and throttle(player.lastFlags, 'combat_without_lineage', lineage.CooldownMs or 45000) then
        local payload = type(data) == 'table' and data or {}
        record(src, 'combat_without_lineage', {
            strikes = strikes,
            last_combat_telemetry_ms = lastCombat > 0 and (now - lastCombat) or nil,
            weapon_type = payload.weaponType,
            weapon_damage = payload.weaponDamage,
            hit_global_id = payload.hitGlobalId,
            will_kill = payload.willKill == true,
            confidence = lastCombat == 0 and 0.72 or 0.82,
        })
    end
end

function module:recordCameraProbe(src, payload)
    src = tonumber(src)
    if not src or src <= 0 or not enabled('freecam_pov_mismatch') then return end
    if cfg().IgnoreAdmins ~= false and utils.isAdmin(src) then return end

    local probe = detectorCfg('freecam_pov_mismatch')
    payload = type(payload) == 'table' and payload or {}
    local player = getState(src)
    local now = utils.millis()
    local strikes = addStrike(player, 'freecam_pov_mismatch', now, probe.StrikeWindowMs or 18000)
    if strikes >= (tonumber(probe.StrikeThreshold) or 2) and throttle(player.lastFlags, 'freecam_pov_mismatch', probe.CooldownMs or 45000) then
        payload.strikes = strikes
        payload.confidence = strikes >= 3 and 0.84 or 0.72
        record(src, 'freecam_pov_mismatch', payload)
    end
end

local function bumpCounter(bucket, key, window)
    if type(bucket) ~= 'table' then
        return 0
    end

    local now = utils.millis()
    if type(bucket[key]) ~= 'table' then
        bucket[key] = {}
    end
    local list = bucket[key]
    list[#list + 1] = now
    prune(list, now, window)
    return #list
end

function module:init()
    if started then return end
    started = true
    zVS.detectionFramework = module

    RegisterNetEvent('zvs-ac:detections:telemetry', function(sample)
        local src = source
        if type(sample) ~= 'table' then return end
        analyzeTelemetry(src, sample)
    end)

    RegisterNetEvent('zvs-ac:detections:combat', function(sample)
        local src = source
        if type(sample) ~= 'table' then return end
        analyzeCombat(src, sample)
    end)

    RegisterNetEvent('zvs-ac:detections:resourceState', function(payload)
        local src = source
        if not enabled('resource_tampering') or type(payload) ~= 'table' then return end
        local player = getState(src)
        local resource = tostring(payload.resource or 'unknown')
        local previous = player.resources[resource]
        player.resources[resource] = payload.state
        if previous and previous ~= payload.state and payload.state ~= 'started' then
            if throttle(player.lastFlags, 'resource_tampering:' .. resource, detectorCfg('resource_tampering').CooldownMs or 60000) then
                record(src, 'resource_tampering', { resource = resource, previous = previous, current = payload.state, confidence = 0.85 })
            end
        end
    end)

    AddEventHandler('entityCreated', function(entity)
        local owner = NetworkGetEntityOwner and NetworkGetEntityOwner(entity) or nil
        local src = tonumber(owner)
        if not src or src <= 0 then return end
        local entityType = GetEntityType(entity)
        local detection = entityType == 2 and 'vehicle_spawn_abuse_v2' or 'entity_spam'
        if not enabled(detection) then return end
        local settings = detectorCfg(detection)
        local count = bumpCounter(entityType == 2 and globalCounters.vehicles or globalCounters.entities, src, settings.WindowMs or 10000)
        if count >= (settings.Threshold or (entityType == 2 and 8 or 18)) then
            local player = getState(src)
            if throttle(player.lastFlags, detection, settings.CooldownMs or 30000) then
                record(src, detection, { entity_type = entityType, count = count, window_ms = settings.WindowMs or 10000, confidence = 0.74 })
            end
        end
    end)

    ensureServerMovementThread()

    AddEventHandler('weaponDamageEvent', function(sender, data)
        handleWeaponDamageEvent(sender, data)
    end)

    AddEventHandler('__cfx_internal:serverEventTriggered', function(eventName, eventSource)
        local src = tonumber(eventSource)
        if not src or src <= 0 or not enabled('event_flood') then return end
        local settings = detectorCfg('event_flood')
        local count = bumpCounter(globalCounters.events, src, settings.WindowMs or 5000)
        if count >= (settings.Threshold or 45) then
            local player = getState(src)
            if throttle(player.lastFlags, 'event_flood', settings.CooldownMs or 30000) then
                record(src, 'event_flood', { event = eventName, count = count, window_ms = settings.WindowMs or 5000, confidence = 0.73 })
            end
        end
    end)

    AddEventHandler('zvs-ac:internal:playerDropped', function(src)
        state[src] = nil
        globalCounters.events[src] = nil
        globalCounters.entities[src] = nil
        globalCounters.vehicles[src] = nil
    end)
end

if zVS and type(zVS.registerModule) == 'function' then
    return zVS.registerModule('server.modules.detection_framework', module)
end

return module
