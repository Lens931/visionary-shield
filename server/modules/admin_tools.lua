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
local handlers = {}

local ensureAdmin

local cfg = nil
local modCfg = {}
local defenseCfg = {}
local defenseStates = {}
local suspiciousFeed = {}
local suspiciousFeedFile = 'data/suspicious_feed.json'
local feedSaveScheduled = false
local stateBroadcastScheduled = false
local previewPortraitRequests = {}
local previewPortraitLastRequest = {}
local previewDetectionState = {
    highSpeed = {},
    invincible = {},
    excessHealth = {},
    highSpeedVehicle = {},
    excessArmor = {},
    invisible = {},
    teleport = {},
    airwalk = {},
    speedBurst = {},
    suddenAscent = {},
    spectatorAbuse = {},
    lastSnapshots = {},
}
local feedLimit = 40
local bans = {}
local banIndexById = {}
local pendingScreenshots = {}
local resourceName = GetCurrentResourceName()
local frozenPlayers = {}
local spectateSessions = {}
local spectateTargetWatchers = {}
local spectateSyncCache = {}
local spectateSyncThrottle = {}
local spectateCameraProbeThrottle = {}
local cloakedAdmins = {}
local weaponLocks = {}
local screenshotHistory = {}
local screenshotHistoryLimit = 8
local detectionScreenshotCooldowns = {}
local moderationNotes = {}
local moderationNotesLimit = 60
local spawnProtectionTargets = {}
local spawnProtectionTargetsByIdentifier = {}
local spawnProtectionTargetsFile = 'data/spawn_protection_targets.json'
local livePreviewSessions = {}
local livePreviewSupport = { checked = false, available = false, reason = nil }
local CLEAR_AREA_DEFAULT_RADIUS = 500.0
local defaultAppearanceSettings = {
    opacity = 0.88,
    baseColor = '#0c1428',
    accentColor = '#7fb0ff',
    consoleOpacity = 0.9,
    consolePanelOpacity = 0.94,
    consoleBackdropOpacity = 0.75,
    consoleBlur = 12,
    consoleBaseColor = '#080e1c',
    consoleAccentColor = '#7fb0ff',
    language = 'en',
    layout = {
        console = {},
        inspector = {
            locked = false,
        },
    },
}

local APPEARANCE_STORAGE_VERSION = 2
local appearanceProfiles = {}
local fallbackAppearanceSettings = utils.copyTable(defaultAppearanceSettings)


-- Production V1.1: per-admin UI/settings persistence.
local AdminSettings = {}
local getAdminAppearanceKey

do
    local VERSION = 1
    local cache = {}
    local dirty = {}
    local timers = {}

    local function cfgSettings()
        local adminCfg = cfg or (Config.AdminTools or {})
        return type(adminCfg.AdminSettings) == 'table' and adminCfg.AdminSettings or {}
    end

    local function sanitizeIdentifier(identifier)
        local value = tostring(identifier or 'unknown'):lower()
        value = value:gsub('[^%w_%-%.:]', '_'):gsub(':', '_')
        if #value > 96 then value = value:sub(1, 96) end
        if value == '' then value = 'unknown' end
        return value
    end

    function AdminSettings.identifier(src)
        if not getAdminAppearanceKey then return nil end
        return getAdminAppearanceKey(src)
    end

    local function fileFor(srcOrIdentifier)
        local settingsCfg = cfgSettings()
        local basePath = type(settingsCfg.StoragePath) == 'string' and settingsCfg.StoragePath ~= '' and settingsCfg.StoragePath or 'data/admin_settings'
        local identifier = srcOrIdentifier
        if type(srcOrIdentifier) == 'number' or tostring(srcOrIdentifier):match('^%d+$') then
            identifier = AdminSettings.identifier(tonumber(srcOrIdentifier))
        end
        return ('%s/%s.json'):format(basePath, sanitizeIdentifier(identifier))
    end

    local function defaults()
        local settingsCfg = cfgSettings()
        local configured = type(settingsCfg.Default) == 'table' and settingsCfg.Default or {}
        local fallback = {
            version = VERSION,
            ui = { theme = 'visionary_dark', scale = 1.0, compactMode = true, animations = true, soundFeedback = false },
            windows = {
                main = { x = 72, y = 54, width = 980, height = 610, opacity = 0.94, locked = false, minimized = false, maximized = false, visible = true },
                playerInspector = { x = 1070, y = 108, width = 336, height = 340, opacity = 0.92, locked = false, minimized = false, maximized = false, visible = false },
                spectateInfo = { x = 72, y = 690, width = 390, height = 178, opacity = 0.92, locked = false, minimized = false, maximized = false, visible = false },
                settings = { x = 140, y = 110, width = 520, height = 500, opacity = 0.94, locked = false, minimized = false, maximized = false, visible = false },
                adminDock = { x = 18, y = 230, width = 46, height = 210, opacity = 0.90, locked = false, minimized = false, maximized = false, visible = false },
            },
            spectate = { defaultMode = 'pov', showInfoPanel = true, updateIntervalMs = 1000, closeSpectateWithPanel = false },
            notifications = { discordLogLevel = 'normal', showLocalToasts = true, soundFeedback = false },
            binds = { openPanel = tostring((cfg and cfg.ToggleKey) or 'F5') },
            dock = { enabled = false },
            tabs = { main = 'overview', right = 'alerts' },
        }
        local merged = utils.copyTable(fallback)
        local function deepMerge(dst, src)
            if type(src) ~= 'table' then return end
            for k, v in pairs(src) do
                if type(v) == 'table' and type(dst[k]) == 'table' then
                    deepMerge(dst[k], v)
                else
                    dst[k] = utils.copyTable(v)
                end
            end
        end
        deepMerge(merged, configured)
        merged.version = VERSION
        return merged
    end

    local function clampInt(value, minValue, maxValue, fallback)
        local n = tonumber(value)
        if not n then return fallback end
        n = math.floor(n + 0.5)
        if n < minValue then n = minValue end
        if n > maxValue then n = maxValue end
        return n
    end

    local function clampFloat(value, minValue, maxValue, fallback)
        local n = tonumber(value)
        if not n then return fallback end
        if n < minValue then n = minValue end
        if n > maxValue then n = maxValue end
        return n
    end

    local function normalizeWindow(input, fallback, isMain)
        local base = type(fallback) == 'table' and utils.copyTable(fallback) or {}
        local source = type(input) == 'table' and input or {}
        base.x = clampInt(source.x, -200, 7680, tonumber(base.x) or 120)
        base.y = clampInt(source.y, -200, 4320, tonumber(base.y) or 80)
        base.width = clampInt(source.width, 260, 2200, tonumber(base.width) or 640)
        base.height = clampInt(source.height, 120, 1600, tonumber(base.height) or 360)
        base.locked = source.locked == true
        base.minimized = isMain and false or source.minimized == true
        base.maximized = source.maximized == true
        base.visible = isMain and true or source.visible ~= false
        base.opacity = clampFloat(source.opacity, 0.45, 1.0, tonumber(base.opacity) or 0.95)
        return base
    end

    function AdminSettings.normalize(settings, base)
        local default = defaults()
        local normalized = type(base) == 'table' and utils.copyTable(base) or default
        local source = type(settings) == 'table' and settings or {}
        normalized.version = VERSION

        normalized.ui = type(normalized.ui) == 'table' and normalized.ui or default.ui
        local ui = type(source.ui) == 'table' and source.ui or {}
        local theme = type(ui.theme) == 'string' and ui.theme:sub(1, 40) or normalized.ui.theme
        normalized.ui.theme = theme ~= '' and theme or 'visionary_dark'
        normalized.ui.scale = clampFloat(ui.scale, 0.75, 1.35, tonumber(normalized.ui.scale) or 1.0)
        normalized.ui.compactMode = ui.compactMode ~= nil and ui.compactMode == true or normalized.ui.compactMode == true
        normalized.ui.animations = ui.animations ~= nil and ui.animations == true or normalized.ui.animations == true
        normalized.ui.soundFeedback = ui.soundFeedback == true

        normalized.windows = type(normalized.windows) == 'table' and normalized.windows or default.windows
        local windows = type(source.windows) == 'table' and source.windows or {}
        normalized.windows.main = normalizeWindow(windows.main, normalized.windows.main or default.windows.main, true)
        normalized.windows.playerInspector = normalizeWindow(windows.playerInspector, normalized.windows.playerInspector or default.windows.playerInspector, false)
        normalized.windows.spectateInfo = normalizeWindow(windows.spectateInfo, normalized.windows.spectateInfo or default.windows.spectateInfo, false)
        normalized.windows.settings = normalizeWindow(windows.settings, normalized.windows.settings or default.windows.settings, false)
        normalized.windows.adminDock = normalizeWindow(windows.adminDock, normalized.windows.adminDock or default.windows.adminDock, false)
        -- ImGui Lite server normalization: prevent old oversized/broken layouts from coming back.
        if tonumber(normalized.windows.main.width) and tonumber(normalized.windows.main.width) > 1080 then
            normalized.windows.main.width = default.windows.main.width
            normalized.windows.main.x = default.windows.main.x
            normalized.windows.main.y = default.windows.main.y
        end
        if tonumber(normalized.windows.main.height) and tonumber(normalized.windows.main.height) > 760 then
            normalized.windows.main.height = default.windows.main.height
            normalized.windows.main.x = default.windows.main.x
            normalized.windows.main.y = default.windows.main.y
        end
        normalized.windows.adminDock.width = math.min(math.max(tonumber(normalized.windows.adminDock.width) or 46, 44), 58)
        normalized.windows.adminDock.height = math.min(math.max(tonumber(normalized.windows.adminDock.height) or 210, 150), 380)
        normalized.windows.playerInspector.visible = false
        normalized.windows.spectateInfo.visible = false


        normalized.spectate = type(normalized.spectate) == 'table' and normalized.spectate or default.spectate
        local spectate = type(source.spectate) == 'table' and source.spectate or {}
        local defaultMode = type(spectate.defaultMode) == 'string' and spectate.defaultMode:lower() or normalized.spectate.defaultMode
        if defaultMode ~= 'pov' and defaultMode ~= 'orbit' then defaultMode = 'pov' end
        normalized.spectate.defaultMode = defaultMode
        normalized.spectate.showInfoPanel = spectate.showInfoPanel ~= false
        normalized.spectate.updateIntervalMs = clampInt(spectate.updateIntervalMs, 850, 5000, tonumber(normalized.spectate.updateIntervalMs) or 1000)
        normalized.spectate.closeSpectateWithPanel = spectate.closeSpectateWithPanel == true

        normalized.notifications = type(normalized.notifications) == 'table' and normalized.notifications or default.notifications
        local notifications = type(source.notifications) == 'table' and source.notifications or {}
        local logLevel = type(notifications.discordLogLevel) == 'string' and notifications.discordLogLevel:lower() or normalized.notifications.discordLogLevel
        if logLevel ~= 'quiet' and logLevel ~= 'normal' and logLevel ~= 'verbose' then logLevel = 'normal' end
        normalized.notifications.discordLogLevel = logLevel
        normalized.notifications.showLocalToasts = notifications.showLocalToasts ~= false
        normalized.notifications.soundFeedback = notifications.soundFeedback == true

        normalized.binds = type(normalized.binds) == 'table' and normalized.binds or default.binds
        local binds = type(source.binds) == 'table' and source.binds or {}
        local openPanel = type(binds.openPanel) == 'string' and binds.openPanel:upper():sub(1, 24) or tostring((cfg and cfg.ToggleKey) or 'F5')
        if openPanel == '' then openPanel = tostring((cfg and cfg.ToggleKey) or 'F5') end
        normalized.binds.openPanel = openPanel

        normalized.dock = type(normalized.dock) == 'table' and normalized.dock or { enabled = false }
        local dock = type(source.dock) == 'table' and source.dock or {}
        normalized.dock.enabled = dock.enabled == true

        normalized.tabs = type(normalized.tabs) == 'table' and normalized.tabs or { main = 'overview', right = 'alerts' }
        local tabs = type(source.tabs) == 'table' and source.tabs or {}
        local mainTab = type(tabs.main) == 'string' and tabs.main or normalized.lastTab or normalized.tabs.main or 'overview'
        if mainTab ~= 'overview' and mainTab ~= 'risk' and mainTab ~= 'history' and mainTab ~= 'defenses' then mainTab = 'overview' end
        local rightTab = type(tabs.right) == 'string' and tabs.right or normalized.tabs.right or 'alerts'
        if rightTab ~= 'alerts' and rightTab ~= 'notes' and rightTab ~= 'bans' and rightTab ~= 'damage' then rightTab = 'alerts' end
        normalized.tabs.main = mainTab
        normalized.tabs.right = rightTab
        normalized.lastTab = mainTab

        return normalized
    end

    function AdminSettings.load(src)
        if not src then return defaults() end
        local identifier = AdminSettings.identifier(src)
        if not identifier then return defaults() end
        if cache[identifier] then return utils.copyTable(cache[identifier]) end
        local raw = LoadResourceFile(resourceName, fileFor(identifier))
        local decoded = nil
        if raw and raw ~= '' then
            local ok, result = pcall(json.decode, raw)
            if ok and type(result) == 'table' then decoded = result else utils.debugLog('Admin settings corrupted; using defaults', identifier, result) end
        end
        local normalized = AdminSettings.normalize(decoded, defaults())
        cache[identifier] = normalized
        return utils.copyTable(normalized)
    end

    function AdminSettings.write(identifier)
        if type(identifier) ~= 'string' or identifier == '' then return false, 'missing_identifier' end
        local settings = cache[identifier]
        if type(settings) ~= 'table' then return false, 'missing_settings' end
        local settingsCfg = cfgSettings()
        local maxBytes = tonumber(settingsCfg.MaxJsonBytes) or 32768
        local ok, encoded = pcall(json.encode, settings)
        if not ok or type(encoded) ~= 'string' then return false, 'encode_failed' end
        if #encoded > maxBytes then return false, 'too_large' end
        local file = fileFor(identifier)
        local direct = SaveResourceFile(resourceName, file, encoded, -1)
        if not direct then return false, 'write_failed' end
        dirty[identifier] = nil
        return true
    end

    function AdminSettings.save(src, settings, immediate)
        if not ensureAdmin(src) then return false, 'not_admin' end
        local identifier = AdminSettings.identifier(src)
        if not identifier then return false, 'missing_identifier' end
        local current = cache[identifier] or AdminSettings.load(src)
        local normalized = AdminSettings.normalize(settings, current)
        cache[identifier] = normalized
        dirty[identifier] = true
        if timers[identifier] then Citizen.ClearTimeout(timers[identifier]); timers[identifier] = nil end
        local settingsCfg = cfgSettings()
        local delay = immediate and 0 or math.max(500, tonumber(settingsCfg.SaveDebounceMs) or 900)
        timers[identifier] = Citizen.SetTimeout(delay, function()
            timers[identifier] = nil
            if dirty[identifier] then
                local ok, err = AdminSettings.write(identifier)
                if not ok then utils.debugLog('Admin settings save failed', identifier, err) end
            end
        end)
        return true, nil, utils.copyTable(normalized)
    end

    function AdminSettings.reset(src)
        if not ensureAdmin(src) then return false, 'not_admin' end
        local identifier = AdminSettings.identifier(src)
        if not identifier then return false, 'missing_identifier' end
        cache[identifier] = defaults()
        dirty[identifier] = true
        local ok, err = AdminSettings.write(identifier)
        return ok, err, utils.copyTable(cache[identifier])
    end

    function AdminSettings.export(src)
        return AdminSettings.load(src)
    end

    function AdminSettings.runtime(src)
        local adminCfg = cfg or (Config.AdminTools or {})
        local moderation = type(adminCfg.Moderation) == 'table' and adminCfg.Moderation or {}
        local staffNoClip = type(adminCfg.StaffNoClip) == 'table' and adminCfg.StaffNoClip or {}
        local adminDock = type(adminCfg.AdminDock) == 'table' and adminCfg.AdminDock or {}
        local discordEnabled = type(Config.Webhook) == 'string' and Config.Webhook ~= '' and not Config.Webhook:find('REPLACE_ME', 1, true)
        local staffNoClipEnabled = staffNoClip.Enabled == true and staffNoClip.DoNotModifyPed ~= true
        local adminPreviewEnabled = false -- production ImGui NUI: preview/clone/camera are intentionally removed.
        local livePreviewEnabled = false
        local adminDockEnabled = adminDock.Enabled ~= false
        return {
            profilePerformance = tostring(Config.PerformanceProfile or 'default'),
            performanceProfile = tostring(Config.PerformanceProfile or 'default'),
            StaffNoClip = {
                Enabled = staffNoClipEnabled,
                UseExternalNoClip = staffNoClip.UseExternalNoClip == true,
                DoNotModifyPed = staffNoClip.DoNotModifyPed ~= false,
            },
            AdminPreview = { Enabled = adminPreviewEnabled },
            AdminDock = { Enabled = adminDockEnabled },
            SpectateCameraOnly = moderation.SpectateCameraOnly ~= false,
            DiscordLogging = { Enabled = discordEnabled },
            permissions = {
                isAdmin = src and utils.isAdmin(src) or false,
                canSpectate = moderation.AllowSpectate ~= false,
                canKick = moderation.AllowKick ~= false,
                canFreeze = moderation.AllowFreeze ~= false,
                canTeleport = moderation.AllowTeleport ~= false,
                canBan = adminCfg.AllowBans ~= false,
            },
            features = {
                adminPreview = adminPreviewEnabled,
                livePreview = livePreviewEnabled,
                preview3d = false,
                adminDock = adminDockEnabled,
                staffNoClip = staffNoClipEnabled,
                externalNoClip = staffNoClip.UseExternalNoClip == true,
                doNotModifyPed = staffNoClip.DoNotModifyPed ~= false,
                spectateCameraOnly = moderation.SpectateCameraOnly ~= false,
                spectateNuiOnly = moderation.SpectateShowHud == false,
                worldEsp = moderation.SpectateDrawWorldEsp == true,
                discordLogging = discordEnabled,
                resourceGuard = type(Config.ResourceGuard) == 'table' and Config.ResourceGuard.Enabled == true,
                monitoring = type(Config.Monitoring) == 'table' and Config.Monitoring.Enabled == true,
                heartbeat = type(Config.Heartbeat) == 'table' and Config.Heartbeat.Enabled == true,
            },
            featuresDisabledProduction = {
                'AdminPreview',
                'LivePreview',
                'Preview3DClone',
                'PreviewCamera',
                'AutoScreenshotLoop',
            },
            intervals = {
                spectateSyncMs = tonumber(moderation.SpectateSyncIntervalMs) or 750,
                spectateCameraMs = tonumber(moderation.SpectateTargetCameraIntervalMs) or 1200,
                settingsSaveDebounceMs = tonumber((adminCfg.AdminSettings or {}).SaveDebounceMs) or 900,
            },
            restartRequired = { performanceProfile = true, resourceGuard = true, heartbeat = true },
        }
    end

    function AdminSettings.flushForSource(src)
        local identifier = AdminSettings.identifier(src)
        if identifier and dirty[identifier] then
            if timers[identifier] then Citizen.ClearTimeout(timers[identifier]); timers[identifier] = nil end
            AdminSettings.write(identifier)
        end
    end
end

local defenseLabels = {
    heartbeat = 'Heartbeat',
    godmode_probe = 'Probe Godmode',
    vehicle_spam = 'Vehicle Spam',
    spawn_abuse = 'Spawn Abuse',
    attachments_audit = 'Attachments Audit',
    damage_monitor = 'Damage Monitor',
    auto_detections = 'Auto Detections',
}

local setEntityHealthNative = SetEntityHealth
if type(setEntityHealthNative) ~= 'function' then
    local nativeHash = 0x6B76DC1F3AE6E6A3 -- SET_ENTITY_HEALTH
    if type(Citizen) == 'table' and type(Citizen.InvokeNative) == 'function' then
        setEntityHealthNative = function(entity, health)
            return Citizen.InvokeNative(nativeHash, entity, health)
        end
    else
        setEntityHealthNative = function()
            error('zVS-AC: SetEntityHealth native is unavailable on this platform')
        end
    end
end

local function getConfiguredLivePreviewMode()
    local previewCfg = cfg and cfg.LivePreview or {}
    local mode = previewCfg and previewCfg.Mode
    if type(mode) == 'string' then
        local normalized = mode:lower()
        if normalized == 'camera' or normalized == 'scripted_camera' then
            return 'camera'
        end
    end
    return 'screenshot'
end

local detectionImmunity = {}

local buildState
local broadcastState

local function getDefenseDefaultState(key)
    if type(defenseCfg.Defenses) == 'table' and defenseCfg.Defenses[key] ~= nil then
        return defenseCfg.Defenses[key] and true or false
    end
    return true
end

local function isDefenseEnabled(key)
    if type(key) ~= 'string' or key == '' then
        return true
    end
    local state = defenseStates[key]
    if state == nil then
        return getDefenseDefaultState(key)
    end
    return state and true or false
end

local function setDefenseEnabled(key, enabled)
    if type(key) ~= 'string' or key == '' then
        return false
    end
    defenseStates[key] = enabled and true or false
    return true
end

local function exportDefenseStates()
    local exported = {}
    for key, label in pairs(defenseLabels) do
        exported[#exported + 1] = {
            key = key,
            label = label,
            enabled = isDefenseEnabled(key),
        }
    end
    table.sort(exported, function(a, b)
        return tostring(a.label) < tostring(b.label)
    end)
    return exported
end

local function trimString(value)
    if type(value) ~= 'string' then
        return value
    end

    local trimmed = value:match('^%s*(.-)%s*$') or value

    -- Strip UTF-8 BOM if present to prevent downstream parsers from failing to
    -- detect data URLs or JSON payloads.
    if trimmed:byte(1) == 0xEF and trimmed:byte(2) == 0xBB and trimmed:byte(3) == 0xBF then
        trimmed = trimmed:sub(4)
    end

    return trimmed
end

local function clampNumber(value, minValue, maxValue)
    if type(value) ~= 'number' then
        return minValue
    end

    if value ~= value then -- NaN guard
        return minValue
    end

    if minValue ~= nil and value < minValue then
        value = minValue
    end

    if maxValue ~= nil and value > maxValue then
        value = maxValue
    end

    return value
end

local function normalizeHexColor(value, fallback)
    if type(value) ~= 'string' then
        return fallback
    end

    local trimmed = trimString(value)
    if not trimmed or trimmed == '' then
        return fallback
    end

    local hex = trimmed
    if hex:sub(1, 1) ~= '#' then
        hex = '#' .. hex
    end

    hex = hex:lower()
    local body = hex:sub(2)
    if body:match('^[0-9a-f]+$') then
        if #body == 3 then
            body = body:gsub('.', '%1%1')
        elseif #body ~= 6 then
            return fallback
        end
        return '#' .. body
    end

    return fallback
end

local supportedLanguageLookup = utils.buildLookup({
    'en',
    'fr',
    'es',
    'de',
    'pt',
    'it',
    'zh-hans',
    'zh-cn',
    'zh',
    'ar',
})

local function normalizeLanguage(value)
    if type(value) ~= 'string' then
        return nil
    end

    local normalized = value:lower():gsub('_', '-'):gsub('%s+', '')
    if normalized == 'zh-cn' or normalized == 'zh' then
        normalized = 'zh-hans'
    end

    if supportedLanguageLookup[normalized] then
        return normalized
    end

    return nil
end

local function normalizeLayout(layout, base)
    local normalized = {
        console = {},
        inspector = {},
    }

    if type(base) == 'table' then
        if type(base.console) == 'table' then
            local x = tonumber(base.console.x)
            local y = tonumber(base.console.y)
            if x then normalized.console.x = math.floor(x + 0.5) end
            if y then normalized.console.y = math.floor(y + 0.5) end
        end
        if type(base.inspector) == 'table' then
            local left = tonumber(base.inspector.left)
            local top = tonumber(base.inspector.top)
            if left then normalized.inspector.left = math.floor(left + 0.5) end
            if top then normalized.inspector.top = math.floor(top + 0.5) end
            if base.inspector.locked ~= nil then
                normalized.inspector.locked = base.inspector.locked and true or false
            end
        end
    end

    if type(layout) ~= 'table' then
        normalized.inspector.locked = normalized.inspector.locked or false
        return normalized
    end

    if type(layout.console) == 'table' then
        local x = tonumber(layout.console.x)
        local y = tonumber(layout.console.y)
        if x then normalized.console.x = math.floor(x + 0.5) end
        if y then normalized.console.y = math.floor(y + 0.5) end
    elseif layout.console == false or layout.console == nil then
        normalized.console = {}
    end

    if type(layout.inspector) == 'table' then
        local left = tonumber(layout.inspector.left)
        local top = tonumber(layout.inspector.top)
        if left then normalized.inspector.left = math.floor(left + 0.5) end
        if top then normalized.inspector.top = math.floor(top + 0.5) end
        if layout.inspector.locked ~= nil then
            normalized.inspector.locked = layout.inspector.locked and true or false
        end
    elseif layout.inspector == false then
        normalized.inspector = { locked = false }
    end

    if normalized.console and next(normalized.console) == nil then
        normalized.console = {}
    end
    if normalized.inspector.locked == nil then
        normalized.inspector.locked = false
    end
    if normalized.inspector and next(normalized.inspector) == nil then
        normalized.inspector = { locked = false }
    end

    return normalized
end

local function normalizeAppearanceSettings(settings, base)
    local normalized = utils.copyTable(defaultAppearanceSettings)

    local function apply(payload)
        if type(payload) ~= 'table' then
            return
        end

        local function normalizeOpacityField(value, minValue, maxValue)
            local numeric = tonumber(value)
            if not numeric then
                return nil
            end
            if numeric > 1.0001 then
                numeric = numeric / 100.0
            end
            return clampNumber(numeric, minValue, maxValue)
        end

        local opacity = normalizeOpacityField(payload.opacity, 0.3, 1.0)
        if opacity then
            normalized.opacity = opacity
        end

        local baseColor = normalizeHexColor(payload.baseColor, normalized.baseColor)
        if baseColor then
            normalized.baseColor = baseColor
        end

        local accentColor = normalizeHexColor(payload.accentColor, normalized.accentColor)
        if accentColor then
            normalized.accentColor = accentColor
        end

        local consoleOpacity = normalizeOpacityField(payload.consoleOpacity, 0.55, 1.0)
        if consoleOpacity then
            normalized.consoleOpacity = consoleOpacity
        end

        local consolePanelOpacity = normalizeOpacityField(payload.consolePanelOpacity, 0.6, 1.0)
        if consolePanelOpacity then
            normalized.consolePanelOpacity = consolePanelOpacity
        end

        local consoleBackdrop = normalizeOpacityField(payload.consoleBackdropOpacity, 0.3, 0.95)
        if consoleBackdrop then
            normalized.consoleBackdropOpacity = consoleBackdrop
        end

        local consoleBlur = tonumber(payload.consoleBlur)
        if consoleBlur then
            normalized.consoleBlur = clampNumber(math.floor(consoleBlur + 0.5), 0, 48)
        end

        local consoleBaseColor = normalizeHexColor(payload.consoleBaseColor, normalized.consoleBaseColor)
        if consoleBaseColor then
            normalized.consoleBaseColor = consoleBaseColor
        end

        local consoleAccentColor = normalizeHexColor(payload.consoleAccentColor, normalized.consoleAccentColor)
        if consoleAccentColor then
            normalized.consoleAccentColor = consoleAccentColor
        end

        if payload.language ~= nil then
            local language = normalizeLanguage(payload.language)
            if language then
                normalized.language = language
            end
        end

        if payload.layout ~= nil then
            normalized.layout = normalizeLayout(payload.layout, normalized.layout)
        end
    end

    apply(base)
    apply(settings)

    if type(normalized.layout) ~= 'table' then
        normalized.layout = utils.copyTable(defaultAppearanceSettings.layout)
    else
        normalized.layout.console = normalized.layout.console or {}
        normalized.layout.inspector = normalized.layout.inspector or { locked = false }
        if normalized.layout.inspector.locked == nil then
            normalized.layout.inspector.locked = false
        end
    end

    if not normalizeLanguage(normalized.language) then
        normalized.language = 'en'
    end

    return normalized
end

local appearanceKeyPriority = {
    'license2:',
    'license:',
    'fivem:',
    'discord:',
    'steam:',
    'xbl:',
    'live:',
}

function getAdminAppearanceKey(src)
    if not src then
        return nil
    end

    local identifiers = GetPlayerIdentifiers and GetPlayerIdentifiers(src) or {}
    local fallback = nil

    for _, identifier in ipairs(identifiers) do
        if type(identifier) == 'string' then
            local lower = identifier:lower()
            fallback = fallback or lower
            for _, prefix in ipairs(appearanceKeyPriority) do
                if lower:sub(1, #prefix) == prefix then
                    return lower
                end
            end
        end
    end

    if fallback then
        return fallback
    end

    return ('player:%s'):format(src)
end

local function prepareAppearanceForStorage(profile)
    if type(profile) ~= 'table' then
        return {}
    end

    local cloned = utils.copyTable(profile)
    if type(cloned.layout) == 'table' then
        if type(cloned.layout.console) == 'table' and next(cloned.layout.console) == nil then
            cloned.layout.console = nil
        end
        if type(cloned.layout.inspector) == 'table' then
            if cloned.layout.inspector.locked == false and next(cloned.layout.inspector) then
                for key in pairs(cloned.layout.inspector) do
                    if key ~= 'locked' and cloned.layout.inspector[key] == nil then
                        cloned.layout.inspector[key] = nil
                    end
                end
            end
            if next(cloned.layout.inspector) == nil then
                cloned.layout.inspector = nil
            end
        end
        if next(cloned.layout) == nil then
            cloned.layout = nil
        end
    end
    return cloned
end

local function saveAppearanceSettings()
    local payload = {
        version = APPEARANCE_STORAGE_VERSION,
        default = prepareAppearanceForStorage(fallbackAppearanceSettings),
        admins = {},
    }

    for key, profile in pairs(appearanceProfiles) do
        if type(key) == 'string' and type(profile) == 'table' then
            payload.admins[key] = prepareAppearanceForStorage(profile)
        end
    end

    local ok, encoded = pcall(json.encode, payload)
    if not ok then
        utils.debugLog('Failed to encode appearance settings', encoded)
        return false, 'encode_failed'
    end

    local success = SaveResourceFile(resourceName, 'data/appearance_settings.json', encoded, -1)
    if not success then
        utils.debugLog('Failed to write appearance settings file')
        return false, 'write_failed'
    end

    return true
end

local function loadAppearanceSettings()
    appearanceProfiles = {}
    fallbackAppearanceSettings = utils.copyTable(defaultAppearanceSettings)

    local data = LoadResourceFile(resourceName, 'data/appearance_settings.json')
    if not data or data == '' then
        saveAppearanceSettings()
        return
    end

    local ok, decoded = pcall(json.decode, data)
    if not ok or type(decoded) ~= 'table' then
        utils.debugLog('Failed to decode appearance settings file, resetting.', decoded)
        saveAppearanceSettings()
        return
    end

    local version = tonumber(decoded.version) or 1
    if version >= APPEARANCE_STORAGE_VERSION then
        if type(decoded.default) == 'table' then
            fallbackAppearanceSettings = normalizeAppearanceSettings(decoded.default)
        end
        if type(decoded.admins) == 'table' then
            for key, profile in pairs(decoded.admins) do
                if type(key) == 'string' and type(profile) == 'table' then
                    appearanceProfiles[key] = normalizeAppearanceSettings(profile, fallbackAppearanceSettings)
                end
            end
        end
    else
        fallbackAppearanceSettings = normalizeAppearanceSettings(decoded)
    end
end

local function exportAppearanceSettings(viewer)
    local key = getAdminAppearanceKey(viewer)
    local profile = nil
    if key then
        profile = appearanceProfiles[key]
    end

    if not profile then
        return utils.copyTable(fallbackAppearanceSettings)
    end

    return utils.copyTable(profile)
end

local function handleSaveAppearance(src, data)
    if not ensureAdmin(src) then return end

    local payload = type(data) == 'table' and data or {}
    local settings = type(payload.settings) == 'table' and payload.settings or payload
    local reset = payload.reset == true

    local key = getAdminAppearanceKey(src)
    if not key then
        return
    end

    local previous = appearanceProfiles[key] and utils.copyTable(appearanceProfiles[key]) or nil
    local nextSettings

    if reset then
        appearanceProfiles[key] = nil
        nextSettings = utils.copyTable(fallbackAppearanceSettings)
    else
        nextSettings = normalizeAppearanceSettings(settings, appearanceProfiles[key] or fallbackAppearanceSettings)
        appearanceProfiles[key] = nextSettings
    end

    local ok, err = saveAppearanceSettings()
    if not ok then
        if previous then
            appearanceProfiles[key] = previous
        else
            appearanceProfiles[key] = nil
        end
        local message = "Impossible d'enregistrer les preferences."
        if err == 'encode_failed' then
            message = "Impossible de preparer les preferences (JSON)."
        elseif err == 'write_failed' then
            message = "Impossible d'ecrire le fichier de preferences."
        end
        TriggerClientEvent('zvs-ac:admin:appearanceSaved', src, {
            ok = false,
            error = err,
            message = message,
            settings = exportAppearanceSettings(src),
        })
        return
    end

    TriggerClientEvent('zvs-ac:admin:appearanceSaved', src, {
        ok = true,
        settings = utils.copyTable(nextSettings),
        message = 'Apparence enregistree.',
    })

    broadcastState()
end

local function detectImageMimeType(binary)
    if type(binary) ~= 'string' or #binary < 4 then
        return 'image/jpeg'
    end

    local byte1, byte2, byte3, byte4 = binary:byte(1, 4)
    if byte1 == 0x89 and byte2 == 0x50 and byte3 == 0x4E and byte4 == 0x47 then
        return 'image/png'
    end

    if byte1 == 0xFF and byte2 == 0xD8 then
        return 'image/jpeg'
    end

    if byte1 == 0x47 and byte2 == 0x49 and byte3 == 0x46 then
        return 'image/gif'
    end

    if byte1 == 0x42 and byte2 == 0x4D then
        return 'image/bmp'
    end

    if byte1 == 0x52 and byte2 == 0x49 and byte3 == 0x46 and byte4 == 0x46 and #binary >= 12 then
        local webp = binary:sub(9, 12)
        if webp == 'WEBP' then
            return 'image/webp'
        end
    end

    return 'image/jpeg'
end

local function normalizeBase64Image(value)
    if type(value) ~= 'string' then
        return nil
    end

    local trimmed = trimString(value)
    if not trimmed or trimmed == '' then
        return nil
    end

    local headerMime = nil
    local payload = trimmed

    if trimmed:sub(1, 5):lower() == 'data:' then
        local header, rest = trimmed:match('^data:(.-),(.*)$')
        if not header or not rest then
            return nil
        end

        local loweredHeader = header:lower()
        if not loweredHeader:find('base64', 1, true) then
            return nil
        end

        local base64Index = loweredHeader:find(';base64', 1, true)
        if base64Index then
            headerMime = trimString(header:sub(1, base64Index - 1))
        else
            headerMime = trimString(header)
        end

        payload = rest
    end

    local sanitized = payload:gsub('%s+', '')
    sanitized = sanitized:gsub('%-', '+'):gsub('_', '/')
    if sanitized == '' then
        return nil
    end

    if sanitized:find('[^A-Za-z0-9+/=]') then
        return nil
    end

    local remainder = #sanitized % 4
    if remainder ~= 0 then
        sanitized = sanitized .. string.rep('=', 4 - remainder)
    end

    local binary, decodeErr = utils.decodeBase64 and utils.decodeBase64(sanitized)
    if not binary then
        utils.debugLog('Screenshot payload rejected (base64 decode failed)', decodeErr or 'decode_error')
        return nil
    end

    local mimeType = headerMime
    if not mimeType or mimeType == '' then
        mimeType = detectImageMimeType(binary)
    end

    return ('data:%s;base64,%s'):format(mimeType, sanitized)
end

local function refreshLivePreviewSupport()
    local previewCfg = cfg and cfg.LivePreview or {}
    if previewCfg.Enabled == false then
        livePreviewSupport.checked = true
        livePreviewSupport.available = false
        livePreviewSupport.reason = 'disabled'
        return false, livePreviewSupport.reason
    end
    if getConfiguredLivePreviewMode() == 'camera' then
        livePreviewSupport.checked = true
        livePreviewSupport.available = true
        livePreviewSupport.reason = nil
        return true, nil
    end
    if previewCfg.Enabled == false then
        livePreviewSupport.checked = true
        livePreviewSupport.available = false
        livePreviewSupport.reason = 'disabled'
        return false, livePreviewSupport.reason
    end

    local state = GetResourceState('screenshot-basic')
    if state ~= 'started' then
        livePreviewSupport.checked = true
        livePreviewSupport.available = false
        livePreviewSupport.reason = 'resource_missing'
        return false, livePreviewSupport.reason
    end

    local ok, requestFn = pcall(function()
        return exports['screenshot-basic'] and exports['screenshot-basic'].requestClientScreenshot
    end)
    if not ok or type(requestFn) ~= 'function' then
        livePreviewSupport.checked = true
        livePreviewSupport.available = false
        livePreviewSupport.reason = 'export_missing'
        return false, livePreviewSupport.reason
    end

    livePreviewSupport.checked = true
    livePreviewSupport.available = true
    livePreviewSupport.reason = nil
    return true, nil
end

local function ensureLivePreviewSupport(force)
    if force or not livePreviewSupport.checked then
        return refreshLivePreviewSupport()
    end
    return livePreviewSupport.available, livePreviewSupport.reason
end

local function shouldFallbackToCamera(reason)
    if not reason then
        return false
    end
    local normalized = tostring(reason):lower()
    return normalized == 'resource_missing' or normalized == 'export_missing'
end

local function resolveLivePreviewState(forceCheck)
    local support, reason = ensureLivePreviewSupport(forceCheck)
    local configured = getConfiguredLivePreviewMode()
    local configuredMode = configured
    local mode = configured
    local fallbackReason = nil

    if configured ~= 'camera' then
        if support == false and shouldFallbackToCamera(reason) then
            mode = 'camera'
            fallbackReason = tostring(reason)
        end
    end

    return {
        mode = tostring(mode),
        configured = tostring(configuredMode),
        fallback = mode ~= configured,
        reason = fallbackReason,
        support = {
            available = support ~= false,
            reason = reason and tostring(reason) or nil,
        },
    }
end

local function getLivePreviewMode(forceCheck)
    local state = resolveLivePreviewState(forceCheck)
    return state.mode, state
end

local function getLivePreviewInterval()
    local previewCfg = cfg and cfg.LivePreview or {}
    local interval = tonumber(previewCfg.RefreshInterval) or 1200
    if interval < 250 then
        interval = 250
    end
    return interval
end

local function resolveLivePreviewOptions()
    local previewCfg = cfg and cfg.LivePreview or {}
    local encoding = normalizeScreenshotEncoding and normalizeScreenshotEncoding(previewCfg.Encoding) or 'jpg'
    if encoding ~= 'jpg' and encoding ~= 'png' and encoding ~= 'jpeg' then
        encoding = 'jpg'
    end

    local options = { encoding = encoding }

    if encoding == 'jpg' or encoding == 'jpeg' then
        local quality = tonumber(previewCfg.Quality) or 45
        if quality < 0 then quality = 0 end
        if quality > 100 then quality = 100 end
        options.quality = math.floor(quality)
    end

    local width = nil
    local height = nil
    if type(previewCfg.Width) == 'number' then
        width = previewCfg.Width
    end
    if type(previewCfg.Height) == 'number' then
        height = previewCfg.Height
    end
    if type(previewCfg.Resolution) == 'table' then
        if type(previewCfg.Resolution.Width) == 'number' then
            width = previewCfg.Resolution.Width
        end
        if type(previewCfg.Resolution.Height) == 'number' then
            height = previewCfg.Resolution.Height
        end
        if type(previewCfg.Resolution.w) == 'number' then
            width = previewCfg.Resolution.w
        end
        if type(previewCfg.Resolution.h) == 'number' then
            height = previewCfg.Resolution.h
        end
    end

    if width and height then
        local w = math.floor(width)
        local h = math.floor(height)
        if w >= 240 and h >= 180 then
            options.resolution = { x = w, y = h }
        end
    end

    return options
end

local DEFAULT_LIVE_PREVIEW_LATENT_THRESHOLD = 512 * 1024
local DEFAULT_LIVE_PREVIEW_LATENT_BPS = 128 * 1024
local hasLatentEventSupport = type(TriggerLatentClientEvent) == 'function'

local function resolveLivePreviewLatentSettings()
    local previewCfg = cfg and cfg.LivePreview or {}
    local threshold = tonumber(previewCfg.LatentThreshold) or DEFAULT_LIVE_PREVIEW_LATENT_THRESHOLD
    if threshold < 64 * 1024 then
        threshold = 64 * 1024
    end

    local bytesPerSecond = tonumber(previewCfg.LatentBytesPerSecond) or DEFAULT_LIVE_PREVIEW_LATENT_BPS
    if bytesPerSecond < 32 * 1024 then
        bytesPerSecond = 32 * 1024
    end

    return threshold, bytesPerSecond
end

local function sendLivePreviewFrameEvent(target, payload)
    if not target then
        return
    end

    if hasLatentEventSupport and type(payload) == 'table' then
        local frameData = payload.frame
        if type(frameData) == 'string' then
            local threshold, bytesPerSecond = resolveLivePreviewLatentSettings()
            if bytesPerSecond and bytesPerSecond > 0 and #frameData >= threshold then
                TriggerLatentClientEvent('zvs-ac:admin:previewFrame', target, payload, bytesPerSecond)
                return
            end
        end
    end

    TriggerClientEvent('zvs-ac:admin:previewFrame', target, payload)
end

local function isBinaryImageData(value)
    if type(value) ~= 'string' then
        return false
    end

    local length = #value
    if length == 0 then
        return false
    end

    local sampleLength = math.min(length, 64)
    local controlCount = 0

    for index = 1, sampleLength do
        local byte = value:byte(index)
        if not byte then
            break
        end

        if byte == 0 then
            return true
        end

        if byte < 32 then
            if byte ~= 9 and byte ~= 10 and byte ~= 13 then
                controlCount = controlCount + 1
            end
        elseif byte > 126 then
            controlCount = controlCount + 1
        end

        if controlCount >= 4 then
            return true
        end
    end

    return false
end

local function normalizeScreenshotEncoding(value)
    if type(value) ~= 'string' then
        return nil
    end

    local lowered = value:lower()
    if lowered == 'jpeg' then
        lowered = 'jpg'
    end

    if lowered == 'jpg' or lowered == 'png' then
        return lowered
    end

    return nil
end

local function buildScreenshotEncodingPriority(preferred)
    local priority = {}
    local seen = {}

    local function push(value)
        local normalized = normalizeScreenshotEncoding(value)
        if normalized and not seen[normalized] then
            priority[#priority + 1] = normalized
            seen[normalized] = true
        end
    end

    if type(preferred) == 'table' then
        for _, value in ipairs(preferred) do
            push(value)
        end
    else
        push(preferred)
    end

    push('jpg')
    push('png')

    return priority
end

local function screenshotExtensionForEncoding(encoding)
    if encoding == 'jpg' then
        return 'jpg'
    end
    if encoding == 'png' then
        return 'png'
    end
    return encoding or 'jpg'
end

local function shouldRetryInvalidImageFormat(errorMessage)
    if type(errorMessage) ~= 'string' then
        return false
    end

    local lowered = errorMessage:lower()
    return lowered == 'invalid_image_format'
        or lowered == 'invalid-image-format'
        or lowered == 'invalid image format'
end

local screenshotErrorLabels = {
    invalid_image_data = 'donnees invalides',
    invalid_image_format = 'format incompatible',
    busy = 'client occupe',
    game_inactive = 'jeu inactif',
    timeout = 'delai depasse',
}

local function classifyScreenshotError(errorMessage)
    if type(errorMessage) ~= 'string' then
        return nil
    end

    local trimmed = trimString(errorMessage)
    if not trimmed or trimmed == '' then
        return nil
    end

    local lowered = trimmed:lower()

    if shouldRetryInvalidImageFormat(lowered) then
        return {
            action = 'retry_encoding',
            code = 'invalid_image_format',
            raw = trimmed,
        }
    end

    if lowered:find('invalid_image_data', 1, true)
        or lowered:find('invalid-image-data', 1, true)
        or lowered:find('invalid image data', 1, true)
        or (lowered:find('invalid', 1, true) and lowered:find('image', 1, true) and lowered:find('data', 1, true))
    then
        return {
            action = 'retry_same',
            code = 'invalid_image_data',
            raw = trimmed,
        }
    end

    if lowered:find('busy', 1, true)
        or lowered:find('in_progress', 1, true)
        or lowered:find('in progress', 1, true)
        or lowered:find('pending', 1, true)
    then
        return {
            action = 'retry_same',
            code = 'busy',
            raw = trimmed,
        }
    end

    if lowered:find('gameinactive', 1, true)
        or lowered:find('game inactive', 1, true)
        or lowered:find('game not active', 1, true)
        or lowered:find('not focused', 1, true)
        or (lowered:find('focus', 1, true) and lowered:find('lost', 1, true))
    then
        return {
            action = 'retry_same',
            code = 'game_inactive',
            raw = trimmed,
        }
    end

    if lowered:find('timeout', 1, true)
        or lowered:find('timed out', 1, true)
        or lowered:find('deadline', 1, true)
    then
        return {
            action = 'retry_same',
            code = 'timeout',
            raw = trimmed,
        }
    end

    return {
        action = nil,
        code = trimmed,
        raw = trimmed,
    }
end

local function formatScreenshotErrorLabel(code, fallback)
    if code and screenshotErrorLabels[code] then
        return screenshotErrorLabels[code]
    end
    if type(fallback) == 'string' and fallback ~= '' then
        return fallback
    end
    if type(code) == 'string' and code ~= '' then
        return code
    end
    return 'erreur'
end

local function extractDiscordAttachmentUrl(body)
    if type(body) ~= 'string' or body == '' then
        return nil
    end

    local ok, decoded = pcall(json.decode, body)
    if not ok or type(decoded) ~= 'table' then
        return nil
    end

    local function resolveFromList(list)
        if type(list) ~= 'table' then
            return nil
        end
        for _, entry in ipairs(list) do
            if type(entry) == 'table' then
                local url = entry.url or entry.proxy_url or entry.attachment_url or entry.href
                if type(url) == 'string' and url ~= '' then
                    return trimString(url)
                end
                if type(entry.image) == 'table' then
                    local imageUrl = entry.image.url or entry.image.proxy_url
                    if type(imageUrl) == 'string' and imageUrl ~= '' then
                        return trimString(imageUrl)
                    end
                end
                if type(entry.thumbnail) == 'table' then
                    local thumbUrl = entry.thumbnail.url or entry.thumbnail.proxy_url
                    if type(thumbUrl) == 'string' and thumbUrl ~= '' then
                        return trimString(thumbUrl)
                    end
                end
                if type(entry.attachments) == 'table' then
                    local nested = resolveFromList(entry.attachments)
                    if nested then
                        return nested
                    end
                end
            end
        end
        return nil
    end

    local url = resolveFromList(decoded.attachments)
    if url then
        return url
    end

    if type(decoded.data) == 'table' then
        url = resolveFromList(decoded.data.attachments)
        if url then
            return url
        end
    end

    if type(decoded.message) == 'table' then
        url = resolveFromList(decoded.message.attachments)
        if url then
            return url
        end
    end

    if type(decoded.embeds) == 'table' then
        url = resolveFromList(decoded.embeds)
        if url then
            return url
        end
    end

    if type(decoded.url) == 'string' and decoded.url ~= '' then
        return trimString(decoded.url)
    end

    if type(decoded[1]) == 'table' then
        local arrayUrl = resolveFromList(decoded)
        if arrayUrl then
            return arrayUrl
        end
        for _, item in ipairs(decoded) do
            if type(item) == 'table' then
                local nested = resolveFromList(item.attachments)
                if nested then
                    return nested
                end
            end
        end
    end

    return nil
end

local function isLikelyImageString(value)
    if type(value) ~= 'string' then
        return nil
    end

    local trimmed = trimString(value)
    if not trimmed or trimmed == '' then
        return nil
    end

    local lowered = trimmed:lower()
    if lowered == 'null' then
        return nil
    end

    local mimeType, payload = utils.parseDataUrl and utils.parseDataUrl(trimmed)
    if mimeType and payload then
        if type(payload) == 'string' then
            local sanitized = payload:gsub('%s+', '')
            if sanitized ~= '' then
                local markerIndex = lowered:find(';base64,', 1, true)
                if markerIndex then
                    return trimmed:sub(1, markerIndex + 7) .. sanitized
                end
                return ('data:%s;base64,%s'):format(mimeType, sanitized)
            end
        end
        return nil
    end

    if lowered:find('^https?://', 1, false)
        or lowered:find('^wss?://', 1, false)
        or lowered:sub(1, 5) == 'blob:'
    then
        return trimmed
    end

    local dataUrl = normalizeBase64Image(trimmed)
    if dataUrl then
        return dataUrl
    end

    return nil
end

local function safePedState(ped, fn)
    if not ped or ped == 0 then
        return false
    end
    if type(fn) ~= 'function' then
        return false
    end
    local ok, result = pcall(fn, ped)
    if not ok then
        return false
    end
    return result == true
end

local function normalizeScreenshotPayload(payload, depth)
    if payload == nil then
        return nil
    end
    depth = depth or 0
    if depth > 4 then
        return nil
    end

    local payloadType = type(payload)
    if payloadType == 'string' then
        if isBinaryImageData(payload) then
            local encoded, encodeErr = utils.encodeBase64 and utils.encodeBase64(payload)
            if encoded and encoded ~= '' then
                local mimeType = detectImageMimeType(payload)
                return ('data:%s;base64,%s'):format(mimeType, encoded)
            elseif encodeErr then
                utils.debugLog('Screenshot payload rejected (base64 encode failed)', encodeErr)
            end
        end

        local trimmed = trimString(payload)
        if not trimmed or trimmed == '' then
            return nil
        end

        local lowered = trimmed:lower()
        if lowered == 'null' then
            return nil
        end

        if trimmed:sub(1, 1) == '"' then
            local ok, decoded = pcall(json.decode, trimmed)
            if ok and type(decoded) == 'string' then
                local normalized = normalizeScreenshotPayload(decoded, depth + 1)
                if normalized then
                    return normalized
                end
            end
        elseif trimmed:sub(1, 1) == "'" and trimmed:sub(-1) == "'" then
            local inner = trimmed:sub(2, -2)
            if inner and inner ~= '' then
                local normalized = normalizeScreenshotPayload(inner, depth + 1)
                if normalized then
                    return normalized
                end
            end
        end

        local candidate = isLikelyImageString(trimmed)
        if candidate then
            return candidate
        end

        local firstChar = trimmed:sub(1, 1)
        if firstChar == '{' or firstChar == '[' then
            local ok, decoded = pcall(json.decode, trimmed)
            if ok and decoded then
                return normalizeScreenshotPayload(decoded, depth + 1)
            end
        end

        return nil
    elseif payloadType == 'table' then
        local keys = { 'data', 'image', 'url', 'result', 'value', 'source', 'payload', 'body', 'raw', 'content' }
        for _, key in ipairs(keys) do
            local normalized = normalizeScreenshotPayload(payload[key], depth + 1)
            if normalized then
                return normalized
            end
        end
        for _, value in ipairs(payload) do
            local normalized = normalizeScreenshotPayload(value, depth + 1)
            if normalized then
                return normalized
            end
        end
        for key, value in pairs(payload) do
            if value ~= payload then
                local valueType = type(value)
                if valueType == 'table' then
                    local normalized = normalizeScreenshotPayload(value, depth + 1)
                    if normalized then
                        return normalized
                    end
                elseif valueType == 'string' then
                    local lowerKey = type(key) == 'string' and key:lower() or ''
                    if lowerKey:find('image', 1, true)
                        or lowerKey:sub(-3) == 'url'
                        or lowerKey == 'data'
                        or lowerKey == 'dataurl'
                        or lowerKey == 'data_url'
                    then
                        local normalized = normalizeScreenshotPayload(value, depth + 1)
                        if normalized then
                            return normalized
                        end
                    end
                end
            end
        end
    end

    return nil
end

local function extractScreenshotBinary(imageData)
    if type(imageData) ~= 'string' then
        return nil, nil, 'invalid_image'
    end

    local mimeType, payload = utils.parseDataUrl and utils.parseDataUrl(imageData)
    if not payload or payload == '' then
        return nil, nil, 'empty_image'
    end

    local sanitizedPayload = payload
    if type(sanitizedPayload) == 'string' and sanitizedPayload ~= '' then
        sanitizedPayload = sanitizedPayload:gsub('%s+', '')
    end

    if not sanitizedPayload or sanitizedPayload == '' then
        return nil, nil, 'empty_image'
    end

    local binary, decodeErr = utils.decodeBase64 and utils.decodeBase64(sanitizedPayload)
    if not binary then
        return nil, nil, decodeErr or 'decode_failed'
    end

    if not mimeType or mimeType == '' then
        mimeType = 'image/jpeg'
    end

    return binary, mimeType, nil
end

local function uploadScreenshotViaHttp(config)
    if type(config) ~= 'table' then
        return false, 'invalid_config'
    end

    local webhook = config.webhook
    if type(webhook) ~= 'string' or webhook == '' then
        return false, 'invalid_webhook'
    end

    local imageData = config.imageData
    if type(imageData) ~= 'string' or imageData == '' then
        return false, 'invalid_image'
    end

    local binary, mimeType, decodeErr = extractScreenshotBinary(imageData)
    if not binary then
        return false, decodeErr or 'decode_failed'
    end

    local parts = {}
    if config.payloadJson and config.payloadJson ~= '' then
        parts[#parts + 1] = {
            name = 'payload_json',
            data = config.payloadJson,
            contentType = 'application/json',
        }
    end

    parts[#parts + 1] = {
        name = config.fieldName or 'file',
        filename = config.fileName or 'screenshot.jpg',
        contentType = mimeType or 'application/octet-stream',
        data = binary,
    }

    local body, boundary = utils.buildMultipartFormData(parts)
    if not body or not boundary then
        return false, 'multipart_failed'
    end

    local headers = {
        ['Content-Type'] = ('multipart/form-data; boundary=%s'):format(boundary),
        ['Content-Length'] = tostring(#body),
    }

    PerformHttpRequest(webhook, function(statusCode, responseBody)
        if type(config.onComplete) == 'function' then
            config.onComplete(statusCode or 0, responseBody or '')
        end
    end, 'POST', body, headers)

    return true, nil
end

local function sanitizeName(name)
    if type(name) ~= 'string' then
        return 'Unknown'
    end
    return name
end

local identifierOrder = { 'license', 'fivem', 'discord', 'steam', 'xbl', 'live', 'ip' }
local formatPrimaryIdentifiersWithOptions

local function collectPlayerIdentifiers(target)
    local identifiers = {}
    local primary = {}
    if not target or target == 0 then
        return identifiers, primary
    end

    local list = GetPlayerIdentifiers(target)
    if type(list) ~= 'table' then
        return identifiers, primary
    end

    for _, identifier in ipairs(list) do
        if type(identifier) == 'string' and identifier ~= '' then
            identifiers[#identifiers + 1] = identifier
            local prefix, value = identifier:match('([^:]+):(.+)')
            if prefix and value and primary[prefix] == nil then
                primary[prefix] = value
            end
        end
    end

    local endpoint = GetPlayerEndpoint and GetPlayerEndpoint(target) or nil
    if type(endpoint) == 'string' and endpoint ~= '' then
        local ip = endpoint:match('^([^:]+)')
        if ip and ip ~= '' and primary.ip == nil then
            primary.ip = ip
        end
        primary.endpoint = endpoint
    end

    return identifiers, primary
end

local function formatPrimaryIdentifiers(primary)
    return formatPrimaryIdentifiersWithOptions(primary, {})
end

formatPrimaryIdentifiersWithOptions = function(primary, options)
    local entries = {}
    if type(primary) ~= 'table' then
        return entries
    end
    options = type(options) == 'table' and options or {}
    local includeIp = options.includeIp ~= false

    for _, key in ipairs(identifierOrder) do
        if key == 'ip' and not includeIp then
            goto continue_ordered_identifier
        end
        local value = primary[key]
        if value then
            entries[#entries + 1] = ('%s: `%s`'):format(key, value)
        end
        ::continue_ordered_identifier::
    end

    for key, value in pairs(primary) do
        if key == 'ip' and not includeIp then
            goto continue_unordered_identifier
        end
        local already = false
        for _, ordered in ipairs(identifierOrder) do
            if ordered == key then
                already = true
                break
            end
        end
        if not already then
            entries[#entries + 1] = ('%s: `%s`'):format(key, value)
        end
        ::continue_unordered_identifier::
    end

    return entries
end

local function getPlayerPersistentIdentifierMap(target)
    local _, primary = collectPlayerIdentifiers(target)
    local map = {}
    for _, key in ipairs({ 'license', 'fivem', 'discord', 'steam', 'xbl', 'live' }) do
        local value = primary[key]
        if type(value) == 'string' and value ~= '' then
            map[key] = value
        end
    end
    return map
end

local function sanitizeSpawnProtectionTargets()
    local sanitized = {}
    local indexByIdentifier = {}
    for _, entry in ipairs(spawnProtectionTargets) do
        if type(entry) == 'table' then
            local identifiers = {}
            if type(entry.identifiers) == 'table' then
                for key, value in pairs(entry.identifiers) do
                    if type(key) == 'string' and type(value) == 'string' and value ~= '' then
                        identifiers[key] = value
                    end
                end
            end
            local hasIdentifier = false
            for _, _ in pairs(identifiers) do
                hasIdentifier = true
                break
            end
            if hasIdentifier then
                local normalized = {
                    id = tostring(entry.id or utils.randomId('spawn-guard-')),
                    targetName = sanitizeName(entry.targetName),
                    enabled = entry.enabled ~= false,
                    reason = trimString(entry.reason) or 'Protection anti-spawn ciblée',
                    createdAt = tonumber(entry.createdAt) or os.time(),
                    updatedAt = tonumber(entry.updatedAt) or os.time(),
                    updatedBy = tonumber(entry.updatedBy) or 0,
                    updatedByName = sanitizeName(entry.updatedByName),
                    identifiers = identifiers,
                }

                sanitized[#sanitized + 1] = normalized
                for key, value in pairs(identifiers) do
                    indexByIdentifier[key .. ':' .. value] = normalized
                end
            end
        end
    end

    spawnProtectionTargets = sanitized
    spawnProtectionTargetsByIdentifier = indexByIdentifier
end

local function saveSpawnProtectionTargets()
    local ok, encoded = pcall(json.encode, spawnProtectionTargets)
    if not ok then
        utils.debugLog('Failed to encode spawn protection targets file', encoded)
        return
    end
    SaveResourceFile(resourceName, spawnProtectionTargetsFile, encoded, -1)
end

local function loadSpawnProtectionTargets()
    local data = LoadResourceFile(resourceName, spawnProtectionTargetsFile)
    if not data or data == '' then
        spawnProtectionTargets = {}
        spawnProtectionTargetsByIdentifier = {}
        return
    end

    local ok, decoded = pcall(json.decode, data)
    if not ok or type(decoded) ~= 'table' then
        utils.debugLog('Failed to decode spawn protection targets file, resetting. Error:', decoded)
        spawnProtectionTargets = {}
        spawnProtectionTargetsByIdentifier = {}
        saveSpawnProtectionTargets()
        return
    end

    spawnProtectionTargets = decoded
    sanitizeSpawnProtectionTargets()
end

local function isSpawnProtectionTarget(target)
    if type(target) ~= 'number' or target <= 0 then
        return false, nil
    end
    local identifierMap = getPlayerPersistentIdentifierMap(target)
    for key, value in pairs(identifierMap) do
        local lookup = spawnProtectionTargetsByIdentifier[key .. ':' .. value]
        if lookup and lookup.enabled then
            return true, lookup
        end
    end
    return false, nil
end

local function getDetectionConfig()
    return (cfg and cfg.AutoDetections) or {}
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

local function resolveDetectionWebhook(typeKey)
    local monitoringCfg = Config.Monitoring or {}
    local webhookCfg = Config.Webhooks or {}
    local detections = webhookCfg.Detections or {}
    local fullKey = ('auto_detection_%s'):format(tostring(typeKey or ''))
    return firstWebhook(
        detections[fullKey],
        detections[tostring(typeKey or '')],
        detections.auto_detection_default,
        monitoringCfg.DetectionWebhook,
        webhookCfg.Default,
        Config.Webhook
    )
end

local function maybeCaptureDetectionEvidence(typeKey, target, targetName, identifiers, identifierMap, identifierSummary, message)
    local detectionCfg = getDetectionConfig()
    local evidenceCfg = detectionCfg.EvidenceScreenshot or {}
    if evidenceCfg.Enabled == false then
        return
    end

    if not target or target == 0 or GetPlayerPed(target) == 0 then
        return
    end

    if GetResourceState('screenshot-basic') ~= 'started' then
        return
    end

    local okExport, uploadFn = pcall(function()
        return exports['screenshot-basic'] and exports['screenshot-basic'].requestClientScreenshotUpload
    end)
    if not okExport or type(uploadFn) ~= 'function' then
        return
    end

    local cooldownMs = math.max(10000, math.floor(tonumber(evidenceCfg.CooldownMs) or 90000))
    local now = GetGameTimer()
    local last = detectionScreenshotCooldowns[target] or 0
    if now - last < cooldownMs then
        return
    end
    detectionScreenshotCooldowns[target] = now

    local webhook = evidenceCfg.UploadWebhook
    if type(webhook) ~= 'string' or webhook == '' then
        webhook = resolveDetectionWebhook(typeKey)
    end
    if type(webhook) ~= 'string' or webhook == '' then
        return
    end

    local encoding = tostring(evidenceCfg.Encoding or 'jpg'):lower()
    if encoding ~= 'jpg' and encoding ~= 'png' and encoding ~= 'webp' then
        encoding = 'jpg'
    end

    local options = {
        encoding = encoding,
        fileName = ('visionary-evidence-%s-%s.%s'):format(tostring(target), os.time(), screenshotExtensionForEncoding(encoding)),
    }
    if encoding == 'jpg' then
        options.quality = math.max(35, math.min(85, tonumber(evidenceCfg.Quality) or 65))
    end

    local content = {
        ('📸 Evidence auto (%s)'):format(tostring(typeKey)),
        ('Joueur: %s (#%s)'):format(targetName or 'Unknown', target),
    }
    if type(message) == 'string' and message ~= '' then
        content[#content + 1] = ('Contexte: %s'):format(message)
    end
    if identifierSummary and identifierSummary ~= '' then
        content[#content + 1] = identifierSummary
    end

    local payloadJson = nil
    local okPayload, encodedPayload = pcall(json.encode, {
        username = 'Visionary AC Evidence',
        content = table.concat(content, '\n'),
    })
    if okPayload and type(encodedPayload) == 'string' then
        payloadJson = encodedPayload
    end

    local uploadConfig = {
        url = webhook,
        field = 'file',
        filename = options.fileName,
    }
    if payloadJson then
        uploadConfig.fields = {
            { name = 'payload_json', value = payloadJson },
        }
    end

    uploadFn(target, uploadConfig, options, function(status, body)
        if status ~= 200 and status ~= 204 then
            logger:flag('auto_detection_evidence_failed', target, {
                detection = typeKey,
                target = target,
                target_name = targetName,
                identifiers = identifiers,
                identifier_map = identifierMap,
                identifier_summary = identifierSummary,
                status = status,
                response = body,
                reason = 'evidence_upload_failed',
            })
            return
        end

        logger:flag('auto_detection_evidence_uploaded', target, {
            detection = typeKey,
            target = target,
            target_name = targetName,
            identifiers = identifiers,
            identifier_map = identifierMap,
            identifier_summary = identifierSummary,
            status = status,
        })
    end)
end

local function grantDetectionImmunity(target, key, durationMs)
    if not target or target == 0 then return end
    if not durationMs or durationMs <= 0 then return end
    detectionImmunity[key] = detectionImmunity[key] or {}
    detectionImmunity[key][target] = GetGameTimer() + durationMs
end

local function hasDetectionImmunity(target, key)
    local bucket = detectionImmunity[key]
    if not bucket then return false end
    local expiry = bucket[target]
    if not expiry then return false end
    local now = GetGameTimer()
    if expiry <= now then
        bucket[target] = nil
        return false
    end
    return true
end

local function clearDetectionImmunity(target)
    if not target then return end
    for key, bucket in pairs(detectionImmunity) do
        if bucket[target] then
            bucket[target] = nil
        end
    end
end

local function grantTeleportImmunity(target)
    local detectionCfg = getDetectionConfig()
    local teleportWindow = detectionCfg.TeleportWindowMs or 5000
    local buffer = detectionCfg.TeleportImmunityBufferMs or 2500
    local airwalkSustain = detectionCfg.AirwalkSustainMs or 2000
    local immunityDuration = math.max(teleportWindow + buffer, 6500)

    grantDetectionImmunity(target, 'teleport', immunityDuration)
    grantDetectionImmunity(target, 'high_speed', math.max(immunityDuration, 6000))
    grantDetectionImmunity(target, 'vehicle_speed', math.max(immunityDuration, 6000))
    grantDetectionImmunity(target, 'airwalk', math.max(airwalkSustain + buffer, 6000))
    grantDetectionImmunity(target, 'speed_burst', math.max(immunityDuration, 6000))
    grantDetectionImmunity(target, 'sudden_ascent', math.max(immunityDuration, 6000))
end

local function sendAdminMessage(target, message, payload)
    if not target or target == 0 then return end
    TriggerClientEvent('zvs-ac:admin:notification', target, {
        message = message,
        payload = payload,
    })
end

local function notifyAdmins(message, payload)
    if cfg.NotifyInChat == false then
        return
    end
    for _, player in ipairs(GetPlayers()) do
        local src = tonumber(player)
        if src and utils.isAdmin(src) then
            sendAdminMessage(src, message, payload)
        end
    end
end

local function trimScreenshotHistory(history)
    if type(history) ~= 'table' then
        return
    end
    if screenshotHistoryLimit <= 0 then
        for index = #history, 1, -1 do
            history[index] = nil
        end
        return
    end
    while #history > screenshotHistoryLimit do
        table.remove(history, 1)
    end
end

local function recordScreenshotHistory(admin, entry)
    if not admin then
        return nil
    end
    if screenshotHistoryLimit <= 0 then
        return nil
    end
    screenshotHistory[admin] = screenshotHistory[admin] or {}
    local history = screenshotHistory[admin]
    history[#history + 1] = entry
    trimScreenshotHistory(history)
    return entry
end

local function exportScreenshotHistory(viewer)
    if screenshotHistoryLimit <= 0 then
        return {}
    end
    local history = screenshotHistory[viewer]
    if not history or #history == 0 then
        return {}
    end
    local list = {}
    for index = #history, 1, -1 do
        local entry = history[index]
        list[#list + 1] = {
            id = entry.id,
            image = entry.image,
            target = entry.target,
            targetName = entry.targetName,
            reason = entry.reason,
            identifierSummary = entry.identifierSummary,
            ts = entry.ts,
            admin = entry.admin,
            adminName = entry.adminName,
            uploadStatus = entry.uploadStatus,
            uploadStatusCode = entry.uploadStatusCode,
            uploadError = entry.uploadError,
            uploadUrl = entry.uploadUrl,
        }
    end
    return list
end

local function clearScreenshotHistory(admin)
    screenshotHistory[admin] = nil
end

local function rebuildScreenshotHistoryLimit()
    local limit = cfg and cfg.ScreenshotHistoryLimit
    if type(limit) ~= 'number' then
        screenshotHistoryLimit = 8
    else
        screenshotHistoryLimit = math.floor(limit)
    end
    if screenshotHistoryLimit < 0 then
        screenshotHistoryLimit = 0
    end
    if screenshotHistoryLimit == 0 then
        for admin, _ in pairs(screenshotHistory) do
            screenshotHistory[admin] = nil
        end
    else
        for _, history in pairs(screenshotHistory) do
            trimScreenshotHistory(history)
        end
    end
end


local noteCategories = {
    observation = 'Observation',
    incident = 'Incident',
    surveillance = 'Surveillance',
    support = 'Support',
}

local function normalizeNoteCategory(value)
    if type(value) ~= 'string' then
        return 'observation', noteCategories.observation
    end

    local lowered = value:lower():gsub('%s+', '_'):gsub('[^%w_%-]', '')
    if lowered == '' then
        lowered = 'observation'
    end

    if noteCategories[lowered] then
        return lowered, noteCategories[lowered]
    end

    return 'observation', noteCategories.observation
end

local function trimModerationNotes()
    if moderationNotesLimit <= 0 then
        moderationNotes = {}
        return
    end

    while #moderationNotes > moderationNotesLimit do
        table.remove(moderationNotes, 1)
    end
end

local function rebuildModerationNotesLimit()
    local limit = cfg and cfg.NotesHistoryLimit
    if type(limit) ~= 'number' then
        moderationNotesLimit = 60
    else
        moderationNotesLimit = math.floor(limit)
    end

    if moderationNotesLimit < 0 then
        moderationNotesLimit = 0
    end

    trimModerationNotes()
end

local function saveModerationNotes()
    local ok, encoded = pcall(json.encode, moderationNotes)
    if not ok then
        utils.debugLog('Failed to encode moderation notes file', encoded)
        return
    end

    SaveResourceFile(resourceName, 'data/moderation_notes.json', encoded, -1)
end

local function loadModerationNotes()
    local data = LoadResourceFile(resourceName, 'data/moderation_notes.json')
    if not data or data == '' then
        moderationNotes = {}
        return
    end

    local ok, decoded = pcall(json.decode, data)
    if not ok or type(decoded) ~= 'table' then
        utils.debugLog('Failed to decode moderation notes file, resetting. Error:', decoded)
        moderationNotes = {}
        saveModerationNotes()
        return
    end

    moderationNotes = decoded
    trimModerationNotes()
end

local function exportModerationNotes()
    local list = {}
    for index = #moderationNotes, 1, -1 do
        local entry = moderationNotes[index]
        if type(entry) == 'table' then
            list[#list + 1] = {
                id = entry.id,
                target = entry.target,
                targetName = entry.targetName,
                admin = entry.admin,
                adminName = entry.adminName,
                category = entry.category,
                categoryLabel = entry.categoryLabel,
                message = entry.message,
                createdAt = entry.createdAt,
                identifierSummary = entry.identifierSummary,
                coords = entry.coords,
            }
        end
    end

    return list
end

local function recordModerationNote(entry)
    if type(entry) ~= 'table' then
        return
    end

    entry.id = entry.id or utils.randomId('note-')
    entry.createdAt = entry.createdAt or os.time()
    moderationNotes[#moderationNotes + 1] = entry
    trimModerationNotes()
    saveModerationNotes()
end

local deniedAdminLogCooldown = {}

ensureAdmin = function(src)
    src = tonumber(src)
    if not src or src <= 0 then
        return false
    end

    if not utils.isAdmin(src) then
        local now = GetGameTimer and GetGameTimer() or math.floor(os.clock() * 1000)
        local nextAllowed = deniedAdminLogCooldown[src] or 0
        if now >= nextAllowed then
            deniedAdminLogCooldown[src] = now + 10000
            logger:flag('admin_tools_denied', src, { reason = 'insufficient_permissions' })
            sendAdminMessage(src, 'Visionary AC: acces refuse.')
        end
        return false
    end
    return true
end

local function getPlayerCoords(src)
    local ped = GetPlayerPed(src)
    if ped == 0 then return nil end
    local coords = GetEntityCoords(ped)
    if not coords then return nil end
    local heading = GetEntityHeading(ped) or 0.0
    return {
        x = coords.x + 0.0,
        y = coords.y + 0.0,
        z = coords.z + 0.0,
        heading = heading + 0.0,
    }
end

local function toCoordsTable(vec)
    if not vec then
        return nil
    end
    return {
        x = (vec.x or 0.0) + 0.0,
        y = (vec.y or 0.0) + 0.0,
        z = (vec.z or 0.0) + 0.0,
    }
end

local function distanceSquared(a, b)
    if not a or not b then
        return math.huge
    end
    local dx = (a.x or 0.0) - (b.x or 0.0)
    local dy = (a.y or 0.0) - (b.y or 0.0)
    local dz = (a.z or 0.0) - (b.z or 0.0)
    return dx * dx + dy * dy + dz * dz
end

local function buildPlayerPedSet()
    local set = {}
    for _, playerId in ipairs(GetPlayers()) do
        local numeric = tonumber(playerId)
        if numeric then
            local ped = GetPlayerPed(numeric)
            if ped and ped ~= 0 then
                set[ped] = true
            end
        end
    end
    return set
end

local function deleteEntity(entity, deleteFn)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return false
    end
    if SetEntityAsMissionEntity then
        SetEntityAsMissionEntity(entity, true, true)
    end
    if deleteFn then
        deleteFn(entity)
    else
        DeleteEntity(entity)
    end
    if DoesEntityExist(entity) then
        DeleteEntity(entity)
    end
    return not DoesEntityExist(entity)
end

local function isVehicleOccupiedByPlayer(vehicle, playerPeds)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return false
    end
    if not playerPeds then
        return false
    end
    for ped in pairs(playerPeds) do
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            local vehicleHandle = GetVehiclePedIsIn(ped, false)
            if vehicleHandle and vehicleHandle == vehicle then
                return true
            end
        end
    end
    return false
end

local function clearEntitiesAroundCoords(coords, radius)
    local removed = { vehicles = 0, peds = 0, objects = 0 }
    if not coords or not radius or radius <= 0 then
        return removed
    end

    local center = toCoordsTable(coords)
    if not center then
        return removed
    end

    local radiusSq = radius * radius
    local playerPeds = buildPlayerPedSet()

    for _, vehicle in ipairs(GetAllVehicles()) do
        if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
            local vehicleCoords = toCoordsTable(GetEntityCoords(vehicle))
            if vehicleCoords and distanceSquared(vehicleCoords, center) <= radiusSq then
                if not isVehicleOccupiedByPlayer(vehicle, playerPeds) then
                    if deleteEntity(vehicle, DeleteVehicle) then
                        removed.vehicles = removed.vehicles + 1
                    end
                end
            end
        end
    end

    for _, ped in ipairs(GetAllPeds()) do
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            if not playerPeds[ped] then
                local pedCoords = toCoordsTable(GetEntityCoords(ped))
                if pedCoords and distanceSquared(pedCoords, center) <= radiusSq then
                    if deleteEntity(ped, DeletePed) then
                        removed.peds = removed.peds + 1
                    end
                end
            end
        end
    end

    for _, object in ipairs(GetAllObjects()) do
        if object and object ~= 0 and DoesEntityExist(object) then
            local objectCoords = toCoordsTable(GetEntityCoords(object))
            if objectCoords and distanceSquared(objectCoords, center) <= radiusSq then
                if deleteEntity(object, DeleteObject) then
                    removed.objects = removed.objects + 1
                end
            end
        end
    end

    return removed
end

local function clampFeed()
    while #suspiciousFeed > feedLimit do
        table.remove(suspiciousFeed)
    end
end

local function saveSuspiciousFeed()
    local payload = {
        version = 1,
        entries = suspiciousFeed,
    }

    local ok, encoded = pcall(json.encode, payload)
    if not ok then
        utils.debugLog('Failed to encode suspicious feed', encoded)
        return false, 'encode_failed'
    end

    local success = SaveResourceFile(resourceName, suspiciousFeedFile, encoded, -1)
    if not success then
        utils.debugLog('Failed to write suspicious feed file')
        return false, 'write_failed'
    end

    return true
end

local function scheduleSuspiciousFeedSave()
    if feedSaveScheduled then return end
    feedSaveScheduled = true
    SetTimeout(1500, function()
        feedSaveScheduled = false
        saveSuspiciousFeed()
    end)
end

local function scheduleStateBroadcast()
    if stateBroadcastScheduled then return end
    stateBroadcastScheduled = true
    SetTimeout(500, function()
        stateBroadcastScheduled = false
        if broadcastState then
            broadcastState()
        end
    end)
end

local function loadSuspiciousFeed()
    local data = LoadResourceFile(resourceName, suspiciousFeedFile)
    if not data or data == '' then
        suspiciousFeed = {}
        return
    end

    local ok, decoded = pcall(json.decode, data)
    if not ok or type(decoded) ~= 'table' then
        utils.debugLog('Failed to decode suspicious feed file, resetting.', decoded)
        suspiciousFeed = {}
        return
    end

    local entries = decoded.entries
    if type(entries) ~= 'table' then
        entries = decoded
    end

    suspiciousFeed = {}
    for _, entry in ipairs(entries) do
        if type(entry) == 'table' then
            suspiciousFeed[#suspiciousFeed + 1] = entry
        end
    end

    clampFeed()
end

local function pushFeed(entry)
    entry.id = entry.id or utils.randomId('flag-')
    entry.ts = entry.ts or utils.iso8601()
    entry.message = entry.message or entry.type or 'Notification'
    table.insert(suspiciousFeed, 1, entry)
    clampFeed()
    scheduleSuspiciousFeedSave()

    if entry.log ~= false then
        logger:flag(entry.logType or entry.type or 'admin_flag', entry.src or 0, entry.payload or {})
    end

    if entry.notify ~= false then
        notifyAdmins(entry.notifyMessage or entry.message, entry.payload)
    end

    scheduleStateBroadcast()
end

local function cleanupPreviewPortraitRequests()
    local now = GetGameTimer()
    for id, request in pairs(previewPortraitRequests) do
        if request.expires and request.expires <= now then
            previewPortraitRequests[id] = nil
        end
    end
end

local function rememberPortraitRequest(admin, target)
    local key = ('%s:%s'):format(admin, target)
    previewPortraitLastRequest[key] = GetGameTimer()
end

local function canRequestPortrait(admin, target)
    local key = ('%s:%s'):format(admin, target)
    local last = previewPortraitLastRequest[key] or 0
    local now = GetGameTimer()
    local detectionCfg = cfg and cfg.AutoDetections or {}
    local cooldown = detectionCfg.PortraitCooldownMs or 4000
    if now - last < cooldown then
        return false
    end
    return true
end

local function requestPreviewPortrait(admin, target)
    if not admin or not target then return end
    if GetPlayerPed(target) == 0 then return end
    if not canRequestPortrait(admin, target) then return end

    cleanupPreviewPortraitRequests()

    local requestId = utils.randomId('portrait-')
    previewPortraitRequests[requestId] = {
        admin = admin,
        target = target,
        expires = GetGameTimer() + 8000,
    }
    rememberPortraitRequest(admin, target)

    TriggerClientEvent('zvs-ac:admin:requestPortrait', target, {
        admin = admin,
        requestId = requestId,
    })
end

local function pushDetectionFlag(typeKey, target, message, payload)
    local targetName = sanitizeName(GetPlayerName(target))
    local identifiers, primary = collectPlayerIdentifiers(target)
    payload = payload or {}
    payload.detection = payload.detection or typeKey
    payload.description = payload.description or message
    payload.target = payload.target or target
    payload.target_name = payload.target_name or targetName
    payload.identifiers = payload.identifiers or identifiers
    payload.identifier_map = payload.identifier_map or primary
    if payload.identifier_summary == nil then
        local summary = formatPrimaryIdentifiers(payload.identifier_map)
        if #summary > 0 then
            payload.identifier_summary = table.concat(summary, '\n')
        end
    end

    TriggerEvent('zvs-ac:risk:record', target, typeKey, payload)

    pushFeed({
        type = 'Detection',
        src = target,
        message = message,
        payload = payload,
        notify = false,
        logType = 'auto_detection_' .. tostring(typeKey),
    })

    maybeCaptureDetectionEvidence(
        typeKey,
        target,
        targetName,
        identifiers,
        payload.identifier_map,
        payload.identifier_summary,
        message
    )
end

local function getRecentDetectionsForTarget(target, limit)
    local numericTarget = tonumber(target)
    if not numericTarget then
        return {}
    end

    local maxItems = math.max(1, math.floor(tonumber(limit) or 3))
    local output = {}
    local nowMs = os.time() * 1000

    for _, entry in ipairs(suspiciousFeed) do
        if #output >= maxItems then
            break
        end

        if type(entry) == 'table' and type(entry.payload) == 'table' and entry.payload.detection then
            local entryTarget = tonumber(entry.src or entry.payload.target)
            if entryTarget and entryTarget == numericTarget then
                local label = tostring(entry.payload.detection)
                local elapsedMs = nil
                if type(entry.ts) == 'string' and entry.ts ~= '' then
                    local stamp = entry.ts:gsub('Z$', '')
                    local year, month, day, hour, minute, second = stamp:match('^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)')
                    if year then
                        local eventEpoch = os.time({
                            year = tonumber(year),
                            month = tonumber(month),
                            day = tonumber(day),
                            hour = tonumber(hour),
                            min = tonumber(minute),
                            sec = tonumber(second),
                        })
                        if eventEpoch then
                            elapsedMs = math.max(0, nowMs - (eventEpoch * 1000))
                        end
                    end
                end

                output[#output + 1] = {
                    type = tostring(entry.payload.detection),
                    label = label,
                    elapsedMs = elapsedMs,
                }
            end
        end
    end

    return output
end

local function cloneVector3(vec)
    local vecType = type(vec)
    if vecType ~= 'table' and vecType ~= 'vector3' then
        return nil
    end
    local x = tonumber(vec.x or vec[1])
    local y = tonumber(vec.y or vec[2])
    local z = tonumber(vec.z or vec[3])
    if not x or not y or not z then
        return nil
    end
    return {
        x = x + 0.0,
        y = y + 0.0,
        z = z + 0.0,
    }
end

local function distanceBetween(a, b)
    if not a or not b then
        return 0.0
    end
    local dx = (a.x or 0.0) - (b.x or 0.0)
    local dy = (a.y or 0.0) - (b.y or 0.0)
    local dz = (a.z or 0.0) - (b.z or 0.0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function detectionCooldownSatisfied(bucket, target, cooldownMs)
    local now = GetGameTimer()
    local expiry = bucket[target]
    if expiry and expiry > now then
        return false
    end
    bucket[target] = now + cooldownMs
    return true
end

local function vectorSubtract(a, b)
    return {
        x = (a.x or 0.0) - (b.x or 0.0),
        y = (a.y or 0.0) - (b.y or 0.0),
        z = (a.z or 0.0) - (b.z or 0.0),
    }
end

local function vectorDot(a, b)
    return ((a.x or 0.0) * (b.x or 0.0)) + ((a.y or 0.0) * (b.y or 0.0)) + ((a.z or 0.0) * (b.z or 0.0))
end

local function vectorLength(a)
    return math.sqrt(vectorDot(a, a))
end

local function cameraRotationToForward(rot)
    if type(rot) ~= 'table' then
        return nil
    end

    local pitch = math.rad(tonumber(rot.x) or 0.0)
    local yaw = math.rad(tonumber(rot.z) or 0.0)
    local forward = {
        x = -math.sin(yaw) * math.cos(pitch),
        y = math.cos(yaw) * math.cos(pitch),
        z = math.sin(pitch),
    }
    local length = vectorLength(forward)
    if length <= 0.0001 then
        return nil
    end
    return {
        x = forward.x / length,
        y = forward.y / length,
        z = forward.z / length,
    }
end

local function distancePointToCameraRay(point, origin, forward)
    local toPoint = vectorSubtract(point, origin)
    local projection = vectorDot(toPoint, forward)
    if projection <= 0 then
        return nil, projection
    end
    local closest = {
        x = origin.x + (forward.x * projection),
        y = origin.y + (forward.y * projection),
        z = origin.z + (forward.z * projection),
    }
    return distanceBetween(point, closest), projection
end

local function getPotentialCameraLookTarget(target, cameraCoords, forward, maxDistance, radius)
    local best = nil
    local bestScore = nil

    for _, playerId in ipairs(GetPlayers()) do
        local other = tonumber(playerId)
        if other and other ~= target then
            local ped = GetPlayerPed(other)
            if ped and ped ~= 0 then
                local coords = getPlayerCoords(other)
                if coords then
                    local point = { x = coords.x + 0.0, y = coords.y + 0.0, z = (coords.z or 0.0) + 0.95 }
                    local distanceFromRay, projection = distancePointToCameraRay(point, cameraCoords, forward)
                    if distanceFromRay and projection <= maxDistance and distanceFromRay <= radius then
                        local score = distanceFromRay + (projection * 0.012)
                        if not bestScore or score < bestScore then
                            bestScore = score
                            best = {
                                id = other,
                                name = sanitizeName(GetPlayerName(other)),
                                distanceFromRay = distanceFromRay,
                                projection = projection,
                                coords = coords,
                            }
                        end
                    end
                end
            end
        end
    end

    return best
end

function evaluateSpectatorCameraAbuse(target, camera, targetCoords)
    if not target or target == 0 then return end
    if not isDefenseEnabled('auto_detections') then return end
    if utils.isAdmin(target) or cloakedAdmins[target] ~= nil then return end
    if hasDetectionImmunity(target, 'spectator_abuse') then return end

    local detectionCfg = cfg and cfg.AutoDetections or {}
    local enabled = detectionCfg.SpectatorCameraDetection ~= false
    if not enabled then return end

    local cameraCoords = cloneVector3(camera)
    targetCoords = cloneVector3(targetCoords) or getPlayerCoords(target)
    if not cameraCoords or not targetCoords then return end

    local minCameraDistance = tonumber(detectionCfg.SpectatorCameraMinDistance) or 28.0
    local maxTargetRayDistance = tonumber(detectionCfg.SpectatorCameraRayDistance) or 220.0
    local rayRadius = tonumber(detectionCfg.SpectatorCameraRayRadius) or 3.0
    local cooldown = tonumber(detectionCfg.SpectatorCameraCooldownMs) or 45000

    local cameraDistance = distanceBetween(cameraCoords, targetCoords)
    if cameraDistance < minCameraDistance then
        return
    end

    local forward = cameraRotationToForward(camera.rot)
    if not forward then
        return
    end

    local observed = getPotentialCameraLookTarget(target, cameraCoords, forward, maxTargetRayDistance, rayRadius)
    if not observed then
        return
    end

    if detectionCooldownSatisfied(previewDetectionState.spectatorAbuse, target, cooldown) then
        local detectionPayload = {
            target = target,
            observed = observed.id,
            observed_name = observed.name,
            detection = 'spectator_abuse',
            camera_distance = cameraDistance,
            ray_distance = observed.distanceFromRay,
            ray_projection = observed.projection,
            camera = cameraCoords,
            coords = targetCoords,
            observed_coords = cloneVector3(observed.coords),
        }
        pushDetectionFlag('spectator_abuse', target, (
            'Detection: %s semble utiliser une camera de spectateur externe vers %s (camera %.1f m de son ped).'
        ):format(sanitizeName(GetPlayerName(target)), observed.name, cameraDistance), detectionPayload)

        if zVS.detectionFramework and type(zVS.detectionFramework.recordCameraProbe) == 'function' then
            detectionPayload.detection = 'freecam_pov_mismatch'
            zVS.detectionFramework:recordCameraProbe(target, detectionPayload)
        end
    end
end

local function evaluatePreviewDetections(target, ped, snapshot)
    if not target or target == 0 then return end
    if not ped or ped == 0 then return end
    if not isDefenseEnabled('auto_detections') then return end

    local detectionCfg = cfg and cfg.AutoDetections or {}

    local highSpeedThreshold = detectionCfg.HighSpeedThreshold or 140.0
    local highSpeedCooldown = detectionCfg.HighSpeedCooldownMs or 15000
    local vehicleSpeedThreshold = detectionCfg.VehicleSpeedThreshold or 260.0
    local vehicleSpeedCooldown = detectionCfg.VehicleSpeedCooldownMs or 20000
    local invincibleCooldown = detectionCfg.InvincibleCooldownMs or 45000
    local excessHealthCooldown = detectionCfg.ExcessHealthCooldownMs or 30000
    local excessHealthTolerance = detectionCfg.ExcessHealthTolerance or 15
    local armorThreshold = detectionCfg.ArmorThreshold or 100
    local armorCooldown = detectionCfg.ArmorCooldownMs or 30000
    local invisibleCooldown = detectionCfg.InvisibleCooldownMs or 45000
    local teleportDistance = detectionCfg.TeleportDistance or 150.0
    local teleportWindow = detectionCfg.TeleportWindowMs or 5000
    local teleportCooldown = detectionCfg.TeleportCooldownMs or 45000
    local teleportSpeedThreshold = detectionCfg.TeleportSpeedThreshold or 220.0
    local airwalkHeightThreshold = detectionCfg.AirwalkHeightThreshold or 6.5
    local airwalkSpeedTolerance = detectionCfg.AirwalkSpeedTolerance or 28.0
    local airwalkCooldown = detectionCfg.AirwalkCooldownMs or 35000
    local airwalkSustainMs = detectionCfg.AirwalkSustainMs or 2000

    local accelerationThreshold = detectionCfg.AccelerationThreshold or 90.0
    local accelerationWindow = detectionCfg.AccelerationWindowMs or 1200
    local accelerationCooldown = detectionCfg.AccelerationCooldownMs or 25000
    local accelerationMinSpeed = detectionCfg.AccelerationMinSpeed or 120.0
    local ascentHeightThreshold = detectionCfg.AscentHeightThreshold or 9.0
    local ascentWindow = detectionCfg.AscentWindowMs or 1500
    local ascentCooldown = detectionCfg.AscentCooldownMs or 32000
    local ascentHorizontalTolerance = detectionCfg.AscentHorizontalTolerance or 25.0
    local ascentVerticalSpeed = detectionCfg.AscentVerticalSpeed or 6.0
    local godmodeHealthFloor = detectionCfg.GodmodeHealthFloor or 170
    local godmodeStationaryWindow = detectionCfg.GodmodeStationaryWindowMs or 4500
    local godmodeCooldown = detectionCfg.GodmodeCooldownMs or 45000

    local coords = snapshot.coords and cloneVector3(snapshot.coords) or nil
    local speed = snapshot.speed or 0.0
    local inVehicle = snapshot.inVehicle
    local health = snapshot.health
    local isAdmin = utils.isAdmin(target)
    local isCloaked = cloakedAdmins[target] ~= nil
    local skipAdminDetections = isAdmin or isCloaked
    local now = GetGameTimer()
    local lastSnapshot = previewDetectionState.lastSnapshots[target]

    local isFalling = safePedState(ped, IsPedFalling)
    local isRagdoll = safePedState(ped, IsPedRagdoll)
    local isJumping = safePedState(ped, IsPedJumping)
    local isParachuting = safePedState(ped, IsPedInParachuteFreeFall)
    local isSwimming = safePedState(ped, IsPedSwimming)
    if safePedState(ped, IsPedSwimmingUnderWater) then
        isSwimming = true
    end

    if
        not skipAdminDetections
        and not hasDetectionImmunity(target, 'high_speed')
        and speed
        and speed > highSpeedThreshold
        and not inVehicle
    then
        if not isFalling and not isRagdoll and not isJumping and not isParachuting then
            if detectionCooldownSatisfied(previewDetectionState.highSpeed, target, highSpeedCooldown) then
                pushDetectionFlag('high_speed', target, (
                    'Detection: %s semble se deplacer anormalement vite (%.1f km/h).'
                ):format(sanitizeName(GetPlayerName(target)), speed), {
                    target = target,
                    speed = speed,
                    detection = 'high_speed',
                    coords = coords,
                })
            end
        end
    end

    if
        not skipAdminDetections
        and not hasDetectionImmunity(target, 'speed_burst')
        and speed
        and accelerationThreshold > 0
        and accelerationWindow > 0
        and lastSnapshot
        and lastSnapshot.speed
        and not inVehicle
    then
        local deltaMs = now - (lastSnapshot.ts or 0)
        if deltaMs > 0 and deltaMs <= accelerationWindow then
            local deltaSpeed = speed - (lastSnapshot.speed or 0.0)
            if deltaSpeed >= accelerationThreshold and speed >= accelerationMinSpeed then
                if not isFalling and not isRagdoll and not isJumping and not isParachuting then
                    if detectionCooldownSatisfied(previewDetectionState.speedBurst, target, accelerationCooldown) then
                        pushDetectionFlag('speed_burst', target, (
                            'Detection: %s accelere anormalement vite (%.1f km/h gagnes en %.0f ms).'
                        ):format(sanitizeName(GetPlayerName(target)), deltaSpeed, deltaMs), {
                            target = target,
                            detection = 'speed_burst',
                            delta_speed = deltaSpeed,
                            elapsed_ms = deltaMs,
                            current_speed = speed,
                            previous_speed = lastSnapshot.speed or 0.0,
                            coords = coords,
                        })
                    end
                end
            end
        end
    end

    if
        not skipAdminDetections
        and coords
        and teleportDistance > 0
        and teleportWindow > 0
        and teleportSpeedThreshold > 0
    then
        if
            lastSnapshot
            and lastSnapshot.coords
            and not inVehicle
            and not lastSnapshot.inVehicle
            and not hasDetectionImmunity(target, 'teleport')
        then
            local deltaMs = now - (lastSnapshot.ts or 0)
            if deltaMs > 0 and deltaMs <= teleportWindow then
                local travelled = distanceBetween(coords, lastSnapshot.coords)
                if travelled >= teleportDistance then
                    local travelSpeedMs = travelled / (deltaMs / 1000.0)
                    local travelSpeedKmh = travelSpeedMs * 3.6
                    if travelSpeedKmh >= teleportSpeedThreshold and not isParachuting and not isFalling and not isRagdoll then
                        if detectionCooldownSatisfied(previewDetectionState.teleport, target, teleportCooldown) then
                            pushDetectionFlag('teleport', target, (
                                'Detection: %s semble se teleporter (%.0f m parcourus en %.1f s).'
                            ):format(sanitizeName(GetPlayerName(target)), travelled, deltaMs / 1000.0), {
                                target = target,
                                detection = 'teleport',
                                distance = travelled,
                                deltaMs = deltaMs,
                                estimatedSpeed = travelSpeedKmh,
                                from_coords = cloneVector3(lastSnapshot.coords),
                                to_coords = coords,
                            })
                        end
                    end
                end
            end
        end
    end

    if
        not skipAdminDetections
        and not hasDetectionImmunity(target, 'vehicle_speed')
        and speed
        and inVehicle
        and speed > vehicleSpeedThreshold
    then
        if detectionCooldownSatisfied(previewDetectionState.highSpeedVehicle, target, vehicleSpeedCooldown) then
            pushDetectionFlag('vehicle_speed', target, (
                'Detection: %s atteint une vitesse extreme en vehicule (%.1f km/h).'
            ):format(sanitizeName(GetPlayerName(target)), speed), {
                target = target,
                speed = speed,
                detection = 'vehicle_speed',
                coords = coords,
            })
        end
    end

    if not skipAdminDetections and GetPlayerInvincible(target) then
        if detectionCooldownSatisfied(previewDetectionState.invincible, target, invincibleCooldown) then
            pushDetectionFlag('invincible', target, (
                'Detection: %s semble beneficier d\'une invincibilite.'
            ):format(sanitizeName(GetPlayerName(target))), {
                target = target,
                detection = 'invincible',
            })
        end
    end

    if
        not skipAdminDetections
        and not hasDetectionImmunity(target, 'godmode')
        and lastSnapshot
        and lastSnapshot.health
        and health
        and health >= godmodeHealthFloor
    then
        local deltaMs = now - (lastSnapshot.ts or 0)
        local healthDelta = math.abs((health or 0) - (lastSnapshot.health or 0))
        if deltaMs > 0 and deltaMs <= godmodeStationaryWindow and healthDelta <= 0.1 and not isSwimming then
            if detectionCooldownSatisfied(previewDetectionState.invincible, target, godmodeCooldown) then
                pushDetectionFlag('godmode_pattern', target, (
                    'Detection: %s conserve sa sante de façon anormale malgré le suivi anti-cheat.'
                ):format(sanitizeName(GetPlayerName(target))), {
                    target = target,
                    detection = 'godmode_pattern',
                    health = health,
                    previous_health = lastSnapshot.health,
                    delta_ms = deltaMs,
                    coords = coords,
                })
            end
        end
    end

    if not skipAdminDetections and health then
        local maxHealth = GetEntityMaxHealth(ped)
        if maxHealth and maxHealth > 0 and health > (maxHealth + excessHealthTolerance) then
            if detectionCooldownSatisfied(previewDetectionState.excessHealth, target, excessHealthCooldown) then
                pushDetectionFlag('excess_health', target, (
                    'Detection: %s affiche une sante inhabituelle (%d / %d).'
                ):format(sanitizeName(GetPlayerName(target)), math.floor(health + 0.5), maxHealth), {
                    target = target,
                    health = health,
                    maxHealth = maxHealth,
                    detection = 'excess_health',
                    coords = coords,
                })
            end
        end
    end

    local armour = snapshot.armor or GetPedArmour(ped)
    armour = armour and tonumber(armour) or nil
    if not skipAdminDetections and armour then
        if armour > armorThreshold then
            if detectionCooldownSatisfied(previewDetectionState.excessArmor, target, armorCooldown) then
                pushDetectionFlag('excess_armor', target, (
                    'Detection: %s dispose d\'une armure anormalement elevee (%d).'
                ):format(sanitizeName(GetPlayerName(target)), math.floor(armour + 0.5)), {
                    target = target,
                    armour = armour,
                    detection = 'excess_armor',
                    coords = coords,
                })
            end
        end
    end

    local heightAboveGround = 0.0
    if type(GetEntityHeightAboveGround) == 'function' then
        local height = GetEntityHeightAboveGround(ped)
        if height then
            heightAboveGround = height + 0.0
        end
    end

    local velocity = type(GetEntityVelocity) == 'function' and GetEntityVelocity(ped) or nil
    local velX, velY, velZ = 0.0, 0.0, 0.0
    local velType = type(velocity)
    if velocity and (velType == 'table' or velType == 'vector3') then
        velX = tonumber(velocity.x or velocity[1]) or 0.0
        velY = tonumber(velocity.y or velocity[2]) or 0.0
        velZ = tonumber(velocity.z or velocity[3]) or 0.0
    end
    local horizontalSpeedKmh = math.sqrt(velX * velX + velY * velY) * 3.6
    local verticalSpeed = math.abs(velZ)

    if
        not skipAdminDetections
        and not hasDetectionImmunity(target, 'airwalk')
        and not inVehicle
        and airwalkHeightThreshold > 0
        and heightAboveGround >= airwalkHeightThreshold
        and airwalkSpeedTolerance > 0
        and airwalkSustainMs > 0
    then
        local timeSinceLast = lastSnapshot and (now - (lastSnapshot.ts or 0)) or 0
        local previousHeight = lastSnapshot and lastSnapshot.height or 0.0
        local sustained = previousHeight >= (airwalkHeightThreshold - 0.75)
            and timeSinceLast >= airwalkSustainMs
            and timeSinceLast <= 10000
        if sustained and horizontalSpeedKmh >= airwalkSpeedTolerance and verticalSpeed <= 6.0 then
            if not isFalling and not isRagdoll and not isJumping and not isParachuting and not isSwimming then
                if detectionCooldownSatisfied(previewDetectionState.airwalk, target, airwalkCooldown) then
                    pushDetectionFlag('airwalk', target, (
                        'Detection: %s se deplace dans les airs (%.1f m au-dessus du sol, %.0f km/h).'
                    ):format(sanitizeName(GetPlayerName(target)), heightAboveGround, horizontalSpeedKmh), {
                        target = target,
                        detection = 'airwalk',
                        height = heightAboveGround,
                        horizontalSpeed = horizontalSpeedKmh,

                        coords = coords,
                    })
                end
            end
        end
    end

    if
        not skipAdminDetections
        and coords
        and lastSnapshot
        and lastSnapshot.coords
        and ascentHeightThreshold > 0
        and ascentWindow > 0
        and not inVehicle
    then
        local deltaMs = now - (lastSnapshot.ts or 0)
        if deltaMs > 0 and deltaMs <= ascentWindow then
            local deltaHeight = (coords.z or 0.0) - (lastSnapshot.coords.z or 0.0)
            if deltaHeight >= ascentHeightThreshold and horizontalSpeedKmh <= ascentHorizontalTolerance and velZ >= ascentVerticalSpeed then
                if not isFalling and not isRagdoll and not isParachuting and not isSwimming then
                    if detectionCooldownSatisfied(previewDetectionState.suddenAscent, target, ascentCooldown) then
                        pushDetectionFlag('sudden_ascent', target, (
                            'Detection: %s gagne de l\'altitude de facon suspecte (%.1f m en %.0f ms).'
                        ):format(sanitizeName(GetPlayerName(target)), deltaHeight, deltaMs), {
                            target = target,
                            detection = 'sudden_ascent',
                            delta_height = deltaHeight,
                            elapsed_ms = deltaMs,
                            vertical_speed = velZ,
                            horizontal_speed = horizontalSpeedKmh,
                            coords = coords,
                        })
                    end
                end
            end
        end
    end
    local visible = IsEntityVisible(ped)
    local alpha = snapshot and snapshot.alpha
    if alpha == nil and type(GetEntityAlpha) == 'function' then
        alpha = GetEntityAlpha(ped)
    end
    if (not visible or (alpha and alpha < 200)) and not isCloaked and not isAdmin then
        if detectionCooldownSatisfied(previewDetectionState.invisible, target, invisibleCooldown) then
            pushDetectionFlag('invisible', target, (
                'Detection: %s semble invisible ou translucide pour les autres joueurs.'
            ):format(sanitizeName(GetPlayerName(target))), {
                target = target,
                detection = 'invisible',
                alpha = alpha,
                visible = visible,
                coords = coords,
            })
        end
    end

    previewDetectionState.lastSnapshots[target] = {
        coords = coords,
        inVehicle = inVehicle,
        ts = now,
        height = heightAboveGround,
        speed = speed,
        health = health,
    }
end

local function stopSpectate(admin, opts)
    local session = spectateSessions[admin]
    if not session then return end

    local target = session.target
    if target then
        local watchers = spectateTargetWatchers[target]
        if watchers then
            watchers[admin] = nil
            if next(watchers) == nil then
                spectateTargetWatchers[target] = nil
                spectateSyncCache[target] = nil
                spectateCameraProbeThrottle[target] = nil
            end
        end
    end

    spectateSessions[admin] = nil
    spectateSyncThrottle[admin] = nil
    if not (opts and opts.noClientEvent) then
        TriggerClientEvent('zvs-ac:admin:spectateTarget', admin, {
            enabled = false,
            reason = opts and opts.reason,
        })
    end

    if not opts or opts.log ~= false then
        local adminName = sanitizeName(GetPlayerName(admin))
        local targetName = sanitizeName(GetPlayerName(session.target))
        pushFeed({
            type = 'admin_spectate_stop',
            src = admin,
            message = ('%s a quitte le mode spectateur sur %s'):format(adminName, targetName),
            payload = {
                admin = admin,
                admin_name = adminName,
                target = session.target,
                target_name = targetName,
                reason = opts and opts.reason or 'manual',
            },
        })
    end

    if opts and opts.reason == 'manual' then
        sendAdminMessage(admin, 'Visionary AC: spectateur desactive.')
    elseif opts and opts.reason == 'target_left' then
        sendAdminMessage(admin, 'Visionary AC: session spectateur fermee (cible indisponible).')
    end

    broadcastState()
end

local function cleanupModeration()
    local dirty = false
    for target, _ in pairs(frozenPlayers) do
        if GetPlayerPed(target) == 0 then
            frozenPlayers[target] = nil
            dirty = true
        end
    end

    for target, _ in pairs(weaponLocks) do
        if GetPlayerPed(target) == 0 then
            weaponLocks[target] = nil
            dirty = true
        end
    end

    for admin, session in pairs(spectateSessions) do
        if GetPlayerPed(admin) == 0 then
            local target = session and session.target
            if target and spectateTargetWatchers[target] then
                spectateTargetWatchers[target][admin] = nil
                if next(spectateTargetWatchers[target]) == nil then
                    spectateTargetWatchers[target] = nil
                    spectateSyncCache[target] = nil
                    spectateCameraProbeThrottle[target] = nil
                end
            end
            spectateSessions[admin] = nil
            spectateSyncThrottle[admin] = nil
            dirty = true
        elseif tonumber(session.target) == tonumber(admin) then
            spectateSessions[admin] = nil
            spectateSyncThrottle[admin] = nil
            TriggerClientEvent('zvs-ac:admin:spectateTarget', admin, {
                enabled = false,
                reason = 'self_guard',
            })
            dirty = true
        elseif GetPlayerPed(session.target) == 0 then
            local target = session.target
            TriggerClientEvent('zvs-ac:admin:spectateTarget', admin, {
                enabled = false,
                reason = 'target_left',
            })
            spectateSessions[admin] = nil
            spectateSyncThrottle[admin] = nil
            if target and spectateTargetWatchers[target] then
                spectateTargetWatchers[target][admin] = nil
                if next(spectateTargetWatchers[target]) == nil then
                    spectateTargetWatchers[target] = nil
                    spectateSyncCache[target] = nil
                    spectateCameraProbeThrottle[target] = nil
                end
            end
            dirty = true
        end
    end

    for admin, _ in pairs(cloakedAdmins) do
        if GetPlayerPed(admin) == 0 then
            cloakedAdmins[admin] = nil
            dirty = true
        end
    end
    return dirty
end

local function exportModeration(viewer)
    cleanupModeration()

    local moderation = {
        frozen = {},
        spectating = {},
        cloaked = {},
        weaponLocks = {},
        spawnProtection = {},
    }

    for target, entry in pairs(frozenPlayers) do
        moderation.frozen[#moderation.frozen + 1] = {
            id = target,
            admin = entry.admin,
            adminName = sanitizeName(GetPlayerName(entry.admin)),
            reason = entry.reason,
            since = entry.since,
        }
    end

    for target, entry in pairs(weaponLocks) do
        moderation.weaponLocks[#moderation.weaponLocks + 1] = {
            id = target,
            admin = entry.admin,
            adminName = entry.adminName or sanitizeName(GetPlayerName(entry.admin)),
            since = entry.since,
        }
    end

    for admin, session in pairs(spectateSessions) do
        moderation.spectating[#moderation.spectating + 1] = {
            admin = admin,
            adminName = sanitizeName(GetPlayerName(admin)),
            target = session.target,
            targetName = sanitizeName(GetPlayerName(session.target)),
            since = session.since,
        }
    end

    for admin, entry in pairs(cloakedAdmins) do
        moderation.cloaked[#moderation.cloaked + 1] = {
            id = admin,
            adminName = sanitizeName(GetPlayerName(admin)),
            since = entry.since,
        }
    end

    for _, entry in ipairs(spawnProtectionTargets) do
        moderation.spawnProtection[#moderation.spawnProtection + 1] = {
            id = entry.id,
            enabled = entry.enabled and true or false,
            targetName = entry.targetName,
            reason = entry.reason,
            createdAt = entry.createdAt,
            updatedAt = entry.updatedAt,
            updatedBy = entry.updatedBy,
            updatedByName = entry.updatedByName,
        }
    end

    if viewer then
        moderation.viewerId = viewer
        local spectating = spectateSessions[viewer]
        if spectating then
            moderation.viewerSpectating = spectating.target
        end
        if cloakedAdmins[viewer] then
            moderation.viewerCloaked = true
        end
    end

    return moderation
end

local function rebuildFeedLimit()
    feedLimit = cfg.FeedLimit or feedLimit
end

local function rebuildBanLookup()
    local now = os.time()
    local indexById = {}
    for index, ban in ipairs(bans) do
        ban.expired = ban.expiresAt and ban.expiresAt ~= 0 and ban.expiresAt <= now or false
        local id = ban.id
        if type(id) == 'string' then
            id = trimString(id)
        end
        if type(id) == 'string' and id ~= '' then
            indexById[id] = index
        end
    end
    banIndexById = indexById
end

local function collectBanIdSet()
    local ids = {}
    for id in pairs(banIndexById) do
        ids[id] = true
    end
    return ids
end

local function normalizeBanEntry(entry, seenIds, now)
    if type(entry) ~= 'table' then
        return nil, true
    end

    local dirty = false
    local effectiveNow = now or os.time()
    local id = entry.id

    if type(entry.name) == 'string' then
        local trimmed = trimString(entry.name)
        if trimmed ~= entry.name then
            entry.name = trimmed
            dirty = true
        end
    end

    if entry.reason ~= nil then
        local reason = entry.reason
        if type(reason) ~= 'string' then
            reason = tostring(reason)
            entry.reason = reason
            dirty = true
        end
        local trimmed = trimString(reason)
        if trimmed ~= reason then
            entry.reason = trimmed
            dirty = true
        end
    else
        entry.reason = ''
        dirty = true
    end

    if entry.bannedBy ~= nil then
        local bannedBy = entry.bannedBy
        if type(bannedBy) ~= 'string' then
            bannedBy = tostring(bannedBy)
            entry.bannedBy = bannedBy
            dirty = true
        end
        local trimmed = trimString(bannedBy)
        if trimmed ~= bannedBy then
            entry.bannedBy = trimmed
            dirty = true
        end
    end

    if type(id) == 'string' then
        id = trimString(id)
    else
        id = ''
    end

    seenIds = seenIds or {}
    if id == '' or seenIds[id] then
        local attempts = 0
        repeat
            id = utils.randomId('ban-')
            attempts = attempts + 1
        until not seenIds[id] or attempts >= 25

        if seenIds[id] then
            id = ('ban-%d'):format(effectiveNow)
            local suffix = 1
            while seenIds[id] do
                suffix = suffix + 1
                id = ('ban-%d-%d'):format(effectiveNow, suffix)
            end
        end
        entry.id = id
        dirty = true
    else
        entry.id = id
    end
    seenIds[id] = true

    local identifiers = {}
    local identifierLookup = {}
    if type(entry.identifiers) == 'table' then
        for _, identifier in ipairs(entry.identifiers) do
            if type(identifier) == 'string' then
                local trimmed = trimString(identifier)
                if trimmed ~= '' and not identifierLookup[trimmed:lower()] then
                    identifiers[#identifiers + 1] = trimmed
                    identifierLookup[trimmed:lower()] = true
                    if trimmed ~= identifier then
                        dirty = true
                    end
                end
            end
        end
    else
        if entry.identifiers ~= nil then
            dirty = true
        end
    end
    if #identifiers ~= #(entry.identifiers or {}) then
        dirty = true
    end
    entry.identifiers = identifiers

    local createdAt = tonumber(entry.createdAt)
    if createdAt then
        entry.createdAt = math.floor(createdAt)
    else
        entry.createdAt = effectiveNow
        dirty = true
    end

    if entry.expiresAt ~= nil then
        local expiresAt = tonumber(entry.expiresAt)
        if expiresAt and expiresAt > 0 then
            entry.expiresAt = math.floor(expiresAt)
        else
            if entry.expiresAt ~= nil then
                dirty = true
            end
            entry.expiresAt = nil
        end
    end

    entry.expired = entry.expiresAt and entry.expiresAt ~= 0 and entry.expiresAt <= effectiveNow or false

    return entry, dirty
end

local function saveBans()
    local ok, encoded = pcall(json.encode, bans)
    if not ok then
        utils.debugLog('Failed to encode bans file', encoded)
        return
    end
    SaveResourceFile(resourceName, 'data/bans.json', encoded, -1)
end

local function loadBans()
    local data = LoadResourceFile(resourceName, 'data/bans.json')
    if not data or data == '' then
        bans = {}
        banIndexById = {}
        return
    end

    local ok, decoded = pcall(json.decode, data)
    if not ok or type(decoded) ~= 'table' then
        utils.debugLog('Failed to decode bans file, resetting. Error:', decoded)
        bans = {}
        saveBans()
        return
    end

    local normalized = {}
    local seenIds = {}
    local dirty = false
    local now = os.time()

    for index, entry in ipairs(decoded) do
        local normalizedEntry, entryDirty = normalizeBanEntry(entry, seenIds, now)
        if normalizedEntry then
            normalized[#normalized + 1] = normalizedEntry
            if entryDirty then
                dirty = true
            end
        else
            dirty = true
            utils.debugLog(('Discarding invalid ban entry at index %s'):format(index))
        end
    end

    bans = normalized
    rebuildBanLookup()

    if dirty or #normalized ~= #decoded then
        saveBans()
    end
end

local function isBanned(identifiers)
    local now = os.time()
    for _, ban in ipairs(bans) do
        if ban.expired then goto continue end
        for _, identifier in ipairs(ban.identifiers or {}) do
            for _, playerIdentifier in ipairs(identifiers or {}) do
                if type(identifier) == 'string' and type(playerIdentifier) == 'string' and identifier:lower() == playerIdentifier:lower() then
                    if ban.expiresAt and ban.expiresAt ~= 0 and ban.expiresAt <= now then
                        ban.expired = true
                        saveBans()
                    else
                        return ban
                    end
                end
            end
        end
        ::continue::
    end
    return nil
end

local function getRiskProfile(src)
    local engine = zVS.riskEngine or (type(zVS.getModule) == 'function' and zVS.getModule('server.modules.risk_engine'))
    if engine and type(engine.getProfile) == 'function' then
        return engine:getProfile(src)
    end
    return nil
end

local function getRiskSnapshot(limit)
    local engine = zVS.riskEngine or (type(zVS.getModule) == 'function' and zVS.getModule('server.modules.risk_engine'))
    if engine and type(engine.getSnapshot) == 'function' then
        return engine:getSnapshot(limit)
    end
    return {}
end

local function getRiskAudit(limit)
    local engine = zVS.riskEngine or (type(zVS.getModule) == 'function' and zVS.getModule('server.modules.risk_engine'))
    if engine and type(engine.getAudit) == 'function' then
        return engine:getAudit(limit)
    end
    return {}
end

local function getRiskApprovals()
    local engine = zVS.riskEngine or (type(zVS.getModule) == 'function' and zVS.getModule('server.modules.risk_engine'))
    if engine and type(engine.getApprovals) == 'function' then
        return engine:getApprovals()
    end
    return {}
end

local function gatherPlayers()
    local players = {}
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if src then
            local ped = GetPlayerPed(src)
            local coords
            local heading
            local health
            local armour
            local vehicle
            local model
            local speed

            if ped and ped ~= 0 then
                local pedCoords = GetEntityCoords(ped)
                if pedCoords then
                    coords = {
                        x = pedCoords.x + 0.0,
                        y = pedCoords.y + 0.0,
                        z = pedCoords.z + 0.0,
                    }
                end
                heading = (GetEntityHeading(ped) or 0.0) + 0.0
                health = GetEntityHealth(ped)
                armour = GetPedArmour(ped)
                vehicle = GetVehiclePedIsIn(ped, false)
                model = GetEntityModel(ped)
                speed = (GetEntitySpeed(ped) or 0.0) * 3.6
            end

            local riskProfile = getRiskProfile(src)

            players[#players + 1] = {
                id = src,
                name = sanitizeName(GetPlayerName(src)),
                ping = GetPlayerPing(src),
                coords = coords,
                heading = heading,
                health = health,
                armor = armour,
                inVehicle = vehicle ~= nil and vehicle ~= 0 or false,
                model = model,
                speed = speed,
                spawnProtection = isSpawnProtectionTarget(src),
                risk = riskProfile and {
                    score = riskProfile.score,
                    peak = riskProfile.peak,
                    confidence = riskProfile.confidence,
                    escalation = riskProfile.escalation,
                    lastDetection = riskProfile.lastDetection,
                } or nil,
            }
        end
    end
    table.sort(players, function(a, b)
        return a.id < b.id
    end)
    return players
end

local function getDamageFeed()
    if zVS.damageMonitor and zVS.damageMonitor.getRecentDamage then
        return zVS.damageMonitor:getRecentDamage(true)
    end
    return {}
end


local function asTable(value)
    if type(value) == 'table' then
        return value
    end

    if value ~= nil then
        return { target = value }
    end

    return {}
end

local function getPayloadTarget(value)
    if type(value) == 'table' then
        return value.target
    end

    return value
end

local function getPayloadField(value, field)
    if type(value) == 'table' then
        return value[field]
    end

    return nil
end


local function safePreviewNative(fnName, ...)
    local fn = _G[fnName]
    if type(fn) ~= 'function' then return nil end
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil
end

local function buildPreviewActivity(ped, vehicle, speed)
    if vehicle and vehicle ~= 0 then return 'vehicle' end
    if safePreviewNative('IsPedRagdoll', ped) or safePreviewNative('IsPedFalling', ped) or safePreviewNative('IsPedBeingStunned', ped) then return 'ragdoll' end
    if safePreviewNative('IsPedShooting', ped) then return 'shoot' end
    if safePreviewNative('IsPedReloading', ped) then return 'reload' end
    if safePreviewNative('IsPedAimingFromCover', ped) or safePreviewNative('IsPedInCombat', ped, 0) then return 'aim' end
    local kmh = tonumber(speed) or 0.0
    if safePreviewNative('IsPedSprinting', ped) or kmh > 22.0 then return 'sprint' end
    if safePreviewNative('IsPedRunning', ped) or kmh > 10.0 then return 'run' end
    if safePreviewNative('IsPedWalking', ped) or kmh > 1.8 then return 'walk' end
    return 'idle'
end

function handlers.handleSnapshot(admin, data)
    if not ensureAdmin(admin) then return end
    local previewCfg = cfg and cfg.LivePreview or {}
    local adminPreviewCfg = cfg and cfg.AdminPreview or {}
    if previewCfg.Enabled == false or adminPreviewCfg.Enabled ~= true then
        return
    end

    local target = tonumber(getPayloadTarget(data))
    if not target then
        return
    end

    local ped = GetPlayerPed(target)
    if not ped or ped == 0 then
        TriggerClientEvent('zvs-ac:admin:preview', admin, {
            id = target,
            missing = true,
            ts = os.time(),
        })
        TriggerClientEvent('zvs-ac:admin:previewPortrait', admin, {
            target = target,
            ts = os.time(),
        })
        return
    end

    local pedCoords = GetEntityCoords(ped)
    local heading = (GetEntityHeading(ped) or 0.0) + 0.0
    local health = GetEntityHealth(ped)
    local armour = GetPedArmour(ped)
    local vehicle = GetVehiclePedIsIn(ped, false)
    local model = GetEntityModel(ped)
    local speed = (GetEntitySpeed(ped) or 0.0) * 3.6
    local vehicleModel = vehicle and vehicle ~= 0 and safePreviewNative('GetEntityModel', vehicle) or nil
    local weapon = safePreviewNative('GetSelectedPedWeapon', ped)
    local activity = buildPreviewActivity(ped, vehicle, speed)

    local coordsForPreview = pedCoords and {
        x = pedCoords.x + 0.0,
        y = pedCoords.y + 0.0,
        z = pedCoords.z + 0.0,
    } or nil

    TriggerClientEvent('zvs-ac:admin:preview', admin, {
        id = target,
        coords = coordsForPreview,
        heading = heading,
        health = health,
        armor = armour,
        inVehicle = vehicle ~= nil and vehicle ~= 0 or false,
        model = model,
        speed = speed,
        weapon = weapon,
        activity = activity,
        vehicleModel = vehicleModel,
        ts = os.time(),
    })

    evaluatePreviewDetections(target, ped, {
        speed = speed,
        inVehicle = vehicle ~= nil and vehicle ~= 0 or false,
        health = health,
        armor = armour,
        coords = coordsForPreview,
        weapon = weapon,
        activity = activity,
        vehicleModel = vehicleModel,
    })

    requestPreviewPortrait(admin, target)
end

function handlers.handleLivePreviewRequest(admin, data)
    if not ensureAdmin(admin) then return end
    local previewCfg = cfg and cfg.LivePreview or {}
    local adminPreviewCfg = cfg and cfg.AdminPreview or {}
    if previewCfg.Enabled == false or adminPreviewCfg.Enabled ~= true then
        sendLivePreviewFrameEvent(admin, { target = tonumber(getPayloadTarget(data)), error = 'disabled', ts = os.time() })
        return
    end

    local target = tonumber(getPayloadTarget(data))
    if not target then
        sendLivePreviewFrameEvent(admin, {
            target = target,
            error = 'invalid_target',
            ts = os.time(),
        })
        return
    end

    local mode, modeState = getLivePreviewMode(true)
    if mode == 'camera' then
        livePreviewSessions[admin] = nil
        sendLivePreviewFrameEvent(admin, {
            target = target,
            mode = 'camera',
            reason = modeState and modeState.reason or nil,
            ts = os.time(),
        })
        return
    end

    local supportInfo = modeState and modeState.support or nil
    if supportInfo and supportInfo.available == false then
        livePreviewSessions[admin] = nil
        sendLivePreviewFrameEvent(admin, {
            target = target,
            error = supportInfo.reason or 'disabled',
            ts = os.time(),
        })
        return
    end

    if GetPlayerPed(target) == 0 then
        sendLivePreviewFrameEvent(admin, {
            target = target,
            error = 'target_missing',
            ts = os.time(),
        })
        livePreviewSessions[admin] = nil
        return
    end

    local session = livePreviewSessions[admin]
    if not session or session.target ~= target then
        session = { target = target, last = 0, pending = false }
        livePreviewSessions[admin] = session
    end

    if session.pending then
        return
    end

    local now = GetGameTimer()
    local interval = getLivePreviewInterval()
    if not getPayloadField(data, 'force') and session.last and now - session.last < interval then
        return
    end

    session.last = now
    session.pending = true

    local options = resolveLivePreviewOptions()

    local ok = pcall(function()
        exports['screenshot-basic']:requestClientScreenshot(target, options, function(errorMessage, imageData)
            session.pending = false
            local active = livePreviewSessions[admin]
            if not active or active.target ~= target then
                return
            end

            if errorMessage then
                local classified = classifyScreenshotError(errorMessage)
                local code = classified and classified.code or trimString(errorMessage) or 'capture_failed'
                sendLivePreviewFrameEvent(admin, {
                    target = target,
                    error = code,
                    ts = os.time(),
                })
                return
            end

            local frameData = nil
            if type(imageData) == 'string' then
                if imageData:find('^data:') then
                    frameData = imageData
                else
                    frameData = normalizeBase64Image(imageData)
                end
            elseif type(imageData) == 'table' then
                if type(imageData.data) == 'string' then
                    frameData = normalizeBase64Image(imageData.data)
                elseif type(imageData.image) == 'string' then
                    frameData = normalizeBase64Image(imageData.image)
                end
            end

            if not frameData then
                sendLivePreviewFrameEvent(admin, {
                    target = target,
                    error = 'invalid_image_data',
                    ts = os.time(),
                })
                return
            end

            sendLivePreviewFrameEvent(admin, {
                target = target,
                frame = frameData,
                ts = os.time(),
            })
        end)
    end)

    if not ok then
        session.pending = false
        sendLivePreviewFrameEvent(admin, {
            target = target,
            error = 'capture_exception',
            ts = os.time(),
        })
    end
end

function handlers.handleLivePreviewStop(admin, data)
    if not ensureAdmin(admin) then return end

    local target = tonumber(getPayloadTarget(data))
    local session = livePreviewSessions[admin]
    if not session then
        return
    end

    if not target or session.target == target then
        livePreviewSessions[admin] = nil
    end
end

local function exportBans()
    local now = os.time()
    local list = {}
    for _, ban in ipairs(bans) do
        list[#list + 1] = {
            id = ban.id,
            name = ban.name,
            reason = ban.reason,
            identifiers = ban.identifiers,
            createdAt = ban.createdAt,
            expiresAt = ban.expiresAt,
            expired = ban.expiresAt and ban.expiresAt ~= 0 and ban.expiresAt <= now,
            bannedBy = ban.bannedBy,
        }
    end
    table.sort(list, function(a, b)
        return (a.createdAt or 0) > (b.createdAt or 0)
    end)
    return list
end

function buildState(viewer)
    local _, livePreviewState = getLivePreviewMode(false)
    return {
        players = gatherPlayers(),
        suspicious = utils.copyTable(suspiciousFeed),
        damage = getDamageFeed(),
        bans = exportBans(),
        moderation = exportModeration(viewer),
        notes = exportModerationNotes(),
        appearance = exportAppearanceSettings(viewer),
        adminSettings = AdminSettings.export(viewer),
        runtimeConfig = AdminSettings.runtime(viewer),
        livePreview = livePreviewState,
        defenses = exportDefenseStates(),
        risk = {
            top = getRiskSnapshot(20),
            approvals = getRiskApprovals(),
            audit = getRiskAudit(40),
            policy = {
                humanReviewOnly = (Config.RiskEngine or {}).HumanReviewOnly ~= false,
                automationEnabled = (Config.RiskEngine or {}).AutomationEnabled == true,
                message = 'Surveillance passive: les détections suggèrent, le staff décide.',
            },
        },
    }
end

function broadcastState()
    for _, player in ipairs(GetPlayers()) do
        local src = tonumber(player)
        if src and utils.isAdmin(src) then
            TriggerClientEvent('zvs-ac:admin:update', src, buildState(src))
        end
    end
end

local function sendState(src)
    TriggerClientEvent('zvs-ac:admin:open', src, buildState(src))
end

local function updateState(src)
    TriggerClientEvent('zvs-ac:admin:update', src, buildState(src))
end

local function registerBan(entry)
    local normalizedEntry = entry
    if type(entry) == 'table' then
        local existingIds = collectBanIdSet()
        normalizedEntry = normalizeBanEntry(entry, existingIds, os.time())
    end

    if not normalizedEntry then
        utils.debugLog('Failed to register ban entry: invalid payload')
        return
    end

    bans[#bans + 1] = normalizedEntry
    rebuildBanLookup()
    saveBans()
end

local function setFrozenState(target, admin, enabled, reason)
    if enabled then
        frozenPlayers[target] = {
            admin = admin,
            reason = reason,
            since = os.time(),
        }
    else
        frozenPlayers[target] = nil
    end
end

local function isFrozen(target)
    return frozenPlayers[target] ~= nil
end

local function setWeaponLockState(target, admin, enabled, adminName)
    if enabled then
        weaponLocks[target] = {
            admin = admin,
            adminName = adminName or sanitizeName(GetPlayerName(admin)),
            since = os.time(),
        }
    else
        weaponLocks[target] = nil
    end
end

local function isWeaponLocked(target)
    return weaponLocks[target] ~= nil
end


local function safeNative(fnName, ...)
    local fn = _G[fnName]
    if type(fn) ~= 'function' then return nil end
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil
end

local function buildSpectatePayload(admin, target)
    local coords = getPlayerCoords(target)
    if not coords then return nil end

    local ped = GetPlayerPed(target)
    local vehicle = ped and ped ~= 0 and safeNative('GetVehiclePedIsIn', ped, false) or 0
    local speed = ped and ped ~= 0 and safeNative('GetEntitySpeed', ped) or nil
    local health = ped and ped ~= 0 and safeNative('GetEntityHealth', ped) or nil
    local armor = ped and ped ~= 0 and safeNative('GetPedArmour', ped) or nil
    local bucket = safeNative('GetPlayerRoutingBucket', target)
    local snapshot = spectateSyncCache[target]

    local payload = {
        target = target,
        name = sanitizeName(GetPlayerName(target) or ('#' .. tostring(target))),
        coords = {
            x = coords.x + 0.0,
            y = coords.y + 0.0,
            z = coords.z + 0.0,
        },
        heading = (coords.heading or 0.0) + 0.0,
        ts = os.time(),
        serverTime = GetGameTimer(),
        speed = speed and ((speed + 0.0) * 3.6) or nil,
        health = health and (health + 0) or nil,
        armor = armor and (armor + 0) or nil,
        inVehicle = vehicle and vehicle ~= 0 or false,
        routingBucket = bucket,
        detections = getRecentDetectionsForTarget(target, 3),
        mode = modCfg.SpectateMode or 'remote_camera',
    }

    if snapshot and type(snapshot.camera) == 'table' then
        local snapGameTime = tonumber(snapshot.gameTime) or tonumber(snapshot.game_time) or nil
        local nowGameTime = GetGameTimer()
        payload.cameraAgeMs = snapGameTime and math.max(0, nowGameTime - snapGameTime) or nil
        payload.camera = {
            x = (snapshot.camera.x or 0.0) + 0.0,
            y = (snapshot.camera.y or 0.0) + 0.0,
            z = (snapshot.camera.z or 0.0) + 0.0,
            ageMs = payload.cameraAgeMs,
        }
        if type(snapshot.camera.rot) == 'table' then
            payload.camera.rot = {
                x = (snapshot.camera.rot.x or 0.0) + 0.0,
                y = (snapshot.camera.rot.y or 0.0) + 0.0,
                z = (snapshot.camera.rot.z or 0.0) + 0.0,
            }
        end
    end

    if snapshot and type(snapshot.state) == 'table' then
        local state = snapshot.state
        payload.activity = state.activity or payload.activity
        payload.weapon = state.weapon or payload.weapon
        payload.vehicleModel = state.vehicleModel or payload.vehicleModel
        payload.speed = state.speed or payload.speed
        payload.health = state.health or payload.health
        payload.armor = state.armor or payload.armor
        if state.inVehicle ~= nil then
            payload.inVehicle = state.inVehicle and true or false
        end
    end

    return payload
end

local function beginSpectate(admin, target)
    admin = tonumber(admin)
    target = tonumber(target)
    if not admin or not target then return false end

    if admin == target then
        if spectateSessions[admin] then
            stopSpectate(admin, { reason = 'self_guard', log = false })
        end
        spectateSessions[admin] = nil
        spectateSyncThrottle[admin] = nil
        sendAdminMessage(admin, 'Visionary AC: impossible de se spectate soi-meme. Collision restauree cote client.')
        TriggerClientEvent('zvs-ac:admin:spectateTarget', admin, {
            enabled = false,
            reason = 'self_guard',
        })
        return false
    end

    if spectateSessions[admin] then
        stopSpectate(admin, { log = false, reason = 'swap', noClientEvent = true })
    end

    local adminName = sanitizeName(GetPlayerName(admin))
    local targetName = sanitizeName(GetPlayerName(target))
    spectateSessions[admin] = {
        target = target,
        since = os.time(),
    }
    spectateTargetWatchers[target] = spectateTargetWatchers[target] or {}
    spectateTargetWatchers[target][admin] = true

    TriggerClientEvent('zvs-ac:admin:spectateTarget', admin, {
        enabled = true,
        target = target,
        targetName = targetName,
        silent = modCfg.SilentSpectate ~= false,
        mode = modCfg.SpectateMode or 'remote_camera',
        useNative = modCfg.UseNativeSpectator == true,
        viewMode = modCfg.SpectateViewMode or 'target_pov',
        snapshot = buildSpectatePayload(admin, target),
    })

    pushFeed({
        type = 'admin_spectate',
        src = admin,
        message = ('%s observe silencieusement %s'):format(adminName, targetName),
        payload = {
            admin = admin,
            admin_name = adminName,
            target = target,
            target_name = targetName,
        },
    })

    sendAdminMessage(admin, ('Visionary AC: vous observez desormais %s.'):format(targetName))

    broadcastState()
end

local function toggleCloak(admin)
    local staffNoClipCfg = cfg and cfg.StaffNoClip or {}
    if staffNoClipCfg.Enabled == false or staffNoClipCfg.DoNotModifyPed == true then
        cloakedAdmins[admin] = nil
        TriggerClientEvent('zvs-ac:admin:cloak', admin, { enabled = false, disabled = true })
        sendAdminMessage(admin, 'Visionary AC: NoClip interne indisponible dans la configuration actuelle.')
        return
    end
    local enabled = not cloakedAdmins[admin]
    if enabled then
        cloakedAdmins[admin] = { since = os.time() }
    else
        cloakedAdmins[admin] = nil
    end

    TriggerClientEvent('zvs-ac:admin:cloak', admin, {
        enabled = enabled,
    })

    local adminName = sanitizeName(GetPlayerName(admin))
    pushFeed({
        type = enabled and 'admin_cloak_on' or 'admin_cloak_off',
        src = admin,
        message = enabled and ('%s est passe en mode furtif.'):format(adminName) or ('%s est redevenu visible.'):format(adminName),
        payload = {
            admin = admin,
            admin_name = adminName,
            enabled = enabled,
        },
    })

    sendAdminMessage(admin, enabled and 'Visionary AC: mode furtif active.' or 'Visionary AC: mode furtif desactive.')

    broadcastState()
end

function handlers.handleDefenseToggle(admin, data)
    if not ensureAdmin(admin) then return end
    if not (defenseCfg and defenseCfg.Enabled) then
        sendAdminMessage(admin, 'Visionary AC: contrôle des défenses désactivé.')
        return
    end

    local key = trimString(tostring(getPayloadField(data, 'key') or ''))
    if key == '' or defenseLabels[key] == nil then
        sendAdminMessage(admin, 'Visionary AC: défense invalide.')
        return
    end

    local enabled = getPayloadField(data, 'enabled')
    if enabled == nil then
        enabled = not isDefenseEnabled(key)
    end
    enabled = enabled and true or false
    setDefenseEnabled(key, enabled)

    local adminName = sanitizeName(GetPlayerName(admin))
    local statusLabel = enabled and 'activée' or 'désactivée'

    pushFeed({
        type = 'DefenseControl',
        src = admin,
        message = ('%s a %s la défense %s'):format(adminName, statusLabel, defenseLabels[key]),
        payload = {
            admin = admin,
            admin_name = adminName,
            defense = key,
            defense_label = defenseLabels[key],
            enabled = enabled,
        },
        notify = false,
        logType = 'admin_defense_control',
    })

    sendAdminMessage(admin, ('Visionary AC: défense %s %s.'):format(defenseLabels[key], statusLabel))
    broadcastState()
end

function handlers.handleBan(src, data)
    if cfg.AllowBans == false then
        sendAdminMessage(src, 'Visionary AC: la fonctionnalite de ban est desactivee.')
        return
    end

    if not ensureAdmin(src) then return end

    local target = tonumber(getPayloadTarget(data))
    if not target then
        sendAdminMessage(src, 'Visionary AC: cible invalide.')
        return
    end

    local identifiers = GetPlayerIdentifiers(target)
    if not identifiers or #identifiers == 0 then
        sendAdminMessage(src, 'Visionary AC: impossible de recuperer les identifiants de la cible.')
        return
    end

    local adminName = sanitizeName(GetPlayerName(src))
    local targetName = sanitizeName(GetPlayerName(target))
    local reason = tostring(getPayloadField(data, 'reason') or 'No reason provided')
    local duration = tonumber(getPayloadField(data, 'duration')) or 0
    local expiresAt = nil
    if duration > 0 then
        expiresAt = os.time() + (duration * 60)
    end

    local banEntry = {
        name = targetName,
        identifiers = identifiers,
        reason = reason,
        expiresAt = expiresAt,
        bannedBy = adminName,
    }

    registerBan(banEntry)

    logger:flag('admin_ban', src, {
        target = target,
        target_name = targetName,
        reason = reason,
        duration_minutes = duration,
        identifiers = identifiers,
    })

    pushFeed({
        type = 'admin_ban',
        src = src,
        message = ('%s a banni %s (%s)'):format(adminName, targetName, reason),
        payload = {
            target = target,
            target_name = targetName,
            reason = reason,
            duration = duration,
        },
    })

    DropPlayer(target, ('Visionary AC - Vous avez ete banni: %s'):format(reason))
end

function handlers.handleKick(src, data)
    if modCfg.AllowKick == false then
        sendAdminMessage(src, "Visionary AC: l'outil kick est desactive.")
        return
    end

    if not ensureAdmin(src) then return end

    local target = tonumber(getPayloadTarget(data))
    if not target then
        sendAdminMessage(src, 'Visionary AC: cible invalide pour le kick.')
        return
    end

    local targetName = sanitizeName(GetPlayerName(target))
    local adminName = sanitizeName(GetPlayerName(src))
    local reason = tostring(getPayloadField(data, 'reason') or 'Action Visionary AC')

    logger:flag('admin_kick', src, {
        target = target,
        target_name = targetName,
        reason = reason,
    })

    pushFeed({
        type = 'admin_kick',
        src = src,
        message = ('%s a expulse %s (%s)'):format(adminName, targetName, reason),
        payload = {
            admin = src,
            admin_name = adminName,
            target = target,
            target_name = targetName,
            reason = reason,
        },
    })

    DropPlayer(target, ('Visionary AC - Vous avez ete expulse: %s'):format(reason))
end

function handlers.handleUnban(src, data)
    if cfg.AllowBans == false then
        sendAdminMessage(src, 'Visionary AC: la fonctionnalite de ban est desactivee.')
        return
    end

    if not ensureAdmin(src) then return end

    local id = tostring(getPayloadField(data, 'id') or '')
    if id == '' then
        sendAdminMessage(src, 'Visionary AC: identifiant de ban invalide.')
        return
    end

    local index = banIndexById[id]
    if not index then
        sendAdminMessage(src, 'Visionary AC: ban introuvable.')
        return
    end

    local ban = table.remove(bans, index)
    rebuildBanLookup()
    saveBans()

    logger:flag('admin_unban', src, {
        ban_id = id,
        target_name = ban and ban.name,
    })

    local adminName = sanitizeName(GetPlayerName(src))
    pushFeed({
        type = 'admin_unban',
        src = src,
        message = ('%s a leve le ban de %s'):format(adminName, (ban and ban.name) or id),
        payload = { id = id },
    })

    updateState(src)
end

function handlers.handleScreenshot(src, data)
    if not cfg.AllowScreenshots then
        sendAdminMessage(src, "Visionary AC: capture d'ecran desactivee.")
        return
    end

    if not ensureAdmin(src) then return end

    local target = tonumber(getPayloadTarget(data))
    if not target then
        sendAdminMessage(src, 'Visionary AC: cible invalide pour la capture.')
        return
    end

    if GetPlayerPed(target) == 0 then
        sendAdminMessage(src, 'Visionary AC: cible hors ligne.')
        return
    end

    local targetName = sanitizeName(GetPlayerName(target))
    local adminName = sanitizeName(GetPlayerName(src))
    local reason = tostring(getPayloadField(data, 'reason') or 'Controle Visionary AC')
    local identifiers, identifierMap = collectPlayerIdentifiers(target)
    local identifierSummaryList = formatPrimaryIdentifiers(identifierMap)
    local identifierSummary = nil
    if #identifierSummaryList > 0 then
        identifierSummary = table.concat(identifierSummaryList, '\n')
    end
    local requestId = utils.randomId('shot-')

    local sanitizedId = requestId:gsub('[^%w%-_]', '')
    if sanitizedId == '' then
        sanitizedId = tostring(os.time())
    end

    local encodingPriority = buildScreenshotEncodingPriority(cfg and cfg.ScreenshotEncoding)
    local primaryEncoding = encodingPriority[1] or 'jpg'
    local function buildScreenshotFileName(id, encoding)
        return ('visionary-ac-%s.%s'):format(id, screenshotExtensionForEncoding(encoding))
    end

    local nativeOptions = {
        encoding = primaryEncoding,
        fileName = buildScreenshotFileName(sanitizedId, primaryEncoding),
    }
    if primaryEncoding == 'jpg' then
        nativeOptions.quality = cfg.ScreenshotQuality or 70
    end

    pendingScreenshots[requestId] = {
        admin = src,
        target = target,
        reason = reason,
        attempt = 0,
        encoding = primaryEncoding,
    }

    local screenshotWebhook = cfg.ScreenshotWebhook
    if not screenshotWebhook or screenshotWebhook == '' then
        screenshotWebhook = Config.Webhook
    end

    local shouldUpload = type(screenshotWebhook) == 'string' and screenshotWebhook ~= ''
    local screenshotResourceState = GetResourceState('screenshot-basic')
    local screenshotResourceStarted = screenshotResourceState == 'started'
    local captureExportAvailable = false
    local uploadExportAvailable = false
    local uploadExportChecked = false
    if screenshotResourceStarted then
        local okCapture, captureExport = pcall(function()
            return exports['screenshot-basic'].requestClientScreenshot
        end)
        captureExportAvailable = okCapture and type(captureExport) == 'function'
        if shouldUpload then
            local okExport, uploadExport = pcall(function()
                return exports['screenshot-basic'].requestClientScreenshotUpload
            end)
            uploadExportChecked = true
            uploadExportAvailable = okExport and type(uploadExport) == 'function'
        end
    end
    screenshotResourceStarted = screenshotResourceStarted and captureExportAvailable
    local useNativeUpload = shouldUpload and screenshotResourceStarted and uploadExportAvailable
    local useFallbackUpload = shouldUpload and screenshotResourceStarted and not uploadExportAvailable and uploadExportChecked
    local uploadPayloadJson = nil
    if shouldUpload then
        local messageLines = {
            ('Capture Visionary AC - %s (#%s)'):format(targetName, target),
            ('Administrateur: %s'):format(adminName),
        }
        if reason and reason ~= '' then
            messageLines[#messageLines + 1] = ('Note: %s'):format(reason)
        end
        if cfg.IncludeIdentifiersInScreenshotUpload == true and identifierSummary then
            messageLines[#messageLines + 1] = identifierSummary
        end
        local ok, encoded = pcall(json.encode, {
            username = 'Visionary AC',
            content = table.concat(messageLines, '\n'),
        })
        if ok and encoded then
            uploadPayloadJson = encoded
        end
    end

    local maxAttemptsPerEncoding = math.max(1, math.floor(tonumber(cfg.ScreenshotRetryAttempts) or 3))
    local retryDelayBaseMs = tonumber(cfg.ScreenshotRetryDelay) or 400
    if retryDelayBaseMs < 0 then
        retryDelayBaseMs = 0
    end

    local function computeRetryDelay(attempt)
        local base = retryDelayBaseMs
        if base <= 0 then
            return 0
        end
        local scaled = math.floor(base * math.max(1, attempt))
        if scaled < base then
            scaled = base
        end
        if scaled > base * 5 then
            scaled = base * 5
        end
        return scaled
    end

    local function captureWithoutNativeUpload(manualUploadRequested, encodingIndex, previousError, attemptNumber)
        manualUploadRequested = manualUploadRequested == true
        encodingIndex = encodingIndex or 1
        attemptNumber = attemptNumber or 1

        local encoding = encodingPriority[encodingIndex]
        local fallbackEncoding = nil
        if not encoding and encodingIndex > 1 then
            fallbackEncoding = encodingPriority[encodingIndex - 1]
        end
        if not encoding then
            pendingScreenshots[requestId] = nil
            local failureReason = previousError or 'invalid_image_format'
            local failureLabel = formatScreenshotErrorLabel(previousError, failureReason)
            sendAdminMessage(src, ('Visionary AC: capture echouee (%s).'):format(failureLabel))
            logger:flag('admin_screenshot_failed', src, {
                target = target,
                target_name = targetName,
                reason = reason,
                error = failureReason,
                raw_error = previousError,
                identifiers = identifiers,
                identifier_map = identifierMap,
                identifier_summary = identifierSummary,
                attempts = attemptNumber,
                encoding = fallbackEncoding,
            })
            return
        end

        local willAttemptManualUpload = shouldUpload and screenshotResourceStarted and (manualUploadRequested or useFallbackUpload)
        local historyEntryRef = nil
        local capturedImageData = nil

        local captureFileName = buildScreenshotFileName(sanitizedId, encoding)

        local options = {
            encoding = encoding,
        }
        if encoding == 'jpg' then
            options.quality = cfg.ScreenshotQuality or 70
        end

        pendingScreenshots[requestId] = {
            admin = src,
            target = target,
            reason = reason,
            attempt = attemptNumber,
            encoding = encoding,
        }

        local function finalizePending()
            local request = pendingScreenshots[requestId]
            if not request then
                return
            end
            if request.timer then
                Citizen.ClearTimeout(request.timer)
                request.timer = nil
            end
            pendingScreenshots[requestId] = nil
        end

        local okCaptureStart, captureStartErr = pcall(function()
            exports['screenshot-basic']:requestClientScreenshot(target, options, function(err, data)
            local request = pendingScreenshots[requestId]
            if not request then
                return
            end
            if request.timer then
                Citizen.ClearTimeout(request.timer)
                request.timer = nil
            end

            local normalizedImage = normalizeScreenshotPayload(data)
            local errorMessage = err

            if (not normalizedImage or normalizedImage == '') and type(errorMessage) == 'string' and errorMessage ~= '' then
                local fallback = normalizeScreenshotPayload(errorMessage)
                if fallback then
                    normalizedImage = fallback
                    errorMessage = nil
                end
            end

            if type(errorMessage) == 'string' then
                local trimmedError = trimString(errorMessage)
                if trimmedError == '' then
                    trimmedError = 'unknown_error'
                else
                    local lowered = trimmedError:lower()
                    if lowered == 'null' or lowered == 'undefined' then
                        trimmedError = 'unknown_error'
                    end
                end

                local classified = classifyScreenshotError(trimmedError)
                if classified and classified.action == 'retry_encoding' then
                    local nextEncodingIndex = encodingIndex + 1
                    local nextEncoding = encodingPriority[nextEncodingIndex]
                    if nextEncoding then
                        local retryAttempts = 1
                        local delay = computeRetryDelay(retryAttempts)
                        finalizePending()
                        local label = formatScreenshotErrorLabel(classified.code, trimmedError)
                        sendAdminMessage(src, ('Visionary AC: nouvelle tentative de capture en %s (%s, essai %d/%d)...')
                            :format(nextEncoding:upper(), label, retryAttempts, maxAttemptsPerEncoding))
                        logger:flag('admin_screenshot_retry', src, {
                            target = target,
                            target_name = targetName,
                            reason = reason,
                            identifiers = identifiers,
                            identifier_map = identifierMap,
                            identifier_summary = identifierSummary,
                            retry_action = 'switch_encoding',
                            retry_reason = classified.code,
                            raw_error = classified.raw,
                            attempts = retryAttempts,
                            max_attempts = maxAttemptsPerEncoding,
                            previous_encoding = encoding,
                            next_encoding = nextEncoding,
                            retry_delay_ms = delay,
                        })
                        local function performRetry()
                            captureWithoutNativeUpload(manualUploadRequested, nextEncodingIndex, classified.raw, retryAttempts)
                        end
                        if delay > 0 then
                            SetTimeout(delay, performRetry)
                        else
                            performRetry()
                        end
                        return
                    end
                elseif classified and classified.action == 'retry_same' then
                    if attemptNumber < maxAttemptsPerEncoding then
                        local nextAttempt = attemptNumber + 1
                        local delay = computeRetryDelay(nextAttempt)
                        finalizePending()
                        local label = formatScreenshotErrorLabel(classified.code, trimmedError)
                        sendAdminMessage(src, ('Visionary AC: nouvelle tentative de capture (%s, essai %d/%d)...')
                            :format(label, nextAttempt, maxAttemptsPerEncoding))
                        logger:flag('admin_screenshot_retry', src, {
                            target = target,
                            target_name = targetName,
                            reason = reason,
                            identifiers = identifiers,
                            identifier_map = identifierMap,
                            identifier_summary = identifierSummary,
                            retry_action = 'retry_same',
                            retry_reason = classified.code,
                            raw_error = classified.raw,
                            attempts = nextAttempt,
                            max_attempts = maxAttemptsPerEncoding,
                            encoding = encoding,
                            retry_delay_ms = delay,
                        })
                        local function performRetry()
                            captureWithoutNativeUpload(manualUploadRequested, encodingIndex, classified.raw, nextAttempt)
                        end
                        if delay > 0 then
                            SetTimeout(delay, performRetry)
                        else
                            performRetry()
                        end
                        return
                    end
                end

                finalizePending()
                local failureLabel = formatScreenshotErrorLabel(classified and classified.code or trimmedError, trimmedError)
                sendAdminMessage(src, ('Visionary AC: capture echouee apres %d tentative(s) (%s).')
                    :format(attemptNumber, failureLabel))
                logger:flag('admin_screenshot_failed', src, {
                    target = target,
                    target_name = targetName,
                    reason = reason,
                    error = classified and classified.code or trimmedError,
                    raw_error = classified and classified.raw or errorMessage,
                    identifiers = identifiers,
                    identifier_map = identifierMap,
                    identifier_summary = identifierSummary,
                    attempts = attemptNumber,
                    encoding = encoding,
                })
                return
            end

            if not normalizedImage then
                if attemptNumber < maxAttemptsPerEncoding then
                    local nextAttempt = attemptNumber + 1
                    local delay = computeRetryDelay(nextAttempt)
                    finalizePending()
                    local label = formatScreenshotErrorLabel('invalid_image_data', 'donnees invalides')
                    sendAdminMessage(src, ('Visionary AC: nouvelle tentative de capture (%s, essai %d/%d)...')
                        :format(label, nextAttempt, maxAttemptsPerEncoding))
                    logger:flag('admin_screenshot_retry', src, {
                        target = target,
                        target_name = targetName,
                        reason = reason,
                        identifiers = identifiers,
                        identifier_map = identifierMap,
                        identifier_summary = identifierSummary,
                        retry_action = 'retry_same',
                        retry_reason = 'invalid_image_data',
                        raw_error = previousError or 'invalid_image_data',
                        attempts = nextAttempt,
                        max_attempts = maxAttemptsPerEncoding,
                        encoding = encoding,
                        retry_delay_ms = delay,
                    })
                    local function performRetry()
                        captureWithoutNativeUpload(manualUploadRequested, encodingIndex, 'invalid_image_data', nextAttempt)
                    end
                    if delay > 0 then
                        SetTimeout(delay, performRetry)
                    else
                        performRetry()
                    end
                    return
                end

                finalizePending()
                sendAdminMessage(src, ('Visionary AC: capture echouee apres %d tentative(s) (donnees invalides).')
                    :format(attemptNumber))
                logger:flag('admin_screenshot_failed', src, {
                    target = target,
                    target_name = targetName,
                    reason = reason,
                    error = 'invalid_image_data',
                    identifiers = identifiers,
                    identifier_map = identifierMap,
                    identifier_summary = identifierSummary,
                    attempts = attemptNumber,
                    encoding = encoding,
                })
                return
            end

            local captureTs = os.time()
            local entry = {
                id = requestId,
                image = normalizedImage,
                target = target,
                targetName = targetName,
                reason = reason,
                identifierSummary = identifierSummary,
                ts = captureTs,
                admin = src,
                adminName = adminName,
                uploadStatus = willAttemptManualUpload and 'pending' or 'skipped',
                uploadUrl = nil,
                attempts = attemptNumber,
            }

            capturedImageData = normalizedImage

            historyEntryRef = recordScreenshotHistory(src, entry)

            TriggerClientEvent('zvs-ac:admin:screenshot', src, {
                id = requestId,
                image = normalizedImage,
                target = target,
                targetName = targetName,
                reason = reason,
                identifiers = identifiers,
                identifierSummary = identifierSummary,
                ts = captureTs,
                adminName = adminName,
                uploadStatus = entry.uploadStatus,
                uploadUrl = entry.uploadUrl,
                attempts = attemptNumber,
            })

            local successMessage = ('Visionary AC: capture recue pour %s (%s).'):format(targetName, reason)
            if shouldUpload then
                if willAttemptManualUpload then
                    successMessage = successMessage .. ' (Upload Discord en cours via Visionary AC.)'
                else
                    successMessage = successMessage .. ' (Upload Discord indisponible.)'
                end
            else
                successMessage = successMessage .. ' (Upload Discord desactive.)'
            end
            sendAdminMessage(src, successMessage)

            logger:flag('admin_screenshot', src, {
                target = target,
                target_name = targetName,
                reason = reason,
                identifiers = identifiers,
                identifier_map = identifierMap,
                identifier_summary = identifierSummary,
                admin_name = adminName,
                attempts = attemptNumber,
                encoding = encoding,
            })

            updateState(src)
            finalizePending()

            local imageDataForUpload = capturedImageData
            if willAttemptManualUpload then
                if imageDataForUpload and historyEntryRef and historyEntryRef.uploadStatus ~= 'pending' then
                    historyEntryRef.uploadStatus = 'pending'
                    historyEntryRef.uploadError = nil
                    historyEntryRef.uploadStatusCode = nil
                    updateState(src)
                end

                local okUpload, uploadErr = uploadScreenshotViaHttp({
                    webhook = screenshotWebhook,
                    payloadJson = uploadPayloadJson,
                    fileName = captureFileName,
                    fieldName = 'file',
                    imageData = imageDataForUpload,
                    onComplete = function(status, body)
                        local attachmentUrl = nil
                        if status == 200 then
                            attachmentUrl = extractDiscordAttachmentUrl(body)
                        end
                        if status ~= 200 and status ~= 204 then
                            utils.debugLog('Screenshot upload failed (manual)', status, body or '')
                            logger:flag('admin_screenshot_upload_failed', src, {
                                target = target,
                                target_name = targetName,
                                reason = reason,
                                identifiers = identifiers,
                                identifier_map = identifierMap,
                            identifier_summary = identifierSummary,
                            status = status,
                            response = body,
                            error = manualUploadRequested and 'manual_upload_failed' or 'fallback_upload_failed',
                            attempts = attemptNumber,
                            encoding = encoding,
                        })
                        if historyEntryRef then
                            historyEntryRef.uploadStatus = 'error'
                            historyEntryRef.uploadError = body or ''
                            historyEntryRef.uploadStatusCode = status
                                updateState(src)
                            end
                        else
                            local payload = {
                                target = target,
                                target_name = targetName,
                                reason = reason,
                                identifiers = identifiers,
                                identifier_map = identifierMap,
                                identifier_summary = identifierSummary,
                                status = status,
                                method = manualUploadRequested and 'manual' or 'fallback',
                                attempts = attemptNumber,
                                encoding = encoding,
                            }
                            if attachmentUrl then
                                payload.url = attachmentUrl
                            end
                            logger:flag('admin_screenshot_uploaded', src, payload)
                            if historyEntryRef then
                                historyEntryRef.uploadStatus = 'ok'
                                historyEntryRef.uploadError = nil
                                historyEntryRef.uploadStatusCode = status
                                if attachmentUrl then
                                    historyEntryRef.uploadUrl = attachmentUrl
                                    historyEntryRef.image = attachmentUrl
                                end
                                updateState(src)
                            end
                        end
                    end,
                })

                if not okUpload then
                    local uploadErrorCode = manualUploadRequested and 'manual_start_failed' or 'fallback_start_failed'
                    logger:flag('admin_screenshot_upload_failed', src, {
                        target = target,
                        target_name = targetName,
                        reason = reason,
                        identifiers = identifiers,
                        identifier_map = identifierMap,
                        identifier_summary = identifierSummary,
                        error = uploadErr or uploadErrorCode,
                        attempts = attemptNumber,
                        encoding = encoding,
                    })
                    if historyEntryRef then
                        historyEntryRef.uploadStatus = 'error'
                        historyEntryRef.uploadError = uploadErr or uploadErrorCode
                        historyEntryRef.uploadStatusCode = 0
                        updateState(src)
                    end
                end
            end
            end)
        end)

        if not okCaptureStart then
            pendingScreenshots[requestId] = nil
            sendAdminMessage(src, 'Visionary AC: capture indisponible (screenshot-basic).')
            logger:flag('admin_screenshot_failed', src, {
                target = target,
                target_name = targetName,
                reason = reason,
                error = tostring(captureStartErr or 'capture_export_failed'),
                identifiers = identifiers,
                identifier_map = identifierMap,
                identifier_summary = identifierSummary,
                attempts = attemptNumber,
                encoding = encoding,
            })
            return
        end

        if cfg.ScreenshotTimeout and cfg.ScreenshotTimeout > 0 then
            pendingScreenshots[requestId].timer = SetTimeout(cfg.ScreenshotTimeout, function()
                local request = pendingScreenshots[requestId]
                if not request then return end
                pendingScreenshots[requestId] = nil
                sendAdminMessage(src, 'Visionary AC: delai de capture depasse.')
                logger:flag('admin_screenshot_failed', src, {
                    target = target,
                    target_name = targetName,
                    reason = reason,
                    error = 'timeout',
                    identifiers = identifiers,
                    identifier_map = identifierMap,
                    identifier_summary = identifierSummary,
                    attempts = (request and request.attempt) or attemptNumber,
                    encoding = request and request.encoding or encoding,
                })
            end)
        end
    end

    if screenshotResourceStarted then
        if useNativeUpload then
            local hasRetriedWithoutNative = false

            local function retryWithoutNativeUpload()
                if hasRetriedWithoutNative then
                    return
                end
                hasRetriedWithoutNative = true
                captureWithoutNativeUpload(true, 1)
            end

            local uploadConfig = {
                url = screenshotWebhook,
                field = 'file',
                filename = nativeOptions.fileName,
            }
            if uploadPayloadJson then
                uploadConfig.fields = {
                    {
                        name = 'payload_json',
                        value = uploadPayloadJson,
                    },
                }
            end

            local nativeAttempt = 1
            local nativeRequest = pendingScreenshots[requestId]
            if nativeRequest then
                nativeRequest.attempt = nativeAttempt
                nativeRequest.encoding = primaryEncoding
            end

            exports['screenshot-basic']:requestClientScreenshotUpload(target, uploadConfig, nativeOptions, function(status, body)
                local request = pendingScreenshots[requestId]
                if not request then
                    return
                end
                if request.timer then
                    Citizen.ClearTimeout(request.timer)
                end
                pendingScreenshots[requestId] = nil

                if status ~= 200 and status ~= 204 then
                    utils.debugLog('Screenshot upload failed (native)', status, body or '')
                    logger:flag('admin_screenshot_upload_failed', src, {
                        target = target,
                        target_name = targetName,
                        reason = reason,
                        identifiers = identifiers,
                        identifier_map = identifierMap,
                        identifier_summary = identifierSummary,
                        status = status,
                        response = body,
                        error = 'native_upload_failed',
                        attempts = nativeAttempt,
                        encoding = primaryEncoding,
                    })
                    sendAdminMessage(src, ('Visionary AC: capture echouee (upload Discord, code %s).'):format(status))
                    retryWithoutNativeUpload()
                    return
                end

                local attachmentUrl = extractDiscordAttachmentUrl(body)
                if not attachmentUrl or attachmentUrl == '' then
                    logger:flag('admin_screenshot_upload_failed', src, {
                        target = target,
                        target_name = targetName,
                        reason = reason,
                        identifiers = identifiers,
                        identifier_map = identifierMap,
                        identifier_summary = identifierSummary,
                        status = status,
                        response = body,
                        error = 'missing_attachment_url',
                        attempts = nativeAttempt,
                        encoding = primaryEncoding,
                    })
                    sendAdminMessage(src, "Visionary AC: capture recue mais Discord n'a pas fourni de lien. Nouvelle tentative interne...")
                    retryWithoutNativeUpload()
                    return
                end

                local captureTs = os.time()
                local entry = {
                    id = requestId,
                    image = attachmentUrl,
                    target = target,
                    targetName = targetName,
                    reason = reason,
                    identifierSummary = identifierSummary,
                    ts = captureTs,
                    admin = src,
                    adminName = adminName,
                    uploadStatus = 'ok',
                    uploadStatusCode = status,
                    uploadError = nil,
                    uploadUrl = attachmentUrl,
                }

                recordScreenshotHistory(src, entry)

                TriggerClientEvent('zvs-ac:admin:screenshot', src, {
                    id = requestId,
                    image = attachmentUrl,
                    target = target,
                    targetName = targetName,
                    reason = reason,
                    identifiers = identifiers,
                    identifierSummary = identifierSummary,
                    ts = captureTs,
                    adminName = adminName,
                    uploadStatus = entry.uploadStatus,
                    uploadUrl = entry.uploadUrl,
                    uploadStatusCode = entry.uploadStatusCode,
                })

                sendAdminMessage(src, ('Visionary AC: capture recue pour %s (%s). (Upload Discord reussi.)'):format(targetName, reason))

                logger:flag('admin_screenshot', src, {
                    target = target,
                    target_name = targetName,
                    reason = reason,
                    identifiers = identifiers,
                    identifier_map = identifierMap,
                    identifier_summary = identifierSummary,
                    admin_name = adminName,
                    upload_method = 'native',
                    attempts = nativeAttempt,
                    encoding = primaryEncoding,
                })

                logger:flag('admin_screenshot_uploaded', src, {
                    target = target,
                    target_name = targetName,
                    reason = reason,
                    identifiers = identifiers,
                    identifier_map = identifierMap,
                    identifier_summary = identifierSummary,
                    status = status,
                    method = 'native',
                    url = attachmentUrl,
                    attempts = nativeAttempt,
                    encoding = primaryEncoding,
                })

                updateState(src)
            end)

            if cfg.ScreenshotTimeout and cfg.ScreenshotTimeout > 0 then
                pendingScreenshots[requestId].timer = SetTimeout(cfg.ScreenshotTimeout, function()
                    local request = pendingScreenshots[requestId]
                    if not request then return end
                    pendingScreenshots[requestId] = nil
                    sendAdminMessage(src, 'Visionary AC: delai de capture depasse (upload Discord).')
                    logger:flag('admin_screenshot_failed', src, {
                        target = target,
                        target_name = targetName,
                        reason = reason,
                        error = 'timeout',
                        identifiers = identifiers,
                        identifier_map = identifierMap,
                        identifier_summary = identifierSummary,
                        attempts = (request and request.attempt) or nativeAttempt,
                        encoding = request and request.encoding or primaryEncoding,
                    })
                    retryWithoutNativeUpload()
                end)
            end
        else
            captureWithoutNativeUpload(false, 1)
        end
    else
        pendingScreenshots[requestId] = nil
        sendAdminMessage(src, 'Visionary AC: capture indisponible. Verifie screenshot-basic.')
        logger:flag('admin_screenshot_failed', src, {
            target = target,
            target_name = targetName,
            reason = reason,
            error = 'screenshot-basic missing',
            identifiers = identifiers,
            identifier_map = identifierMap,
            identifier_summary = identifierSummary,
        })
    end
end

function handlers.handleFreeze(src, data)
    if modCfg.AllowFreeze == false then
        sendAdminMessage(src, 'Visionary AC: gel des joueurs desactive.')
        return
    end

    if not ensureAdmin(src) then return end

    local target = tonumber(getPayloadTarget(data))
    if not target then
        sendAdminMessage(src, 'Visionary AC: cible invalide pour le gel.')
        return
    end

    if GetPlayerPed(target) == 0 then
        sendAdminMessage(src, 'Visionary AC: cible hors ligne pour le gel.')
        return
    end

    local adminName = sanitizeName(GetPlayerName(src))
    local targetName = sanitizeName(GetPlayerName(target))
    local reason = tostring(getPayloadField(data, 'reason') or 'Controle Visionary AC')
    local enable = not isFrozen(target)

    setFrozenState(target, src, enable, reason)

    TriggerClientEvent('zvs-ac:admin:freeze', target, {
        enabled = enable,
        admin = adminName,
        reason = reason,
    })

    logger:flag('admin_freeze', src, {
        target = target,
        target_name = targetName,
        enabled = enable,
        reason = reason,
    })

    pushFeed({
        type = enable and 'admin_freeze' or 'admin_unfreeze',
        src = src,
        message = enable and ('%s a gele %s (%s)'):format(adminName, targetName, reason) or ('%s a libere %s'):format(adminName, targetName),
        payload = {
            admin = src,
            admin_name = adminName,
            target = target,
            target_name = targetName,
            enabled = enable,
            reason = reason,
        },
    })

    sendAdminMessage(src, enable and ('Visionary AC: %s gele.'):format(targetName) or ('Visionary AC: %s libere.'):format(targetName))

    broadcastState()
end

function handlers.handleSpectate(src, data)
    if modCfg.AllowSpectate == false then
        sendAdminMessage(src, 'Visionary AC: spectateur silencieux desactive.')
        return
    end

    if not ensureAdmin(src) then return end

    local target = tonumber(getPayloadTarget(data))
    if not target or target == 0 then
        if spectateSessions[src] then
            stopSpectate(src, { reason = 'manual' })
        else
            sendAdminMessage(src, 'Visionary AC: aucune session spectateur en cours.')
        end
        return
    end

    if target == src then
        if spectateSessions[src] then
            stopSpectate(src, { reason = 'self_guard', log = false })
        end
        sendAdminMessage(src, 'Visionary AC: auto-spectate bloque pour eviter no-collision/loop map.')
        TriggerClientEvent('zvs-ac:admin:spectateTarget', src, {
            enabled = false,
            reason = 'self_guard',
        })
        return
    end

    if GetPlayerPed(target) == 0 then
        sendAdminMessage(src, 'Visionary AC: cible hors ligne pour spectateur.')
        return
    end

    beginSpectate(src, target)
end

function handlers.handleGoto(src, data)
    if modCfg.AllowTeleport == false then
        sendAdminMessage(src, 'Visionary AC: teleportation vers un joueur desactivee.')
        return
    end

    if not ensureAdmin(src) then return end

    local target = tonumber(getPayloadTarget(data))
    if not target then
        sendAdminMessage(src, 'Visionary AC: cible invalide pour la teleportation.')
        return
    end

    local coords = getPlayerCoords(target)
    if not coords then
        sendAdminMessage(src, 'Visionary AC: impossible de recuperer la position de la cible.')
        return
    end

    TriggerClientEvent('zvs-ac:admin:teleport', src, {
        x = coords.x,
        y = coords.y,
        z = coords.z,
        heading = coords.heading,
        context = 'goto',
        target = target,
    })

    grantTeleportImmunity(src)

    local adminName = sanitizeName(GetPlayerName(src))
    local targetName = sanitizeName(GetPlayerName(target))

    logger:flag('admin_goto', src, {
        target = target,
        target_name = targetName,
        coords = coords,
    })

    pushFeed({
        type = 'admin_goto',
        src = src,
        message = ("%s s'est teleporte vers %s"):format(adminName, targetName),
        payload = {
            admin = src,
            admin_name = adminName,
            target = target,
            target_name = targetName,
        },
        notify = false,
    })

    sendAdminMessage(src, ('Visionary AC: teleporte vers %s.'):format(targetName))
end

function handlers.handleBring(src, data)
    if modCfg.AllowTeleport == false then
        sendAdminMessage(src, "Visionary AC: teleportation d'un joueur desactivee.")
        return
    end

    if not ensureAdmin(src) then return end

    local target = tonumber(getPayloadTarget(data))
    if not target then
        sendAdminMessage(src, 'Visionary AC: cible invalide pour le bring.')
        return
    end

    local coords = getPlayerCoords(src)
    if not coords then
        sendAdminMessage(src, 'Visionary AC: impossible de recuperer votre position.')
        return
    end

    TriggerClientEvent('zvs-ac:admin:teleport', target, {
        x = coords.x,
        y = coords.y,
        z = coords.z,
        heading = coords.heading,
        context = 'bring',
        admin = src,
    })

    grantTeleportImmunity(target)

    local adminName = sanitizeName(GetPlayerName(src))
    local targetName = sanitizeName(GetPlayerName(target))

    logger:flag('admin_bring', src, {
        target = target,
        target_name = targetName,
        coords = coords,
    })

    pushFeed({
        type = 'admin_bring',
        src = src,
        message = ('%s a rapatrie %s a sa position.'):format(adminName, targetName),
        payload = {
            admin = src,
            admin_name = adminName,
            target = target,
            target_name = targetName,
        },
        notify = false,
    })

    sendAdminMessage(src, ('Visionary AC: %s rapatrie.'):format(targetName))
end

function handlers.handleHeal(src, data)
    if modCfg.AllowHeal == false then
        sendAdminMessage(src, 'Visionary AC: soin rapide desactive.')
        return
    end

    if not ensureAdmin(src) then return end

    local target = tonumber(getPayloadTarget(data))
    if not target then
        sendAdminMessage(src, 'Visionary AC: cible invalide pour le soin.')
        return
    end

    local ped = GetPlayerPed(target)
    if ped == 0 then
        sendAdminMessage(src, 'Visionary AC: cible hors ligne pour le soin.')
        return
    end

    local adminName = sanitizeName(GetPlayerName(src))
    local targetName = sanitizeName(GetPlayerName(target))

    local maxHealth = GetEntityMaxHealth(ped)
    setEntityHealthNative(ped, maxHealth)
    SetPedArmour(ped, 100)

    TriggerClientEvent('zvs-ac:admin:heal', target, {
        health = maxHealth,
        armour = 100,
        admin = adminName,
    })

    logger:flag('admin_heal', src, {
        target = target,
        target_name = targetName,
    })

    pushFeed({
        type = 'admin_heal',
        src = src,
        message = ('%s a soigne %s'):format(adminName, targetName),
        payload = {
            admin = src,
            admin_name = adminName,
            target = target,
            target_name = targetName,
        },
        notify = false,
    })

    sendAdminMessage(src, ('Visionary AC: %s soigne.'):format(targetName))
end

function handlers.handleWeaponWipe(src, data)
    if modCfg.AllowWeaponClear == false then
        sendAdminMessage(src, "Visionary AC: confiscation d'armes desactivee.")
        return
    end

    if not ensureAdmin(src) then return end

    local target = tonumber(getPayloadTarget(data))
    if not target then
        sendAdminMessage(src, 'Visionary AC: cible invalide pour la confiscation.')
        return
    end

    local ped = GetPlayerPed(target)
    if ped == 0 then
        sendAdminMessage(src, 'Visionary AC: cible hors ligne pour la confiscation.')
        return
    end

    local adminName = sanitizeName(GetPlayerName(src))
    local targetName = sanitizeName(GetPlayerName(target))

    RemoveAllPedWeapons(ped, true)
    TriggerClientEvent('zvs-ac:admin:wipeWeapons', target, {
        admin = adminName,
    })

    logger:flag('admin_weapon_wipe', src, {
        target = target,
        target_name = targetName,
    })

    pushFeed({
        type = 'admin_weapon_wipe',
        src = src,
        message = ("%s a vide l'arsenal de %s"):format(adminName, targetName),
        payload = {
            admin = src,
            admin_name = adminName,
            target = target,
            target_name = targetName,
        },
        notify = false,
    })

    sendAdminMessage(src, ('Visionary AC: armes retirees pour %s.'):format(targetName))
end


function handlers.handleWeaponLock(src, data)
    if modCfg.AllowWeaponDisable == false then
        sendAdminMessage(src, "Visionary AC: neutralisation d'armes desactivee.")
        return
    end

    if not ensureAdmin(src) then return end

    local target = tonumber(getPayloadTarget(data))
    if not target then
        sendAdminMessage(src, "Visionary AC: cible invalide pour la neutralisation d'armes.")
        return
    end

    local ped = GetPlayerPed(target)
    if ped == 0 then
        sendAdminMessage(src, "Visionary AC: cible hors ligne pour la neutralisation d'armes.")
        return
    end

    local enable = not isWeaponLocked(target)
    local adminName = sanitizeName(GetPlayerName(src))
    local targetName = sanitizeName(GetPlayerName(target))

    if enable then
        RemoveAllPedWeapons(ped, true)
    end

    setWeaponLockState(target, src, enable, adminName)

    TriggerClientEvent('zvs-ac:admin:weaponLock', target, {
        enabled = enable,
        admin = adminName,
    })

    logger:flag('admin_weapon_lock', src, {
        target = target,
        target_name = targetName,
        enabled = enable,
    })

    pushFeed({
        type = enable and 'admin_weapon_lock' or 'admin_weapon_unlock',
        src = src,
        message = enable
            and ('%s a neutralise les armes de %s'):format(adminName, targetName)
            or ('%s a restaure les armes de %s'):format(adminName, targetName),
        payload = {
            admin = src,
            admin_name = adminName,
            target = target,
            target_name = targetName,
            enabled = enable,
        },
        notify = false,
    })

    sendAdminMessage(src, enable and ('Visionary AC: armes neutralisees pour %s.'):format(targetName) or ('Visionary AC: armes restaurees pour %s.'):format(targetName))

    broadcastState()
end


function handlers.handleClearArea(src, data)
    if not ensureAdmin(src) then return end

    local radius = CLEAR_AREA_DEFAULT_RADIUS
    if type(data) == 'table' then
        local requested = tonumber(getPayloadField(data, 'radius'))
        if requested and requested > 0 then
            radius = clampNumber(requested + 0.0, 50.0, 1000.0)
        end
    end

    local coords = getPlayerCoords(src)
    if not coords then
        sendAdminMessage(src, 'Visionary AC: impossible de nettoyer la zone - position inconnue.')
        return
    end

    local removed = clearEntitiesAroundCoords(coords, radius)
    local adminName = sanitizeName(GetPlayerName(src))
    local radiusLabel = math.floor(radius + 0.5)

    TriggerClientEvent('zvs-ac:admin:clearArea', -1, {
        admin = src,
        adminName = adminName,
        coords = coords,
        radius = radius + 0.0,
        removed = removed,
    })

    logger:flag('admin_clear_area', src, {
        radius = radius,
        removed = removed,
        coords = coords,
    })

    pushFeed({
        type = 'admin_clear_area',
        src = src,
        message = ('%s a nettoye la zone sur %dm.'):format(adminName, radiusLabel),
        payload = {
            admin = src,
            admin_name = adminName,
            radius = radius,
            removed = removed,
        },
        notify = false,
    })

    sendAdminMessage(
        src,
        ('Visionary AC: zone nettoyee (%dm) - vehicules: %d, PNJ: %d, objets: %d.')
            :format(radiusLabel, removed.vehicles or 0, removed.peds or 0, removed.objects or 0)
    )
end


function handlers.handleVehicleEject(src, data)
    if modCfg.AllowVehicleEject == false then
        sendAdminMessage(src, 'Visionary AC: expulsion de vehicule desactivee.')
        return
    end

    if not ensureAdmin(src) then return end

    local target = tonumber(getPayloadTarget(data))
    if not target then
        sendAdminMessage(src, "Visionary AC: cible invalide pour l'expulsion du vehicule.")
        return
    end

    local ped = GetPlayerPed(target)
    if ped == 0 then
        sendAdminMessage(src, "Visionary AC: cible hors ligne pour l'expulsion du vehicule.")
        return
    end

    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        sendAdminMessage(src, "Visionary AC: la cible n'est pas dans un vehicule.")
        return
    end

    local adminName = sanitizeName(GetPlayerName(src))
    local targetName = sanitizeName(GetPlayerName(target))

    TriggerClientEvent('zvs-ac:admin:forceVehicleExit', target, {
        admin = adminName,
    })

    logger:flag('admin_vehicle_eject', src, {
        target = target,
        target_name = targetName,
        vehicle = vehicle,
    })

    pushFeed({
        type = 'admin_vehicle_eject',
        src = src,
        message = ('%s a force %s a quitter son vehicule'):format(adminName, targetName),
        payload = {
            admin = src,
            admin_name = adminName,
            target = target,
            target_name = targetName,
        },
        notify = false,
    })

    sendAdminMessage(src, ('Visionary AC: %s a ete expulse de son vehicule.'):format(targetName))
end


function handlers.handleNote(src, data)
    if cfg.AllowNotes == false then
        sendAdminMessage(src, 'Visionary AC: journal de notes desactive.')
        return
    end

    if not ensureAdmin(src) then return end
    if type(data) ~= 'table' then return end

    local target = tonumber(getPayloadTarget(data))
    if not target then
        sendAdminMessage(src, "Visionary AC: impossible d'enregistrer la note (cible inconnue).")
        return
    end

    local rawMessage = trimString(getPayloadField(data, 'message') or '')
    if type(rawMessage) ~= 'string' or rawMessage == '' then
        sendAdminMessage(src, 'Visionary AC: veuillez saisir un contenu pour la note.')
        return
    end

    local maxLength = cfg.NoteMaxLength
    if type(maxLength) == 'number' then
        maxLength = math.floor(maxLength)
        if maxLength > 0 and #rawMessage > maxLength then
            rawMessage = rawMessage:sub(1, maxLength)
        end
    end

    local category, categoryLabel = normalizeNoteCategory(getPayloadField(data, 'category'))

    local adminName = sanitizeName(GetPlayerName(src))
    local targetName = sanitizeName(GetPlayerName(target))
    local coords = getPlayerCoords(target)
    local identifiers, identifierMap = collectPlayerIdentifiers(target)
    local identifierSummaryList = formatPrimaryIdentifiersWithOptions(identifierMap, { includeIp = false })
    local identifierSummary = #identifierSummaryList > 0 and table.concat(identifierSummaryList, '\n') or nil
    local fullIdentifierSummaryList = formatPrimaryIdentifiersWithOptions(identifierMap, { includeIp = true })
    local fullIdentifierSummary = #fullIdentifierSummaryList > 0 and table.concat(fullIdentifierSummaryList, '\n') or nil

    local entry = {
        admin = src,
        adminName = adminName,
        target = target,
        targetName = targetName,
        category = category,
        categoryLabel = categoryLabel,
        message = rawMessage,
        createdAt = os.time(),
        coords = coords,
        identifierSummary = identifierSummary,
    }

    recordModerationNote(entry)

    logger:flag('admin_note', src, {
        target = target,
        target_name = targetName,
        admin_name = adminName,
        category = category,
        message = rawMessage,
        coords = coords,
        identifiers = identifiers,
        identifier_map = identifierMap,
        identifier_summary = fullIdentifierSummary,
    })

    pushFeed({
        type = 'admin_note',
        src = src,
        message = ('%s a ajoute une note sur %s'):format(adminName, targetName),
        payload = {
            admin = src,
            admin_name = adminName,
            target = target,
            target_name = targetName,
            category = category,
        },
        notify = false,
        log = false,
    })

    sendAdminMessage(src, ('Visionary AC: note enregistree pour %s.'):format(targetName))
    broadcastState()
end

function handlers.handleSpawnProtectionToggle(src, data)
    if not ensureAdmin(src) then return end
    if cfg and cfg.TargetedSpawnProtection and cfg.TargetedSpawnProtection.Enabled == false then
        sendAdminMessage(src, 'Visionary AC: protection anti-spawn ciblée désactivée dans la configuration.')
        return
    end
    if type(data) ~= 'table' then return end

    local target = tonumber(getPayloadTarget(data))
    if not target then
        sendAdminMessage(src, "Visionary AC: cible invalide pour la protection anti-spawn.")
        return
    end

    if GetPlayerPed(target) == 0 then
        sendAdminMessage(src, "Visionary AC: la cible est hors ligne pour la protection anti-spawn.")
        return
    end

    local desiredEnabled = getPayloadField(data, 'enabled')
    if desiredEnabled ~= nil then
        desiredEnabled = desiredEnabled and true or false
    end
    local currentEnabled, currentEntry = isSpawnProtectionTarget(target)
    local nextEnabled = desiredEnabled
    if nextEnabled == nil then
        nextEnabled = not currentEnabled
    end
    if currentEnabled == nextEnabled and currentEntry then
        sendAdminMessage(src, ('Visionary AC: protection anti-spawn déjà %s pour %s.'):format(nextEnabled and 'active' or 'inactive', sanitizeName(GetPlayerName(target))))
        return
    end

    local identifiers = getPlayerPersistentIdentifierMap(target)
    local hasIdentifier = false
    for _, _ in pairs(identifiers) do
        hasIdentifier = true
        break
    end
    if not hasIdentifier then
        sendAdminMessage(src, "Visionary AC: impossible d'identifier durablement la cible.")
        return
    end

    local targetName = sanitizeName(GetPlayerName(target))
    local adminName = sanitizeName(GetPlayerName(src))
    local reason = trimString(getPayloadField(data, 'reason') or '')
    if type(reason) ~= 'string' or reason == '' then
        reason = 'Contrôle anti-abuse ciblé'
    end

    if nextEnabled then
        local entry = currentEntry or {
            id = utils.randomId('spawn-guard-'),
            createdAt = os.time(),
        }
        entry.enabled = true
        entry.targetName = targetName
        entry.reason = reason
        entry.updatedAt = os.time()
        entry.updatedBy = src
        entry.updatedByName = adminName
        entry.identifiers = identifiers
        if not currentEntry then
            spawnProtectionTargets[#spawnProtectionTargets + 1] = entry
        end
    elseif currentEntry then
        currentEntry.enabled = false
        currentEntry.updatedAt = os.time()
        currentEntry.updatedBy = src
        currentEntry.updatedByName = adminName
        currentEntry.targetName = targetName
    end

    sanitizeSpawnProtectionTargets()
    saveSpawnProtectionTargets()
    do
        local category = 'surveillance'
        recordModerationNote({
            admin = src,
            adminName = adminName,
            target = target,
            targetName = targetName,
            category = category,
            categoryLabel = noteCategories[category] or 'Surveillance',
            message = nextEnabled
                and ('Protection anti-spawn activée (%s).'):format(reason)
                or ('Protection anti-spawn désactivée.'),
            createdAt = os.time(),
        })
    end

    logger:flag('admin_spawn_protection_toggle', src, {
        target = target,
        target_name = targetName,
        admin_name = adminName,
        enabled = nextEnabled,
        reason = reason,
        identifiers = GetPlayerIdentifiers(target),
        identifier_map = select(2, collectPlayerIdentifiers(target)),
    })

    pushFeed({
        type = 'admin_spawn_protection_toggle',
        src = src,
        message = nextEnabled
            and ('%s a activé la protection anti-spawn sur %s'):format(adminName, targetName)
            or ('%s a désactivé la protection anti-spawn sur %s'):format(adminName, targetName),
        payload = {
            admin = src,
            admin_name = adminName,
            target = target,
            target_name = targetName,
            enabled = nextEnabled,
            reason = reason,
        },
        notify = false,
    })

    sendAdminMessage(src, nextEnabled
        and ('Visionary AC: protection anti-spawn active pour %s.'):format(targetName)
        or ('Visionary AC: protection anti-spawn désactivée pour %s.'):format(targetName))
    broadcastState()
end

function module.handleWarn(src, data)
    if modCfg.AllowWarn == false then
        sendAdminMessage(src, 'Visionary AC: avertissements desactives.')
        return
    end

    if not ensureAdmin(src) then return end

    local target = tonumber(getPayloadTarget(data))
    if not target then
        sendAdminMessage(src, "Visionary AC: cible invalide pour l'avertissement.")
        return
    end

    local message = tostring(getPayloadField(data, 'message') or getPayloadField(data, 'reason') or 'Veuillez respecter les regles du serveur.')
    if message == '' then
        sendAdminMessage(src, "Visionary AC: message d'avertissement requis.")
        return
    end

    local adminName = sanitizeName(GetPlayerName(src))
    local targetName = sanitizeName(GetPlayerName(target))

    TriggerClientEvent('zvs-ac:admin:warn', target, {
        message = message,
        admin = adminName,
    })

    logger:flag('admin_warn', src, {
        target = target,
        target_name = targetName,
        message = message,
    })

    pushFeed({
        type = 'admin_warn',
        src = src,
        message = ('%s a averti %s: %s'):format(adminName, targetName, message),
        payload = {
            admin = src,
            admin_name = adminName,
            target = target,
            target_name = targetName,
            message = message,
        },
        notify = false,
    })

    sendAdminMessage(src, ('Visionary AC: avertissement envoye a %s.'):format(targetName))
end

function module.openMenu(src)
    if not ensureAdmin(src) then return end
    sendState(src)
end

function module.onPlayerConnecting(name, setKickReason, deferrals)
    local src = source
    local identifiers = GetPlayerIdentifiers(src)
    local ban = isBanned(identifiers)
    if not ban then return end

    local message = ('Visionary AC - Vous etes banni: %s'):format(ban.reason or 'Raison non definie')
    if deferrals then
        deferrals.defer()
        Wait(0)
        deferrals.done(message)
    else
        setKickReason(message)
    end
    CancelEvent()
end

function module:init()
    cfg = Config.AdminTools or {}
    modCfg = cfg.Moderation or {}
    defenseCfg = cfg.DefenseControl or {}
    if not cfg.Enabled then
        utils.debugLog('Admin tools disabled by configuration')
        return
    end

    rebuildFeedLimit()
    rebuildModerationNotesLimit()
    rebuildScreenshotHistoryLimit()
    loadBans()
    loadModerationNotes()
    loadSpawnProtectionTargets()
    loadSuspiciousFeed()
    loadAppearanceSettings()

    RegisterCommand(tostring((cfg.AdminSettings or {}).ResetCommand or 'zvs_resetui'), function(src)
        if src == 0 then
            print('zVS-AC: /zvs_resetui must be run by an in-game admin because settings are per identifier.')
            return
        end
        local ok, err, settings = AdminSettings.reset(src)
        TriggerClientEvent('zvs-ac:admin:settingsSaved', src, {
            ok = ok == true,
            reset = true,
            error = err,
            settings = settings or AdminSettings.export(src),
            runtimeConfig = AdminSettings.runtime(src),
        })
        if ok then
            updateState(src)
            sendAdminMessage(src, 'Visionary AC: interface réinitialisée.')
        else
            sendAdminMessage(src, ('Visionary AC: reset UI impossible (%s).'):format(tostring(err)))
        end
    end, false)

    RegisterNetEvent('zvs-ac:admin:requestOpen', function()
        local src = source
        module.openMenu(src)
    end)

    RegisterNetEvent('zvs-ac:admin:refresh', function()
        local src = source
        if ensureAdmin(src) then
            updateState(src)
        end
    end)

    RegisterNetEvent('zvs-ac:admin:saveAppearance', function(data)
        handleSaveAppearance(source, asTable(data))
    end)

    RegisterNetEvent('zvs-ac:admin:saveSettings', function(data)
        local src = source
        local payload = type(data) == 'table' and data or {}
        local ok, err, settings = AdminSettings.save(src, payload.settings or payload, payload.immediate == true)
        TriggerClientEvent('zvs-ac:admin:settingsSaved', src, {
            ok = ok == true,
            error = err,
            settings = settings or AdminSettings.export(src),
            runtimeConfig = AdminSettings.runtime(src),
        })
    end)

    RegisterNetEvent('zvs-ac:admin:resetSettings', function()
        local src = source
        local ok, err, settings = AdminSettings.reset(src)
        TriggerClientEvent('zvs-ac:admin:settingsSaved', src, {
            ok = ok == true,
            reset = true,
            error = err,
            settings = settings or AdminSettings.export(src),
            runtimeConfig = AdminSettings.runtime(src),
        })
        if ok then
            updateState(src)
        end
    end)

    RegisterNetEvent('zvs:server:getRuntimeConfig', function()
        local src = source
        if not ensureAdmin(src) then return end
        TriggerClientEvent('zvs-ac:admin:runtimeConfig', src, {
            runtimeConfig = AdminSettings.runtime(src),
            adminSettings = AdminSettings.export(src),
        })
    end)

    RegisterNetEvent('zvs-ac:admin:requestSnapshot', function(data)
        handlers.handleSnapshot(source, asTable(data))
    end)

    RegisterNetEvent('zvs-ac:admin:requestLivePreviewFrame', function(data)
        handlers.handleLivePreviewRequest(source, asTable(data))
    end)

    RegisterNetEvent('zvs-ac:admin:stopLivePreview', function(data)
        handlers.handleLivePreviewStop(source, asTable(data))
    end)

    RegisterNetEvent('zvs-ac:admin:submitPortrait', function(data)
        local src = source
        if type(data) ~= 'table' then return end
        local requestId = tostring(data.requestId or '')
        if requestId == '' then return end

        local request = previewPortraitRequests[requestId]
        if not request then return end
        if request.target ~= src then return end

        previewPortraitRequests[requestId] = nil

        if not request.admin or request.admin == 0 then return end
        if GetPlayerPed(request.admin) == 0 then return end

        TriggerClientEvent('zvs-ac:admin:previewPortrait', request.admin, {
            target = src,
            portrait = data.portrait,
            error = data.error,
            mode = data.mode,
            format = data.format,
            ts = os.time(),
        })
    end)

    RegisterNetEvent('zvs-ac:admin:ban', function(data)
        handlers.handleBan(source, asTable(data))
    end)

    RegisterNetEvent('zvs-ac:admin:unban', function(data)
        handlers.handleUnban(source, asTable(data))
    end)

    RegisterNetEvent('zvs-ac:admin:requestScreenshot', function(data)
        handlers.handleScreenshot(source, asTable(data))
    end)

    RegisterNetEvent('zvs-ac:admin:kick', function(data)
        handlers.handleKick(source, asTable(data))
    end)

    RegisterNetEvent('zvs-ac:admin:toggleFreeze', function(data)
        handlers.handleFreeze(source, asTable(data))
    end)

    RegisterNetEvent('zvs-ac:admin:toggleSpectate', function(data)
        handlers.handleSpectate(source, asTable(data))
    end)

    RegisterNetEvent('zvs-ac:admin:spectate:requestSync', function()
        local src = source
        local session = spectateSessions[src]
        if not session then return end

        local now = GetGameTimer()
        local minInterval = math.max(250, tonumber(modCfg.SpectateSyncIntervalMs) or 350)
        local nextAllowed = spectateSyncThrottle[src] or 0
        if now < nextAllowed then return end
        spectateSyncThrottle[src] = now + minInterval

        local target = session.target
        if not target then return end
        if tonumber(target) == tonumber(src) then
            stopSpectate(src, { log = false, reason = 'self_guard' })
            TriggerClientEvent('zvs-ac:admin:spectateTarget', src, {
                enabled = false,
                reason = 'self_guard',
            })
            return
        end
        if GetPlayerPed(target) == 0 then
            stopSpectate(src, { log = false, reason = 'target_left' })
            return
        end

        local payload = buildSpectatePayload(src, target)
        if not payload then return end

        TriggerClientEvent('zvs-ac:admin:spectate:sync', src, payload)

        -- Target POV probes are admin-only and throttled per target to keep the client near 0.00ms.
        if modCfg.RequestTargetCamera == true then
            local probeInterval = math.max(650, tonumber(modCfg.SpectateTargetCameraIntervalMs) or 850)
            local nextProbe = spectateCameraProbeThrottle[target] or 0
            if now >= nextProbe then
                spectateCameraProbeThrottle[target] = now + probeInterval
                TriggerClientEvent('zvs-ac:admin:spectate:requestCamera', target, {
                    target = target,
                    interval = probeInterval,
                    silent = true,
                })
            end
        end
    end)

    RegisterNetEvent('zvs-ac:admin:spectate:camera', function(data)
        local src = source
        if type(data) ~= 'table' then return end
        local target = tonumber(getPayloadTarget(data))
        if not target or target ~= src then
            return
        end

        local watchers = spectateTargetWatchers[target]
        if not watchers then return end

        local camera = type(data.camera) == 'table' and data.camera or {}
        local rotation = type(camera.rot) == 'table' and camera.rot or {}
        local targetCoords = cloneVector3(data.coords) or getPlayerCoords(target)
        local incomingState = type(data.state) == 'table' and data.state or {}
        local stateSnapshot = {
            activity = type(incomingState.activity) == 'string' and incomingState.activity or nil,
            speed = tonumber(incomingState.speed),
            health = tonumber(incomingState.health),
            armor = tonumber(incomingState.armor),
            weapon = tonumber(incomingState.weapon),
            inVehicle = incomingState.inVehicle and true or false,
            vehicleModel = tonumber(incomingState.vehicleModel),
        }
        local cameraSnapshot = {
            x = tonumber(camera.x) or 0.0,
            y = tonumber(camera.y) or 0.0,
            z = tonumber(camera.z) or 0.0,
            rot = {
                x = tonumber(rotation.x) or 0.0,
                y = tonumber(rotation.y) or 0.0,
                z = tonumber(rotation.z) or 0.0,
            },
        }
        spectateSyncCache[target] = {
            camera = cameraSnapshot,
            coords = targetCoords,
            state = stateSnapshot,
            ts = os.time(),
            gameTime = GetGameTimer(),
        }
        evaluateSpectatorCameraAbuse(target, cameraSnapshot, targetCoords)
    end)

    RegisterNetEvent('zvs-ac:admin:goto', function(data)
        handlers.handleGoto(source, asTable(data))
    end)

    RegisterNetEvent('zvs-ac:admin:bring', function(data)
        handlers.handleBring(source, asTable(data))
    end)

    RegisterNetEvent('zvs-ac:admin:heal', function(data)
        handlers.handleHeal(source, asTable(data))
    end)

    RegisterNetEvent('zvs-ac:admin:wipeWeapons', function(data)
        handlers.handleWeaponWipe(source, asTable(data))
    end)

    RegisterNetEvent('zvs-ac:admin:toggleWeaponLock', function(data)
        handlers.handleWeaponLock(source, asTable(data))
    end)

    RegisterNetEvent('zvs-ac:admin:clearArea', function(data)
        handlers.handleClearArea(source, asTable(data))
    end)

    RegisterNetEvent('zvs-ac:admin:forceVehicleExit', function(data)
        handlers.handleVehicleEject(source, asTable(data))
    end)

    RegisterNetEvent('zvs-ac:admin:warn', function(data)
        module.handleWarn(source, asTable(data))
    end)

    RegisterNetEvent('zvs-ac:admin:addNote', function(data)
        handlers.handleNote(source, asTable(data))
    end)

    RegisterNetEvent('zvs-ac:admin:toggleSpawnProtection', function(data)
        handlers.handleSpawnProtectionToggle(source, asTable(data))
    end)

    RegisterNetEvent('zvs-ac:admin:toggleCloak', function()
        local src = source
        local staffNoClipCfg = cfg and cfg.StaffNoClip or {}
        if modCfg.AllowCloak == false or staffNoClipCfg.Enabled ~= true or staffNoClipCfg.DoNotModifyPed == true then
            sendAdminMessage(src, 'Visionary AC: NoClip interne indisponible dans la configuration actuelle.')
            return
        end

        if not ensureAdmin(src) then return end

        toggleCloak(src)
    end)

    RegisterNetEvent('zvs-ac:admin:setDefenseState', function(data)
        handlers.handleDefenseToggle(source, asTable(data))
    end)

    RegisterNetEvent('zvs-ac:admin:resolveRiskApproval', function(data)
        local src = source
        if not ensureAdmin(src) then return end
        local id = type(data) == 'table' and tostring(data.id or '') or ''
        if id == '' then return end
        local approved = type(data) == 'table' and data.approved == true
        local engine = zVS.riskEngine or (type(zVS.getModule) == 'function' and zVS.getModule('server.modules.risk_engine'))
        if not engine or type(engine.resolveApproval) ~= 'function' then return end
        local ok, reason = engine:resolveApproval(id, src, approved)
        if ok then
            pushFeed({
                type = approved and 'risk_approval_approved' or 'risk_approval_rejected',
                src = src,
                message = ('%s a %s une suggestion Risk Engine.'):format(sanitizeName(GetPlayerName(src)), approved and 'validé humainement' or 'rejeté'),
                payload = { approval = id, approved = approved, admin_name = sanitizeName(GetPlayerName(src)), human_review_only = true },
                logType = approved and 'risk_staff_decision_approved' or 'risk_staff_decision_rejected',
            })
        else
            sendAdminMessage(src, ('Visionary AC: approbation introuvable (%s).'):format(tostring(reason)))
        end
    end)

    AddEventHandler('zvs-ac:adminTools:flag', function(entry)
        if type(entry) ~= 'table' then return end
        pushFeed(entry)
    end)

    AddEventHandler('playerDropped', function()
        local src = source
        AdminSettings.flushForSource(src)
        local dirty = false
        for id, pending in pairs(pendingScreenshots) do
            if pending.admin == src or pending.target == src then
                if pending.timer then
                    Citizen.ClearTimeout(pending.timer)
                end
                pendingScreenshots[id] = nil
            end
        end

        clearScreenshotHistory(src)

        if livePreviewSessions[src] then
            livePreviewSessions[src] = nil
        end

        for admin, session in pairs(livePreviewSessions) do
            if session.target == src then
                livePreviewSessions[admin] = nil
                sendLivePreviewFrameEvent(admin, {
                    target = src,
                    error = 'target_left',
                    ts = os.time(),
                })
            end
        end

        if frozenPlayers[src] then
            frozenPlayers[src] = nil
            dirty = true
        end

        spectateSyncThrottle[src] = nil
        if spectateSessions[src] then
            local session = spectateSessions[src]
            if session and session.target and spectateTargetWatchers[session.target] then
                spectateTargetWatchers[session.target][src] = nil
                if next(spectateTargetWatchers[session.target]) == nil then
                    spectateTargetWatchers[session.target] = nil
                    spectateSyncCache[session.target] = nil
                    spectateCameraProbeThrottle[session.target] = nil
                end
            end
            spectateSessions[src] = nil
            dirty = true
        end

        if cloakedAdmins[src] then
            cloakedAdmins[src] = nil
            dirty = true
        end

        if weaponLocks[src] then
            weaponLocks[src] = nil
            dirty = true
        end

        previewDetectionState.highSpeed[src] = nil
        previewDetectionState.highSpeedVehicle[src] = nil
        previewDetectionState.invincible[src] = nil
        previewDetectionState.excessHealth[src] = nil
        previewDetectionState.excessArmor[src] = nil
        previewDetectionState.invisible[src] = nil
        previewDetectionState.teleport[src] = nil
        previewDetectionState.airwalk[src] = nil
        previewDetectionState.speedBurst[src] = nil
        previewDetectionState.suddenAscent[src] = nil
        previewDetectionState.spectatorAbuse[src] = nil
        previewDetectionState.lastSnapshots[src] = nil

        clearDetectionImmunity(src)

        for id, request in pairs(previewPortraitRequests) do
            if request.admin == src or request.target == src then
                previewPortraitRequests[id] = nil
            end
        end

        for key, _ in pairs(previewPortraitLastRequest) do
            local adminId, targetId = key:match('^(%-?%d+):(%-?%d+)$')
            if adminId then
                if tonumber(adminId) == src or tonumber(targetId) == src then
                    previewPortraitLastRequest[key] = nil
                end
            end
        end

        for admin, session in pairs(spectateSessions) do
            if session.target == src then
                stopSpectate(admin, { log = false, reason = 'target_left' })
                sendAdminMessage(admin, 'Visionary AC: cible deconnectee, spectateur ferme.')
                dirty = true
            end
        end

        spectateTargetWatchers[src] = nil
        spectateSyncCache[src] = nil
        spectateCameraProbeThrottle[src] = nil

        if dirty then
            broadcastState()
        end
    end)

    AddEventHandler('playerConnecting', module.onPlayerConnecting)

    if cfg.Command and cfg.Command ~= '' then
        RegisterCommand(cfg.Command, function(src)
            if src == 0 then
                print('[zvs-ac] Admin menu cannot be opened from the console.')
                return
            end
            module.openMenu(src)
        end, false)
    end

    RegisterCommand('zvs_fixcollision', function(src, args)
        args = args or {}
        local targetArg = tostring(args[1] or ''):lower()

        if src ~= 0 and not ensureAdmin(src) then
            return
        end

        local payload = { reason = 'admin-command', notify = true, force = false }

        if targetArg == 'all' then
            for _, player in ipairs(GetPlayers()) do
                TriggerClientEvent('zvs-ac:client:repairCollision', tonumber(player), payload)
            end
            if src == 0 then
                print('[zvs-ac] Collision repair sent to all players.')
            else
                sendAdminMessage(src, 'Visionary AC: collision repair envoyé à tous les joueurs.')
            end
            return
        end

        local target = tonumber(args[1])
        if not target and src ~= 0 then
            target = src
        end

        if not target or GetPlayerPed(target) == 0 then
            if src == 0 then
                print('[zvs-ac] Usage: zvs_fixcollision <id|all>')
            else
                sendAdminMessage(src, 'Visionary AC: usage /zvs_fixcollision [id|all]')
            end
            return
        end

        TriggerClientEvent('zvs-ac:client:repairCollision', target, payload)
        if src == 0 then
            print(('[zvs-ac] Collision repair sent to player %s.'):format(target))
        else
            sendAdminMessage(src, ('Visionary AC: collision repair envoyé à %s.'):format(target))
        end
    end, false)

    AddEventHandler('zvs-ac:risk:autoFreeze', function(target, reason, payload)
        target = tonumber(target)
        if not target or GetPlayerPed(target) == 0 then return end
        setFrozenState(target, 0, true, reason or 'Visionary Risk Engine staff-approved freeze')
        TriggerClientEvent('zvs-ac:admin:freezeState', target, { enabled = true, reason = reason })
        pushFeed({
            type = 'risk_staff_freeze',
            src = target,
            message = ('Risk Engine a gelé %s après validation staff.'):format(sanitizeName(GetPlayerName(target))),
            payload = payload or {},
            logType = 'risk_staff_freeze',
        })
    end)

    AddEventHandler('zvs-ac:risk:autoBan', function(target, reason, payload)
        target = tonumber(target)
        if not target or GetPlayerPed(target) == 0 then return end
        local identifiers = GetPlayerIdentifiers(target) or {}
        registerBan({
            name = sanitizeName(GetPlayerName(target)),
            identifiers = identifiers,
            reason = reason or 'Visionary Risk Engine staff-approved ban',
            bannedBy = 'Visionary Risk Engine / staff-approved',
        })
        pushFeed({
            type = 'risk_staff_ban',
            src = target,
            message = ('Risk Engine a banni %s après validation staff.'):format(sanitizeName(GetPlayerName(target))),
            payload = payload or {},
            logType = 'risk_staff_ban',
        })
        DropPlayer(target, ('Visionary AC - %s'):format(reason or 'Risk Engine staff-approved ban'))
    end)

    zVS.adminTools = zVS.adminTools or {}
    zVS.adminTools.pushFeed = pushFeed
    zVS.adminTools.getState = buildState
    zVS.adminTools.notifyAdmins = notifyAdmins
    zVS.adminTools.isDefenseEnabled = isDefenseEnabled
    zVS.adminTools.isRealtimeSpawnProtectionEnabledFor = function(target)
        local targetedCfg = cfg and cfg.TargetedSpawnProtection or {}
        if targetedCfg.Enabled == false then
            return true
        end
        local defaultProtectAll = targetedCfg.DefaultProtectAll == true
        if defaultProtectAll then
            return true
        end
        return isSpawnProtectionTarget(target)
    end

    utils.debugLog('Admin tools module initialised')
end

if zVS and type(zVS.registerModule) == 'function' then
    return zVS.registerModule('server.modules.admin_tools', module)
end

return module
