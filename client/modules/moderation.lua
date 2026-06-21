zVS = zVS or {}
local cfg = zVS.Config.AdminTools or {}
local perfCfg = zVS.Config.Performance or {}

if not cfg.Enabled then
    return
end

local isFrozen = false
local freezeThreadStarted = false
local spectateState = {
    active = false,
    target = nil,
    targetPlayerIndex = -1,
    origin = nil,
    autoInvisible = false,
    syncThread = false,
    hudThread = false,
    targetSnapshot = nil,
    detectionHistory = {},
    lastPedRetryAt = 0,
    pedRetryDelayMs = 500,
    cameraThread = false,
    cameraHandle = nil,
    cameraDistance = 8.0,
    cameraTargetDistance = 8.0,
    cameraYaw = 0.0,
    cameraPitch = -12.0,
    nativeEnabled = false,
    lastFocusAt = 0,
    viewMode = 'target_pov',
    targetCameraFreshUntil = 0,
    lastCameraProbeSentAt = 0,
    restoreThread = false,
    restoreUntil = 0,
    restoreOrigin = nil,
    returnHudThread = false,
    returnMessage = nil,
    returnHardUntil = 0,
    smoothCam = nil,
    smoothRot = nil,
    lastTargetSwitchAt = 0,
}
local resourceStopping = false
local cloakActive = false
local noclipState = {
    enabled = false,
    speedIndex = 3,
    speeds = { 3.0, 6.0, 9.5, 14.0, 20.0, 35.0, 60.0, 100.0, 200.0 },
    lastSafeCoords = nil,
    lastGroundProbeAt = 0,
    restoreGuardRunning = false,
}

local noclipThreadStarted = false
local weaponLockActive = false
local weaponLockThreadRunning = false
local adminNoticeOpen = false
local weaponLockDisableControls = {
    12, -- weapon wheel up/down (mouse)
    13, -- weapon wheel up/down (mouse)
    14, -- weapon wheel left/right (mouse)
    24, -- attack
    25, -- aim
    37, -- weapon wheel
    44, -- cover
    45, -- reload
    68, -- attack
    69, -- attack
    70, -- attack
    92, -- vehicle aim
    106, -- vehicle mouse look
    114, -- vehicle attack
    140, -- melee attack light
    141, -- melee attack heavy
    142, -- melee attack alternate
    143, -- melee block
    157, -- weapon select 1
    158, -- weapon select 2
    159, -- weapon select 3
    160, -- weapon select 4
    161, -- weapon select 5
    162, -- weapon select 6
    163, -- weapon select 7
    164, -- weapon select 8
}

local moderationCfg = cfg.Moderation or {}
local staffNoClipCfg = cfg.StaffNoClip or {}
local STAFF_NOCLIP_ENABLED = staffNoClipCfg.Enabled == true and staffNoClipCfg.DoNotModifyPed ~= true
local spectateMode = tostring(moderationCfg.SpectateMode or 'remote_camera'):lower()
local SPECTATE_USE_NATIVE = (moderationCfg.SpectateCameraOnly == false) and (moderationCfg.UseNativeSpectator == true or spectateMode == 'native')
local SPECTATE_NATIVE_FALLBACK = moderationCfg.NativeSpectatorFallback == true
local SPECTATE_SHOW_HUD = moderationCfg.SpectateShowHud ~= false
local SPECTATE_FOCUS_INTERVAL_MS = math.max(500, tonumber(moderationCfg.SpectateFocusIntervalMs) or 650)
local SPECTATE_TARGET_CAMERA_STALE_MS = math.max(900, tonumber(moderationCfg.SpectateTargetCameraStaleMs) or 2200)
local SPECTATE_SMART_ESP = moderationCfg.SpectateSmartEsp ~= false
local SPECTATE_MINIMAL_HUD = moderationCfg.SpectateMinimalHud ~= false
local SPECTATE_WORLD_ESP = moderationCfg.SpectateDrawWorldEsp == true
local SPECTATE_BOTTOM_HELP = moderationCfg.SpectateBottomHelp ~= false
local SPECTATE_SAFE_RETURN_MS = tonumber(moderationCfg.SpectateSafeReturnMs) or 0
local SPECTATE_RETURN_FREEZE_MAX_MS = tonumber(moderationCfg.SpectateReturnFreezeMaxMs) or 0
local SPECTATE_RETURN_UNDERMAP_DELTA = tonumber(moderationCfg.SpectateReturnUnderMapDelta) or 5.5
local SPECTATE_RETURN_MAX_DISTANCE = tonumber(moderationCfg.SpectateReturnMaxDistance) or 7.5
local SPECTATE_CAMERA_LERP = tonumber(moderationCfg.SpectateCameraLerp) or 0.22
if SPECTATE_CAMERA_LERP < 0.05 then SPECTATE_CAMERA_LERP = 0.05 end
if SPECTATE_CAMERA_LERP > 1.0 then SPECTATE_CAMERA_LERP = 1.0 end
local SPECTATE_DEFAULT_VIEW_MODE = tostring(moderationCfg.SpectateViewMode or 'target_pov'):lower()
if SPECTATE_DEFAULT_VIEW_MODE ~= 'target_pov' and SPECTATE_DEFAULT_VIEW_MODE ~= 'orbit' and SPECTATE_DEFAULT_VIEW_MODE ~= 'hybrid' then
    SPECTATE_DEFAULT_VIEW_MODE = 'target_pov'
end
-- V20: strict camera-only spectate. By default spectate must never touch the admin ped
-- collision, gravity, visibility, freeze, invincibility, coords or vehicle seat.
local SPECTATE_CAMERA_ONLY = moderationCfg.SpectateCameraOnly ~= false

local CLEAR_AREA_DEFAULT_RADIUS = 500.0
local SPECTATE_SYNC_INTERVAL_MS = math.max(650, tonumber(moderationCfg.SpectateSyncIntervalMs) or 750)
local SPECTATE_DRAW_DISTANCE = tonumber(moderationCfg.SpectateMaxDistance) or 2500.0
local SPECTATE_THEME_COLOR = { 116, 247, 255, 235 }
local SPECTATE_ESP_COLOR = { 116, 247, 255, 230 }
local SPECTATE_CAM_COLOR = { 255, 79, 216, 225 }
local SPECTATE_CAMERA_DISTANCE_MIN = 2.0
local SPECTATE_CAMERA_DISTANCE_MAX = 45.0
local SPECTATE_CAMERA_DISTANCE_STEP = 2.5
local SPECTATE_CAMERA_HEIGHT = 1.2
local SPECTATE_CAMERA_FOV = 54.0
local SPECTATE_FRUSTUM_RANGE = 2.4
local SPECTATE_FRUSTUM_ASPECT = 16.0 / 9.0
local SPECTATE_CAMERA_DEFAULT_DISTANCE = 8.0
local SPECTATE_CAMERA_TICK_MS = math.max(0, math.floor(tonumber(perfCfg.SpectateCameraTickMs) or 16))
local SPECTATE_HUD_TICK_MS = math.max(0, math.floor(tonumber(perfCfg.SpectateHudTickMs) or 0))

local function isSelfSpectateTarget(target)
    local numeric = tonumber(target)
    return numeric and numeric == GetPlayerServerId(PlayerId())
end

local function notifyChat(prefix, message)
    if not message or message == '' then return end
    TriggerEvent('chat:addMessage', {
        color = { 88, 129, 255 },
        multiline = true,
        args = { prefix or '^5Visionary AC', message }
    })
end

local function ensureEntityControl(entity, attempts)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return false
    end
    if NetworkHasControlOfEntity(entity) then
        return true
    end
    local maxAttempts = attempts or 6
    local waited = 0
    NetworkRequestControlOfEntity(entity)
    while waited < maxAttempts and not NetworkHasControlOfEntity(entity) do
        Wait(0)
        NetworkRequestControlOfEntity(entity)
        waited = waited + 1
    end
    return NetworkHasControlOfEntity(entity)
end

local function deleteEntitySafely(entity, deleteFn)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return false
    end
    ensureEntityControl(entity)
    SetEntityAsMissionEntity(entity, true, true)
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

local function vectorDistanceSquared(a, b)
    if not a or not b then
        return math.huge
    end
    local ax, ay, az = a.x or 0.0, a.y or 0.0, a.z or 0.0
    local bx, by, bz = b.x or 0.0, b.y or 0.0, b.z or 0.0
    local dx = ax - bx
    local dy = ay - by
    local dz = az - bz
    return dx * dx + dy * dy + dz * dz
end

local function vecAdd(a, b)
    return vector3((a.x or 0.0) + (b.x or 0.0), (a.y or 0.0) + (b.y or 0.0), (a.z or 0.0) + (b.z or 0.0))
end

local function vecSub(a, b)
    return vector3((a.x or 0.0) - (b.x or 0.0), (a.y or 0.0) - (b.y or 0.0), (a.z or 0.0) - (b.z or 0.0))
end

local function vecScale(v, scalar)
    return vector3((v.x or 0.0) * scalar, (v.y or 0.0) * scalar, (v.z or 0.0) * scalar)
end

local function vecLength(v)
    local x, y, z = v.x or 0.0, v.y or 0.0, v.z or 0.0
    return math.sqrt((x * x) + (y * y) + (z * z))
end

local function vecNormalize(v)
    local length = vecLength(v)
    if length <= 0.0001 then
        return vector3(0.0, 0.0, 1.0)
    end
    return vecScale(v, 1.0 / length)
end

local function vecCross(a, b)
    return vector3(
        ((a.y or 0.0) * (b.z or 0.0)) - ((a.z or 0.0) * (b.y or 0.0)),
        ((a.z or 0.0) * (b.x or 0.0)) - ((a.x or 0.0) * (b.z or 0.0)),
        ((a.x or 0.0) * (b.y or 0.0)) - ((a.y or 0.0) * (b.x or 0.0))
    )
end

local function buildCleanupPlayerPedMap()
    local map = {}
    for _, player in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(player)
        if ped and ped ~= 0 then
            map[ped] = true
        end
    end
    return map
end

local function isVehicleUsedByPlayers(vehicle, playerPeds)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return false
    end
    if not playerPeds then
        return false
    end
    for ped in pairs(playerPeds) do
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            if GetVehiclePedIsIn(ped, false) == vehicle then
                return true
            end
        end
    end
    return false
end

local function getNoClipSpeed()
    return noclipState.speeds[noclipState.speedIndex] or noclipState.speeds[#noclipState.speeds]
end

local function adjustNoClipSpeed(delta)
    local nextIndex = math.floor((noclipState.speedIndex or 1) + delta)
    if nextIndex < 1 then
        nextIndex = 1
    elseif nextIndex > #noclipState.speeds then
        nextIndex = #noclipState.speeds
    end
    noclipState.speedIndex = nextIndex
end

local function ensureWeaponLockThread()
    if weaponLockThreadRunning then
        return
    end

    weaponLockThreadRunning = true

    Citizen.CreateThread(function()
        while weaponLockActive do
            local ped = PlayerPedId()
            if ped and ped ~= 0 then
                SetPedCanSwitchWeapon(ped, false)
                DisablePlayerFiring(PlayerId(), true)
                for _, control in ipairs(weaponLockDisableControls) do
                    DisableControlAction(0, control, true)
                end
                HudWeaponWheelIgnoreControlInput(true)
                HudWeaponWheelIgnoreSelection(true)
                BlockWeaponWheelThisFrame()

                local currentWeapon = GetSelectedPedWeapon(ped)
                if currentWeapon ~= `WEAPON_UNARMED` then
                    SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
                end

                if IsPedArmed(ped, 7) then
                    RemoveAllPedWeapons(ped, false)
                end
            end

            Wait(0)
        end

        weaponLockThreadRunning = false

        local ped = PlayerPedId()
        if ped and ped ~= 0 then
            SetPedCanSwitchWeapon(ped, true)
        end

        HudWeaponWheelIgnoreControlInput(false)
        HudWeaponWheelIgnoreSelection(false)
    end)
end


local function vec3From(value)
    if not value then return nil end
    return vector3(value.x + 0.0, value.y + 0.0, value.z + 0.0)
end

local function requestLocalCollision(coords)
    coords = vec3From(coords)
    if not coords then return end
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    if type(RequestAdditionalCollisionAtCoord) == 'function' then
        RequestAdditionalCollisionAtCoord(coords.x, coords.y, coords.z)
    end
end

local function hardRestoreEntityPhysics(entity, opts)
    opts = opts or {}
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end

    SetEntityVelocity(entity, 0.0, 0.0, 0.0)
    SetEntityCollision(entity, true, true)
    if type(SetEntityCompletelyDisableCollision) == 'function' then
        SetEntityCompletelyDisableCollision(entity, false, false)
    end
    if type(SetEntityRecordsCollisions) == 'function' then
        SetEntityRecordsCollisions(entity, true)
    end
    if type(SetEntityLoadCollisionFlag) == 'function' then
        SetEntityLoadCollisionFlag(entity, true)
    end
    if type(SetEntityDynamic) == 'function' then
        SetEntityDynamic(entity, true)
    end
    if type(SetEntityHasGravity) == 'function' then
        SetEntityHasGravity(entity, true)
    end
    if type(ActivatePhysics) == 'function' then
        ActivatePhysics(entity)
    end
    FreezeEntityPosition(entity, false)

    if opts.visual ~= false then
        SetEntityVisible(entity, true, false)
        SetEntityAlpha(entity, 255, false)
        ResetEntityAlpha(entity)
    end
    if opts.invincible ~= false then
        SetEntityInvincible(entity, false)
    end
end

local function getNoClipCarrier(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return 0, 0 end
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        return vehicle, vehicle
    end
    return ped, 0
end

local function setEntityNoClipMode(entity, enabled)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end
    if enabled then
        FreezeEntityPosition(entity, true)
        SetEntityVelocity(entity, 0.0, 0.0, 0.0)
        SetEntityCollision(entity, false, false)
        -- Do not use SetEntityCompletelyDisableCollision(true) while flying.
        -- On some streamed maps this native can stick for a few frames after restore
        -- and is the main reason admins fall through the world after NoClip.
        if type(SetEntityRecordsCollisions) == 'function' then
            SetEntityRecordsCollisions(entity, false)
        end
        if type(SetEntityHasGravity) == 'function' then
            SetEntityHasGravity(entity, false)
        end
    else
        SetEntityVelocity(entity, 0.0, 0.0, 0.0)
        if type(SetEntityCompletelyDisableCollision) == 'function' then
            SetEntityCompletelyDisableCollision(entity, false, false)
            SetEntityCompletelyDisableCollision(entity, false, true)
        end
        SetEntityCollision(entity, true, true)
        SetEntityCollision(entity, true, false)
        if type(SetEntityRecordsCollisions) == 'function' then
            SetEntityRecordsCollisions(entity, true)
        end
        if type(SetEntityLoadCollisionFlag) == 'function' then
            SetEntityLoadCollisionFlag(entity, true)
        end
        if type(SetEntityDynamic) == 'function' then
            SetEntityDynamic(entity, true)
        end
        if type(SetEntityHasGravity) == 'function' then
            SetEntityHasGravity(entity, true)
        end
        if type(ActivatePhysics) == 'function' then
            ActivatePhysics(entity)
        end
    end
end

local function restoreNoClipVisuals(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end
    SetEntityVisible(ped, true, false)
    SetEntityAlpha(ped, 255, false)
    ResetEntityAlpha(ped)
    SetEntityInvincible(ped, false)
    SetPlayerInvincible(PlayerId(), false)
    SetEveryoneIgnorePlayer(PlayerId(), false)
    SetPoliceIgnorePlayer(PlayerId(), false)
    if type(SetPedCanRagdoll) == 'function' then
        SetPedCanRagdoll(ped, true)
    end
end

local function focusStreamingAt(coords)
    coords = vec3From(coords)
    if not coords then return end
    requestLocalCollision(coords)
    if type(SetFocusPosAndVel) == 'function' then
        SetFocusPosAndVel(coords.x, coords.y, coords.z, 0.0, 0.0, 0.0)
    end
end

local function clearStreamingFocusSoon(delayMs)
    CreateThread(function()
        Wait(delayMs or 1200)
        if type(ClearFocus) == 'function' then ClearFocus() end
    end)
end

local function tryGroundZAt(coords)
    coords = vec3From(coords)
    if not coords then return nil end
    focusStreamingAt(coords)

    local heights = { 1200.0, 900.0, 650.0, 450.0, 300.0, 180.0, 90.0, 45.0, 20.0, 8.0, 2.0 }
    for _, offset in ipairs(heights) do
        local ok, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + offset, true)
        if ok and groundZ and groundZ > -250.0 and groundZ < 3000.0 then
            return vector3(coords.x, coords.y, groundZ + 1.12)
        end
    end

    for _, offset in ipairs(heights) do
        local ok, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + offset, false)
        if ok and groundZ and groundZ > -250.0 and groundZ < 3000.0 then
            return vector3(coords.x, coords.y, groundZ + 1.12)
        end
    end

    return nil
end

local function tryGroundRaycast(coords, ignoreEntity)
    coords = vec3From(coords)
    if not coords or type(StartShapeTestRay) ~= 'function' or type(GetShapeTestResult) ~= 'function' then return nil end
    focusStreamingAt(coords)
    local fromZ = math.max((coords.z or 0.0) + 80.0, 80.0)
    local toZ = (coords.z or 0.0) - 1400.0
    local ray = StartShapeTestRay(coords.x, coords.y, fromZ, coords.x, coords.y, toZ, 1 + 16, ignoreEntity or 0, 7)
    local _, hit, endCoords = GetShapeTestResult(ray)
    if hit == 1 and endCoords and endCoords.z and endCoords.z > -250.0 then
        return vector3(endCoords.x, endCoords.y, endCoords.z + 1.12)
    end
    return nil
end

local function tryVehicleNode(coords)
    coords = vec3From(coords)
    if not coords or type(GetClosestVehicleNodeWithHeading) ~= 'function' then return nil end
    local ok, nodeCoords, heading = GetClosestVehicleNodeWithHeading(coords.x, coords.y, coords.z, 1, 3.0, 0)
    if ok and nodeCoords and nodeCoords.x and nodeCoords.z and nodeCoords.z > -250.0 then
        return vector3(nodeCoords.x, nodeCoords.y, nodeCoords.z + 1.12), heading or 0.0
    end
    ok, nodeCoords, heading = GetClosestVehicleNodeWithHeading(coords.x, coords.y, coords.z, 0, 3.0, 0)
    if ok and nodeCoords and nodeCoords.x and nodeCoords.z and nodeCoords.z > -250.0 then
        return vector3(nodeCoords.x, nodeCoords.y, nodeCoords.z + 1.12), heading or 0.0
    end
    return nil
end

local function trySafeCoordForPed(coords)
    coords = vec3From(coords)
    if not coords or type(GetSafeCoordForPed) ~= 'function' then return nil end
    local okCall, ok, safe = pcall(GetSafeCoordForPed, coords.x, coords.y, coords.z, true, 16)
    if okCall and ok and safe and safe.x and safe.z and safe.z > -250.0 then
        return vector3(safe.x, safe.y, safe.z + 1.12)
    end
    return nil
end

local function resolveSolidLanding(coords, ignoreEntity)
    coords = vec3From(coords)
    if not coords then return nil end
    return tryGroundZAt(coords)
        or tryGroundRaycast(coords, ignoreEntity)
        or trySafeCoordForPed(coords)
        or select(1, tryVehicleNode(coords))
end

local function updateNoClipLastSafeCoords(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end
    local now = GetGameTimer()
    if now - (noclipState.lastGroundProbeAt or 0) < 450 then return end
    noclipState.lastGroundProbeAt = now

    local coords = GetEntityCoords(entity)
    local ground = resolveSolidLanding(coords, entity)
    if ground then
        noclipState.lastSafeCoords = ground
    end
end

local function waitCollisionAt(entity, coords, timeoutMs)
    coords = vec3From(coords)
    if coords then focusStreamingAt(coords) end
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end

    local deadline = GetGameTimer() + (timeoutMs or 2200)
    while GetGameTimer() < deadline do
        if not DoesEntityExist(entity) then return false end
        local current = GetEntityCoords(entity)
        requestLocalCollision(coords or current)
        requestLocalCollision(current)
        local loaded = type(HasCollisionLoadedAroundEntity) ~= 'function' or HasCollisionLoadedAroundEntity(entity)
        local waiting = type(IsEntityWaitingForWorldCollision) == 'function' and IsEntityWaitingForWorldCollision(entity) or false
        if loaded and not waiting then
            return true
        end
        Wait(25)
    end
    return false
end

local function warpEntitySafe(entity, coords, heading)
    coords = vec3From(coords)
    if not entity or entity == 0 or not DoesEntityExist(entity) or not coords then return end
    focusStreamingAt(coords)
    SetEntityVelocity(entity, 0.0, 0.0, 0.0)
    SetEntityCoordsNoOffset(entity, coords.x, coords.y, coords.z, false, false, true)
    if heading then SetEntityHeading(entity, heading + 0.0) end
end

local function chooseNoClipLandingCoords(entity, fallbackCoords)
    local current = entity and entity ~= 0 and DoesEntityExist(entity) and GetEntityCoords(entity) or nil
    local landing = current and resolveSolidLanding(current, entity) or nil
    if landing then return landing, nil end

    local fallback = vec3From(fallbackCoords or noclipState.lastSafeCoords)
    if fallback then
        landing = resolveSolidLanding(fallback, entity)
        if landing then return landing, nil end
        return vector3(fallback.x, fallback.y, fallback.z + 0.15), nil
    end

    if current then
        local node, heading = tryVehicleNode(current)
        if node then return node, heading end
        return vector3(current.x, current.y, current.z + 2.0), nil
    end
    return nil, nil
end

local function forceSolidState(entity, frozen)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end
    FreezeEntityPosition(entity, frozen == true)
    SetEntityVelocity(entity, 0.0, 0.0, 0.0)
    if type(SetEntityCompletelyDisableCollision) == 'function' then
        SetEntityCompletelyDisableCollision(entity, false, false)
        SetEntityCompletelyDisableCollision(entity, false, true)
    end
    SetEntityCollision(entity, true, true)
    SetEntityCollision(entity, true, false)
    if type(SetEntityRecordsCollisions) == 'function' then SetEntityRecordsCollisions(entity, true) end
    if type(SetEntityLoadCollisionFlag) == 'function' then SetEntityLoadCollisionFlag(entity, true) end
    if type(SetEntityDynamic) == 'function' then SetEntityDynamic(entity, true) end
    if type(SetEntityHasGravity) == 'function' then SetEntityHasGravity(entity, true) end
    if type(ActivatePhysics) == 'function' then ActivatePhysics(entity) end
end

local function startNoClipPostDisableGuard(entity, ped, fallbackCoords)
    if noclipState.restoreGuardRunning then return end
    noclipState.restoreGuardRunning = true

    CreateThread(function()
        local guardUntil = GetGameTimer() + 3600
        local fallback = vec3From(fallbackCoords or noclipState.lastSafeCoords)
        local hardTicks = 0

        while GetGameTimer() < guardUntil do
            local livePed = PlayerPedId()
            local liveEntity = entity
            if not liveEntity or liveEntity == 0 or not DoesEntityExist(liveEntity) then
                liveEntity = select(1, getNoClipCarrier(livePed))
            end

            if livePed and livePed ~= 0 and DoesEntityExist(livePed) then
                restoreNoClipVisuals(livePed)
                forceSolidState(livePed, false)
            end
            if liveEntity and liveEntity ~= 0 and DoesEntityExist(liveEntity) and liveEntity ~= livePed then
                forceSolidState(liveEntity, false)
            end

            if liveEntity and liveEntity ~= 0 and DoesEntityExist(liveEntity) then
                local coords = GetEntityCoords(liveEntity)
                local ground = resolveSolidLanding(coords, liveEntity)
                if ground then fallback = ground end

                local waiting = type(IsEntityWaitingForWorldCollision) == 'function' and IsEntityWaitingForWorldCollision(liveEntity) or false
                local shouldRescue = false
                if fallback and coords.z < fallback.z - 1.25 then shouldRescue = true end
                if waiting and hardTicks < 10 then shouldRescue = true end

                if shouldRescue and fallback then
                    hardTicks = hardTicks + 1
                    forceSolidState(liveEntity, true)
                    warpEntitySafe(liveEntity, fallback)
                    waitCollisionAt(liveEntity, fallback, 650)
                    if type(PlaceEntityOnGroundProperly) == 'function' then PlaceEntityOnGroundProperly(liveEntity) end
                    forceSolidState(liveEntity, false)
                end
            end

            Wait(80)
        end

        local livePed = PlayerPedId()
        local liveEntity = select(1, getNoClipCarrier(livePed))
        if livePed and livePed ~= 0 and DoesEntityExist(livePed) then
            restoreNoClipVisuals(livePed)
            forceSolidState(livePed, false)
            FreezeEntityPosition(livePed, false)
        end
        if liveEntity and liveEntity ~= 0 and DoesEntityExist(liveEntity) and liveEntity ~= livePed then
            forceSolidState(liveEntity, false)
            FreezeEntityPosition(liveEntity, false)
        end
        clearStreamingFocusSoon(250)
        noclipState.restoreGuardRunning = false
    end)
end

local function RestorePedAfterNoClip(ped, lastSafeCoords)
    ped = ped or PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end

    local entity, vehicle = getNoClipCarrier(ped)
    if not entity or entity == 0 or not DoesEntityExist(entity) then entity = ped end

    local current = GetEntityCoords(entity)
    local landing, heading = chooseNoClipLandingCoords(entity, lastSafeCoords or noclipState.lastSafeCoords)
    landing = landing or vector3(current.x, current.y, current.z + 2.0)

    -- Hard phase: freeze, restore collision flags, stream landing zone, then warp.
    forceSolidState(entity, true)
    forceSolidState(ped, true)
    restoreNoClipVisuals(ped)
    focusStreamingAt(landing)
    waitCollisionAt(entity, landing, 1800)
    warpEntitySafe(entity, landing, heading)
    if vehicle ~= 0 and DoesEntityExist(vehicle) then
        SetVehicleOnGroundProperly(vehicle)
    elseif type(PlaceEntityOnGroundProperly) == 'function' then
        PlaceEntityOnGroundProperly(entity)
    end

    waitCollisionAt(entity, landing, 1200)
    forceSolidState(entity, true)
    forceSolidState(ped, true)
    warpEntitySafe(entity, landing, heading)
    Wait(120)

    -- Release phase only after flags and streamed collision are restored.
    forceSolidState(entity, false)
    forceSolidState(ped, false)
    if vehicle ~= 0 and DoesEntityExist(vehicle) then
        SetVehicleOnGroundProperly(vehicle)
        FreezeEntityPosition(vehicle, false)
    end
    FreezeEntityPosition(ped, false)
    restoreNoClipVisuals(ped)

    noclipState.lastSafeCoords = landing
    startNoClipPostDisableGuard(entity, ped, landing)
end

local function restoreNoClipSolidPed(reason)
    local ped = PlayerPedId()
    RestorePedAfterNoClip(ped, noclipState.lastSafeCoords)
end

local function drawNoClipHud()
    -- No DrawText in production. Send compact status to NUI at low frequency from the active NoClip loop.
end

local lastNoClipNuiAt = 0
local function sendNoClipNui(enabled)
    local now = GetGameTimer()
    if enabled and now - lastNoClipNuiAt < 500 then return end
    lastNoClipNuiAt = now
    SendNUIMessage({
        action = 'noclipStatus',
        data = {
            enabled = enabled == true,
            speed = getNoClipSpeed(),
            speedIndex = noclipState.speedIndex,
        }
    })
end

local function updateNoClipMovement()
    if not STAFF_NOCLIP_ENABLED or not noclipState.enabled then return end

    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end

    local moveEntity, vehicle = getNoClipCarrier(ped)
    if not moveEntity or moveEntity == 0 or not DoesEntityExist(moveEntity) then return end

    setEntityNoClipMode(moveEntity, true)
    if vehicle ~= 0 then setEntityNoClipMode(ped, true) end
    updateNoClipLastSafeCoords(moveEntity)

    if staffNoClipCfg.HideAdmin ~= false then
        SetEntityVisible(ped, false, false)
        SetEntityAlpha(ped, 90, false)
    end
    if staffNoClipCfg.InvincibleWhileActive ~= false then
        SetEntityInvincible(ped, true)
        SetPlayerInvincible(PlayerId(), true)
    end
    SetEveryoneIgnorePlayer(PlayerId(), true)
    SetPoliceIgnorePlayer(PlayerId(), true)
    if type(SetPedCanRagdoll) == 'function' then SetPedCanRagdoll(ped, false) end

    local rot = GetGameplayCamRot(2)
    local heading = math.rad(rot.z)
    local pitch = math.rad(rot.x)
    local cosPitch = math.cos(pitch)

    local forward = { x = -math.sin(heading) * cosPitch, y = math.cos(heading) * cosPitch, z = math.sin(pitch) }
    local right = { x = math.cos(heading), y = math.sin(heading), z = 0.0 }
    local move = { x = 0.0, y = 0.0, z = 0.0 }

    local function add(vec)
        move.x = move.x + vec.x
        move.y = move.y + vec.y
        move.z = move.z + vec.z
    end

    for _, control in ipairs({ 30, 31, 32, 33, 34, 35, 21, 22, 36, 23, 24, 25, 37, 44, 45, 140, 141, 142, 143 }) do
        DisableControlAction(0, control, true)
    end

    if IsDisabledControlPressed(0, 32) then add(forward) end
    if IsDisabledControlPressed(0, 33) then add({ x = -forward.x, y = -forward.y, z = -forward.z }) end
    if IsDisabledControlPressed(0, 35) then add(right) end
    if IsDisabledControlPressed(0, 34) then add({ x = -right.x, y = -right.y, z = 0.0 }) end
    if IsDisabledControlPressed(0, 22) then add({ x = 0.0, y = 0.0, z = 1.0 }) end
    if IsDisabledControlPressed(0, 36) then add({ x = 0.0, y = 0.0, z = -1.0 }) end

    if IsDisabledControlJustPressed(0, 15) or IsDisabledControlJustPressed(0, 172) then
        adjustNoClipSpeed(1)
    elseif IsDisabledControlJustPressed(0, 14) or IsDisabledControlJustPressed(0, 173) then
        adjustNoClipSpeed(-1)
    end

    local magnitude = math.sqrt(move.x * move.x + move.y * move.y + move.z * move.z)
    if magnitude > 0.0001 then
        move.x = move.x / magnitude
        move.y = move.y / magnitude
        move.z = move.z / magnitude
    end

    local speed = getNoClipSpeed() * (IsDisabledControlPressed(0, 21) and 3.0 or 1.0)
    local displacement = speed * GetFrameTime()
    local coords = GetEntityCoords(moveEntity)

    if displacement > 0.0 and magnitude > 0.0001 then
        coords = vector3(coords.x + move.x * displacement, coords.y + move.y * displacement, coords.z + move.z * displacement)
    end

    SetEntityVelocity(moveEntity, 0.0, 0.0, 0.0)
    if vehicle ~= 0 then SetEntityVelocity(ped, 0.0, 0.0, 0.0) end
    SetEntityCoordsNoOffset(moveEntity, coords.x, coords.y, coords.z, false, false, false)
    SetEntityHeading(moveEntity, rot.z)
    if vehicle ~= 0 then SetEntityHeading(ped, rot.z) end
    drawNoClipHud()
end

local function ensureNoClipThread()
    if not STAFF_NOCLIP_ENABLED then
        noclipState.enabled = false
        cloakActive = false
        sendNoClipNui(false)
        return
    end
    if noclipThreadStarted then return end
    noclipThreadStarted = true
    CreateThread(function()
        while noclipState.enabled do
            updateNoClipMovement()
            sendNoClipNui(true)
            Wait(0)
        end
        noclipThreadStarted = false
        sendNoClipNui(false)
        restoreNoClipSolidPed('noclip-disabled')
    end)
end

local function applyStealthState()
    if not STAFF_NOCLIP_ENABLED then
        cloakActive = false
        noclipState.enabled = false
        sendNoClipNui(false)
        restoreNoClipSolidPed('noclip-disabled-config')
        return
    end

    local ped = PlayerPedId()
    if cloakActive == true then
        noclipState.enabled = true
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            local entity = select(1, getNoClipCarrier(ped))
            updateNoClipLastSafeCoords(entity)
        end
        ensureNoClipThread()
    else
        local wasThreadRunning = noclipThreadStarted == true
        noclipState.enabled = false
        cloakActive = false
        if not wasThreadRunning then
            restoreNoClipSolidPed('noclip-toggle-off')
        end
        sendNoClipNui(false)
    end
end

local function restoreEntitySolid(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end
    SetEntityVisible(entity, true, false)
    SetEntityAlpha(entity, 255, false)
    ResetEntityAlpha(entity)
    SetEntityCollision(entity, true, true)
    if type(SetEntityCompletelyDisableCollision) == 'function' then
        SetEntityCompletelyDisableCollision(entity, false, false)
    end
    if type(SetEntityLoadCollisionFlag) == 'function' then
        SetEntityLoadCollisionFlag(entity, true)
    end
    if type(SetEntityRecordsCollisions) == 'function' then
        SetEntityRecordsCollisions(entity, true)
    end
    if type(SetEntityDynamic) == 'function' then
        SetEntityDynamic(entity, true)
    end
    if type(ActivatePhysics) == 'function' then
        ActivatePhysics(entity)
    end
    FreezeEntityPosition(entity, false)
    SetEntityInvincible(entity, false)
    if type(SetEntityCanBeDamaged) == 'function' then
        SetEntityCanBeDamaged(entity, true)
    end
    if type(NetworkSetEntityInvisibleToNetwork) == 'function' then
        NetworkSetEntityInvisibleToNetwork(entity, false)
    end
end

local function restoreLocalPlayerFlags()
    SetPlayerControl(PlayerId(), true, 0)
    SetPlayerInvincible(PlayerId(), false)
    SetEveryoneIgnorePlayer(PlayerId(), false)
    SetPoliceIgnorePlayer(PlayerId(), false)
    if type(SetLocalPlayerVisibleLocally) == 'function' then
        SetLocalPlayerVisibleLocally(true)
    end
    local ped = PlayerPedId()
    if ped and ped ~= 0 and DoesEntityExist(ped) then
        SetPedCanRagdoll(ped, true)
        if type(SetPedCanRagdollFromPlayerImpact) == 'function' then
            SetPedCanRagdollFromPlayerImpact(ped, true)
        end
        if type(SetPedCanBeKnockedOffVehicle) == 'function' then
            SetPedCanBeKnockedOffVehicle(ped, 1)
        end
    end
end

local ensureSpectateReturnHudThread

local function getCoordsFromOrigin(origin)
    if type(origin) ~= 'table' or not origin.coords then return nil end
    local coords = origin.coords
    if coords.x and coords.y and coords.z then
        return coords
    end
    return nil
end

local function requestCollisionAroundPed(ped, coords)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end
    coords = coords or GetEntityCoords(ped)
    if not coords then return end
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    if type(RequestAdditionalCollisionAtCoord) == 'function' then
        RequestAdditionalCollisionAtCoord(coords.x, coords.y, coords.z)
    end
    -- Do not call SetFocusEntity() from the generic repair path.
    -- Spectate return has its own local focus loader; generic/manual repair stays harmless.
end

local function distanceSquaredBetweenCoords(a, b)
    if not a or not b then return math.huge end
    local dx = (a.x or 0.0) - (b.x or 0.0)
    local dy = (a.y or 0.0) - (b.y or 0.0)
    local dz = (a.z or 0.0) - (b.z or 0.0)
    return dx * dx + dy * dy + dz * dz
end

local function resolveSafeReturnCoords(coords)
    if not coords then return nil end
    local x, y, z = coords.x + 0.0, coords.y + 0.0, coords.z + 0.0
    local probes = { 110.0, 80.0, 55.0, 32.0, 18.0, 8.0 }
    for _, offset in ipairs(probes) do
        RequestCollisionAtCoord(x, y, z + offset)
        local ok, groundZ = GetGroundZFor_3dCoord(x, y, z + offset, false)
        if ok and groundZ and groundZ > -150.0 then
            return vector3(x, y, groundZ + 0.92)
        end
        Wait(0)
    end
    return vector3(x, y, z + 0.92)
end

local function startLocalSceneLoad(coords)
    if not coords then return end
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    if type(SetFocusPosAndVel) == 'function' then
        SetFocusPosAndVel(coords.x, coords.y, coords.z, 0.0, 0.0, 0.0)
    end
    if type(SetHdArea) == 'function' then
        SetHdArea(coords.x, coords.y, coords.z, 45.0)
    end
    if type(NewLoadSceneStartSphere) == 'function' then
        NewLoadSceneStartSphere(coords.x, coords.y, coords.z, 48.0, 0)
    elseif type(LoadScene) == 'function' then
        LoadScene(coords.x, coords.y, coords.z)
    end
end

local function stopLocalSceneLoad()
    if type(NewLoadSceneStop) == 'function' then
        NewLoadSceneStop()
    end
    if type(ClearHdArea) == 'function' then
        ClearHdArea()
    end
    if type(ClearFocus) == 'function' then
        ClearFocus()
    end
end

local function gentleLocalCollisionRepair(reason)
    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end

    stopLocalSceneLoad()

    restoreEntitySolid(ped)
    restoreLocalPlayerFlags()
    SetEntityVelocity(ped, 0.0, 0.0, 0.0)

    local coords = GetEntityCoords(ped)
    if coords then
        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    end

    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        restoreEntitySolid(vehicle)
        SetVehicleEngineOn(vehicle, true, true, false)
        local vCoords = GetEntityCoords(vehicle)
        if vCoords then
            RequestCollisionAtCoord(vCoords.x, vCoords.y, vCoords.z)
        end
    end
end

local function startSpectatePhysicsRepair(reason, origin)
    -- Release Production V1: camera-only spectate. No collision/freeze/teleport repair.
    do return end
    if resourceStopping or reason == 'resource-stop' then
        gentleLocalCollisionRepair(reason)
        return
    end

    if cloakActive then
        applyStealthState()
        return
    end

    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end

    local originCoords = getCoordsFromOrigin(origin) or getCoordsFromOrigin(spectateState.restoreOrigin) or GetEntityCoords(ped)
    if not originCoords then
        gentleLocalCollisionRepair(reason)
        return
    end

    spectateState.restoreOrigin = origin or spectateState.restoreOrigin or { coords = originCoords, heading = GetEntityHeading(ped) }
    spectateState.restoreUntil = GetGameTimer() + SPECTATE_SAFE_RETURN_MS
    spectateState.returnHardUntil = GetGameTimer() + SPECTATE_SAFE_RETURN_MS + 1200
    spectateState.returnMessage = '~b~Retour spectate sécurisé~s~ : rechargement collision locale...'
    if ensureSpectateReturnHudThread then ensureSpectateReturnHudThread() end

    if spectateState.restoreThread then
        return
    end

    spectateState.restoreThread = true
    CreateThread(function()
        local startedAt = GetGameTimer()
        local freezeUntil = startedAt + SPECTATE_RETURN_FREEZE_MAX_MS
        local didFallbackPlace = false
        local safeCoords = nil
        local originHeading = spectateState.restoreOrigin and spectateState.restoreOrigin.heading
        local originVehicle = spectateState.restoreOrigin and spectateState.restoreOrigin.vehicle
        local originSeat = spectateState.restoreOrigin and spectateState.restoreOrigin.seat or -1

        startLocalSceneLoad(originCoords)
        notifyChat('^5Visionary AC', 'Retour spectate sécurisé: collision en cours de rechargement, ne bouge pas une demi-seconde.')

        while GetGameTimer() < (spectateState.restoreUntil or 0) do
            if cloakActive or spectateState.active then
                break
            end

            ped = PlayerPedId()
            if ped and ped ~= 0 and DoesEntityExist(ped) then
                restoreEntitySolid(ped)
                restoreLocalPlayerFlags()
                requestCollisionAroundPed(ped, originCoords)
                SetEntityVelocity(ped, 0.0, 0.0, 0.0)

                local currentCoords = GetEntityCoords(ped)
                local tooFar = distanceSquaredBetweenCoords(currentCoords, originCoords) > (SPECTATE_RETURN_MAX_DISTANCE * SPECTATE_RETURN_MAX_DISTANCE)
                local underMap = currentCoords and ((currentCoords.z or 0.0) < ((originCoords.z or 0.0) - SPECTATE_RETURN_UNDERMAP_DELTA) or (currentCoords.z or 0.0) < -80.0)

                if (tooFar or underMap) and not didFallbackPlace then
                    safeCoords = safeCoords or resolveSafeReturnCoords(originCoords)
                    if safeCoords then
                        RequestCollisionAtCoord(safeCoords.x, safeCoords.y, safeCoords.z)
                        SetEntityCoordsNoOffset(ped, safeCoords.x, safeCoords.y, safeCoords.z, false, false, false)
                        if originHeading then SetEntityHeading(ped, originHeading) end
                        didFallbackPlace = true
                        spectateState.returnMessage = '~o~Retour spectate~s~ : position corrigée, vérification collision...'
                    end
                end

                if originVehicle and DoesEntityExist(originVehicle) then
                    restoreEntitySolid(originVehicle)
                    SetVehicleEngineOn(originVehicle, true, true, false)
                    requestCollisionAroundPed(originVehicle, GetEntityCoords(originVehicle))
                end

                local collisionLoaded = true
                if type(HasCollisionLoadedAroundEntity) == 'function' then
                    collisionLoaded = HasCollisionLoadedAroundEntity(ped)
                end

                -- Very short anchor only. Never leave the admin stuck frozen if GTA does not report collision loaded.
                if not collisionLoaded and GetGameTimer() < freezeUntil then
                    FreezeEntityPosition(ped, true)
                    spectateState.returnMessage = '~b~Retour spectate sécurisé~s~ : chargement de la zone staff...'
                else
                    FreezeEntityPosition(ped, false)
                end

                if collisionLoaded and GetGameTimer() > startedAt + 550 then
                    spectateState.returnMessage = '~g~Retour spectate OK~s~ : collision restaurée.'
                    break
                end
            end

            Wait(85)
        end

        ped = PlayerPedId()
        if ped and ped ~= 0 and DoesEntityExist(ped) and not cloakActive and not spectateState.active then
            restoreEntitySolid(ped)
            restoreLocalPlayerFlags()
            FreezeEntityPosition(ped, false)
            SetEntityVelocity(ped, 0.0, 0.0, 0.0)

            local finalCoords = GetEntityCoords(ped)
            local finalUnderMap = finalCoords and ((finalCoords.z or 0.0) < ((originCoords.z or 0.0) - SPECTATE_RETURN_UNDERMAP_DELTA) or (finalCoords.z or 0.0) < -80.0)
            if finalUnderMap then
                safeCoords = safeCoords or resolveSafeReturnCoords(originCoords)
                if safeCoords then
                    SetEntityCoordsNoOffset(ped, safeCoords.x, safeCoords.y, safeCoords.z, false, false, false)
                    if originHeading then SetEntityHeading(ped, originHeading) end
                    RequestCollisionAtCoord(safeCoords.x, safeCoords.y, safeCoords.z)
                end
            end

            if originVehicle and DoesEntityExist(originVehicle) then
                restoreEntitySolid(originVehicle)
                if not IsPedInAnyVehicle(ped, false) then
                    TaskWarpPedIntoVehicle(ped, originVehicle, originSeat or -1)
                end
            end
        end

        stopLocalSceneLoad()
        spectateState.returnMessage = '~g~Retour spectate terminé~s~ : contrôles et collision restaurés.'
        spectateState.returnHardUntil = GetGameTimer() + 900
        Wait(900)
        spectateState.restoreThread = false
        spectateState.restoreOrigin = nil
        spectateState.restoreUntil = 0
        if not spectateState.returnHudThread then
            spectateState.returnMessage = nil
        end
    end)
end

local function forceRestoreSpectatePhysics(reason, origin)
    -- Release Production V1: camera-only spectate. No physical ped restore from spectate paths.
    do return end
    if spectateState.active or cloakActive then
        applyStealthState()
        return
    end

    local ped = PlayerPedId()
    restoreEntitySolid(ped)
    restoreLocalPlayerFlags()

    local vehicle = ped and ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0
    if vehicle and vehicle ~= 0 then
        restoreEntitySolid(vehicle)
        SetVehicleEngineOn(vehicle, true, true, false)
    end

    if reason == 'resource-stop' or resourceStopping then
        gentleLocalCollisionRepair(reason)
        return
    end

    if reason ~= 'spectate-start-reset' then
        startSpectatePhysicsRepair(reason, origin)
    end
end

local function drawText2D(x, y, text, scale, color)
    -- NUI-only production HUD.
end



ensureSpectateReturnHudThread = function()
    -- Release V1: return notices are NUI/chat only; no DrawText/DrawRect loop.
end

local function lerpNumber(a, b, t)
    a = tonumber(a) or 0.0
    b = tonumber(b) or a
    return a + ((b - a) * t)
end

local function normalizeAngle(angle)
    angle = (tonumber(angle) or 0.0) % 360.0
    if angle > 180.0 then angle = angle - 360.0 end
    return angle
end

local function lerpAngle(a, b, t)
    a = tonumber(a) or 0.0
    b = tonumber(b) or a
    local delta = normalizeAngle(b - a)
    return a + (delta * t)
end

local function lerpVec3(current, desired, t)
    if not desired then return current end
    if not current then
        return vector3(desired.x + 0.0, desired.y + 0.0, desired.z + 0.0)
    end
    return vector3(
        lerpNumber(current.x, desired.x, t),
        lerpNumber(current.y, desired.y, t),
        lerpNumber(current.z, desired.z, t)
    )
end

local function lerpRot(current, desired, t)
    if not desired then return current end
    if not current then
        return { x = (desired.x or 0.0) + 0.0, y = (desired.y or 0.0) + 0.0, z = (desired.z or 0.0) + 0.0 }
    end
    return {
        x = lerpAngle(current.x, desired.x, t),
        y = lerpAngle(current.y, desired.y, t),
        z = lerpAngle(current.z, desired.z, t),
    }
end

local function isTargetCameraFresh(snapshot)
    if type(snapshot) ~= 'table' or type(snapshot.camera) ~= 'table' then return false end
    local cam = snapshot.camera
    if not cam.x or not cam.y or not cam.z then return false end
    local age = tonumber(snapshot.cameraAgeMs or cam.ageMs or 0) or 0
    if age > SPECTATE_TARGET_CAMERA_STALE_MS then return false end
    return true
end

local function drawSpectateReticle(isLive)
    -- Release Production V1: spectate HUD is NUI-only.
    do return end
    if not SPECTATE_SMART_ESP then return end
    local alpha = isLive and 185 or 82
    local r, g, b = isLive and 116 or 255, isLive and 247 or 190, isLive and 255 or 120
    DrawRect(0.5, 0.5, 0.018, 0.0018, r, g, b, alpha)
    DrawRect(0.5, 0.5, 0.0018, 0.018, r, g, b, alpha)
end

local function drawSpectateCameraBadge(snapshot, targetPos, isLive)
    -- Release Production V1: spectate info goes to NUI floating panel only.
    do return end
    if not SPECTATE_SMART_ESP then return end
    local mode = spectateState.viewMode == 'orbit' and 'ORBIT' or 'POV'
    local age = tonumber(snapshot and snapshot.cameraAgeMs) or nil
    local status = isLive and 'LIVE' or 'STALE'
    local ageText = age and ('%dms'):format(math.floor(age + 0.5)) or 'offline'
    DrawRect(0.5, 0.055, 0.235, 0.038, 2, 8, 18, 154)
    DrawRect(0.5, 0.034, 0.235, 0.0035, isLive and 116 or 255, isLive and 247 or 190, isLive and 255 or 120, 205)
    drawText2D(0.392, 0.044, ('~b~Spectate~s~ #%s  %s  %s %s'):format(tostring(spectateState.target), mode, status, ageText), 0.255, { 226, 238, 255, 230 })
    if targetPos and not SPECTATE_MINIMAL_HUD then
        drawText2D(0.392, 0.068, ('~c~X %.1f Y %.1f Z %.1f  |  G: POV/Orbit'):format(targetPos.x, targetPos.y, targetPos.z), 0.215, { 190, 210, 235, 210 })
    end
end


local function drawSpectateBottomHelp(snapshot, targetPos, isLive)
    -- NUI-only production HUD.
end

local function getSpectateAnchorCoords()
    local playerIndex = spectateState.targetPlayerIndex
    local targetPed = playerIndex and playerIndex ~= -1 and GetPlayerPed(playerIndex) or 0
    if targetPed and targetPed ~= 0 and DoesEntityExist(targetPed) then
        return GetEntityCoords(targetPed), targetPed
    end

    if type(spectateState.targetSnapshot) == 'table' and type(spectateState.targetSnapshot.coords) == 'table' then
        local snapshotCoords = spectateState.targetSnapshot.coords
        return vector3((snapshotCoords.x or 0.0) + 0.0, (snapshotCoords.y or 0.0) + 0.0, (snapshotCoords.z or 0.0) + 0.0), 0
    end

    return nil, 0
end

local function drawSpectateWorldEsp(snapshot)
    -- Release Production V1: world ESP drawing disabled by default.
    do return end
    if not SPECTATE_WORLD_ESP then return end
    if type(snapshot) ~= 'table' or type(snapshot.coords) ~= 'table' then
        return
    end

    local coords = vector3((snapshot.coords.x or 0.0) + 0.0, (snapshot.coords.y or 0.0) + 0.0, (snapshot.coords.z or 0.0) + 0.0)
    local pulse = (math.sin(GetGameTimer() / 280.0) + 1.0) * 0.5
    local targetAlpha = math.floor(150 + (pulse * 70))

    DrawMarker(2, coords.x, coords.y, coords.z + 1.25, 0.0, 0.0, 0.0, 180.0, 0.0, 0.0, 0.18, 0.18, 0.18, SPECTATE_ESP_COLOR[1], SPECTATE_ESP_COLOR[2], SPECTATE_ESP_COLOR[3], targetAlpha, false, true, 2, nil, nil, false)
    DrawMarker(1, coords.x, coords.y, coords.z - 0.92, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.72, 0.72, 0.035, SPECTATE_ESP_COLOR[1], SPECTATE_ESP_COLOR[2], SPECTATE_ESP_COLOR[3], 92, false, true, 2, nil, nil, false)

    local cam = snapshot.camera
    if type(cam) == 'table' and cam.x and cam.y and cam.z then
        local camPos = vector3(cam.x + 0.0, cam.y + 0.0, (cam.z or 0.0) + 0.0)
        local targetHeadPos = vector3(coords.x, coords.y, coords.z + 0.95)
        local forward = vecNormalize(vecSub(targetHeadPos, camPos))
        if type(cam.rot) == 'table' and cam.rot.x and cam.rot.z then
            local pitch = math.rad((cam.rot.x or 0.0) + 0.0)
            local yaw = math.rad((cam.rot.z or 0.0) + 0.0)
            forward = vecNormalize(vector3(-math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch)))
        end
        local worldUp = vector3(0.0, 0.0, 1.0)
        local right = vecNormalize(vecCross(forward, worldUp))
        if vecLength(right) <= 0.0001 then
            right = vector3(1.0, 0.0, 0.0)
        end
        local up = vecNormalize(vecCross(right, forward))
        local frustumCenter = vecAdd(camPos, vecScale(forward, SPECTATE_FRUSTUM_RANGE))
        local halfHeight = math.tan(math.rad(SPECTATE_CAMERA_FOV * 0.5)) * SPECTATE_FRUSTUM_RANGE
        local halfWidth = halfHeight * SPECTATE_FRUSTUM_ASPECT

        local topLeft = vecAdd(vecAdd(frustumCenter, vecScale(up, halfHeight)), vecScale(right, -halfWidth))
        local topRight = vecAdd(vecAdd(frustumCenter, vecScale(up, halfHeight)), vecScale(right, halfWidth))
        local bottomLeft = vecAdd(vecAdd(frustumCenter, vecScale(up, -halfHeight)), vecScale(right, -halfWidth))
        local bottomRight = vecAdd(vecAdd(frustumCenter, vecScale(up, -halfHeight)), vecScale(right, halfWidth))

        DrawMarker(28, camPos.x, camPos.y, camPos.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.09, 0.09, 0.09, SPECTATE_CAM_COLOR[1], SPECTATE_CAM_COLOR[2], SPECTATE_CAM_COLOR[3], 210, false, true, 2, nil, nil, false)
        DrawLine(coords.x, coords.y, coords.z + 1.0, camPos.x, camPos.y, camPos.z, SPECTATE_ESP_COLOR[1], SPECTATE_ESP_COLOR[2], SPECTATE_ESP_COLOR[3], 120)

        DrawLine(camPos.x, camPos.y, camPos.z, topLeft.x, topLeft.y, topLeft.z, SPECTATE_CAM_COLOR[1], SPECTATE_CAM_COLOR[2], SPECTATE_CAM_COLOR[3], 190)
        DrawLine(camPos.x, camPos.y, camPos.z, topRight.x, topRight.y, topRight.z, SPECTATE_CAM_COLOR[1], SPECTATE_CAM_COLOR[2], SPECTATE_CAM_COLOR[3], 190)
        DrawLine(camPos.x, camPos.y, camPos.z, bottomLeft.x, bottomLeft.y, bottomLeft.z, SPECTATE_CAM_COLOR[1], SPECTATE_CAM_COLOR[2], SPECTATE_CAM_COLOR[3], 190)
        DrawLine(camPos.x, camPos.y, camPos.z, bottomRight.x, bottomRight.y, bottomRight.z, SPECTATE_CAM_COLOR[1], SPECTATE_CAM_COLOR[2], SPECTATE_CAM_COLOR[3], 190)

        DrawLine(topLeft.x, topLeft.y, topLeft.z, topRight.x, topRight.y, topRight.z, SPECTATE_CAM_COLOR[1], SPECTATE_CAM_COLOR[2], SPECTATE_CAM_COLOR[3], 160)
        DrawLine(topRight.x, topRight.y, topRight.z, bottomRight.x, bottomRight.y, bottomRight.z, SPECTATE_CAM_COLOR[1], SPECTATE_CAM_COLOR[2], SPECTATE_CAM_COLOR[3], 160)
        DrawLine(bottomRight.x, bottomRight.y, bottomRight.z, bottomLeft.x, bottomLeft.y, bottomLeft.z, SPECTATE_CAM_COLOR[1], SPECTATE_CAM_COLOR[2], SPECTATE_CAM_COLOR[3], 160)
        DrawLine(bottomLeft.x, bottomLeft.y, bottomLeft.z, topLeft.x, topLeft.y, topLeft.z, SPECTATE_CAM_COLOR[1], SPECTATE_CAM_COLOR[2], SPECTATE_CAM_COLOR[3], 160)

        local aimPoint = vecAdd(camPos, vecScale(forward, 12.0))
        DrawLine(camPos.x, camPos.y, camPos.z, aimPoint.x, aimPoint.y, aimPoint.z, 255, 255, 255, 95)
    end
end

local function formatDetectionHistoryLine(entry)
    if type(entry) ~= 'table' then
        return '~o~OFF~s~'
    end
    local label = tostring(entry.label or entry.type or 'N/A')
    local elapsed = tonumber(entry.elapsedMs)
    if elapsed and elapsed >= 0 then
        local seconds = math.floor(elapsed / 1000)
        if seconds < 60 then
            return ('~r~%s~s~ (%ss)'):format(label, tostring(seconds))
        end
        local minutes = math.floor(seconds / 60)
        return ('~r~%s~s~ (%sm)'):format(label, tostring(minutes))
    end
    return ('~r~%s~s~'):format(label)
end

local clearSpectate

local lastSpectateNuiAt = 0
local function sendSpectateNui(payload, force)
    if type(SendNUIMessage) ~= 'function' then return end
    if payload and payload.hide then
        SendNUIMessage({ action = 'spectateInfo', data = { active = false, hide = true } })
        return
    end
    if not spectateState.active then return end
    local now = GetGameTimer()
    if not force and now - lastSpectateNuiAt < 650 then return end
    lastSpectateNuiAt = now
    payload = type(payload) == 'table' and payload or {}
    payload.active = true
    payload.target = payload.target or spectateState.target
    payload.mode = spectateState.viewMode == 'orbit' and 'ORBIT' or 'POV'
    payload.live = payload.live == true
    payload.status = payload.live and 'LIVE' or 'STALE'
    SendNUIMessage({ action = 'spectateInfo', data = payload })
end

local function buildSpectateNuiPayload(snapshot)
    snapshot = type(snapshot) == 'table' and snapshot or {}
    local distance = nil
    if type(snapshot.coords) == 'table' then
        local myPos = GetEntityCoords(PlayerPedId())
        local targetPos = vector3((snapshot.coords.x or 0.0) + 0.0, (snapshot.coords.y or 0.0) + 0.0, (snapshot.coords.z or 0.0) + 0.0)
        distance = #(myPos - targetPos)
    end
    return {
        target = snapshot.target or spectateState.target,
        name = snapshot.name or snapshot.targetName,
        distance = distance,
        health = snapshot.health,
        armor = snapshot.armor,
        speed = snapshot.speed,
        inVehicle = snapshot.inVehicle,
        vehicleModel = snapshot.vehicleModel,
        activity = snapshot.activity,
        mode = spectateState.viewMode == 'orbit' and 'ORBIT' or 'POV',
        live = isTargetCameraFresh(snapshot),
    }
end

local function ensureSpectateSyncThread()
    if spectateState.syncThread then return end
    spectateState.syncThread = true

    CreateThread(function()
        while spectateState.active do
            if isSelfSpectateTarget(spectateState.target) then
                clearSpectate()
                notifyChat('^1Visionary AC', '^1Auto-spectate bloqué: sortie caméra uniquement.')
                break
            end

            local now = GetGameTimer()
            local playerIndex = spectateState.target and GetPlayerFromServerId(spectateState.target) or -1
            spectateState.targetPlayerIndex = playerIndex

            local targetPed = playerIndex ~= -1 and GetPlayerPed(playerIndex) or 0
            if spectateState.nativeEnabled and targetPed and targetPed ~= 0 then
                if now >= (spectateState.lastPedRetryAt or 0) then
                    NetworkSetInSpectatorMode(true, targetPed)
                    spectateState.lastPedRetryAt = now + spectateState.pedRetryDelayMs
                end
            end

            TriggerServerEvent('zvs-ac:admin:spectate:requestSync')
            Wait(SPECTATE_SYNC_INTERVAL_MS)
        end
        spectateState.syncThread = false
    end)
end

local function ensureSpectateHudThread()
    if spectateState.hudThread then return end
    spectateState.hudThread = true

    CreateThread(function()
        while spectateState.active do
            local snapshot = spectateState.targetSnapshot
            if SPECTATE_SHOW_HUD and type(snapshot) == 'table' and type(snapshot.coords) == 'table' then
                local myPos = GetEntityCoords(PlayerPedId())
                local targetPos = vector3((snapshot.coords.x or 0.0) + 0.0, (snapshot.coords.y or 0.0) + 0.0, (snapshot.coords.z or 0.0) + 0.0)
                local distance = #(myPos - targetPos)
                local cameraLive = isTargetCameraFresh(snapshot)

                if SPECTATE_WORLD_ESP and distance <= SPECTATE_DRAW_DISTANCE then
                    drawSpectateWorldEsp(snapshot)
                end

                drawSpectateReticle(cameraLive and (spectateState.viewMode ~= 'orbit'))
                if not SPECTATE_BOTTOM_HELP then
                    drawSpectateCameraBadge(snapshot, targetPos, cameraLive)
                end
                drawSpectateBottomHelp(snapshot, targetPos, cameraLive)

                if not SPECTATE_MINIMAL_HUD then
                    local speedLine = cameraLive and '~b~Flux caméra~s~ LIVE' or '~o~Flux caméra~s~ stale/offline'
                    local line1 = ('~b~VISION SPECTATE~s~  ID %s  |  Dist %.1fm'):format(tostring(spectateState.target), distance)
                    local line2 = ('~b~Vue staff~s~ %s %.1fm  ~c~G: POV/Orbit | Molette +/-'):format(spectateState.viewMode or 'target_pov', spectateState.cameraTargetDistance or spectateState.cameraDistance)
                    DrawRect(0.805, 0.124, 0.32, 0.092, 2, 8, 18, 170)
                    DrawRect(0.805, 0.078, 0.32, 0.004, SPECTATE_THEME_COLOR[1], SPECTATE_THEME_COLOR[2], SPECTATE_THEME_COLOR[3], 195)
                    drawText2D(0.652, 0.091, line1, 0.285, { SPECTATE_THEME_COLOR[1], SPECTATE_THEME_COLOR[2], SPECTATE_THEME_COLOR[3], 235 })
                    drawText2D(0.652, 0.118, line2, 0.242, { 226, 238, 255, 218 })
                    drawText2D(0.652, 0.143, speedLine, 0.235, { 170, 235, 255, 205 })
                end
            end
            Wait(SPECTATE_SHOW_HUD and SPECTATE_HUD_TICK_MS or 500)
        end

        spectateState.hudThread = false
    end)
end

local function destroySpectateCamera()
    local cam = spectateState.cameraHandle
    spectateState.cameraHandle = nil
    spectateState.smoothCam = nil
    spectateState.smoothRot = nil
    if cam and DoesCamExist(cam) then
        SetCamActive(cam, false)
        RenderScriptCams(false, true, 260, true, true)
        DestroyCam(cam, false)
    else
        RenderScriptCams(false, true, 260, true, true)
    end
    ClearFocus()
    if type(ClearHdArea) == 'function' then
        ClearHdArea()
    end
end

local function ensureSpectateCameraThread()
    if spectateState.cameraThread then return end
    spectateState.cameraThread = true

    CreateThread(function()
        local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
        if cam and cam ~= 0 then
            spectateState.cameraHandle = cam
            SetCamActive(cam, true)
            SetCamFov(cam, SPECTATE_CAMERA_FOV)
            RenderScriptCams(true, true, 250, true, true)
        end

        while spectateState.active do
            if isSelfSpectateTarget(spectateState.target) then
                clearSpectate()
                notifyChat('^1Visionary AC', '^1Auto-spectate bloqué: sortie caméra uniquement.')
                break
            end

            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 14, true)
            DisableControlAction(0, 15, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)

            if IsControlJustPressed(0, 47) or IsDisabledControlJustPressed(0, 47) then
                spectateState.viewMode = (spectateState.viewMode == 'orbit') and 'target_pov' or 'orbit'
            end

            local targetCoords, targetPed = getSpectateAnchorCoords()
            if targetCoords and cam and DoesCamExist(cam) then
                local now = GetGameTimer()
                if now >= (spectateState.lastFocusAt or 0) then
                    SetFocusPosAndVel(targetCoords.x, targetCoords.y, targetCoords.z, 0.0, 0.0, 0.0)
                    RequestCollisionAtCoord(targetCoords.x, targetCoords.y, targetCoords.z)
                    if type(SetHdArea) == 'function' then
                        SetHdArea(targetCoords.x, targetCoords.y, targetCoords.z, 45.0)
                    end
                    spectateState.lastFocusAt = now + SPECTATE_FOCUS_INTERVAL_MS
                end

                local snapshot = spectateState.targetSnapshot
                local cameraLive = isTargetCameraFresh(snapshot)
                local useTargetPov = cameraLive and spectateState.viewMode ~= 'orbit' and type(snapshot.camera.rot) == 'table'

                if useTargetPov then
                    local targetCam = snapshot.camera
                    local rot = targetCam.rot or {}
                    local desiredCam = vector3((targetCam.x or targetCoords.x) + 0.0, (targetCam.y or targetCoords.y) + 0.0, (targetCam.z or (targetCoords.z + 1.0)) + 0.0)
                    local desiredRot = { x = (rot.x or 0.0) + 0.0, y = (rot.y or 0.0) + 0.0, z = (rot.z or 0.0) + 0.0 }
                    spectateState.smoothCam = lerpVec3(spectateState.smoothCam, desiredCam, SPECTATE_CAMERA_LERP)
                    spectateState.smoothRot = lerpRot(spectateState.smoothRot, desiredRot, SPECTATE_CAMERA_LERP)
                    SetCamCoord(cam, spectateState.smoothCam.x, spectateState.smoothCam.y, spectateState.smoothCam.z)
                    SetCamRot(cam, spectateState.smoothRot.x, spectateState.smoothRot.y, spectateState.smoothRot.z, 2)
                    SetCamFov(cam, SPECTATE_CAMERA_FOV)
                else
                    local yawInput = GetDisabledControlNormal(0, 1)
                    local pitchInput = GetDisabledControlNormal(0, 2)
                    spectateState.cameraYaw = spectateState.cameraYaw + (yawInput * 7.8)
                    spectateState.cameraPitch = spectateState.cameraPitch - (pitchInput * 7.2)
                    if spectateState.cameraPitch > 18.0 then spectateState.cameraPitch = 18.0 end
                    if spectateState.cameraPitch < -72.0 then spectateState.cameraPitch = -72.0 end

                    if IsDisabledControlJustPressed(0, 15) or IsControlJustPressed(0, 15) then
                        spectateState.cameraTargetDistance = math.max(SPECTATE_CAMERA_DISTANCE_MIN, (spectateState.cameraTargetDistance or spectateState.cameraDistance) - SPECTATE_CAMERA_DISTANCE_STEP)
                    elseif IsDisabledControlJustPressed(0, 14) or IsControlJustPressed(0, 14) then
                        spectateState.cameraTargetDistance = math.min(SPECTATE_CAMERA_DISTANCE_MAX, (spectateState.cameraTargetDistance or spectateState.cameraDistance) + SPECTATE_CAMERA_DISTANCE_STEP)
                    end

                    local currentDistance = spectateState.cameraDistance or 9.0
                    local targetDistance = spectateState.cameraTargetDistance or currentDistance
                    currentDistance = currentDistance + ((targetDistance - currentDistance) * 0.18)
                    spectateState.cameraDistance = currentDistance

                    local yawRad = math.rad(spectateState.cameraYaw or 0.0)
                    local pitchRad = math.rad(spectateState.cameraPitch or -10.0)
                    local horizontalDistance = math.cos(pitchRad) * currentDistance
                    local offsetX = math.sin(yawRad) * horizontalDistance
                    local offsetY = math.cos(yawRad) * horizontalDistance
                    local offsetZ = math.sin(-pitchRad) * currentDistance + SPECTATE_CAMERA_HEIGHT

                    local focusZ = targetCoords.z + 0.95
                    if targetPed and targetPed ~= 0 and DoesEntityExist(targetPed) then
                        local bonePos = GetPedBoneCoords(targetPed, 31086, 0.0, 0.0, 0.0)
                        focusZ = (bonePos.z or focusZ) + 0.2
                    end

                    local desiredCam = vector3(targetCoords.x + offsetX, targetCoords.y + offsetY, targetCoords.z + offsetZ)
                    spectateState.smoothCam = lerpVec3(spectateState.smoothCam, desiredCam, SPECTATE_CAMERA_LERP)
                    spectateState.smoothRot = nil
                    SetCamCoord(cam, spectateState.smoothCam.x, spectateState.smoothCam.y, spectateState.smoothCam.z)
                    PointCamAtCoord(cam, targetCoords.x, targetCoords.y, focusZ)
                end
            end

            Wait(SPECTATE_CAMERA_TICK_MS)
        end

        destroySpectateCamera()
        spectateState.cameraThread = false
    end)
end

clearSpectate = function()
    if not spectateState.active then return end

    local hadNativeSpectator = spectateState.nativeEnabled == true

    -- V20 camera-only exit:
    -- Do not call any native on the admin ped here. No collision restore, no freeze,
    -- no visibility, no alpha, no coords, no gravity, no vehicle warp.
    -- We only destroy our scripted camera/focus and reset local spectate state.
    if hadNativeSpectator then
        -- Only needed if native fallback was explicitly enabled in config.
        NetworkSetInSpectatorMode(false, 0)
    end

    destroySpectateCamera()
    stopLocalSceneLoad()

    spectateState.active = false
    spectateState.target = nil
    spectateState.origin = nil
    spectateState.autoInvisible = false
    spectateState.targetPlayerIndex = -1
    spectateState.targetSnapshot = nil
    spectateState.detectionHistory = {}
    spectateState.lastPedRetryAt = 0
    spectateState.cameraDistance = SPECTATE_CAMERA_DEFAULT_DISTANCE
    spectateState.cameraTargetDistance = SPECTATE_CAMERA_DEFAULT_DISTANCE
    spectateState.cameraYaw = 0.0
    spectateState.cameraPitch = -12.0
    spectateState.nativeEnabled = false
    spectateState.lastFocusAt = 0
    spectateState.viewMode = SPECTATE_DEFAULT_VIEW_MODE
    spectateState.targetCameraFreshUntil = 0
    spectateState.smoothCam = nil
    spectateState.smoothRot = nil
    sendSpectateNui({ hide = true }, true)

    if cloakActive then
        -- Cloak is an explicit admin feature and remains independent from spectate.
        applyStealthState()
    end
end

local function startSpectate(data)
    data = type(data) == 'table' and data or {}
    local target = tonumber(data.target)
    if not target then
        notifyChat('^1Visionary AC', '^1Spectateur: cible invalide.')
        return
    end

    if isSelfSpectateTarget(target) then
        if spectateState.active then
            clearSpectate()
        end
        spectateState.active = false
        spectateState.target = nil
        notifyChat('^1Visionary AC', '^1Impossible de te spectate toi-même. Sortie caméra uniquement, ped non modifié.')
        return
    end

    local playerIndex = GetPlayerFromServerId(target)
    local targetPed = playerIndex ~= -1 and GetPlayerPed(playerIndex) or 0
    local useNative = (not SPECTATE_CAMERA_ONLY) and SPECTATE_USE_NATIVE and targetPed and targetPed ~= 0
    if not useNative and SPECTATE_USE_NATIVE and not SPECTATE_NATIVE_FALLBACK then
        notifyChat('^1Visionary AC', '^1Spectateur natif indisponible: cible non streamée.')
        return
    end

    local switchingTarget = spectateState.active and tonumber(spectateState.target) ~= target

    local ped = PlayerPedId()
    spectateState.active = true
    spectateState.target = target
    spectateState.targetPlayerIndex = playerIndex
    spectateState.nativeEnabled = useNative
    spectateState.autoInvisible = false
    spectateState.targetSnapshot = type(data.snapshot) == 'table' and data.snapshot or nil
    spectateState.lastPedRetryAt = 0
    spectateState.lastFocusAt = 0
    spectateState.targetCameraFreshUntil = 0
    if not switchingTarget then
        spectateState.viewMode = SPECTATE_DEFAULT_VIEW_MODE
    end
    if switchingTarget then
        spectateState.lastTargetSwitchAt = GetGameTimer()
        -- Keep the scripted camera alive and let the lerp move to the next target.
        -- This avoids the hard black/physics reset that made previous/next feel rough.
    else
        spectateState.smoothCam = nil
        spectateState.smoothRot = nil
        -- Keep an informational origin only. Do not freeze/move/hide/disable collision on the admin ped.
        spectateState.origin = {
            coords = ped and ped ~= 0 and GetEntityCoords(ped) or nil,
            heading = ped and ped ~= 0 and GetEntityHeading(ped) or nil,
        }
    end

    if useNative then
        -- Native spectator is disabled by default. If explicitly enabled, it is the only mode that uses the native spectator state.
        NetworkSetInSpectatorMode(true, targetPed)
    end

    ensureSpectateSyncThread()
    if SPECTATE_SHOW_HUD then ensureSpectateHudThread() end
    ensureSpectateCameraThread()
    sendSpectateNui({ target = target, name = data.targetName, mode = spectateState.viewMode == 'orbit' and 'ORBIT' or 'POV', live = false, status = 'LOADING' }, true)
    if cloakActive then
        applyStealthState()
    end

    local suffix = data.targetName and ('^7' .. data.targetName) or ('#' .. tostring(target))
    local modeLabel = useNative and 'natif fallback' or 'caméra distante camera-only'
    notifyChat('^5Visionary AC', ('Mode spectateur %s activé sur %s.'):format(modeLabel, suffix))
end

local function stopSpectate(reason)
    if not spectateState.active then
        return
    end
    clearSpectate()
    if reason == 'target_left' then
        notifyChat('^1Visionary AC', '^1Le joueur a quitté la session spectateur.')
    elseif reason == 'self_guard' then
        notifyChat('^1Visionary AC', '^1Auto-spectate bloqué. Caméra fermée, ped non modifié.')
    elseif reason == 'manual' then
        notifyChat('^5Visionary AC', 'Mode spectateur fermé.')
    end
end

RegisterNetEvent('zvs-ac:admin:freeze', function(data)
    isFrozen = data and data.enabled or false
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, isFrozen)
    SetEntityCollision(ped, not isFrozen, not isFrozen)
    if isFrozen then
        ClearPedTasksImmediately(ped)
        notifyChat('^1Visionary AC', ('Vous avez été immobilisé%s.'):format(data and data.reason and (' ^7(' .. data.reason .. ')') or ''))
    else
        notifyChat('^5Visionary AC', 'Vous pouvez de nouveau bouger.')
    end

    if isFrozen and not freezeThreadStarted then
        freezeThreadStarted = true
        CreateThread(function()
            while isFrozen do
                DisableAllControlActions(0)
                EnableControlAction(0, 200, true) -- ESC
                EnableControlAction(0, 245, true) -- chat
                EnableControlAction(0, 249, true) -- push to talk
                Wait(0)
            end
            freezeThreadStarted = false
        end)
    end
end)

RegisterNetEvent('zvs-ac:admin:teleport', function(data)
    if type(data) ~= 'table' then return end
    local x = data.x or (data.coords and data.coords.x)
    local y = data.y or (data.coords and data.coords.y)
    local z = data.z or (data.coords and data.coords.z)
    if not x or not y or not z then return end

    local ped = PlayerPedId()
    SetPedCoordsKeepVehicle(ped, x + 0.0, y + 0.0, z + 0.0)
    if data.heading then
        SetEntityHeading(ped, data.heading + 0.0)
    end

    if data.context == 'goto' then
        notifyChat('^5Visionary AC', 'Téléportation vers la cible effectuée.')
    elseif data.context == 'bring' then
        notifyChat('^1Visionary AC', 'Un administrateur vous a déplacé.')
    end
end)

RegisterNetEvent('zvs-ac:admin:heal', function(data)
    local ped = PlayerPedId()
    local targetHealth = data and data.health or GetEntityMaxHealth(ped)
    SetEntityHealth(ped, targetHealth)
    if data and data.armour then
        SetPedArmour(ped, data.armour)
    end
    notifyChat('^5Visionary AC', 'Vos points de vie ont été restaurés par un administrateur.')
end)

RegisterNetEvent('zvs-ac:admin:wipeWeapons', function(data)
    local ped = PlayerPedId()
    RemoveAllPedWeapons(ped, true)
    notifyChat('^1Visionary AC', 'Votre équipement a été confisqué par un administrateur.')
end)

RegisterNetEvent('zvs-ac:admin:weaponLock', function(data)
    local ped = PlayerPedId()
    local enabled = data and data.enabled or false
    weaponLockActive = enabled

    if enabled then
        RemoveAllPedWeapons(ped, true)
        if ped and ped ~= 0 then
            SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
            SetPedCanSwitchWeapon(ped, false)
        end

        local adminLabel = data and data.admin or 'un administrateur'
        notifyChat('^1Visionary AC', ('Vos armes ont été neutralisées par %s.'):format(adminLabel))
        ensureWeaponLockThread()
    else
        if ped and ped ~= 0 then
            SetPedCanSwitchWeapon(ped, true)
        end
        HudWeaponWheelIgnoreControlInput(false)
        HudWeaponWheelIgnoreSelection(false)
        notifyChat('^5Visionary AC', 'Vous pouvez de nouveau utiliser vos armes.')
    end
end)


local function setAdminNoticeFocus(enabled)
    adminNoticeOpen = enabled == true
    if type(SetNuiFocusKeepInput) == 'function' then
        SetNuiFocusKeepInput(false)
    end
    SetNuiFocus(adminNoticeOpen, adminNoticeOpen)
end

RegisterNUICallback('closeAdminNotice', function(_, cb)
    setAdminNoticeFocus(false)
    cb({ ok = true })
end)

RegisterNetEvent('zvs-ac:admin:warn', function(data)
    local admin = data and data.admin or 'Visionary AC'
    local message = data and data.message or 'Avertissement administratif.'

    SendNUIMessage({
        action = 'adminNotice',
        data = {
            title = 'Avertissement staff',
            subtitle = tostring(admin),
            message = tostring(message),
            severity = 'warn',
        },
    })
    setAdminNoticeFocus(true)
    notifyChat(('^1%s'):format(admin), message)
end)

RegisterNetEvent('zvs-ac:admin:forceVehicleExit', function(data)
    local ped = PlayerPedId()
    if not ped or ped == 0 then return end

    local vehicle = GetVehiclePedIsIn(ped, false)
    local adminLabel = data and data.admin or 'un administrateur'

    if vehicle ~= 0 then
        TaskLeaveVehicle(ped, vehicle, 256)
        notifyChat('^1Visionary AC', ('%s vous a fait quitter votre véhicule.'):format(adminLabel))
    else
        notifyChat('^5Visionary AC', ('%s a tenté de vous faire quitter votre véhicule.'):format(adminLabel))
    end
end)

RegisterNetEvent('zvs-ac:admin:clearArea', function(data)
    if type(data) ~= 'table' then return end
    local coords = data.coords
    if type(coords) ~= 'table' then return end

    local radius = tonumber(data.radius) or CLEAR_AREA_DEFAULT_RADIUS
    if not radius or radius <= 0 then
        radius = CLEAR_AREA_DEFAULT_RADIUS
    end

    local center = vector3((coords.x or 0.0) + 0.0, (coords.y or 0.0) + 0.0, (coords.z or 0.0) + 0.0)
    local radiusSq = radius * radius
    local playerPeds = buildCleanupPlayerPedMap()
    local removed = { vehicles = 0, peds = 0, objects = 0 }

    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if vehicle and DoesEntityExist(vehicle) then
            local pos = GetEntityCoords(vehicle, false)
            if pos and vectorDistanceSquared(pos, center) <= radiusSq then
                if not isVehicleUsedByPlayers(vehicle, playerPeds) then
                    if deleteEntitySafely(vehicle, DeleteVehicle) then
                        removed.vehicles = removed.vehicles + 1
                    end
                end
            end
        end
    end

    for _, ped in ipairs(GetGamePool('CPed')) do
        if ped and DoesEntityExist(ped) and not playerPeds[ped] then
            local pos = GetEntityCoords(ped, false)
            if pos and vectorDistanceSquared(pos, center) <= radiusSq then
                if deleteEntitySafely(ped, DeletePed) then
                    removed.peds = removed.peds + 1
                end
            end
        end
    end

    for _, object in ipairs(GetGamePool('CObject')) do
        if object and DoesEntityExist(object) then
            local pos = GetEntityCoords(object, false)
            if pos and vectorDistanceSquared(pos, center) <= radiusSq then
                if deleteEntitySafely(object, DeleteObject) then
                    removed.objects = removed.objects + 1
                end
            end
        end
    end

    ClearArea(center.x, center.y, center.z, radius, true, true, true, true)
    ClearAreaOfVehicles(center.x, center.y, center.z, radius, false, false, false, false, false)

    if data.admin and tonumber(data.admin) == GetPlayerServerId(PlayerId()) then
        notifyChat(
            '^5Visionary AC',
            ('Zone nettoyée (%dm) — véhicules: %d, PNJ: %d, objets: %d.')
                :format(math.floor(radius + 0.5), removed.vehicles, removed.peds, removed.objects)
        )
    end
end)

RegisterNetEvent('zvs-ac:admin:spectateTarget', function(data)
    if not data then return end
    if data.enabled then
        startSpectate(data)
    else
        stopSpectate(data.reason)
    end
end)

RegisterNetEvent('zvs-ac:admin:spectate:sync', function(data)
    if not spectateState.active or type(data) ~= 'table' then
        return
    end
    if tonumber(data.target) ~= tonumber(spectateState.target) then
        return
    end
    spectateState.targetSnapshot = data
    sendSpectateNui(buildSpectateNuiPayload(data), false)
    if isTargetCameraFresh(data) then
        spectateState.targetCameraFreshUntil = GetGameTimer() + SPECTATE_TARGET_CAMERA_STALE_MS
    end
    if type(data.detections) == 'table' then
        spectateState.detectionHistory = data.detections
    else
        spectateState.detectionHistory = {}
    end
end)

RegisterNetEvent('zvs-ac:admin:spectate:requestCamera', function(data)
    if type(data) ~= 'table' then return end

    local target = tonumber(data.target)
    if not target then return end
    local myServerId = GetPlayerServerId(PlayerId())
    if target ~= myServerId then return end

    local now = GetGameTimer()
    if now - (spectateState.lastCameraProbeSentAt or 0) < 500 then return end
    spectateState.lastCameraProbeSentAt = now

    local cam = GetFinalRenderedCamCoord()
    local rot = GetFinalRenderedCamRot(2)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local vehicle = GetVehiclePedIsIn(ped, false)
    local speed = (GetEntitySpeed(ped) or 0.0) * 3.6
    local activity = 'idle'
    if vehicle and vehicle ~= 0 then
        activity = 'vehicle'
    elseif IsPedRagdoll(ped) or IsPedFalling(ped) or IsPedBeingStunned(ped) then
        activity = 'ragdoll'
    elseif IsPedShooting(ped) then
        activity = 'shoot'
    elseif IsPedReloading(ped) then
        activity = 'reload'
    elseif IsPlayerFreeAiming(PlayerId()) or IsPlayerTargettingAnything(PlayerId()) or IsPedAimingFromCover(ped) then
        activity = 'aim'
    elseif IsPedSprinting(ped) or speed > 22.0 then
        activity = 'sprint'
    elseif IsPedRunning(ped) or speed > 10.0 then
        activity = 'run'
    elseif IsPedWalking(ped) or speed > 1.8 then
        activity = 'walk'
    end
    local vehicleModel = nil
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        vehicleModel = GetEntityModel(vehicle)
    end
    TriggerServerEvent('zvs-ac:admin:spectate:camera', {
        target = target,
        camera = {
            x = cam.x + 0.0,
            y = cam.y + 0.0,
            z = cam.z + 0.0,
            rot = { x = rot.x + 0.0, y = rot.y + 0.0, z = rot.z + 0.0 },
        },
        coords = { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0 },
        heading = GetEntityHeading(ped) + 0.0,
        state = {
            activity = activity,
            speed = speed,
            health = GetEntityHealth(ped),
            armor = GetPedArmour(ped),
            weapon = GetSelectedPedWeapon(ped),
            inVehicle = vehicle and vehicle ~= 0 or false,
            vehicleModel = vehicleModel,
        },
        ts = GetGameTimer(),
    })
end)

RegisterNetEvent('zvs-ac:admin:cloak', function(data)
    data = type(data) == 'table' and data or {}
    if data.disabled == true or not STAFF_NOCLIP_ENABLED then
        cloakActive = false
        noclipState.enabled = false
        restoreNoClipSolidPed('noclip-disabled-config')
        applyStealthState()
        notifyChat('^5Visionary AC', 'NoClip interne indisponible dans la configuration actuelle.')
        return
    end
    cloakActive = data.enabled == true
    applyStealthState()
    notifyChat('^5Visionary AC', cloakActive and 'NoClip staff activé.' or 'NoClip staff désactivé.')
end)

RegisterNetEvent('zvs-ac:client:repairCollision', function(data)
    data = type(data) == 'table' and data or {}
    if isFrozen and data.force ~= true then
        notifyChat('^5Visionary AC', 'Collision repair ignoré: joueur actuellement freeze par un staff.')
        return
    end

    gentleLocalCollisionRepair(data.reason or 'manual-repair')
    if data.notify ~= false then
        notifyChat('^5Visionary AC', 'Collision locale restaurée.')
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    -- Restart-safe: never run the heavy post-spectate repair on every player.
    -- Only clients actually modified by this resource are touched, and no async freeze/focus loop is started while stopping.
    local hadSpectate = spectateState.active == true
    local hadCloak = cloakActive == true or noclipState.enabled == true
    local hadFreeze = isFrozen == true
    local hadWeaponLock = weaponLockActive == true

    resourceStopping = true

    if hadSpectate then
        -- Camera-only spectate cleanup: never run ped/physics repair on resource restart.
        clearSpectate()
    end

    if hadCloak then
        cloakActive = false
        noclipState.enabled = false
        applyStealthState()
        forceRestoreSpectatePhysics('resource-stop')
    end

    if hadFreeze then
        isFrozen = false
        local ped = PlayerPedId()
        restoreEntitySolid(ped)
        restoreLocalPlayerFlags()
    end

    if hadWeaponLock then
        weaponLockActive = false
        weaponLockThreadRunning = false
        local ped = PlayerPedId()
        if ped and ped ~= 0 then
            SetPedCanSwitchWeapon(ped, true)
        end
        HudWeaponWheelIgnoreControlInput(false)
        HudWeaponWheelIgnoreSelection(false)
    end

    if hadCloak or hadFreeze then
        gentleLocalCollisionRepair('resource-stop')
    end
end)
