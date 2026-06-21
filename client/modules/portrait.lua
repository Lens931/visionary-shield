zVS = zVS or {}

-- Production NUI v1.5.6: portrait/preview capture removed.
-- The admin frontend no longer uses ped headshots, clone peds, cameras or render targets.
-- This module stays as a safe no-op so older server events do not error if triggered.
RegisterNetEvent('zvs-ac:admin:requestPortrait', function(data)
    data = type(data) == 'table' and data or {}
    if type(data.requestId) == 'string' and data.requestId ~= '' then
        TriggerServerEvent('zvs-ac:admin:submitPortrait', {
            requestId = data.requestId,
            error = 'portrait_removed',
            mode = 'disabled'
        })
    end
end)
