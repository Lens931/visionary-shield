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

local function sanitizeLabel(value)
    if type(value) ~= 'string' then
        return nil
    end
    local sanitized = value:gsub('[\r\n]', ' ')
    sanitized = sanitized:match('^%s*(.-)%s*$') or sanitized
    return sanitized
end

function module:init()
    local guardCfg = Config.ResourceGuard or {}
    if guardCfg.Enabled == false then
        utils.debugLog('Resource guard disabled by configuration')
        return
    end

    local resourceName = GetCurrentResourceName()

    local protectedLookup = {}
    local protectedNames = {}

    local function registerResource(name)
        if type(name) ~= 'string' then return end
        local trimmed = sanitizeLabel(name)
        if not trimmed or trimmed == '' then return end
        local normalized = trimmed:lower()
        if not protectedLookup[normalized] then
            protectedLookup[normalized] = trimmed
            protectedNames[#protectedNames + 1] = trimmed
        end
    end

    if type(guardCfg.ProtectedResources) == 'table' then
        for _, name in ipairs(guardCfg.ProtectedResources) do
            registerResource(name)
        end
    end

    registerResource(resourceName)

    if #protectedNames == 0 then
        utils.debugLog('Resource guard: no resources registered for protection')
        return
    end

    local function canonicalName(name)
        if type(name) ~= 'string' then return nil end
        return protectedLookup[name:lower()]
    end

    local function listProtected()
        local items = {}
        for _, name in ipairs(protectedNames) do
            items[#items + 1] = name
        end
        return table.concat(items, ', ')
    end

    utils.debugLog(('Resource guard monitoring: %s'):format(listProtected()))

    local alertCooldown = math.max(tonumber(guardCfg.AlertCooldownMs) or 15000, 1000)
    local restartDelay = math.max(tonumber(guardCfg.RestartDelayMs) or 600, 100)
    local restartAttempts = math.max(math.floor(tonumber(guardCfg.RestartAttempts) or 3), 1)
    local monitorInterval = math.max(tonumber(guardCfg.MonitorIntervalMs) or 5000, 1000)
    local healthGrace = math.max(tonumber(guardCfg.HealthCheckGraceMs) or 4000, 500)

    local recentAlerts = {}
    local restartPending = {}
    local offlineSince = {}
    local lastActors = {}

    local function recordActor(resource, actor)
        if resource then
            lastActors[resource] = actor
        end
    end

    local function consumeActor(resource)
        if not resource then return nil end
        local actor = lastActors[resource]
        lastActors[resource] = nil
        return actor
    end

    local function throttle(key)
        local now = GetGameTimer()
        local expiry = recentAlerts[key]
        if expiry and expiry > now then
            return true
        end
        recentAlerts[key] = now + alertCooldown
        return false
    end

    local function describeActor(actor)
        if not actor then
            return 'Console serveur'
        end
        if actor.type == 'player' then
            if actor.name and actor.name ~= '' then
                return ('%s (#%s)'):format(actor.name, actor.id)
            end
            return ('Joueur #%s'):format(actor.id)
        elseif actor.type == 'resource' then
            return ('Ressource %s'):format(actor.name)
        elseif actor.type == 'rcon' then
            return 'Console RCON'
        elseif actor.type == 'console' then
            return 'Console serveur'
        end
        if actor.label and actor.label ~= '' then
            return actor.label
        end
        return 'Origine inconnue'
    end

    local function enrichPayloadWithActor(payload, actor)
        if not actor then
            payload.invoker = payload.invoker or 'console'
            payload.invoker_label = payload.invoker_label or 'Console serveur'
            return
        end

        payload.actor_type = payload.actor_type or actor.type

        if actor.type == 'player' then
            payload.src = payload.src or actor.id
            payload.invoker = payload.invoker or actor.id
            payload.invoker_name = payload.invoker_name or actor.name
        elseif actor.type == 'resource' then
            payload.invoker_resource = payload.invoker_resource or actor.name
            payload.invoker = payload.invoker or ('resource:' .. actor.name)
        elseif actor.type == 'rcon' then
            payload.invoker = payload.invoker or 'rcon'
        else
            payload.invoker = payload.invoker or actor.label or actor.type
        end

        payload.invoker_label = payload.invoker_label or describeActor(actor)

        if actor.command then
            payload.command = payload.command or actor.command
        end
        if actor.raw_command then
            payload.raw_command = payload.raw_command or actor.raw_command
        end
        if actor.reason then
            payload.reason = payload.reason or actor.reason
        end
    end

    local function pushGuardFeed(kind, message, payload, options)
        options = options or {}
        payload = payload or {}

        local key = options.alertKey or (kind .. ':' .. tostring(payload.resource or ''))
        if not options.force and throttle(key) then
            return
        end

        local eventPayload = utils.copyTable(payload)
        eventPayload.guard = eventPayload.guard or 'resource'
        eventPayload.event = eventPayload.event or kind
        eventPayload.description = eventPayload.description or message
        eventPayload.detection = eventPayload.detection or kind

        local entry = {
            type = options.feedType or 'ResourceGuard',
            message = message,
            payload = eventPayload,
            category = 'Sécurité',
            categoryLabel = 'Protection',
            logType = options.logType or ('resource_guard_' .. kind),
        }

        if payload.src then
            entry.src = payload.src
        end

        if options.notify == false then
            entry.notify = false
        else
            entry.notifyMessage = options.notifyMessage or message
        end

        if zVS.adminTools and zVS.adminTools.pushFeed then
            zVS.adminTools.pushFeed(entry)
        else
            logger:flag(entry.logType, payload.src or 0, eventPayload)
        end
    end

    local function clearRestartState(name)
        restartPending[name] = nil
        offlineSince[name] = nil
    end

    local function scheduleRestart(name, context)
        if restartPending[name] then
            return
        end

        restartPending[name] = true
        local attempt = 0

        local function tryRestart()
            local state = GetResourceState(name)
            if state == 'started' then
                clearRestartState(name)
                if context and context.successMessage then
                    pushGuardFeed('restart_success', context.successMessage, {
                        resource = name,
                        reason = context.reason or 'auto_restart',
                        attempts = attempt,
                        detection = 'resource_guard_restart_success',
                        invoker_label = context.invokerLabel,
                    }, { notify = false, alertKey = 'restart_success:' .. name })
                end
                return
            elseif state == 'starting' then
                if attempt < restartAttempts then
                    Citizen.SetTimeout(restartDelay, tryRestart)
                    return
                end
            end

            attempt = attempt + 1
            local ok, err = pcall(StartResource, name)
            if not ok then
                utils.debugLog(('Resource guard: unable to restart %s (%s)'):format(name, err or 'unknown error'))
            end

            if attempt < restartAttempts then
                Citizen.SetTimeout(restartDelay, tryRestart)
            else
                clearRestartState(name)
                pushGuardFeed('restart_failed', ('Échec du redémarrage automatique de %s après %s tentatives.'):format(name, attempt), {
                    resource = name,
                    attempts = attempt,
                    reason = context and context.reason or 'auto_restart',
                    detection = 'resource_guard_restart_failed',
                    invoker_label = context and context.invokerLabel,
                }, { alertKey = 'restart_failed:' .. name, notify = true })
            end
        end

        Citizen.SetTimeout(restartDelay, tryRestart)
    end

    AddEventHandler('rconCommand', function(commandName, args, rawCommand)
        local cmd = type(commandName) == 'string' and commandName:lower() or nil
        if not cmd then return end
        if cmd ~= 'stop' and cmd ~= 'restart' and cmd ~= 'ensure' then return end

        local target = args and args[1]
        if type(target) ~= 'string' then return end

        local actual = canonicalName(target)
        if not actual then return end

        local actor = {
            type = 'rcon',
            label = 'Console RCON',
            command = cmd,
            raw_command = rawCommand,
            reason = 'rcon_command',
        }

        recordActor(actual, actor)

        local message = ('Commande %s détectée via RCON pour la ressource protégée %s.'):format(cmd, actual)
        pushGuardFeed('command_detected', message, {
            resource = actual,
            command = cmd,
            raw_command = rawCommand,
            detection = 'resource_guard_command',
            reason = 'rcon_command',
        }, { alertKey = 'command:' .. cmd .. ':' .. actual, notifyMessage = message, force = true })
    end)

    AddEventHandler('onResourceStop', function(name)
        local actual = canonicalName(name)
        if not actual then return end

        local actor = consumeActor(actual)

        local src = actor and actor.src or source
        local srcNumber = tonumber(src)
        if not actor and srcNumber and srcNumber > 0 then
            actor = {
                type = 'player',
                id = srcNumber,
                name = sanitizeLabel(GetPlayerName(srcNumber)),
            }
        end

        local invokerResource = actor and actor.invoker_resource or nil
        if type(GetInvokingResource) == 'function' then
            local ok, invoker = pcall(GetInvokingResource)
            if ok and invoker and invoker ~= '' then
                invokerResource = invoker
                if not actor or actor.type ~= 'player' then
                    actor = actor or {}
                    actor.type = actor.type or 'resource'
                    actor.name = actor.name or invoker
                    actor.invoker_resource = invoker
                end
            end
        end

        if not actor then
            actor = { type = 'console', label = 'Console serveur' }
        end

        local actorLabel = describeActor(actor)
        local message = ('Tentative d\'arrêt détectée sur la ressource protégée %s (origine: %s). Relance automatique enclenchée.'):format(actual, actorLabel)

        local payload = {
            resource = actual,
            detection = 'resource_guard_stop',
            reason = actor.reason or 'resource_stop',
            invoker_resource = invokerResource,
        }

        enrichPayloadWithActor(payload, actor)

        pushGuardFeed('stop_detected', message, payload, { notifyMessage = message, alertKey = 'stop:' .. actual, force = true })

        scheduleRestart(actual, {
            reason = payload.reason,
            invokerLabel = actorLabel,
            successMessage = ('Ressource protégée %s relancée automatiquement après une coupure.'):format(actual),
        })
    end)

    AddEventHandler('onResourceStart', function(name)
        local actual = canonicalName(name)
        if not actual then return end
        restartPending[actual] = nil
        offlineSince[actual] = nil
    end)

    CreateThread(function()
        while true do
            Wait(monitorInterval)
            local now = GetGameTimer()
            for _, protected in ipairs(protectedNames) do
                local state = GetResourceState(protected)
                if state ~= 'started' then
                    local firstSeen = offlineSince[protected]
                    if not firstSeen then
                        offlineSince[protected] = now
                    end

                    if not restartPending[protected] and firstSeen and (now - firstSeen) >= healthGrace then
                        local message = ('Surveillance: %s est hors ligne, tentative de relance automatique.'):format(protected)
                        pushGuardFeed('health_check', message, {
                            resource = protected,
                            detection = 'resource_guard_health',
                            reason = 'health_check',
                        }, { alertKey = 'health:' .. protected, notifyMessage = message, force = true })

                        scheduleRestart(protected, {
                            reason = 'health_check',
                            invokerLabel = 'surveillance automatique',
                            successMessage = ('%s relancée après surveillance automatique.'):format(protected),
                        })
                    end
                else
                    offlineSince[protected] = nil
                end
            end
        end
    end)
end

if zVS and type(zVS.registerModule) == 'function' then
    return zVS.registerModule('server.modules.resource_guard', module)
end

return module
