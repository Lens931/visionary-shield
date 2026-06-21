zVS = zVS or {}
local cfg = zVS.Config.AdminTools or {}

if not cfg.Enabled then
    return
end

local isMenuOpen = false
local spectateNuiVisible = false
local floatingNuiVisible = false
local floatingNuiInteractive = false
local pauseShieldActive = false
local nuiTextInputActive = false
local inputGuardThreadStarted = false
local runtimeRequestedAt = 0

local function asTable(value)
    if type(value) == 'table' then
        return value
    end
    if value ~= nil then
        return { target = value }
    end
    return {}
end

local function setKeepInputEnabled(enabled)
    if type(SetNuiFocusKeepInput) == 'function' then
        SetNuiFocusKeepInput(enabled == true)
    end
end

local startInputGuardThread

local function hasVisibleAdminNui()
    return isMenuOpen or spectateNuiVisible or floatingNuiVisible
end

local function hasFocusedAdminNui()
    return isMenuOpen or floatingNuiInteractive or nuiTextInputActive
end

local function applyFocusState()
    if pauseShieldActive then
        -- Native pause menu and CEF focus do not mix well. Release focus,
        -- but never mutate the JS runtime visibility of floating windows.
        SetNuiFocus(false, false)
        setKeepInputEnabled(false)
        return
    end

    if hasFocusedAdminNui() then
        -- Focus is interactive-only. When no text field is active, keep game input
        -- enabled so the registered keymapping can close the dashboard smoothly.
        -- Text fields switch keep-input off and are guarded below.
        SetNuiFocus(true, true)
        setKeepInputEnabled(not nuiTextInputActive)
        startInputGuardThread()
    else
        SetNuiFocus(false, false)
        setKeepInputEnabled(false)
    end
end

startInputGuardThread = function()
    if inputGuardThreadStarted then return end
    inputGuardThreadStarted = true
    CreateThread(function()
        while true do
            local focused = hasFocusedAdminNui()
            if nuiTextInputActive and focused and not pauseShieldActive then
                DisableAllControlActions(0)
                DisableAllControlActions(1)
                DisableAllControlActions(2)
                Wait(0)
            elseif focused and not pauseShieldActive then
                -- Keep common UI hotkeys from leaking to other resources while
                -- this CEF layer is focused/clickable. No permanent idle loop.
                DisableControlAction(0, 245, true) -- chat
                DisableControlAction(0, 244, true) -- interaction menu
                DisableControlAction(0, 288, true) -- F1 / phone-style menus
                DisableControlAction(0, 289, true) -- F2 / inventory-style menus
                DisableControlAction(0, 170, true) -- F3
                DisableControlAction(0, 167, true) -- F6
                DisableControlAction(0, 168, true) -- F7
                DisableControlAction(0, 56, true)  -- F9
                Wait(0)
            else
                inputGuardThreadStarted = false
                return
            end
        end
    end)
end

local function setTextInputActive(active)
    nuiTextInputActive = active == true
    applyFocusState()
    if hasVisibleAdminNui() then
        startInputGuardThread()
    end
end


local function setPauseShield(active)
    active = active == true
    if pauseShieldActive == active then return end
    pauseShieldActive = active
    SendNUIMessage({
        action = 'pauseState',
        data = { active = pauseShieldActive },
    })
    applyFocusState()
end

CreateThread(function()
    local lastState = false
    while true do
        local hasVisibleNui = hasVisibleAdminNui()
        local paused = IsPauseMenuActive() == true or (type(IsPauseMenuRestarting) == 'function' and IsPauseMenuRestarting() == true)
        if paused ~= lastState then
            lastState = paused
            setPauseShield(paused)
        elseif pauseShieldActive and not paused then
            setPauseShield(false)
        end
        Wait((hasVisibleNui or pauseShieldActive) and 120 or 650)
    end
end)

local function sendClosed(reason)
    SendNUIMessage({
        action = 'close',
        reason = reason or 'close',
    })
end

local function closeMenu(reason)
    if not isMenuOpen then
        sendClosed(reason or 'already-closed')
        applyFocusState()
        return
    end
    isMenuOpen = false
    nuiTextInputActive = false
    floatingNuiInteractive = false
    sendClosed(reason or 'close-menu')
    applyFocusState()
end

local function toggleDashboardByBind()
    -- Let the NUI decide from its own runtime state. This avoids client/CEF
    -- desync where the dashboard is visible but isMenuOpen is stale.
    SendNUIMessage({
        action = 'toggleDashboardByBind',
        reason = 'keymapping',
    })
end

local function closeDashboardByBind()
    if not isMenuOpen and not floatingNuiVisible and not spectateNuiVisible then
        applyFocusState()
        return
    end
    toggleDashboardByBind()
end

local function closeDashboardOnly(floatingVisible, interactive)
    isMenuOpen = false
    nuiTextInputActive = false
    floatingNuiVisible = floatingVisible == true
    floatingNuiInteractive = floatingNuiVisible and interactive == true
    applyFocusState()
end

local function openMenu(state)
    isMenuOpen = true
    floatingNuiInteractive = false
    SendNUIMessage({
        action = 'open',
        state = state or {},
        mode = 'disabled',
        livePreview = { enabled = false, mode = 'disabled', reason = 'preview_removed' },
        staffOverlay = { enabled = false, available = false },
    })
    applyFocusState()
end

local function updateMenu(state)
    if not isMenuOpen and not floatingNuiVisible and not spectateNuiVisible then
        return
    end
    SendNUIMessage({
        action = 'update',
        state = state or {},
        mode = 'disabled',
        livePreview = { enabled = false, mode = 'disabled', reason = 'preview_removed' },
        staffOverlay = { enabled = false, available = false },
    })
end

local function requestRuntimeConfig(force)
    local now = GetGameTimer()
    if not force and runtimeRequestedAt ~= 0 and (now - runtimeRequestedAt) < 1500 then
        return
    end
    runtimeRequestedAt = now
    TriggerServerEvent('zvs:server:getRuntimeConfig')
end

RegisterNetEvent('zvs-ac:admin:open', function(state)
    openMenu(state)
    requestRuntimeConfig(true)
end)

RegisterNetEvent('zvs-ac:admin:update', function(state)
    updateMenu(state)
end)

RegisterNetEvent('zvs-ac:admin:notification', function(data)
    local message = data
    if type(data) == 'table' then
        message = data.message or ''
    end
    if not message or message == '' then
        return
    end
    TriggerEvent('chat:addMessage', {
        color = { 116, 247, 255 },
        multiline = true,
        args = { '^5Visionary AC', message }
    })
end)

RegisterNetEvent('zvs-ac:admin:appearanceSaved', function(data)
    SendNUIMessage({ action = 'appearanceSaved', data = data or {} })
end)

RegisterNetEvent('zvs-ac:admin:settingsSaved', function(data)
    SendNUIMessage({ action = 'settingsSaved', data = data or {} })
end)

RegisterNetEvent('zvs-ac:admin:runtimeConfig', function(data)
    SendNUIMessage({ action = 'runtimeConfig', data = data or {} })
end)

RegisterNetEvent('zvs-ac:admin:screenshot', function(data)
    data = type(data) == 'table' and data or {}
    floatingNuiVisible = true
    SendNUIMessage({ action = 'screenshotResult', data = data })
    applyFocusState()
end)

RegisterNetEvent('zvs-ac:admin:spectateTarget', function(data)
    data = type(data) == 'table' and data or {}
    spectateNuiVisible = data.enabled == true
    applyFocusState()
end)

-- Preview events are intentionally ignored in the production ImGui NUI.
-- No clone ped, no scripted preview camera, no render target, no live screenshot loop.
RegisterNetEvent('zvs-ac:admin:preview', function(_) end)
RegisterNetEvent('zvs-ac:admin:previewPortrait', function(_) end)
RegisterNetEvent('zvs-ac:admin:previewFrame', function(_) end)

local toggleCommand = cfg.ToggleCommand
if type(toggleCommand) ~= 'string' or toggleCommand == '' then
    toggleCommand = 'zvsac_togglemenu'
end

local toggleKey = cfg.ToggleKey
if type(toggleKey) ~= 'string' or toggleKey == '' then
    toggleKey = 'F5'
end

local cloakToggleCommand = cfg.CloakToggleCommand
if type(cloakToggleCommand) ~= 'string' or cloakToggleCommand == '' then
    cloakToggleCommand = 'zvsac_togglecloak'
end

local cloakToggleKey = cfg.CloakToggleKey
if type(cloakToggleKey) ~= 'string' then
    cloakToggleKey = ''
end

RegisterCommand(cfg.Command or 'zvsadmin', function()
    TriggerServerEvent('zvs-ac:admin:requestOpen')
end, false)

RegisterCommand(toggleCommand, function()
    if isMenuOpen or floatingNuiVisible or spectateNuiVisible then
        toggleDashboardByBind()
    else
        TriggerServerEvent('zvs-ac:admin:requestOpen')
    end
end, false)

if cloakToggleCommand ~= toggleCommand then
    RegisterCommand(cloakToggleCommand, function()
        TriggerServerEvent('zvs-ac:admin:toggleCloak')
    end, false)
end

if type(RegisterKeyMapping) == 'function' then
    RegisterKeyMapping(toggleCommand, 'Visionary AC — Ouvrir/Fermer', 'keyboard', toggleKey)
    if cloakToggleCommand ~= toggleCommand then
        RegisterKeyMapping(cloakToggleCommand, 'Visionary AC — NoClip staff', 'keyboard', cloakToggleKey)
    end
end

RegisterNUICallback('ready', function(_, cb)
    isMenuOpen = false
    spectateNuiVisible = false
    floatingNuiVisible = false
    floatingNuiInteractive = false
    pauseShieldActive = false
    nuiTextInputActive = false
    sendClosed('nui-ready')
    applyFocusState()
    requestRuntimeConfig(true)
    cb({ ok = true })
end)

RegisterNUICallback('close', function(_, cb)
    closeMenu('nui-close')
    cb({ ok = true })
end)

RegisterNUICallback('closeDashboard', function(data, cb)
    data = asTable(data)
    closeDashboardOnly(data.floatingVisible == true, data.interactive == true or data.focus == true)
    cb({ ok = true })
end)

RegisterNUICallback('setFloatingLayerVisible', function(data, cb)
    data = asTable(data)
    floatingNuiVisible = data.visible == true
    floatingNuiInteractive = floatingNuiVisible and (data.interactive == true or data.focus == true)
    if not floatingNuiInteractive then
        nuiTextInputActive = false
    end
    applyFocusState()
    cb({ ok = true, focused = hasFocusedAdminNui() })
end)

RegisterNUICallback('setTextInputActive', function(data, cb)
    data = asTable(data)
    setTextInputActive(data.active == true)
    cb({ ok = true })
end)

RegisterNUICallback('requestOpen', function(_, cb)
    if isMenuOpen then
        toggleDashboardByBind()
    else
        TriggerServerEvent('zvs-ac:admin:requestOpen')
    end
    cb({ ok = true })
end)

RegisterNUICallback('requestRefresh', function(_, cb)
    if isMenuOpen or floatingNuiVisible or spectateNuiVisible then
        TriggerServerEvent('zvs-ac:admin:refresh')
    end
    cb({ ok = true })
end)

RegisterNUICallback('getRuntimeConfig', function(_, cb)
    requestRuntimeConfig(true)
    cb({ ok = true })
end)

RegisterNUICallback('saveAppearanceSettings', function(data, cb)
    TriggerServerEvent('zvs-ac:admin:saveAppearance', asTable(data))
    cb({ ok = true })
end)

RegisterNUICallback('saveAdminSettings', function(data, cb)
    TriggerServerEvent('zvs-ac:admin:saveSettings', asTable(data))
    cb({ ok = true })
end)

RegisterNUICallback('resetAdminSettings', function(_, cb)
    TriggerServerEvent('zvs-ac:admin:resetSettings')
    cb({ ok = true })
end)

RegisterNUICallback('setSpectatePanelVisible', function(data, cb)
    spectateNuiVisible = type(data) == 'table' and data.visible == true or false
    applyFocusState()
    cb({ ok = true })
end)

RegisterNUICallback('requestPlayerSnapshot', function(_, cb)
    cb({ ok = true, disabled = true })
end)

RegisterNUICallback('requestLivePreviewFrame', function(_, cb)
    cb({ ok = true, disabled = true })
end)

RegisterNUICallback('stopLivePreview', function(_, cb)
    cb({ ok = true, disabled = true })
end)

RegisterNUICallback('banPlayer', function(data, cb) TriggerServerEvent('zvs-ac:admin:ban', asTable(data)); cb({ ok = true }) end)
RegisterNUICallback('unbanPlayer', function(data, cb) TriggerServerEvent('zvs-ac:admin:unban', asTable(data)); cb({ ok = true }) end)
RegisterNUICallback('requestScreenshot', function(data, cb) TriggerServerEvent('zvs-ac:admin:requestScreenshot', asTable(data)); cb({ ok = true }) end)
RegisterNUICallback('recordNote', function(data, cb) TriggerServerEvent('zvs-ac:admin:addNote', asTable(data)); cb({ ok = true }) end)
RegisterNUICallback('kickPlayer', function(data, cb) TriggerServerEvent('zvs-ac:admin:kick', asTable(data)); cb({ ok = true }) end)
RegisterNUICallback('toggleFreeze', function(data, cb) TriggerServerEvent('zvs-ac:admin:toggleFreeze', asTable(data)); cb({ ok = true }) end)
RegisterNUICallback('toggleSpectate', function(data, cb) TriggerServerEvent('zvs-ac:admin:toggleSpectate', asTable(data)); cb({ ok = true }) end)
RegisterNUICallback('teleportGoto', function(data, cb) TriggerServerEvent('zvs-ac:admin:goto', asTable(data)); cb({ ok = true }) end)
RegisterNUICallback('teleportBring', function(data, cb) TriggerServerEvent('zvs-ac:admin:bring', asTable(data)); cb({ ok = true }) end)
RegisterNUICallback('healPlayer', function(data, cb) TriggerServerEvent('zvs-ac:admin:heal', asTable(data)); cb({ ok = true }) end)
RegisterNUICallback('wipeWeapons', function(data, cb) TriggerServerEvent('zvs-ac:admin:wipeWeapons', asTable(data)); cb({ ok = true }) end)
RegisterNUICallback('toggleWeaponLock', function(data, cb) TriggerServerEvent('zvs-ac:admin:toggleWeaponLock', asTable(data)); cb({ ok = true }) end)
RegisterNUICallback('toggleSpawnProtection', function(data, cb) TriggerServerEvent('zvs-ac:admin:toggleSpawnProtection', asTable(data)); cb({ ok = true }) end)
RegisterNUICallback('forceVehicleExit', function(data, cb) TriggerServerEvent('zvs-ac:admin:forceVehicleExit', asTable(data)); cb({ ok = true }) end)
RegisterNUICallback('clearArea', function(data, cb) TriggerServerEvent('zvs-ac:admin:clearArea', asTable(data)); cb({ ok = true }) end)
RegisterNUICallback('warnPlayer', function(data, cb) TriggerServerEvent('zvs-ac:admin:warn', asTable(data)); cb({ ok = true }) end)
RegisterNUICallback('toggleCloak', function(_, cb) TriggerServerEvent('zvs-ac:admin:toggleCloak'); cb({ ok = true }) end)
RegisterNUICallback('setDefenseState', function(data, cb) TriggerServerEvent('zvs-ac:admin:setDefenseState', asTable(data)); cb({ ok = true }) end)
RegisterNUICallback('resolveRiskApproval', function(data, cb) TriggerServerEvent('zvs-ac:admin:resolveRiskApproval', asTable(data)); cb({ ok = true }) end)

RegisterNUICallback('toggleStaffOverlay', function(_, cb)
    cb({ ok = true, enabled = false, available = false, disabled = true })
end)

RegisterNUICallback('setPreviewLock', function(_, cb)
    cb({ ok = true, disabled = true })
end)

RegisterCommand('zvsac_close', function()
    closeMenu('command-close')
end, false)

RegisterCommand('zvs_resetui', function()
    TriggerServerEvent('zvs-ac:admin:resetSettings')
end, false)

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    CreateThread(function()
        Wait(0)
        isMenuOpen = false
        spectateNuiVisible = false
        floatingNuiVisible = false
        pauseShieldActive = false
        nuiTextInputActive = false
        sendClosed('client-resource-start')
        applyFocusState()
    end)
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    if not isMenuOpen then
        sendClosed('player-loaded')
        applyFocusState()
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    isMenuOpen = false
    spectateNuiVisible = false
    floatingNuiVisible = false
    floatingNuiInteractive = false
    pauseShieldActive = false
    nuiTextInputActive = false
    sendClosed('resource-stop')
    applyFocusState()
end)
