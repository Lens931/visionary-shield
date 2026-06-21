zVS = zVS or {}

local utils = zVS.utils
if not utils then
    local ok, mod = pcall(require, 'shared.utils')
    if not ok then
        error(('zVS-AC: unable to load shared utils (%s)'):format(mod))
    end
    utils = mod
end

local logger = zVS.logger
if not logger then
    local ok, mod = pcall(require, 'server.utils.logger')
    if not ok then
        error(('zVS-AC: unable to load server logger (%s)'):format(mod))
    end
    logger = mod
end

local resourceName = GetCurrentResourceName and GetCurrentResourceName() or 'zvs-ac'

local modulePaths = {
    'server.modules.risk_engine',
    'server.modules.detection_framework',
    'server.modules.admin_tools',
    'server.modules.resource_guard',
    'server.modules.heartbeat',
    'server.modules.attachments',
    'server.modules.vehicle_spam',
    'server.modules.spawn_control',
    'server.modules.godmode',
    'server.modules.pvp_headshot',
    'server.modules.damage_monitor',
    'server.modules.monitoring',
}

local moduleLoaders = {}

local function canonicalize(name)
    if type(name) ~= 'string' then
        return nil
    end

    name = name:gsub('\\', '/')

    if name:match('^server/modules/') then
        name = name:gsub('/', '.')
    end

    if name:match('^server%.modules%.') then
        return name
    end

    if not name:find('.', 1, true) then
        return 'server.modules.' .. name
    end

    return name
end

local function resolveModule(path)
    local canonical = canonicalize(path)
    if not canonical then
        return nil, 'invalid_module_path'
    end

    local loader = nil

    if type(zVS.getModule) == 'function' then
        loader = zVS.getModule(canonical) or zVS.getModule(path)
    end

    if loader ~= nil then
        return loader
    end

    local ok, result = pcall(require, canonical)
    if not ok then
        return nil, result
    end

    if result == nil then
        result = true
    end

    if type(zVS.registerModule) == 'function' then
        loader = zVS.registerModule(canonical, result)
    else
        loader = result
    end

    return loader
end

local function rebuildModuleLoaders()
    local missing = {}
    moduleLoaders = {}

    for _, path in ipairs(modulePaths) do
        local loader, reason = resolveModule(path)
        if loader ~= nil then
            moduleLoaders[#moduleLoaders + 1] = loader
        else
            missing[#missing + 1] = { path = path, reason = reason }
        end
    end

    if #missing > 0 then
        for _, entry in ipairs(missing) do
            utils.debugLog(('zVS-AC: module %s indisponible (%s)'):format(entry.path, tostring(entry.reason)))
        end
    end
end

local function initModule(loader)
    if type(loader) == 'table' and type(loader.init) == 'function' then
        loader:init()
    elseif type(loader) == 'function' then
        loader()
    end
end

local function startModules()
    rebuildModuleLoaders()
    utils.debugLog('Starting Visionary Anti-Cheat modules')
    for _, loader in ipairs(moduleLoaders) do
        initModule(loader)
    end
end

AddEventHandler('onResourceStart', function(resource)
    if resource ~= resourceName then
        return
    end
    startModules()
end)

if GetResourceState and resourceName and GetResourceState(resourceName) == 'started' then
    startModules()
end

AddEventHandler('playerDropped', function()
    TriggerEvent('zvs-ac:internal:playerDropped', source)
end)

exports('getModule', function(name)
    if type(zVS.getModule) ~= 'function' then
        return nil
    end
    return zVS.getModule(name)
end)

exports('listModules', function()
    if type(zVS.listRegisteredModules) == 'function' then
        return zVS.listRegisteredModules()
    end
    return {}
end)

return {
    logger = logger,
}
