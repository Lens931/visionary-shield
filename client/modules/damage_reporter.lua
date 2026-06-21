zVS = zVS or {}
local utils = zVS and zVS.utils
if not utils then
    local ok, mod = pcall(require, 'shared.utils')
    if not ok then
        error(('zVS-AC: unable to load shared utils (%s)'):format(mod))
    end
    utils = mod
end
local cfg = zVS.Config.DamageMonitor or {}

if not cfg.Enabled then
    return
end

local HEAD_BONES = {
    [31086] = true,
    [20] = true,
    [39317] = true,
}

local lastHealth = {}
local lastCacheAt = 0

local function getAdaptiveWait()
    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return tonumber(cfg.ClientNoPedWaitMs) or 8000
    end

    if IsPedShooting(ped) or IsPedInMeleeCombat(ped) or IsPedBeingStunned(ped, 0) then
        return tonumber(cfg.ClientCombatCacheMs) or 700
    end

    local weapon = GetSelectedPedWeapon(ped)
    if weapon and weapon ~= 0 and weapon ~= `WEAPON_UNARMED` then
        return tonumber(cfg.ClientArmedCacheMs) or 1800
    end

    return tonumber(cfg.ClientIdleCacheMs) or 6000
end

local function cacheHealthForPlayers()
    local players = GetActivePlayers()
    for _, playerIdx in ipairs(players) do
        local ped = GetPlayerPed(playerIdx)
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            lastHealth[ped] = GetEntityHealth(ped)
        end
    end
    lastCacheAt = GetGameTimer()
end

CreateThread(function()
    while true do
        Wait(getAdaptiveWait())
        cacheHealthForPlayers()
    end
end)

AddEventHandler('gameEventTriggered', function(name, data)
    if name ~= 'CEventNetworkEntityDamage' then
        return
    end

    local victim = data[1]
    local attacker = data[2]

    if attacker ~= PlayerPedId() then
        if victim == PlayerPedId() then
            lastHealth[victim] = GetEntityHealth(victim)
        end
        return
    end

    if victim == attacker then return end
    if victim == 0 or not DoesEntityExist(victim) then return end

    local victimType = GetEntityType(victim)
    if victimType ~= 1 then
        if cfg.LogNonPedTargets ~= true then
            return
        end
    end

    local victimIdx = NetworkGetPlayerIndexFromPed(victim)
    if victimIdx == -1 then return end

    local targetSrc = GetPlayerServerId(victimIdx)
    if not targetSrc or targetSrc == 0 then return end

    if GetGameTimer() - lastCacheAt > 1500 then
        lastHealth[victim] = GetEntityHealth(victim)
    end

    local victimHealth = GetEntityHealth(victim)
    local before = lastHealth[victim] or victimHealth
    local damage = before - victimHealth
    lastHealth[victim] = victimHealth

    if damage < 0 then damage = 0 end

    local attackerCoords = GetEntityCoords(PlayerPedId())
    local victimCoords = GetEntityCoords(victim)
    local distance = #(attackerCoords - victimCoords)
    local isHeadshot = HEAD_BONES[data[10]] or false
    local payload = {
        target = targetSrc,
        victimName = GetPlayerName(victimIdx),
        weapon = data[7],
        bone = data[10],
        fatal = data[4] == 1 or IsPedDeadOrDying(victim, true),
        melee = data[8] == 1,
        headshot = isHeadshot,
        damage = damage,
        health_before = before,
        health_after = victimHealth,
        distance = distance,
        pos = { utils.round(victimCoords.x, 2), utils.round(victimCoords.y, 2), utils.round(victimCoords.z, 2) },
        tick = GetGameTimer(),
    }

    TriggerServerEvent('zvs-ac:damageReport', payload)

    if isHeadshot and (zVS.Config.HeadshotLog and zVS.Config.HeadshotLog.Enabled ~= false) then
        TriggerServerEvent('zvs-ac:headshotLog', {
            target = targetSrc,
            weapon = payload.weapon,
            bone = payload.bone,
            distance = payload.distance,
            fatal = payload.fatal,
            pos = payload.pos,
        })
    end
end)
