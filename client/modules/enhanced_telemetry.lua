zVS = zVS or {}
local Config = zVS.Config or {}
local cfg = Config.EnhancedDetections or {}

if cfg.Enabled == false or cfg.ClientTelemetry == false then
    return
end

local activeInterval = math.max(1500, tonumber(cfg.ClientTelemetryIntervalMs) or 3000)
local idleInterval = math.max(activeInterval, tonumber(cfg.ClientIdleTelemetryIntervalMs) or (activeInterval * 3))
local combatInterval = math.max(180, tonumber(cfg.CombatTelemetryIntervalMs) or 350)
local combatIdleInterval = math.max(750, tonumber(cfg.CombatIdleIntervalMs) or 1500)
local lastCombat = 0
local lastAimStart = 0
local lastAimHeading = nil
local lastTelemetryAt = 0
local lastTelemetryCoords = nil

local function coordsTable(vec)
    if not vec then return nil end
    return { x = vec.x + 0.0, y = vec.y + 0.0, z = vec.z + 0.0 }
end

local function distanceSq(a, b)
    if not a or not b then return math.huge end
    local dx = (a.x or 0.0) - (b.x or 0.0)
    local dy = (a.y or 0.0) - (b.y or 0.0)
    local dz = (a.z or 0.0) - (b.z or 0.0)
    return (dx * dx) + (dy * dy) + (dz * dz)
end

local function safeHeight(ped)
    if type(GetEntityHeightAboveGround) ~= 'function' then return 0.0 end
    return (GetEntityHeightAboveGround(ped) or 0.0) + 0.0
end

local function isPedActive(ped, veh, speedKmh)
    if IsPedShooting(ped) or IsPedInMeleeCombat(ped) or IsPedBeingStunned(ped, 0) then
        return true
    end
    if IsPlayerFreeAiming(PlayerId()) then
        return true
    end
    if IsPedFalling(ped) or IsPedInParachuteFreeFall(ped) then
        return true
    end
    if veh and veh ~= 0 and speedKmh >= 25.0 then
        return true
    end
    local weapon = GetSelectedPedWeapon(ped)
    return weapon and weapon ~= 0 and weapon ~= `WEAPON_UNARMED`
end

local function sendTelemetry(ped, coords, veh, speedKmh)
    local _, weapon = GetCurrentPedWeapon(ped, true)
    local camRot = GetGameplayCamRot(2)
    local alpha = type(GetEntityAlpha) == 'function' and GetEntityAlpha(ped) or 255
    local visible = type(IsEntityVisible) == 'function' and IsEntityVisible(ped) or true
    local invincible = type(GetPlayerInvincible) == 'function' and GetPlayerInvincible(PlayerId()) or false

    TriggerServerEvent('zvs-ac:detections:telemetry', {
        coords = coordsTable(coords),
        heading = (GetEntityHeading(ped) or 0.0) + 0.0,
        cameraHeading = camRot and ((camRot.z or 0.0) + 0.0) or nil,
        cameraPitch = camRot and ((camRot.x or 0.0) + 0.0) or nil,
        speed = speedKmh,
        health = GetEntityHealth(ped),
        armor = GetPedArmour(ped),
        alpha = alpha,
        visible = visible,
        invincible = invincible,
        weapon = weapon,
        aiming = IsPlayerFreeAiming(PlayerId()),
        shooting = IsPedShooting(ped),
        reloading = IsPedReloading(ped),
        inVehicle = veh ~= nil and veh ~= 0,
        heightAboveGround = safeHeight(ped),
        falling = IsPedFalling(ped),
        parachuting = IsPedInParachuteFreeFall(ped),
        swimming = IsPedSwimming(ped) or IsPedSwimmingUnderWater(ped),
        ping = 0,
    })
    lastTelemetryAt = GetGameTimer()
    lastTelemetryCoords = coordsTable(coords)
end

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        if ped and ped ~= 0 then
            local now = GetGameTimer()
            local coords = GetEntityCoords(ped)
            local veh = GetVehiclePedIsIn(ped, false)
            local speedKmh = (GetEntitySpeed(ped) or 0.0) * 3.6
            local active = isPedActive(ped, veh, speedKmh)
            local interval = active and activeInterval or idleInterval
            local movedEnough = distanceSq(coordsTable(coords), lastTelemetryCoords) >= (active and 4.0 or 64.0)

            if movedEnough or (now - lastTelemetryAt) >= interval then
                sendTelemetry(ped, coords, veh, speedKmh)
            end

            Wait(interval)
        else
            Wait(idleInterval)
        end
    end
end)

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        if ped and ped ~= 0 then
            local now = GetGameTimer()
            local aiming = IsPlayerFreeAiming(PlayerId())
            local shooting = IsPedShooting(ped)

            if aiming then
                if lastAimStart == 0 then
                    lastAimStart = now
                    lastAimHeading = GetGameplayCamRot(2).z
                end
            else
                lastAimStart = 0
                lastAimHeading = nil
            end

            if shooting and now - lastCombat >= combatInterval then
                lastCombat = now
                local _, weapon = GetCurrentPedWeapon(ped, true)
                local camRot = GetGameplayCamRot(2)
                local snapAngle = 0.0
                if lastAimHeading then
                    snapAngle = math.abs(((camRot.z - lastAimHeading + 180.0) % 360.0) - 180.0)
                end
                local coords = GetEntityCoords(ped)
                TriggerServerEvent('zvs-ac:detections:combat', {
                    weapon = weapon,
                    reactionMs = lastAimStart > 0 and (now - lastAimStart) or nil,
                    snapAngle = snapAngle,
                    lockTimeMs = lastAimStart > 0 and (now - lastAimStart) or nil,
                    headshot = false,
                    visible = true,
                    aiming = aiming,
                    shooting = shooting,
                    coords = coordsTable(coords),
                    cameraHeading = camRot and ((camRot.z or 0.0) + 0.0) or nil,
                    cameraPitch = camRot and ((camRot.x or 0.0) + 0.0) or nil,
                })
            end

            Wait((aiming or shooting) and combatInterval or combatIdleInterval)
        else
            Wait(combatIdleInterval)
        end
    end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() then return end
    TriggerServerEvent('zvs-ac:detections:resourceState', { resource = resource, state = 'stopped' })
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource == GetCurrentResourceName() then return end
    TriggerServerEvent('zvs-ac:detections:resourceState', { resource = resource, state = 'started' })
end)
