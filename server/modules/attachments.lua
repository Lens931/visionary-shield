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

local isEntityAttachedWarned = false

local function isEntityAttachedSafe(entity)
    if type(IsEntityAttached) == 'function' then
        return IsEntityAttached(entity)
    end

    if not Citizen or type(Citizen.InvokeNative) ~= 'function' then
        if not isEntityAttachedWarned then
            utils.debugLog('attachments: IsEntityAttached native unavailable, attachment audit disabled')
            isEntityAttachedWarned = true
        end
        return false
    end

    local ok, resultOrErr = pcall(Citizen.InvokeNative, 0xEE5C8230FC682A52, entity)
    if not ok then
        if not isEntityAttachedWarned then
            utils.debugLog(('attachments: failed to query attachment state (%s)'):format(resultOrErr))
            isEntityAttachedWarned = true
        end
        return false
    end

    return resultOrErr and resultOrErr ~= 0
end

local function buildIgnoreSet(models)
    local set = {}
    for _, hash in ipairs(models or {}) do
        set[tonumber(hash)] = true
    end
    return set
end

local function entityTypeName(entityType)
    if entityType == 1 then return 'ped' end
    if entityType == 2 then return 'vehicle' end
    if entityType == 3 then return 'object' end
    return 'unknown'
end

function module:init()
    local cfg = Config.AttachmentsAudit or {}
    if not cfg.Enabled then
        return
    end

    local ignoreSet = buildIgnoreSet(cfg.IgnoreModels)

    AddEventHandler('entityCreated', function(entity)
        if zVS.adminTools and type(zVS.adminTools.isDefenseEnabled) == 'function' and not zVS.adminTools.isDefenseEnabled('attachments_audit') then
            return
        end
        if not entity or entity == 0 then return end
        CreateThread(function()
            Wait(0)
            if not DoesEntityExist(entity) then return end
            if not isEntityAttachedSafe(entity) then return end

            local owner = NetworkGetEntityOwner(entity)
            if not owner or owner == 0 then return end
            if utils.isAdmin(owner) then return end

            local model = GetEntityModel(entity)
            if ignoreSet[model] then return end

            local entityType = GetEntityType(entity)
            if entityType == 3 and not cfg.LogAttachedObjects then return end
            if entityType == 2 and not cfg.LogAttachedVehicles then return end

            local attachedTo = GetEntityAttachedTo(entity)
            local attachedType = attachedTo ~= 0 and GetEntityType(attachedTo) or 0
            local coords = GetEntityCoords(entity)

            logger:flag('attachments_audit', owner, {
                entity_type = entityTypeName(entityType),
                model = model,
                attached_to_type = entityTypeName(attachedType),
                attached_to_net = NetworkGetNetworkIdFromEntity(attachedTo),
                pos = { utils.round(coords.x, 2), utils.round(coords.y, 2), utils.round(coords.z, 2) }
            })
        end)
    end)
end

if zVS and type(zVS.registerModule) == 'function' then
    return zVS.registerModule('server.modules.attachments', module)
end

return module
