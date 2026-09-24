AddEventHandler('onClientResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    if Config.WeaponWheel and Config.WeaponWheel.Enabled then return end
    local ped = PlayerPedId()
    if ped and ped ~= 0 then
        RemoveAllPedWeapons(ped, true, true)
    end
end)

local CraftPeds = {}

CreateThread(function()
    repeat Wait(2000) until LocalPlayer.state.IsInSession
    EnableHudContext(GetHashKey("HUD_CTX_MP_IN_ROLE_CUTSCENE"))
end)

if Config.DevMode then
    AddEventHandler('onClientResourceStart', function(resourceName)
        if (GetCurrentResourceName() ~= resourceName) then
            return
        end

        SendNUIMessage({ action = "hide" })
        RemoveAllPedWeapons(PlayerPedId(), true, true)
        TriggerServerEvent("DEV:loadweapons")
        TriggerServerEvent("vorpinventory:getItemsTable")
        Wait(1000)
        TriggerServerEvent("vorpinventory:getInventory")
        Wait(1000)
        TriggerServerEvent("vorpCore:LoadAllAmmo")
        Wait(100)
        TriggerEvent("vorpinventory:loaded")
        print("^1WARNING: Dev mode is enabled^7 do not use this in production live servers")
    end)
end

local function isControlDown(controls)
    for _, control in ipairs(controls) do
        for _, padIndex in ipairs({ 0, 2 }) do
            if IsDisabledControlPressed(padIndex, control) or IsControlPressed(padIndex, control) then
                return true
            end
        end
    end

    return false
end

local function isControlJustPressed(controls)
    for _, control in ipairs(controls) do
        for _, padIndex in ipairs({ 0, 2 }) do
            if IsDisabledControlJustPressed(padIndex, control) or IsControlJustPressed(padIndex, control) then
                return true
            end
        end
    end

    return false
end

local hotbarModifierControls = {
    0x8FFC75D6, -- INPUT_SPRINT / Left Shift
}

local lastHotbarToggle = 0
local function toggleHotbar()
    if Config.WeaponWheel and Config.WeaponWheel.Enabled then
        return
    end
    if GetGameTimer() - lastHotbarToggle < 250 then return end
    lastHotbarToggle = GetGameTimer()
    print("^2[vorp_inventory]^7 Hotbar toggled.")
    SendNUIMessage({ action = "toggleHotbar" })
    pcall(NUIService.SendHotbarItems)
end

RegisterCommand("vorp_toggle_hotbar", function() toggleHotbar() end, false)

CreateThread(function()
    if Config.WeaponWheel and Config.WeaponWheel.Enabled then
        print("^3[vorp_inventory]^7 Native weapon wheel enabled — hotbar quick-use shortcuts disabled.")
        return
    end
    repeat Wait(2000) until LocalPlayer.state.IsInSession
    print("^2[vorp_inventory]^7 Hotbar controls active.")
    local tabControl = 0xB238FE0B
    print("^2[vorp_inventory]^7 Suppressing native weapon wheel controls (default TAB and 1-5).")
    local hotbarControls = {
        { controls = { 0xE6F612E4 }, slot = 1 },
        { controls = { 0x1CE6D9EB }, slot = 2 },
        { controls = { 0x4F49CC4C, 0xAE69478F }, slot = 3 },
        { controls = { 0x8F9F9E58 }, slot = 4 },
        { controls = { 0xAB62E997 }, slot = 5 },
    }

    local VK_TAB = 0x09
    local tabWasDown = false

    while true do
        Wait(0)
        DisableControlAction(0, tabControl, true)
        DisableControlAction(2, tabControl, true)
        for _, hotkey in ipairs(hotbarControls) do
            for _, control in ipairs(hotkey.controls) do
                DisableControlAction(0, control, true)
                DisableControlAction(2, control, true)
            end
        end

        local tabDownNow = IsRawKeyPressed and IsRawKeyPressed(VK_TAB)
        if tabDownNow and not tabWasDown then
            toggleHotbar()
        end
        tabWasDown = tabDownNow

        if not InInventory then
            for _, hotkey in ipairs(hotbarControls) do
                if isControlJustPressed(hotkey.controls) then
                    print(("Hotbar slot %d pressed (controls: %s)"):format(hotkey.slot, table.concat(hotkey.controls, ", ")))
                    if isControlDown(hotbarModifierControls) then
                        print(("Modifier key held, holstering slot %d instead of using it."):format(hotkey.slot))
                        NUIService.HolsterHotbarSlot(hotkey.slot)
                    else
                        print(("Using hotbar slot %d"):format(hotkey.slot))
                        NUIService.UseHotbarSlot(hotkey.slot)
                    end
                end
            end
        end
    end
end)

local function getCraftInteractionCoords(loc)
    if loc.ped and loc.ped.coords then
        return loc.ped.coords
    end

    return loc.coord
end

local function spawnCraftPed(loc, index)
    local pedConfig = loc.ped
    if not pedConfig or pedConfig.enabled == false then
        return
    end

    local coords = pedConfig.coords or loc.coord
    if not coords then
        print(("[vorp_inventory] Craft location %s is missing coords for ped spawn."):format(index))
        return
    end

    local model = pedConfig.model or "U_M_M_NbxGeneralStoreOwner_01"
    local modelHash = type(model) == "string" and joaat(model) or model
    if not IsModelValid(modelHash) then
        print(("[vorp_inventory] Invalid craft ped model at location %s: %s"):format(index, tostring(model)))
        return
    end

    RequestModel(modelHash)
    local timeout = 0
    while not HasModelLoaded(modelHash) and timeout < 5000 do
        Wait(50)
        timeout = timeout + 50
    end

    if not HasModelLoaded(modelHash) then
        print(("[vorp_inventory] Failed to load craft ped model at location %s: %s"):format(index, tostring(model)))
        return
    end

    local heading = pedConfig.heading or 0.0
    local ped

    local ok = pcall(function()
        ped = CreatePed(modelHash, coords.x, coords.y, coords.z - 1.0, heading, false, true, true, true)
    end)

    if not ok or not ped or ped == 0 then
        pcall(function()
            ped = CreatePed(0, modelHash, coords.x, coords.y, coords.z - 1.0, heading, false, true, true, true)
        end)
    end

    if not ped or ped == 0 then
        print(("[vorp_inventory] Failed to create craft ped at location %s."):format(index))
        SetModelAsNoLongerNeeded(modelHash)
        return
    end

    SetEntityAsMissionEntity(ped, true, true)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)

    if pedConfig.scenario and pedConfig.scenario ~= "" then
        local scenarioStarted = pcall(function()
            TaskStartScenarioInPlace(ped, pedConfig.scenario, -1, true, false, false, false)
        end)

        if not scenarioStarted then
            pcall(function()
                TaskStartScenarioInPlace(ped, joaat(pedConfig.scenario), -1, true, false, false, false)
            end)
        end
    else
        TaskStandStill(ped, -1)
    end

    CraftPeds[index] = ped
    SetModelAsNoLongerNeeded(modelHash)
end

local function cleanupCraftPeds()
    for index, ped in pairs(CraftPeds) do
        if ped and DoesEntityExist(ped) then
            pcall(DeletePed, ped)
            if DoesEntityExist(ped) then
                DeleteEntity(ped)
            end
        end
        CraftPeds[index] = nil
    end
end

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    cleanupCraftPeds()
end)

CreateThread(function()
    if not Config.CraftLocations or #Config.CraftLocations == 0 then return end

    repeat Wait(2000) until LocalPlayer.state.IsInSession

    for index, loc in ipairs(Config.CraftLocations) do
        spawnCraftPed(loc, index)
    end

    local craftGroup = GetRandomIntInRange(0, 0xffffff)
    local craftPrompt = UiPromptRegisterBegin()
    UiPromptSetControlAction(craftPrompt, 0xCEFD9220)
    UiPromptSetText(craftPrompt, CreateVarString(10, "LITERAL_STRING", "Craft"))
    UiPromptSetEnabled(craftPrompt, true)
    UiPromptSetVisible(craftPrompt, true)
    UiPromptSetHoldMode(craftPrompt, 1000)
    UiPromptSetGroup(craftPrompt, craftGroup, 0)
    UiPromptRegisterEnd(craftPrompt)

    while true do
        local sleep = 1000
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed, true, true)

        for _, loc in ipairs(Config.CraftLocations) do
            local interactCoords = getCraftInteractionCoords(loc)
            local interactDistance = loc.interactDistance or 2.0
            local dist = #(playerCoords - interactCoords)
            if dist <= interactDistance then
                sleep = 0

                local label = CreateVarString(10, "LITERAL_STRING", loc.label or "Craft Station")
                UiPromptSetActiveGroupThisFrame(craftGroup, label, 0, 0, 0, 0)

                if UiPromptHasHoldModeCompleted(craftPrompt) then
                    NUIService.OpenInv()
                    SendNUIMessage({ action = "openCraft" })
                    TriggerServerEvent("vorpinventory:getCraftItems")
                end
                break
            end
        end

        Wait(sleep)
    end
end)


local RepairCore = exports.vorp_core:GetCore()
CreateThread(function()
    local durConfig = Config.WeaponDurability
    if not durConfig or not durConfig.Enabled or not durConfig.RepairLocations or #durConfig.RepairLocations == 0 then return end

    repeat Wait(2000) until LocalPlayer.state.IsInSession

    local repairGroup = GetRandomIntInRange(0, 0xffffff)
    local repairPrompt = UiPromptRegisterBegin()
    UiPromptSetControlAction(repairPrompt, 0xCEFD9220)
    UiPromptSetText(repairPrompt, CreateVarString(10, "LITERAL_STRING", "Repair Weapon"))
    UiPromptSetEnabled(repairPrompt, true)
    UiPromptSetVisible(repairPrompt, true)
    UiPromptSetStandardMode(repairPrompt, true)
    UiPromptSetGroup(repairPrompt, repairGroup, 0)
    UiPromptRegisterEnd(repairPrompt)

    while true do
        local sleep = 1000
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed, true, true)

        for _, loc in ipairs(durConfig.RepairLocations) do
            local dist = #(playerCoords - loc.coord)
            if dist <= 2.0 then
                sleep = 0
                local label = CreateVarString(10, "LITERAL_STRING", "Gunsmith")
                UiPromptSetActiveGroupThisFrame(repairGroup, label, 0, 0, 0, 0)

                if UiPromptHasStandardModeCompleted(repairPrompt, 0) then
                    CreateThread(function()
                        local ped = PlayerPedId()
                        local _, weaponHash = GetCurrentPedWeapon(ped, false, 0, false)
                        if not weaponHash or weaponHash == 0 or weaponHash == `WEAPON_UNARMED` then
                            RepairCore.NotifyRightTip("No weapon in hand", 3000)
                            return
                        end
                        local foundId = nil
                        for id, wp in pairs(UserWeapons) do
                            if wp:getUsed() and joaat(wp:getName()) == weaponHash then
                                foundId = id
                                break
                            end
                        end
                        if not foundId then
                            RepairCore.NotifyRightTip("No weapon found", 3000)
                            return
                        end
                        local weapon = UserWeapons[foundId]
                        if weapon:getDurability() >= 100 then
                            RepairCore.NotifyRightTip(T("weaponFullDurability") or "This weapon doesn't need repair", 3000)
                            return
                        end
                        local repairTime = math.floor((durConfig.MaxRepairTime or 60000) * (1 - weapon:getDurability() / 100))
                        weapon:UnequipWeapon()
                        UserWeapons[foundId] = nil
                        NUIService.LoadInv()
                        local progressbar = exports.vorp_progressbar:initiate()
                        progressbar.start("Repairing...", repairTime, function() end, "linear", "rgb(74, 158, 107)")
                        TriggerServerEvent("vorpinventory:repairWeapon", foundId, repairTime)
                    end)
                end
                break
            end
        end

        Wait(sleep)
    end
end)

CreateThread(function()
    if not Config.UseLanternPutOnBelt then
        return
    end

    repeat Wait(2000) until LocalPlayer.state.IsInSession

    local lastLantern = 0
    while true do
        local pedid = PlayerPedId()
        local weaponHeld <const> = GetPedCurrentHeldWeapon(pedid)
        local isLantern <const> = IsWeaponLantern(weaponHeld) == 1 -- assuming it will return all lanterns to true
        if isLantern then
            lastLantern = weaponHeld
        end

        if lastLantern ~= 0 and not isLantern then
            SetCurrentPedWeapon(pedid, lastLantern, true, 12, false, false)
            lastLantern = 0
        end
        Wait(500)
    end
end)


local StealCore = exports.vorp_core:GetCore()
RegisterCommand("steal", function()
    if InInventory then return end
    if Config.StealRequiresWeapon then
        local ped = PlayerPedId()
        local _, weaponHash = GetCurrentPedWeapon(ped, false, 0, false)
        if not weaponHash or weaponHash == 0 or weaponHash == `WEAPON_UNARMED` then
            StealCore.NotifyRightTip(T("stealNeedWeapon") or "You need a weapon to steal", 3000)
            return
        end
    end
    local nearestPlayers = Utils.getNearestPlayers()
    if #nearestPlayers == 0 then
        StealCore.NotifyRightTip(T("noplayersnearby") or "No players nearby", 3000)
        return
    end
    local closestPlayer = nil
    local closestDist = 999.0
    local myCoords = GetEntityCoords(PlayerPedId(), true, true)
    for _, player in ipairs(nearestPlayers) do
        local targetPed = GetPlayerPed(player)
        local targetCoords = GetEntityCoords(targetPed, true, true)
        local dist = #(targetCoords - myCoords)
        if dist < closestDist then
            closestDist = dist
            closestPlayer = player
        end
    end
    if closestPlayer then
        local targetServerId = GetPlayerServerId(closestPlayer)
        TriggerServerEvent("vorpinventory:stealPlayer", targetServerId)
    end
end, false)

-- Stash prompts
CreateThread(function()
    if not Config.Stashes or #Config.Stashes == 0 then return end

    repeat Wait(2000) until LocalPlayer.state.IsInSession

    local stashGroup = GetRandomIntInRange(0, 0xffffff)
    local stashPrompt = UiPromptRegisterBegin()
    UiPromptSetControlAction(stashPrompt, Config.StashPrompt.Key or 0xCEFD9220)
    UiPromptSetText(stashPrompt, CreateVarString(10, "LITERAL_STRING", "Open Stash"))
    UiPromptSetEnabled(stashPrompt, true)
    UiPromptSetVisible(stashPrompt, true)
    UiPromptSetHoldMode(stashPrompt, Config.StashPrompt.HoldDuration or 500)
    UiPromptSetGroup(stashPrompt, stashGroup, 0)
    UiPromptRegisterEnd(stashPrompt)

    local lastTriggered = 0
    while true do
        local sleep = 1000
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed, true, true)
        local drawDist = Config.StashPrompt.DrawDistance or 2.0

        for _, stash in ipairs(Config.Stashes) do
            local dist = #(playerCoords - stash.coord)
            if dist <= drawDist then
                sleep = 0
                local label = CreateVarString(10, "LITERAL_STRING", stash.name or "Stash")
                UiPromptSetActiveGroupThisFrame(stashGroup, label, 0, 0, 0, 0)

                if UiPromptHasHoldModeCompleted(stashPrompt) and not InInventory and (GetGameTimer() - lastTriggered) > 2000 then
                    lastTriggered = GetGameTimer()
                    TriggerServerEvent("vorpinventory:openStash", stash.id)
                end
                break
            end
        end

        Wait(sleep)
    end
end)

-- DEV: test steal on yourself
if Config.DevMode then
    RegisterCommand("stealself", function()
        if InInventory then return end
        TriggerServerEvent("vorpinventory:stealPlayer", GetPlayerServerId(PlayerId()))
    end, false)
end

CreateThread(function()
    repeat Wait(5000) until LocalPlayer.state.IsInSession
    if not Config.EnablePushToTalk then
        return
    end
    local isNuiFocused = false

    while true do
        local sleep = 0
        if InInventory then
            if not isNuiFocused then
                SetNuiFocusKeepInput(true)
                isNuiFocused = true
            end

            DisableAllControlActions(0)
            EnableControlAction(0, `INPUT_PUSH_TO_TALK`, true)
        else
            sleep = 1000
            if isNuiFocused then
                SetNuiFocusKeepInput(false)
                isNuiFocused = false
            end
        end
        Wait(sleep)
    end
end)
