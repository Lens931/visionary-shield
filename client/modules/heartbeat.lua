zVS = zVS or {}
local cfg = zVS.Config.Heartbeat or {}

if cfg.Enabled == false then
    return
end

CreateThread(function()
    local interval = cfg.Interval or 15000
    while true do
        TriggerServerEvent('zvs-ac:heartbeat', {
            ts = GetGameTimer(),
            ped = PlayerPedId(),
        })
        Wait(interval)
    end
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    TriggerServerEvent('zvs-ac:heartbeat', { ts = GetGameTimer(), startup = true })
end)
