zVS = zVS or {}

local resourceName = GetCurrentResourceName and GetCurrentResourceName() or nil
local resourcePath = resourceName and GetResourcePath and GetResourcePath(resourceName) or nil

if type(package) == 'table' and type(package.path) == 'string' and resourcePath then
    local normalizedPath = resourcePath:gsub('\\', '/')
    local modulePath = normalizedPath .. '/?.lua'
    local initPath = normalizedPath .. '/?/init.lua'

    local function append(path)
        if not package.path:find(path, 1, true) then
            package.path = ('%s;%s'):format(package.path, path)
        end
    end

    append(modulePath)
    append(initPath)
end

local registry = zVS.moduleRegistry or {
    byCanonical = {},
    byAlias = {},
    order = {},
}

zVS.moduleRegistry = registry

local function canonicalize(name)
    if type(name) ~= 'string' or name == '' then
        return nil
    end

    name = name:gsub('\\', '/'):gsub('%.lua$', '')

    if name:match('^server/modules/') then
        name = name:gsub('/', '.')
    end

    if not name:match('^server%.modules%.') then
        if name:find('.', 1, true) then
            return nil
        end
        name = 'server.modules.' .. name
    end

    return name
end

local function registerAlias(alias, loader)
    if alias and alias ~= '' then
        registry.byAlias[alias] = loader
    end
end

local function setPackageLoaded(canonical, loader)
    if type(package) ~= 'table' or type(package.loaded) ~= 'table' then
        return
    end

    package.loaded[canonical] = loader
    package.loaded[canonical:gsub('%.', '/')] = loader
end

function zVS.registerModule(name, loader)
    local canonical = canonicalize(name)
    if not canonical then
        error('zVS-AC: invalid module name provided to registerModule', 2)
    end

    if loader == nil then
        error(('zVS-AC: attempted to register %s with a nil loader'):format(canonical), 2)
    end

    local isFirstRegistration = registry.byCanonical[canonical] == nil
    registry.byCanonical[canonical] = loader

    if isFirstRegistration then
        registry.order[#registry.order + 1] = canonical
    end

    local shortName = canonical:gsub('^server%.modules%.', '')
    registerAlias(shortName, loader)
    registerAlias('server.modules.' .. shortName, loader)
    registerAlias('server/modules/' .. shortName:gsub('%.', '/'), loader)
    registerAlias(canonical, loader)

    setPackageLoaded(canonical, loader)

    return loader
end

function zVS.getModule(name)
    if type(name) ~= 'string' then
        return nil
    end

    local canonical = canonicalize(name)
    if canonical and registry.byCanonical[canonical] then
        return registry.byCanonical[canonical]
    end

    name = name:gsub('\\', '/')
    name = name:gsub('%.lua$', '')

    return registry.byAlias[name]
end

function zVS.iterateRegisteredModules()
    local index = 0
    return function()
        index = index + 1
        local canonical = registry.order[index]
        if not canonical then
            return nil
        end
        return canonical, registry.byCanonical[canonical]
    end
end

function zVS.listRegisteredModules()
    local list = {}
    for _, canonical in ipairs(registry.order) do
        list[#list + 1] = {
            name = canonical,
            loader = registry.byCanonical[canonical],
        }
    end
    return list
end

return zVS
