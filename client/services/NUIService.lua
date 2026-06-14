local isProcessingPay = false
local timerUse = 0
local candrop = true
local cangive = true
local InventoryIsDisabled = false

local Core = exports.vorp_core:GetCore()
StoreSynMenu = false
GenSynInfo = {}
InInventory = false
NUIService = {}
SynPending = false

RegisterNetEvent('inv:dropstatus', function(x)
    candrop = x
end)

RegisterNetEvent('inv:givestatus')
AddEventHandler('inv:givestatus', function(x)
    cangive = x
end)

function NUIService.ReloadInventory(inventory, packed)
    local payload = {}
    if packed then
        payload = msgpack.unpack(packed)
    else
        payload = json.decode(inventory)
    end

    if payload.itemList == '[]' then
        payload.itemList = {}
    end

    for _, item in pairs(payload.itemList) do
        if item.type == "item_weapon" then
            item.label = item.custom_label or Utils.GetWeaponDefaultLabel(item.name)

            if item.desc and item.custom_desc then
                item.desc = item.custom_desc
            end

            if not item.desc then
                item.desc = Utils.GetWeaponDefaultDesc(item.name)
            end
        else
            -- for syn scripts where description wasnt saved
            if not item.desc then
                if not ClientItems[item.name] then
                    print("Item,", item.name, " no longer exist did you delete from database? or name was modified?")
                else
                    item.desc = ClientItems[item.name].desc
                end
            end
        end
    end

    SendNUIMessage(payload)
    Wait(500)
    NUIService.LoadInv()
    SynPending = false
end

local inCustomInventory = false
function NUIService.OpenCustomInventory(name, id, capacity, weight)
    inCustomInventory = true
    DisplayRadar(false)
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "display",
        type = "custom",
        title = tostring(name),
        id = tostring(id),
        capacity = capacity,
        weight = weight
    })
    InInventory = true
end

function NUIService.NUIMoveToCustom(obj)
    TriggerServerEvent("vorp_inventory:MoveToCustom", json.encode(obj))
end

function NUIService.NUITakeFromCustom(obj)
    TriggerServerEvent("vorp_inventory:TakeFromCustom", json.encode(obj))
end

function NUIService.OpenPlayerInventory(name, id, type)
    DisplayRadar(false)
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "display",
        type = type,
        title = name,
        id = id
    })
    InInventory = true
end

function NUIService.NUIMoveToPlayer(obj)
    TriggerServerEvent("vorp_inventory:MoveToPlayer", json.encode(obj))
end

function NUIService.NUITakeFromPlayer(obj)
    TriggerServerEvent("vorp_inventory:TakeFromPlayer", json.encode(obj))
end

function NUIService.TransferLimitExceeded(maxValue)
    local message = string.format(T("MaxItemTransfer"), maxValue.max)
    Core.NotifyRightTip(message, 4000)
end

-- was closed by the client
function NUIService.CloseInv()
    if StoreSynMenu then
        StoreSynMenu = false
        GenSynInfo = {}
        for _, item in pairs(UserInventory) do
            if item.metadata ~= nil and item.metadata.description ~= nil and
                (item.metadata.orgdescription ~= nil or item.metadata.orgdescription == "") then
                if item.metadata.orgdescription == "" then
                    item.metadata.description = nil
                else
                    item.metadata.description = item.metadata.orgdescription
                end
                item.metadata.orgdescription = nil
            end
        end
    end

    DisplayRadar(true)
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = "hide"
    })
    InInventory = false
    TriggerEvent("vorp_stables:setClosedInv", false)
    TriggerEvent("syn:closeinv")
    if inCustomInventory then
        inCustomInventory = false
        TriggerServerEvent("vorp_inventory:Server:CloseCustomInventory")
    end
    -- Unlock drop
    if CurrentDropId then
        TriggerServerEvent("vorpinventory:unlockDrop", CurrentDropId)
        CurrentDropId = nil
    end
end

function NUIService.setProcessingPayFalse()
    isProcessingPay = false
end

function NUIService.NUIUnequipWeapon(obj)
    local data = obj

    if UserWeapons[tonumber(data.id)] then
        UserWeapons[tonumber(data.id)]:UnequipWeapon()
    end

    NUIService.LoadInv()
end

function NUIService.NUIGetNearPlayers(obj)
    local nearestPlayers = Utils.getNearestPlayers()

    local playerIds = {}
    for _, player in ipairs(nearestPlayers) do
        if player ~= PlayerId() then
            local playerId = GetPlayerServerId(player)
            if Config.ShowCharacterNameOnGive then
                local character = Player(playerId).state.Character or {}
                local firstName = character.FirstName or character.firstname or ""
                local lastName = character.LastName or character.lastname or ""
                local name = (tostring(firstName) .. " " .. tostring(lastName)):gsub("^%s+", ""):gsub("%s+$", "")
                if name == "" then
                    name = tostring(playerId)
                end
                playerIds[#playerIds + 1] = {
                    label = name,
                    player = playerId
                }
            else
                playerIds[#playerIds + 1] = {
                    label = playerId,
                    player = playerId
                }
            end
        end
    end
    if #playerIds > 0 then
        NUIService.NUISetNearPlayers(obj, playerIds)
    else
        Core.NotifyRightTip(T("noplayersnearby"), 5000)
    end
end

function NUIService.NUISetNearPlayers(obj, nearestPlayers)
    local nuiReturn = {}

    nuiReturn.action = "nearPlayers"
    nuiReturn.foundAny = true
    nuiReturn.players = nearestPlayers
    nuiReturn.item = obj.item
    nuiReturn.hash = obj.hash or 1
    nuiReturn.count = obj.count or 1
    nuiReturn.id = obj.id or 0
    nuiReturn.type = obj.type
    nuiReturn.what = obj.what
    SendNUIMessage(nuiReturn)
end

function NUIService.NUIGiveItem(obj)
    if not cangive then
        return Core.NotifyRightTip(T("cantgivehere"), 5000)
    end

    local nearestPlayers = Utils.getNearestPlayers()
    local data = obj
    local data2 = data.data
    local isvalid = Validator.IsValidNuiCallback(data.hsn)

    if isvalid then
        for _, player in ipairs(nearestPlayers) do
            if GetPlayerServerId(player) == tonumber(data.player) then
                local itemId = data2.id
                local target = tonumber(data.player)

                if data2.type == "item_money" then
                    if isProcessingPay then
                        return
                    end
                    isProcessingPay = true
                    TriggerServerEvent("vorpinventory:giveMoneyToPlayer", target, tonumber(data2.count))
                elseif Config.UseGoldItem and data2.type == "item_gold" then
                    if isProcessingPay then
                        return
                    end
                    isProcessingPay = true
                    TriggerServerEvent("vorpinventory:giveGoldToPlayer", target, tonumber(data2.count))
                elseif data2.type == "item_ammo" then
                    if isProcessingPay then
                        return
                    end
                    isProcessingPay = true
                    local amount = tonumber(data2.count)
                    local ammotype = data2.item
                    local maxcount = SharedData.MaxAmmo[ammotype]
                    if amount > 0 and maxcount >= amount then
                        TriggerServerEvent("vorpinventory:servergiveammo", ammotype, amount, target, maxcount)
                    end
                elseif data2.type == "item_standard" then
                    local amount = tonumber(data2.count)
                    local item = UserInventory[itemId]

                    if amount > 0 and item ~= nil and item:getCount() >= amount then
                        TriggerServerEvent("vorpinventory:serverGiveItem", itemId, amount, target)
                    end
                else
                    TriggerServerEvent("vorpinventory:serverGiveWeapon", tonumber(itemId), target)
                end

                NUIService.LoadInv()
            end
        end
    end
end

pendingDropSlot = nil

function NUIService.NUIDropItem(obj)
    if not candrop then
        return Core.NotifyRightTip(T("cantdrophere"), 5000)
    end

    local aux = Utils.expandoProcessing(obj)
    local isvalid = Validator.IsValidNuiCallback(aux.hsn)

    if isvalid then
        pendingDropSlot = aux.targetSlot
        local itemName = aux.item
        local itemId = aux.id
        local metadata = aux.metadata
        local type = aux.type
        local qty = tonumber(aux.number)
        local degradation = aux.degradation
        print("[vorp_inventory] NUIDropItem: type=" .. tostring(type) .. " qty=" .. tostring(qty) .. " item=" ..
                  tostring(itemName))
        if type == "item_money" then
            pendingDropSlot = aux.targetSlot
            TriggerServerEvent("vorpinventory:serverDropMoney", qty)
        end

        if type == "item_gold" then
            print("[vorp_inventory] DropGold: qty=" .. tostring(qty) .. " targetSlot=" .. tostring(aux.targetSlot))
            pendingDropSlot = aux.targetSlot
            TriggerServerEvent("vorpinventory:serverDropGold", qty)
        end

        if type == "item_standard" then
            if aux.number ~= nil and aux.number ~= '' then
                local item = UserInventory[itemId]
                if not item then
                    return
                end

                if qty <= 0 or qty > item:getCount() then
                    return
                end

                TriggerServerEvent("vorpinventory:serverDropItem", itemName, itemId, qty, metadata, degradation)
            end
        end

        if type == "item_weapon" then
            TriggerServerEvent("vorpinventory:serverDropWeapon", aux.id)

            if UserWeapons[aux.id] then
                local weapon = UserWeapons[aux.id]

                if weapon:getUsed() then
                    weapon:setUsed(false)
                    weapon:UnequipWeapon()
                end

                UserWeapons[aux.id] = nil
            end
        end
        SetTimeout(100, function()
            NUIService.LoadInv()
        end)
    end
end

local function getGuidFromItemId(inventoryId, itemData, category, slotId)
    local outItem = DataView.ArrayBuffer(8 * 13)

    if not itemData then
        itemData = 0
    end
    -- InventoryGetGuidFromItemid
    local success = Citizen.InvokeNative(0x886DFD3E185C8A89, inventoryId, itemData, category, slotId, outItem:Buffer())
    if success then
        return outItem:Buffer() -- Seems to not return anythign diff. May need to pull from native above
    else
        return nil
    end
end

local function addWardrobeInventoryItem(itemName, slotHash)
    local itemHash = joaat(itemName)
    local addReason = joaat("ADD_REASON_DEFAULT")
    local inventoryId = 1

    -- _ITEMDATABASE_IS_KEY_VALID
    local isValid = Citizen.InvokeNative(0x6D5D51B188333FD1, itemHash, 0) -- ItemdatabaseIsKeyValid
    if not isValid then
        return false
    end

    local characterItem = getGuidFromItemId(inventoryId, nil, joaat("CHARACTER"), 0xA1212100)
    if not characterItem then
        return false
    end

    local wardrobeItem = getGuidFromItemId(inventoryId, characterItem, joaat("WARDROBE"), 0x3DABBFA7)
    if not wardrobeItem then
        return false
    end

    local itemData = DataView.ArrayBuffer(8 * 13)

    -- _INVENTORY_ADD_ITEM_WITH_GUID
    local isAdded = Citizen.InvokeNative(0xCB5D11F9508A928D, inventoryId, itemData:Buffer(), wardrobeItem, itemHash,
        slotHash, 1, addReason)
    if not isAdded then
        return false
    end

    -- _INVENTORY_EQUIP_ITEM_WITH_GUID
    local equipped = Citizen.InvokeNative(0x734311E2852760D0, inventoryId, itemData:Buffer(), true)
    return equipped;
end

local function hasOtherUsedOneHandedWeapon(currentWeaponId)
    for _, weapon in pairs(UserWeapons) do
        if tonumber(weapon:getId()) ~= currentWeaponId and (weapon:getUsed() or weapon:getUsed2()) then
            local otherHash = joaat(weapon:getName())
            if Citizen.InvokeNative(0x705BE297EEBDB95D, otherHash) and
                Citizen.InvokeNative(0xD955FEE4B87AFA07, otherHash) then
                return true
            end
        end
    end
    return false
end

local function useWeapon(data)
    data.type = data.type or "item_weapon"
    local ped = PlayerPedId()
    local _, weaponHash = GetCurrentPedWeapon(ped, false, 0, false)
    local weaponId = tonumber(data.id)

    if not weaponId or not UserWeapons[weaponId] then
        return print("Weapon not found")
    end
    -- Durability check: weapon cannot be used if durability is 0
    if Config.WeaponDurability and Config.WeaponDurability.Enabled and UserWeapons[weaponId]:getDurability() <= 0 then
        Core.NotifyRightTip(T("weaponBroken") or "This weapon is broken", 3000)
        return
    end
    local weapName = joaat(UserWeapons[weaponId]:getName())
    local weaponGroup = GetWeapontypeGroup(weapName)
    local isWeaponBow = weaponGroup == joaat("GROUP_BOW")
    local isWeaponAGun = Citizen.InvokeNative(0x705BE297EEBDB95D, weapName)
    local isWeaponOneHanded = Citizen.InvokeNative(0xD955FEE4B87AFA07, weapName)
    local isLasso = weapName == WEAPON_LASSO or weapName == WEAPON_LASSO_REINFORCED
    local hasCurrentWeapon = weaponHash and weaponHash ~= 0 and weaponHash ~= WEAPON_UNARMED
    local notdual = false
    local canOneHandDualWield = isWeaponAGun and isWeaponOneHanded and not isLasso
    local hasOtherDualWeapon = canOneHandDualWield and hasOtherUsedOneHandedWeapon(weaponId)
    local isWeaponThrowable = Citizen.InvokeNative(0x30E7C16B12DA8211, weapName)
    local shouldEquipWeapon = not UserWeapons[weaponId]:getUsed()
    if canOneHandDualWield and hasCurrentWeapon and not Config.DuelWield then
        return
    elseif canOneHandDualWield and Config.DuelWield and not UserWeapons[weaponId]:getUsed() then
        addWardrobeInventoryItem("CLOTHING_ITEM_M_OFFHAND_000_TINT_004", 0xF20B6B4A)
        addWardrobeInventoryItem("UPGRADE_OFFHAND_HOLSTER", 0x39E57B01)

        if (hasCurrentWeapon and weaponHash ~= weapName) or hasOtherDualWeapon then
            UserWeapons[weaponId].used2 = true
        end

        UserWeapons[weaponId]:equipwep()
        UserWeapons[weaponId]:loadComponents()
        UserWeapons[weaponId]:setUsed(true)
        TriggerServerEvent("syn_weapons:weaponused", data)
    elseif shouldEquipWeapon then
        notdual = true
    end

    if notdual then
        UserWeapons[weaponId]:equipwep()
        UserWeapons[weaponId]:loadComponents()
        UserWeapons[weaponId]:setUsed(true)
        TriggerServerEvent("syn_weapons:weaponused", data)
    end

    if UserWeapons[weaponId]:getUsed() then
        local serial = UserWeapons[weaponId]:getSerialNumber()
        local info = {
            weaponId = weaponId,
            serialNumber = serial
        }
        local key = string.format("GetEquippedWeaponData_%d", weapName)
        LocalPlayer.state:set(key, info, true)

        -- Restore ammo to ped from weapon's own ammo first, then from player ammo cache
        local weaponAmmo = UserWeapons[weaponId]:getAllAmmo() or {}
        for type, amount in pairs(weaponAmmo) do
            if amount and amount > 0 and not isWeaponBow then
                SetPedAmmoByType(ped, joaat(type), amount)
            end
        end
        if PlayerAmmoInfo and PlayerAmmoInfo.ammo then
            local ammotypes = SharedData.AmmoTypes and SharedData.AmmoTypes[weaponGroup]
            if ammotypes then
                for ammo_name, _ in pairs(ammotypes) do
                    local qty = PlayerAmmoInfo.ammo[ammo_name]
                    if qty and qty > 0 and (isWeaponBow or not weaponAmmo[ammo_name] or weaponAmmo[ammo_name] == 0) then
                        SetPedAmmoByType(ped, joaat(ammo_name), qty)
                    end
                end
            end
        end
    end
    TriggerServerEvent("vorpinventory:setUsedWeapon", weaponId, UserWeapons[weaponId]:getUsed(),
        UserWeapons[weaponId]:getUsed2())

    NUIService.LoadInv()
end

exports("useWeapon", useWeapon)

local function useItem(data)
    if timerUse <= 0 then
        TriggerServerEvent("vorp_inventory:useItem", data)
        timerUse = Config.SpamDelay
    else
        Core.NotifyRightTip(T("slow"), 5000)
    end
end

function NUIService.NUIUseItem(data)
    if data.type == "item_standard" then
        useItem(data)
    elseif data.type == "item_weapon" then
        useWeapon(data)
        local weaponId = tonumber(data.id)
        if weaponId and UserWeapons[weaponId] then
            local weapon = UserWeapons[weaponId]
            SendNUIMessage({
                action = "itemNotification",
                ["type"] = "used",
                name = weapon:getName(),
                label = weapon:getLabel(),
                count = 1
            })
        end
    end
end

exports("useItem", useItem) -- not tested yet

function NUIService.SetWornClothing(worn)
    SendNUIMessage({
        action = "setWornClothing",
        worn = worn or {}
    })
end

exports("setWornClothing", NUIService.SetWornClothing)
RegisterNetEvent("vorp_inventory:setWornClothing", NUIService.SetWornClothing)

RegisterCommand("setworn", function(args)
    local slot = args[1]
    if slot then
        local worn = {}
        worn[slot] = true
        NUIService.SetWornClothing(worn)
    end
end, false)

function NUIService.NUISound()
    if Config.SFX.ItemHover then
        PlaySoundFrontend("BACK", "RDRO_Character_Creator_Sounds", true, 0)
    end
end

function NUIService.NUIFocusOff()
    DisplayRadar(true)
    if Config.SFX.CloseInventory then
        PlaySoundFrontend("SELECT", "RDRO_Character_Creator_Sounds", true, 0)
    end
    NUIService.CloseInv()
end

local function loadItems()
    local items = {}
    if not StoreSynMenu then
        for id, item in pairs(UserInventory) do
            table.insert(items, item)
        end
    elseif StoreSynMenu then
        for _, item in pairs(UserInventory) do
            if item.metadata ~= nil and item.metadata.orgdescription ~= nil then
                item.metadata.description = item.metadata.orgdescription
                item.metadata.orgdescription = nil
            end
        end

        local buyitems = GenSynInfo.buyitems
        if buyitems and next(buyitems) then
            for _, item in pairs(UserInventory) do
                for k, v in ipairs(buyitems) do
                    if item.name == v.name then
                        item.metadata = item.metadata or {}
                        if item.metadata.orgdescription == nil then
                            if item.metadata.description ~= nil then
                                item.metadata.orgdescription = item.metadata.description
                            else
                                item.metadata.orgdescription = ""
                            end
                        else
                        end
                        item.metadata.description = T("cansell") .. "<span style=color:Green;>" .. v.price .. "</span>"
                    end
                end
                table.insert(items, item)
            end
        else
            for _, item in pairs(UserInventory) do
                table.insert(items, item)
            end
        end
    end
    return items
end

local function loadWeapons()
    local weapons = {}
    for _, currentWeapon in pairs(UserWeapons) do
        local weapon = {}
        weapon.count = currentWeapon:getTotalAmmoCount()
        weapon.limit = -1
        weapon.label = currentWeapon:getLabel()
        weapon.name = currentWeapon:getName()
        weapon.metadata = {}
        weapon.hash = GetHashKey(currentWeapon:getName())
        weapon.type = "item_weapon"
        weapon.canUse = true
        weapon.canRemove = true
        weapon.id = currentWeapon:getId()
        weapon.used = currentWeapon:getUsed()
        weapon.used2 = currentWeapon:getUsed2()
        weapon.desc = currentWeapon:getDesc()
        weapon.group = 5
        weapon.serial_number = currentWeapon:getSerialNumber()
        weapon.custom_label = currentWeapon:getCustomLabel()
        weapon.custom_desc = currentWeapon:getCustomDesc()
        weapon.custom_label = currentWeapon:getCustomLabel()
        weapon.weight = currentWeapon:getWeight()
        weapon.slot = currentWeapon:getSlot()
        weapon.ammo_total = currentWeapon:getAmmoTotal()
        weapon.durability = currentWeapon:getDurability()
        weapon.comps = currentWeapon:getComps()
        weapon.ammo = currentWeapon:getAllAmmo() or {}
        weapon.ammoAllowed = {}

        local weaponHash = joaat(currentWeapon:getName())
        local weaponGroup = GetWeapontypeGroup(weaponHash)
        local ammoTypes = SharedData.AmmoTypes and SharedData.AmmoTypes[weaponGroup]

        if ammoTypes then
            for ammoName, _ in pairs(ammoTypes) do
                local beltAmount = PlayerAmmoInfo and PlayerAmmoInfo.ammo and PlayerAmmoInfo.ammo[ammoName] or 0
                local weaponAmount = currentWeapon:getAmmo(ammoName) or 0

                if beltAmount > 0 or weaponAmount > 0 then
                    table.insert(weapon.ammoAllowed, ammoName)
                end
            end
        end

        local _, currentPedWeapon = GetCurrentPedWeapon(PlayerPedId(), false, 0, false)
        if currentPedWeapon == weaponHash then
            local weaponObject = GetPedWeaponObject(PlayerPedId(), true)
            local currentAmmoHash = weaponObject and GetCurrentPedWeaponAmmoType(PlayerPedId(), weaponObject)
            if currentAmmoHash and ammoTypes then
                for ammoName, _ in pairs(ammoTypes) do
                    if joaat(ammoName) == currentAmmoHash then
                        weapon.currentAmmoType = ammoName
                        break
                    end
                end
            end
        end

        table.insert(weapons, weapon)
    end
    return weapons
end

local function loadItemsAndWeapons()
    local itemsToSend = {}
    local items = loadItems()
    local weapons = loadWeapons()

    if Config.InventoryOrder == "items" then
        for _, item in pairs(items) do
            table.insert(itemsToSend, item)
        end
        for _, weapon in pairs(weapons) do
            table.insert(itemsToSend, weapon)
        end
    else
        for _, weapon in pairs(weapons) do
            table.insert(itemsToSend, weapon)
        end
        for _, item in pairs(items) do
            table.insert(itemsToSend, item)
        end
    end

    return itemsToSend
end

function NUIService.LoadInv()
    local payload<const> = {}

    Core.Callback.TriggerAsync("vorpinventory:get_slots", function(result)
        if not result then
            return
        end

        SendNUIMessage({
            action = "changecheck",
            check = string.format("%.1f", (result.totalInvWeight or 0)),
            info = string.format("%.1f", (result.slots or 0))
        })
        SendNUIMessage({
            action = "updateStatusHud",
            show = not IsRadarHidden(),
            money = result.money,
            gold = result.gold,
            rol = result.rol,
            id = GetPlayerServerId(PlayerId()),
            charName = result.charName
        })
    end)

    local itemsAndWeapons = loadItemsAndWeapons()
    payload.action = "setItems"
    payload.itemList = itemsAndWeapons
    payload.timenow = GlobalState.TimeNow
    SendNUIMessage(payload)
end

function NUIService.UseHotbarSlot(slotNum)
    local allItems = loadItemsAndWeapons()

    -- Assign slots for items without slot (same logic as NUI assignSlots)
    local usedSlots = {}
    for _, item in ipairs(allItems) do
        if item.slot then
            usedSlots[item.slot] = true
        end
    end
    local nextSlot = 1
    for _, item in ipairs(allItems) do
        if not item.slot then
            while usedSlots[nextSlot] do
                nextSlot = nextSlot + 1
            end
            item.slot = nextSlot
            usedSlots[nextSlot] = true
        end
    end

    -- Find item at slot
    for _, item in ipairs(allItems) do
        if item.slot == slotNum then
            local data = {
                item = item.name,
                type = item.type,
                id = item.id,
                amount = item.count or 1,
                hash = item.hash or GetHashKey(item.name)
            }
            if item.type == "item_weapon" then
                if item.used or item.used2 then
                    NUIService.NUIUnequipWeapon(data)
                else
                    NUIService.NUIUseItem(data)
                end
            elseif item.type == "item_standard" then
                useItem(data)
            end
            return
        end
    end
end

function NUIService.HolsterHotbarSlot(slotNum)
    local allItems = loadItemsAndWeapons()

    local usedSlots = {}
    for _, item in ipairs(allItems) do
        if item.slot then
            usedSlots[item.slot] = true
        end
    end
    local nextSlot = 1
    for _, item in ipairs(allItems) do
        if not item.slot then
            while usedSlots[nextSlot] do
                nextSlot = nextSlot + 1
            end
            item.slot = nextSlot
            usedSlots[nextSlot] = true
        end
    end

    for _, item in ipairs(allItems) do
        if item.slot == slotNum and item.type == "item_weapon" then
            local weaponId = tonumber(item.id)
            local weapon = weaponId and UserWeapons[weaponId]
            if not weapon or not (weapon:getUsed() or weapon:getUsed2()) then
                return
            end

            local ped = PlayerPedId()
            local weaponHash = joaat(weapon:getName())
            local _, currentWeapon = GetCurrentPedWeapon(ped, false, 0, false)
            if currentWeapon == weaponHash then
                SetCurrentPedWeapon(ped, WEAPON_UNARMED, true, 0, false, false)
            else
                SetCurrentPedWeapon(ped, weaponHash, false, 0, false, false)
            end
            return
        end
    end
end

function NUIService.SendHotbarItems()
    local itemsAndWeapons = loadItemsAndWeapons()
    SendNUIMessage({
        action = "setHotbarItems",
        itemList = itemsAndWeapons,
        timenow = GlobalState.TimeNow
    })
end

function NUIService.OpenInv()
    DisplayRadar(false)
    if Config.SFX.OpenInventory then
        PlaySoundFrontend("SELECT", "RDRO_Character_Creator_Sounds", true, 0)
    end
    -- Open inventory animation
    if Config.OpenInventoryAnimation and Config.OpenInventoryAnimation.Enabled then
        CreateThread(function()
            local ped = PlayerPedId()
            local dict = Config.OpenInventoryAnimation.Dict
            local anim = Config.OpenInventoryAnimation.Anim
            RequestAnimDict(dict)
            local timeout = 0
            while not HasAnimDictLoaded(dict) and timeout < 1000 do
                Wait(10)
                timeout = timeout + 10
            end
            if HasAnimDictLoaded(dict) then
                TaskPlayAnim(ped, dict, anim, 4.0, -4.0, -1, 0, 0, false, false, false)
                Wait(1500)
                ClearPedTasks(ped)
            end
        end)
    end
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "display",
        type = "main"
    })
    InInventory = true -- internal
    NUIService.LoadInv()
    PickupsService.sendNearbyDropsToNUI()
end

function NUIService.TransactionStarted()
    SetNuiFocus(true, false)
    SendNUIMessage({
        action = "transaction",
        type = "started",
        text = T("TransactionLoading")
    })
end

function NUIService.TransactionComplete(keepInventoryOpen)
    keepInventoryOpen = keepInventoryOpen == nil and true or keepInventoryOpen
    SetNuiFocus(keepInventoryOpen, keepInventoryOpen)
    SendNUIMessage({
        action = "transaction",
        type = "completed"
    })
end

function NUIService.initiateData()
    -- Add Locales
    SendNUIMessage({
        action = "initiate",
        language = {
            empty = T("emptyammo"),
            prompttitle = T("prompttitle"),
            prompttitle2 = T("prompttitle2"),
            promptaccept = T("promptaccept"),
            inventoryclose = T("inventoryclose"),
            inventorysearch = T("inventorysearch"),
            toplayerpromptitle = T("toplayerpromptitle"),
            toplaterpromptaccept = T("toplaterpromptaccept"),
            gunbeltlabel = T("gunbeltlabel"),
            gunbeltdescription = T("gunbeltdescription"),
            inventorymoneylabel = T("inventorymoneylabel"),
            inventorymoneydescription = T("inventorymoneydescription"),
            givemoney = T("givemoney"),
            dropmoney = T("dropmoney"),
            inventorygoldlabel = T("inventorygoldlabel"),
            inventorygolddescription = T("inventorygolddescription"),
            givegold = T("givegold"),
            dropgold = T("dropgold"),
            unequip = T("unequip"),
            equip = T("equip"),
            use = T("use"),
            give = T("give"),
            drop = T("drop"),
            copyserial = T("copyserial"),
            labels = T("labels"),
            ui = T("ui")
        },
        config = {
            UseGoldItem = Config.UseGoldItem,
            AddGoldItem = Config.AddGoldItem,
            AddDollarItem = Config.AddDollarItem,
            AddAmmoItem = Config.AddAmmoItem,
            DoubleClickToUse = Config.DoubleClickToUse,
            UseRolItem = Config.UseRolItem,
            WeightMeasure = Config.WeightMeasure or "Kg",
            DropInventory = Config.DropInventory or {
                MaxWeight = 100.0,
                Slots = 25
            },
            PlayerInventorySlots = Config.PlayerInventorySlots or 25,
            ShowCharacterNameInTitle = Config.ShowCharacterNameInTitle or false,
            ContextMenuActions = Config.ContextMenuActions or {
                Enabled = false
            }
        }
    })
end

local blockInventory = false

CreateThread(function()
    local controlVar = false -- best to use variable than to check statebag every frame

    repeat
        Wait(2000)
    until LocalPlayer.state.IsInSession
    NUIService.initiateData()

    while true do
        local sleep = 1000
        if not InInventory and not blockInventory then
            sleep = 0
            if IsControlJustReleased(1, Config.OpenKey) then
                local player = PlayerPedId()
                local hogtied = IsPedHogtied(player) == 1
                local cuffed = IsPedCuffed(player)
                if not hogtied and not cuffed and not InventoryIsDisabled then
                    NUIService.OpenInv()
                end
            end
        end

        if Config.DisableDeathInventory then
            if InInventory and IsPedDeadOrDying(PlayerPedId(), false) then
                NUIService.CloseInv()
            end
        end

        if InInventory then
            if not controlVar then
                controlVar = true
                LocalPlayer.state:set("IsInvActive", true, true) -- can also listen for statebag change
                TriggerEvent("vorp_inventory:Client:OnInvStateChange", true)
            end
        else
            if controlVar then
                controlVar = false
                LocalPlayer.state:set("IsInvActive", false, true)
                TriggerEvent("vorp_inventory:Client:OnInvStateChange", false)
            end
        end

        Wait(sleep)
    end
end)

-- prevent player from opening inventory from server or client
RegisterNetEvent("vorp_inventory:blockInventory")
AddEventHandler("vorp_inventory:blockInventory", function(state)
    blockInventory = state
    if InInventory then
        NUIService.CloseInv()
    end
end)

-- Prevent Spam
CreateThread(function()
    repeat
        Wait(2000)
    until LocalPlayer.state.IsInSession
    while true do
        Wait(1000)
        if timerUse > 0 then
            timerUse = timerUse - 1000
        end
    end
end)

function NUIService.NUIPickupFromDrop(data, cb)
    if not data then
        if cb then
            cb('ok')
        end
        return
    end
    TriggerServerEvent("vorpinventory:pickupFromDrop", data.dropId, data.fromSlot, data.targetSlot, data.amount,
        data.name, data.type, data.isMoney, data.isGold, data.uuid, data.uids)
    if cb then
        cb('ok')
    end
end

-- Craft callbacks
function NUIService.NUICraftAddItem(data, cb)
    if not data then
        if cb then
            cb('ok')
        end
        return
    end
    TriggerServerEvent("vorpinventory:craftAddItem", data.itemId, data.amount, data.targetSlot)
    if cb then
        cb('ok')
    end
end

function NUIService.NUICraftRemoveItem(data, cb)
    if not data then
        if cb then
            cb('ok')
        end
        return
    end
    TriggerServerEvent("vorpinventory:craftRemoveItem", data.fromSlot, data.amount, data.targetSlot)
    if cb then
        cb('ok')
    end
end

function NUIService.NUICraftSwapSlot(data, cb)
    if not data then
        if cb then
            cb('ok')
        end
        return
    end
    TriggerServerEvent("vorpinventory:craftSwapSlot", data.fromSlot, data.toSlot)
    if cb then
        cb('ok')
    end
end

function NUIService.NUICraftMergeSlot(data, cb)
    if not data then
        if cb then
            cb('ok')
        end
        return
    end
    TriggerServerEvent("vorpinventory:craftMergeSlot", data.fromSlot, data.toSlot, data.amount)
    if cb then
        cb('ok')
    end
end

function NUIService.NUICraftSplitSlot(data, cb)
    if not data then
        if cb then
            cb('ok')
        end
        return
    end
    TriggerServerEvent("vorpinventory:craftSplitSlot", data.fromSlot, data.toSlot, data.amount)
    if cb then
        cb('ok')
    end
end

function NUIService.NUIStartCraft(data, cb)
    if not data then
        if cb then
            cb('ok')
        end
        return
    end
    TriggerServerEvent("vorpinventory:startCraft", data.rewardName, data.amount or 1)
    if cb then
        cb('ok')
    end
end

-- Craft events from server
RegisterNetEvent("vorpInventory:setCraftItems", function(items, recipeData)
    SendNUIMessage({
        action = "setCraftItems",
        items = items,
        recipe = recipeData
    })
end)

RegisterNetEvent("vorpInventory:craftStarted", function(timer)
    SendNUIMessage({
        action = "craftStarted",
        timer = timer
    })
end)

RegisterNetEvent("vorpInventory:craftCompleted", function(rewardName)
    SendNUIMessage({
        action = "craftCompleted",
        rewardName = rewardName
    })
end)

RegisterNetEvent("vorpInventory:itemNotify", function(nType, name, label, count)
    SendNUIMessage({
        action = "itemNotification",
        ["type"] = nType,
        name = name,
        label = label,
        count = count
    })
end)

RegisterNetEvent("vorpInventory:usedNotification", function(name, label)
    SendNUIMessage({
        action = "itemNotification",
        ["type"] = "used",
        name = name,
        label = label,
        count = 1
    })
end)

function NUIService.NUISecondSwapSlot(data, cb)
    if not data then
        if cb then
            cb('ok')
        end
        return
    end
    TriggerServerEvent("vorpinventory:secondSwapSlot", data.invId, data.fromSlot, data.toSlot)
    if cb then
        cb('ok')
    end
end

function NUIService.NUISecondMergeSlot(data, cb)
    if not data then
        if cb then
            cb('ok')
        end
        return
    end
    TriggerServerEvent("vorpinventory:secondMergeSlot", data.invId, data.fromSlot, data.toSlot, data.amount)
    if cb then
        cb('ok')
    end
end

function NUIService.NUISecondSplitSlot(data, cb)
    if not data then
        if cb then
            cb('ok')
        end
        return
    end
    TriggerServerEvent("vorpinventory:secondSplitSlot", data.invId, data.fromSlot, data.toSlot, data.amount)
    if cb then
        cb('ok')
    end
end

function NUIService.NUIDropSwapSlot(data, cb)
    if not data then
        if cb then
            cb('ok')
        end
        return
    end
    TriggerServerEvent("vorpinventory:dropSwapSlot", data.dropId, data.fromSlot, data.toSlot)
    if cb then
        cb('ok')
    end
end

function NUIService.NUIDropMergeSlot(data, cb)
    if not data then
        if cb then
            cb('ok')
        end
        return
    end
    TriggerServerEvent("vorpinventory:dropMergeSlot", data.dropId, data.fromSlot, data.toSlot, data.amount)
    if cb then
        cb('ok')
    end
end

function NUIService.NUIDropSplitSlot(data, cb)
    if not data then
        if cb then
            cb('ok')
        end
        return
    end
    TriggerServerEvent("vorpinventory:dropSplitSlot", data.dropId, data.fromSlot, data.toSlot, data.amount)
    if cb then
        cb('ok')
    end
end

function NUIService.NUIMergeSlots(data, cb)
    if not data then
        return cb('ok')
    end
    TriggerServerEvent("vorpinventory:mergeSlots", data.fromId, data.toId, data.amount)
    if cb then
        cb('ok')
    end
end

function NUIService.NUISplitSlot(data, cb)
    if not data then
        if cb then
            cb('ok')
        end
        return
    end
    TriggerServerEvent("vorpinventory:splitSlot", data.itemId, data.fromSlot, data.toSlot, data.amount)
    if cb then
        cb('ok')
    end
end

function NUIService.NUIUpdateSlot(data, cb)
    if not data then
        if cb then
            cb('ok')
        end
        return
    end
    if data.itemId and data.slot then
        local id = tonumber(data.itemId)
        if data.itemType == "item_weapon" then
            if id and UserWeapons[id] then
                if UserWeapons[id]:getUsed() or UserWeapons[id]:getUsed2() then
                    if cb then
                        cb('ok')
                    end
                    return
                end
                UserWeapons[id]:setSlot(data.slot)
            end
        else
            if id and UserInventory[id] then
                UserInventory[id]:setSlot(data.slot)
            end
        end
        TriggerServerEvent("vorpinventory:updateSlot", data.itemId, data.slot, data.itemType)
    end
    if cb then
        cb('ok')
    end
end

function NUIService.ChangeClothing(item)
    if item then
        ExecuteCommand(tostring(item))
    end
end

function NUIService.DisableInventory(param)
    InventoryIsDisabled = param
end

function NUIService.getActionsConfig(_, cb)
    cb(Actions)
end

function NUIService.CacheImages(info)
    local unpack = msgpack.unpack(info)
    SendNUIMessage({
        action = "cacheImages",
        info = unpack
    })
end

function NUIService.ContextMenu(data)
    if not data then
        return
    end

    if data.close then
        NUIService.CloseInv()
    end

    if data.event.client then
        TriggerEvent(data.event.client, data.event.arguments, data.itemid)
    elseif data.event.server then
        TriggerServerEvent(data.event.server, data.event.arguments, data.itemid)
    end
end
