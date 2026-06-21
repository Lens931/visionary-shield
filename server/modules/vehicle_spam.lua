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

local function normalizeModel(value)
    if type(value) == 'number' then
        return value
    end
    if type(value) == 'string' and value ~= '' then
        return GetHashKey(value)
    end
    return nil
end

function module:init()
    local cfg = Config.VehicleSpam or {}
    local window = cfg.Window or 10000
    local threshold = cfg.Threshold or 4
    local cooldown = cfg.Cooldown or 5000
    local freeroamWindow = tonumber(cfg.FreeroamWindow) or window
    local freeroamThreshold = tonumber(cfg.FreeroamThreshold) or threshold
    local freeroamCooldown = tonumber(cfg.FreeroamCooldown) or cooldown
    local freeroamModels = utils.buildLookup(cfg.FreeroamModelGrace, normalizeModel)
    local logInterval = cfg.CooldownLogInterval
    if type(logInterval) ~= 'number' then
        logInterval = math.min(cooldown, 2000)
    end
    if logInterval < 0 then
        logInterval = 0
    end

    local history = {}
    local cooldownUntil = {}
    local nextCooldownLog = {}

    local function getBucket(owner)
        local bucket = history[owner]
        if bucket then
            return bucket
        end
        bucket = { cursor = 1, timestamps = {} }
        history[owner] = bucket
        return bucket
    end

    local function pruneBucket(bucket, now, activeWindow)
        local kept = {}
        local count = 0
        for _, ts in ipairs(bucket.timestamps) do
            if now - ts <= activeWindow then
                count = count + 1
                kept[count] = ts
            end
        end
        bucket.timestamps = kept
        if bucket.cursor > count + 1 then
            bucket.cursor = count + 1
        end
        return count
    end

    AddEventHandler('zvs-ac:internal:playerDropped', function(src)
        history[src] = nil
        cooldownUntil[src] = nil
        nextCooldownLog[src] = nil
    end)

    AddEventHandler('entityCreating', function(entity)
        if zVS.adminTools and type(zVS.adminTools.isDefenseEnabled) == 'function' and not zVS.adminTools.isDefenseEnabled('vehicle_spam') then
            return
        end
        if not DoesEntityExist(entity) then return end
        if GetEntityType(entity) ~= 2 then return end
        local owner = NetworkGetEntityOwner(entity)
        if not owner or owner == 0 then return end
        if utils.isAdmin(owner) then return end
        if zVS.adminTools and type(zVS.adminTools.isRealtimeSpawnProtectionEnabledFor) == 'function' then
            if not zVS.adminTools.isRealtimeSpawnProtectionEnabledFor(owner) then
                return
            end
        end

        local model = GetEntityModel(entity)
        local isFreeroamModel = freeroamModels[model] == true
        local activeWindow = isFreeroamModel and freeroamWindow or window
        local activeThreshold = isFreeroamModel and freeroamThreshold or threshold
        local activeCooldown = isFreeroamModel and freeroamCooldown or cooldown

        local now = GetGameTimer()
        local bucket = getBucket(owner)

        if cooldownUntil[owner] and now < cooldownUntil[owner] then
            local shouldLog = logInterval == 0 or not nextCooldownLog[owner] or now >= nextCooldownLog[owner]
            if shouldLog then
                logger:flag('vehicle_spawn_cooldown', owner, {
                    model = model,
                    ms_remaining = math.max(0, cooldownUntil[owner] - now),
                    cooldown_ms = activeCooldown,
                    freeroam = isFreeroamModel,
                })
                nextCooldownLog[owner] = logInterval > 0 and (now + logInterval) or now
            end
            CancelEvent()
            return
        end

        nextCooldownLog[owner] = nil
        bucket.timestamps[#bucket.timestamps + 1] = now
        local count = pruneBucket(bucket, now, activeWindow)

        if count >= activeThreshold then
            logger:flag('vehicle_spam', owner, {
                model = model,
                within_ms = activeWindow,
                count = count,
                threshold = activeThreshold,
                freeroam = isFreeroamModel,
            })
            history[owner] = nil
            cooldownUntil[owner] = now + activeCooldown
            nextCooldownLog[owner] = nil
            if cfg.CancelOnTrip then
                CancelEvent()
            end
        end
    end)
end

if zVS and type(zVS.registerModule) == 'function' then
    return zVS.registerModule('server.modules.vehicle_spam', module)
end

return module
