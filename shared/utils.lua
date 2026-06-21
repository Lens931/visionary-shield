zVS = zVS or {}
local Config = zVS.Config or {}

local utils = {}

local BASE64_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local BASE64_LOOKUP = {}
for index = 1, #BASE64_ALPHABET do
    BASE64_LOOKUP[BASE64_ALPHABET:sub(index, index)] = index - 1
end

if IsDuplicityVersion and IsDuplicityVersion() then
    local resourceName = GetCurrentResourceName and GetCurrentResourceName()
    local resourcePath = resourceName and GetResourcePath(resourceName)
    if type(package) == 'table' and type(package.path) == 'string' and resourcePath then
        resourcePath = resourcePath:gsub('\\', '/')
        local searchPath = table.concat({
            resourcePath .. '/?.lua',
            resourcePath .. '/?/init.lua'
        }, ';')
        if not package.path:find(resourcePath, 1, true) then
            package.path = ('%s;%s'):format(package.path, searchPath)
        end
    end
end

local adminLookup = nil

local function buildAdminLookup()
    adminLookup = {}
    for _, identifier in ipairs(Config.AdminIdentifiers or {}) do
        if type(identifier) == 'string' then
            adminLookup[identifier:lower()] = true
        end
    end
end

function utils.isAdmin(source)
    if not Config.AdminBypass then
        return false
    end
    if adminLookup == nil then
        buildAdminLookup()
    end
    local identifiers = GetPlayerIdentifiers and GetPlayerIdentifiers(source) or {}
    for _, id in ipairs(identifiers) do
        if type(id) == 'string' and adminLookup[id:lower()] then
            return true
        end
    end
    return false
end

function utils.debugLog(...)
    if Config.EnableDebug then
        print('[zvs-ac:debug]', ...)
    end
end

function utils.iso8601(now)
    local ts = now and math.floor(now / 1000) or os.time()
    return os.date('!%Y-%m-%dT%H:%M:%SZ', ts)
end

function utils.copyTable(tbl)
    if type(tbl) ~= 'table' then return tbl end
    local out = {}
    for k, v in pairs(tbl) do
        if type(v) == 'table' then
            out[k] = utils.copyTable(v)
        else
            out[k] = v
        end
    end
    return out
end

function utils.round(value, decimals)
    if type(value) ~= 'number' then return value end
    local precision = 10 ^ (decimals or 0)
    return math.floor(value * precision + 0.5) / precision
end

function utils.buildLookup(list, transformer)
    local map = {}
    for _, value in ipairs(list or {}) do
        if transformer then
            value = transformer(value)
        end
        if value ~= nil then
            map[value] = true
        end
    end
    return map
end

function utils.hex(hash)
    if type(hash) ~= 'number' then
        return tostring(hash)
    end
    if hash < 0 and _VERSION == 'Lua 5.4' then
        hash = hash & 0xFFFFFFFF
    elseif hash < 0 then
        hash = hash + 0x100000000
    end
    return ('0x%08X'):format(hash)
end

function utils.randomId(prefix)
    local id = ('%04x%04x'):format(math.random(0, 0xffff), math.random(0, 0xffff))
    if prefix then
        return prefix .. id
    end
    return id
end

function utils.encodeBase64(data)
    if type(data) ~= 'string' then
        return nil, 'invalid_type'
    end

    local length = #data
    if length == 0 then
        return ''
    end

    local output = {}
    local index = 1

    while index <= length do
        local a = data:byte(index) or 0
        local b = data:byte(index + 1)
        local c = data:byte(index + 2)

        local hasB = b ~= nil
        local hasC = c ~= nil

        b = b or 0
        c = c or 0

        local combined = (a * 65536) + (b * 256) + c

        local first = math.floor(combined / 262144) % 64
        local second = math.floor(combined / 4096) % 64
        local third = math.floor(combined / 64) % 64
        local fourth = combined % 64

        output[#output + 1] = BASE64_ALPHABET:sub(first + 1, first + 1)
        output[#output + 1] = BASE64_ALPHABET:sub(second + 1, second + 1)

        if hasB then
            output[#output + 1] = BASE64_ALPHABET:sub(third + 1, third + 1)
        else
            output[#output + 1] = '='
        end

        if hasC then
            output[#output + 1] = BASE64_ALPHABET:sub(fourth + 1, fourth + 1)
        else
            output[#output + 1] = '='
        end

        index = index + 3
    end

    return table.concat(output)
end

function utils.decodeBase64(data)
    if type(data) ~= 'string' then
        return nil, 'invalid_type'
    end
    local sanitized = data:gsub('%s+', ''):gsub('%-', '+'):gsub('_', '/')
    local length = #sanitized
    if length == 0 or length % 4 ~= 0 then
        return nil, 'invalid_length'
    end

    local output = {}
    for index = 1, length, 4 do
        local aChar = sanitized:sub(index, index)
        local bChar = sanitized:sub(index + 1, index + 1)
        local cChar = sanitized:sub(index + 2, index + 2)
        local dChar = sanitized:sub(index + 3, index + 3)

        local a = BASE64_LOOKUP[aChar]
        local b = BASE64_LOOKUP[bChar]

        if a == nil or b == nil then
            return nil, 'invalid_character'
        end

        local c = cChar ~= '=' and BASE64_LOOKUP[cChar] or nil
        local d = dChar ~= '=' and BASE64_LOOKUP[dChar] or nil

        if (cChar ~= '=' and c == nil) or (dChar ~= '=' and d == nil) then
            return nil, 'invalid_character'
        end

        local combined = (a * 262144) + (b * 4096)
        if c then
            combined = combined + (c * 64)
            if d then
                combined = combined + d
            end
        end

        local firstByte = math.floor(combined / 65536) % 256
        local secondByte = math.floor(combined / 256) % 256
        local thirdByte = combined % 256

        output[#output + 1] = string.char(firstByte)
        if cChar ~= '=' then
            output[#output + 1] = string.char(secondByte)
            if dChar ~= '=' then
                output[#output + 1] = string.char(thirdByte)
            end
        end
    end

    return table.concat(output)
end

function utils.parseDataUrl(dataUrl)
    if type(dataUrl) ~= 'string' then
        return nil, nil
    end

    local trimmed = dataUrl:match('^%s*(.-)%s*$')
    if not trimmed or trimmed == '' then
        return nil, nil
    end

    local lowered = trimmed:lower()
    if lowered:sub(1, 5) ~= 'data:' then
        return nil, trimmed
    end

    local base64Marker = ';base64,'
    local markerIndex = lowered:find(base64Marker, 1, true)
    if not markerIndex then
        return nil, trimmed
    end

    local mime = trimmed:sub(6, markerIndex - 1)
    local payload = trimmed:sub(markerIndex + #base64Marker)
    return mime, payload
end

function utils.buildMultipartFormData(parts)
    if type(parts) ~= 'table' then
        return nil, nil
    end

    local boundary = ('----zvsac-%s-%s'):format(os.time(), utils.randomId())
    local buffer = {}

    for _, part in ipairs(parts) do
        if type(part) == 'table' and part.name then
            buffer[#buffer + 1] = ('--%s\r\n'):format(boundary)
            local disposition = ('Content-Disposition: form-data; name="%s"'):format(part.name)
            if part.filename then
                disposition = disposition .. ('; filename="%s"'):format(part.filename)
            end
            buffer[#buffer + 1] = disposition .. '\r\n'
            if part.contentType then
                buffer[#buffer + 1] = ('Content-Type: %s\r\n'):format(part.contentType)
            end
            buffer[#buffer + 1] = '\r\n'
            buffer[#buffer + 1] = part.data or ''
            buffer[#buffer + 1] = '\r\n'
        end
    end

    buffer[#buffer + 1] = ('--%s--\r\n'):format(boundary)

    return table.concat(buffer), boundary
end

function utils.millis()
    if type(GetGameTimer) == 'function' then
        return GetGameTimer()
    end
    return os.time() * 1000
end

zVS.utils = utils

if type(package) == 'table' and type(package.loaded) == 'table' then
    package.loaded['shared.utils'] = utils
    package.loaded['shared/utils'] = utils
end

return utils
