zVS = zVS or {}
local utils = zVS and zVS.utils
if not utils then
    local ok, mod = pcall(require, 'shared.utils')
    if not ok then
        error(('zVS-AC: unable to load shared utils (%s)'):format(mod))
    end
    utils = mod
end

local probeCfg = zVS.Config and zVS.Config.GodmodeProbe or {}
local spawnGraceMs = tonumber(probeCfg.SpawnGraceMs) or 45000
local requireCollisionLoaded = probeCfg.RequireCollisionLoaded ~= false
local probeGraceUntil = GetGameTimer() + spawnGraceMs

local function extendProbeGrace(reason, duration)
    local grace = tonumber(duration) or spawnGraceMs
    probeGraceUntil = math.max(probeGraceUntil or 0, GetGameTimer() + grace)
    TriggerServerEvent('zvs-ac:godmodeClientReady', {
        reason = reason or 'client_grace',
        grace = grace,
    })
end

AddEventHandler('playerSpawned', function()
    extendProbeGrace('playerSpawned', spawnGraceMs)
end)

CreateThread(function()
    Wait(2500)
    extendProbeGrace('client_loaded', spawnGraceMs)
end)

RegisterNetEvent('zvs-ac:probeGodmode', function(data)
    local ped = PlayerPedId()
    local now = GetGameTimer()
    if now < (probeGraceUntil or 0) then
        TriggerServerEvent('zvs-ac:godmodeResult', { skipped = true, reason = 'spawn_grace' })
        return
    end

    if not DoesEntityExist(ped) or IsEntityDead(ped) then
        TriggerServerEvent('zvs-ac:godmodeResult', { skipped = true, reason = 'dead' })
        return
    end

    if IsPlayerSwitchInProgress() or IsScreenFadedOut() or IsPedFalling(ped) or IsPedRagdoll(ped) or IsEntityInAir(ped) then
        TriggerServerEvent('zvs-ac:godmodeResult', { skipped = true, reason = 'unstable_player_state' })
        return
    end

    if requireCollisionLoaded and not HasCollisionLoadedAroundEntity(ped) then
        TriggerServerEvent('zvs-ac:godmodeResult', { skipped = true, reason = 'collision_not_loaded' })
        extendProbeGrace('collision_not_loaded', math.min(spawnGraceMs, 15000))
        return
    end

    local damage = (data and data.damage) or (zVS.Config.GodmodeProbe and zVS.Config.GodmodeProbe.Damage) or 1
    local minimum = (data and data.minimum) or (zVS.Config.GodmodeProbe and zVS.Config.GodmodeProbe.MinimumHealth) or 140
    local restore = data and data.restore
    if restore == nil then
        restore = zVS.Config.GodmodeProbe and zVS.Config.GodmodeProbe.RestoreHealth
    end
    local restoreDelay = (data and data.restore_delay) or (zVS.Config.GodmodeProbe and zVS.Config.GodmodeProbe.RestoreDelay) or 200

    local beforeHp = GetEntityHealth(ped)
    if beforeHp <= minimum then
        TriggerServerEvent('zvs-ac:godmodeResult', {
            skipped = true,
            reason = 'low_health',
            before = beforeHp,
        })
        return
    end

    local beforeArmour = GetPedArmour(ped)
    local coords = GetEntityCoords(ped)
    local invincibleBefore = GetPlayerInvincible(PlayerId())

    SetEntityHealth(ped, math.max(0, beforeHp - damage))
    Wait(restoreDelay)
    local afterHp = GetEntityHealth(ped)
    local afterArmour = GetPedArmour(ped)

    if restore then
        SetEntityHealth(ped, beforeHp)
        SetPedArmour(ped, beforeArmour)
    end

    TriggerServerEvent('zvs-ac:godmodeResult', {
        before = beforeHp,
        after = afterHp,
        damage = damage,
        armour_before = beforeArmour,
        armour_after = afterArmour,
        invincible = invincibleBefore and true or false,
        pos = { utils.round(coords.x, 2), utils.round(coords.y, 2), utils.round(coords.z, 2) },
    })
end)
