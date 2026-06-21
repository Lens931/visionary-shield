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

local getModelDimensionsWarned = false
local dimensionCache = {}
local dimensionKeys = {}

local function normalizeModel(value)
    if type(value) == 'number' then
        return value
    end
    if type(value) == 'string' and value ~= '' then
        return GetHashKey(value)
    end
    return nil
end

local function trimDimensionCache(limit)
    while #dimensionKeys > limit do
        local oldest = table.remove(dimensionKeys, 1)
        dimensionCache[oldest] = nil
    end
end

local function getModelDimensions(model)
    if type(GetModelDimensions) == 'function' then
        return GetModelDimensions(model)
    end

    if not Citizen or type(Citizen.InvokeNative) ~= 'function' or not Citizen.PointerValueVector3 or type(vector3) ~= 'function' then
        if not getModelDimensionsWarned then
            utils.debugLog('spawn_control: GetModelDimensions native unavailable, heavy spawn checks disabled')
            getModelDimensionsWarned = true
        end
        return nil, nil
    end

    local ok, minDim, maxDim = pcall(function()
        local minVec = vector3(0.0, 0.0, 0.0)
        local maxVec = vector3(0.0, 0.0, 0.0)
        Citizen.InvokeNative(0xC16DE94D9BEA14A0, model, Citizen.PointerValueVector3(minVec), Citizen.PointerValueVector3(maxVec))
        return minVec, maxVec
    end)

    if not ok then
        if not getModelDimensionsWarned then
            utils.debugLog(('spawn_control: failed to query model dimensions (%s)'):format(minDim))
            getModelDimensionsWarned = true
        end
        return nil, nil
    end

    return minDim, maxDim
end

local function calculateDiagonal(model, cfg)
    if cfg.CacheModelDimensions ~= false then
        local cached = dimensionCache[model]
        if cached ~= nil then
            return cached
        end
    end

    local minDim, maxDim = getModelDimensions(model)
    if not minDim or not maxDim then
        return 0.0
    end
    local dx = maxDim.x - minDim.x
    local dy = maxDim.y - minDim.y
    local dz = maxDim.z - minDim.z
    local diagonal = math.sqrt(dx * dx + dy * dy + dz * dz)

    if cfg.CacheModelDimensions ~= false then
        dimensionCache[model] = diagonal
        dimensionKeys[#dimensionKeys + 1] = model
        trimDimensionCache(math.max(64, tonumber(cfg.DimensionCacheSize) or 512))
    end

    return diagonal
end

function module:init()
    local cfg = Config.SpawnAbuse or {}
    local heavyThreshold = cfg.HeavyDimensionThreshold or 5.0
    local vehicleCooldown = cfg.VehicleCooldown or 5000
    local objectCooldown = cfg.ObjectCooldown or 8000
    local freeroamVehicleCooldown = tonumber(cfg.FreeroamVehicleCooldown) or vehicleCooldown
    local freeroamObjectCooldown = tonumber(cfg.FreeroamObjectCooldown) or objectCooldown
    local cleanupInterval = math.max(5000, tonumber(cfg.CleanupIntervalMs) or 60000)
    local stateTtl = math.max(cleanupInterval, tonumber(cfg.PlayerStateTtlMs) or 180000)
    local freeroamModels = utils.buildLookup(cfg.FreeroamModelGrace, normalizeModel)

    local lastVehicleSpawn = {}
    local lastObjectSpawn = {}
    local playerTouchedAt = {}

    local function touchPlayer(owner, now)
        playerTouchedAt[owner] = now
    end

    local function resolveCooldown(entityType, isFreeroam)
        if entityType == 2 then
            return isFreeroam and freeroamVehicleCooldown or vehicleCooldown
        end
        return isFreeroam and freeroamObjectCooldown or objectCooldown
    end

    CreateThread(function()
        while true do
            Wait(cleanupInterval)
            local now = GetGameTimer()
            for owner, touchedAt in pairs(playerTouchedAt) do
                if now - touchedAt >= stateTtl then
                    playerTouchedAt[owner] = nil
                    lastVehicleSpawn[owner] = nil
                    lastObjectSpawn[owner] = nil
                end
            end
        end
    end)

    AddEventHandler('zvs-ac:internal:playerDropped', function(src)
        lastVehicleSpawn[src] = nil
        lastObjectSpawn[src] = nil
        playerTouchedAt[src] = nil
    end)

    AddEventHandler('entityCreating', function(entity)
        if zVS.adminTools and type(zVS.adminTools.isDefenseEnabled) == 'function' and not zVS.adminTools.isDefenseEnabled('spawn_abuse') then
            return
        end
        if not DoesEntityExist(entity) then return end
        local entityType = GetEntityType(entity)
        if entityType ~= 2 and entityType ~= 3 then return end

        local owner = NetworkGetEntityOwner(entity)
        if not owner or owner == 0 then return end
        if utils.isAdmin(owner) then return end
        if zVS.adminTools and type(zVS.adminTools.isRealtimeSpawnProtectionEnabledFor) == 'function' then
            if not zVS.adminTools.isRealtimeSpawnProtectionEnabledFor(owner) then
                return
            end
        end

        local model = GetEntityModel(entity)
        local now = GetGameTimer()
        touchPlayer(owner, now)

        local diagonal = calculateDiagonal(model, cfg)
        local isHeavy = diagonal >= heavyThreshold
        local isFreeroamModel = freeroamModels[model] == true
        local useFreeroamThreshold = isFreeroamModel or not isHeavy
        local requiredCooldown = resolveCooldown(entityType, useFreeroamThreshold)

        if entityType == 2 then
            local last = lastVehicleSpawn[owner] or 0
            if now - last < requiredCooldown then
                logger:flag('spawn_abuse', owner, {
                    type = useFreeroamThreshold and 'vehicle_freeroam' or 'vehicle',
                    model = model,
                    since_ms = now - last,
                    required_ms = requiredCooldown,
                    size_diag = utils.round(diagonal, 2),
                    freeroam = useFreeroamThreshold,
                })
                CancelEvent()
                return
            end
            lastVehicleSpawn[owner] = now
        elseif entityType == 3 then
            local last = lastObjectSpawn[owner] or 0
            if now - last < requiredCooldown then
                logger:flag('spawn_abuse', owner, {
                    type = useFreeroamThreshold and 'object_freeroam' or 'object',
                    model = model,
                    since_ms = now - last,
                    required_ms = requiredCooldown,
                    size_diag = utils.round(diagonal, 2),
                    freeroam = useFreeroamThreshold,
                })
                CancelEvent()
                return
            end
            lastObjectSpawn[owner] = now
        end
    end)
end

if zVS and type(zVS.registerModule) == 'function' then
    return zVS.registerModule('server.modules.spawn_control', module)
end

return module
