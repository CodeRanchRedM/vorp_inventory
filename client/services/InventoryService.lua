ClientItems = {}
InventoryService = {}
UserWeapons = {}
UserInventory = {}
local loadoutInitialized = false

function findNextFreeSlot()
    local usedSlots = {}
    for _, item in pairs(UserInventory) do
        if item:getSlot() then
            usedSlots[item:getSlot()] = true
        end
    end
    for _, weapon in pairs(UserWeapons) do
        if weapon:getSlot() then
            usedSlots[weapon:getSlot()] = true
        end
    end
    local slot = 1
    while usedSlots[slot] do
        slot = slot + 1
    end
    return slot
end

local function giveWeaponToPedForWheel(weaponName, ammoTotal)
    if not Config.WeaponWheel or not Config.WeaponWheel.Enabled then
        return
    end
    if not weaponName or weaponName == "" then
        return
    end
    local ped = PlayerPedId()
    if not ped or ped == 0 then
        return
    end
    local hash = joaat(weaponName)
    if Citizen.InvokeNative(0x8DECB02F88F428BC, ped, hash, 0, true) then
        return
    end
    GiveWeaponToPed(ped, hash, ammoTotal or 0, true, false)
end

function InventoryService.receiveItem(name, id, amount, metadata, degradation, percentage)
    if not name or not ClientItems[name] then
        return
    end

    if UserInventory[id] ~= nil then
        UserInventory[id]:addCount(amount)
    else
        local freeSlot = findNextFreeSlot()
        UserInventory[id] = Item:New({
            id = id,
            count = amount,
            limit = ClientItems[name].limit,
            label = ClientItems[name].label,
            name = name,
            metadata = SharedUtils.MergeTables(ClientItems[name].metadata, metadata),
            type = "item_standard",
            canUse = true,
            canRemove = ClientItems[name].canRemove,
            desc = ClientItems[name].desc,
            group = ClientItems[name].group or 1,
            weight = ClientItems[name].weight or 0.25,
            degradation = degradation,
            maxDegradation = ClientItems[name].maxDegradation,
            percentage = percentage,
            slot = freeSlot
        })
    end
    NUIService.LoadInv()
    SendNUIMessage({
        action = "itemNotification",
        ["type"] = "add",
        name = name,
        label = ClientItems[name].label,
        count = amount
    })
end

function InventoryService.removeItem(name, id, count)
    local item = UserInventory[id]
    if not item then
        return
    end

    local label = item:getLabel()
    item:quitCount(count)

    if item:getCount() <= 0 then
        UserInventory[id] = nil
    end

    NUIService.LoadInv()
    SendNUIMessage({
        action = "itemNotification",
        ["type"] = "remove",
        name = name,
        label = label,
        count = count
    })
end

function InventoryService.receiveWeapon(id, propietary, name, ammos, label, serial_number, custom_label, source,
    custom_desc, weight, slot, ammo_total, durability)
    local weaponAmmo = {}

    for type, amount in pairs(ammos) do
        weaponAmmo[type] = tonumber(amount)
    end

    if not UserWeapons[id] then
        local newWeapon = Weapon:New({
            id = id,
            propietary = propietary,
            name = name,
            label = custom_label or label,
            ammo = weaponAmmo,
            used = false,
            used2 = false,
            desc = custom_desc or Utils.GetWeaponDefaultDesc(name),
            group = 5,
            source = source,
            serial_number = serial_number,
            custom_label = custom_label,
            custom_desc = custom_desc,
            weight = weight,
            slot = slot,
            ammo_total = ammo_total or 0,
            durability = durability or 100
        })
        UserWeapons[newWeapon:getId()] = newWeapon
        giveWeaponToPedForWheel(name, ammo_total)
        NUIService.LoadInv()
    end
end

function InventoryService.setWeaponCustomLabel(id, label)
    if UserWeapons[id] then
        UserWeapons[id]:setCustomLabel(label)
    end
end

function InventoryService.setWeaponCustomDesc(id, desc)
    if UserWeapons[id] then
        UserWeapons[id]:setCustomDesc(desc)
    end
end

function InventoryService.setWeaponSerialNumber(id, serial_number)
    if UserWeapons[id] then
        UserWeapons[id]:setSerialNumber(serial_number)
    end
end

function InventoryService.onSelectedCharacter()
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = "hide"
    })
    print("Loading Inventory")
    TriggerServerEvent("vorpinventory:getItemsTable")
    Wait(300)
    TriggerServerEvent("vorpinventory:getInventory")
    Wait(1000)
    TriggerServerEvent("vorpCore:LoadAllAmmo")
    Wait(1000)
    print("ammo loaded")
    TriggerEvent("vorpinventory:loaded")
end

function InventoryService.processItems(items)
    ClientItems = {}
    local data = msgpack.unpack(items)
    for _, item in pairs(data) do
        ClientItems[item.item] = Item:New(item)
    end
end

function InventoryService.getLoadout(loadout)
    local newIds = {}
    for _, weapon in ipairs(loadout) do
        newIds[tonumber(weapon.id)] = true
    end
    for id, wp in pairs(UserWeapons) do
        if not newIds[id] then
            if wp.getUsed and (wp:getUsed() or wp:getUsed2()) then
                wp:UnequipWeapon()
            end
            UserWeapons[id] = nil
        end
    end
    for _, weapon in ipairs(loadout) do
        local weaponAmmo = weapon.ammo
        for type, amount in pairs(weaponAmmo) do
            weaponAmmo[type] = tonumber(amount)
        end

        local weaponUsed = false
        local weaponUsed2 = false

        if weapon.used == 1 or weapon.used == true then
            weaponUsed = true
        end
        if weapon.used2 == 1 or weapon.used2 == true then
            weaponUsed2 = true
        end

        if weapon.currInv == "default" and (weapon.dropped == nil or weapon.dropped == 0) then
            local weaponId = tonumber(weapon.id)
            local existingWeapon = UserWeapons[weaponId]
            if existingWeapon then
                existingWeapon.used = weaponUsed
                existingWeapon.used2 = weaponUsed2

                existingWeapon:setPropietary(weapon.identifier)
                existingWeapon:setLabel(weapon.custom_label or Utils.GetWeaponDefaultLabel(weapon.name))
                existingWeapon:setName(weapon.name)
                existingWeapon.ammo = weaponAmmo
                existingWeapon.components = weapon.components
                existingWeapon:setDesc(weapon.custom_desc or Utils.GetWeaponDefaultDesc(weapon.name))
                existingWeapon:setCurrInv(weapon.curr_inv)
                existingWeapon.dropped = 0
                existingWeapon.group = 5
                existingWeapon:setCustomLabel(weapon.custom_label)
                existingWeapon:setSerialNumber(weapon.serial_number)
                existingWeapon:setCustomDesc(weapon.custom_desc)
                existingWeapon.weight = weapon.weight
                existingWeapon:setSlot(weapon.slot)
                existingWeapon:setAmmoTotal(weapon.ammo_total or 0)
                existingWeapon:setDurability(weapon.durability or 100)
                existingWeapon.comps = weapon.comps or {}
                giveWeaponToPedForWheel(weapon.name, weapon.ammo_total)
            else
                local newWeapon = Weapon:New({
                    id = weaponId,
                    identifier = weapon.identifier,
                    label = weapon.custom_label or Utils.GetWeaponDefaultLabel(weapon.name),
                    name = weapon.name,
                    ammo = weaponAmmo,
                    components = weapon.components,
                    used = weaponUsed,
                    used2 = weaponUsed2,
                    desc = weapon.custom_desc or Utils.GetWeaponDefaultDesc(weapon.name),
                    currInv = weapon.curr_inv,
                    dropped = 0,
                    group = 5,
                    custom_label = weapon.custom_label,
                    serial_number = weapon.serial_number,
                    custom_desc = weapon.custom_desc,
                    weight = weapon.weight,
                    slot = weapon.slot,
                    ammo_total = weapon.ammo_total or 0,
                    durability = weapon.durability or 100,
                    comps = weapon.comps or {}
                })
                UserWeapons[newWeapon:getId()] = newWeapon
                giveWeaponToPedForWheel(weapon.name, weapon.ammo_total)

                if not loadoutInitialized and newWeapon:getUsed() then
                    Utils.useWeapon(newWeapon:getId())
                end
            end
        end
    end
    loadoutInitialized = true
end

function InventoryService.getInventory(inventory)
    UserInventory = {}
    local inventoryItems = msgpack.unpack(inventory)

    for id, item in pairs(inventoryItems) do
        UserInventory[item.id] = Item:New({
            id = item.id,
            count = item.count,
            limit = item.limit,
            label = item.label,
            name = item.name,
            metadata = item.metadata,
            type = item.type,
            canUse = item.canUse,
            canRemove = item.canRemove,
            desc = item.desc,
            owner = item.owner,
            group = item.group,
            weight = item.weight,
            degradation = item.degradation,
            maxDegradation = item.maxDegradation,
            percentage = item.percentage,
            slot = item.slot
        })
    end
end
