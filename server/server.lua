local Core <const> = exports.vorp_core:GetCore()

if Config.DevMode then
    print("^1[DEV] ^7DEV MODE IS ENABLED, THIS IS NOT FOR PRODUCTION SERVERS")
end

local DropInUse = {} -- [dropId] = sourceServerId
local RepairingWeapons = {}
local StealTargets = {} -- [sourceServerId] = targetServerId

local function isStealBlacklistedItem(name)
    if not Config.StealBlacklist or not Config.StealBlacklist.Items then return false end
    return Config.StealBlacklist.Items[name] == true
end

local function isStealBlacklistedWeapon(name)
    if not Config.StealBlacklist or not Config.StealBlacklist.Weapons then return false end
    return Config.StealBlacklist.Weapons[name] == true
end

local function getCharacterDisplayName(character)
    if not character then return "" end
    local firstName = character.firstname or character.FirstName or ""
    local lastName = character.lastname or character.LastName or ""
    local name = (tostring(firstName) .. " " .. tostring(lastName)):gsub("^%s+", ""):gsub("%s+$", "")
    return name ~= "" and name or "Unknown"
end

local function canStackInventoryItems(firstItem, secondItem)
    if not firstItem or not secondItem then return false end
    if firstItem:getName() ~= secondItem:getName() then return false end
    if not SharedUtils.Table_equals(firstItem:getMetadata() or {}, secondItem:getMetadata() or {}, true) then return false end

    local firstMax = firstItem:getMaxDegradation() or 0
    local secondMax = secondItem:getMaxDegradation() or 0
    if firstMax ~= secondMax then return false end
    if firstMax > 0 then
        return firstItem:getPercentage() == secondItem:getPercentage() and firstItem:getDegradation() == secondItem:getDegradation()
    end

    return true
end

CreateThread(function()
    local migrations = {
        { table = "character_inventories", column = "slot", sql = "ALTER TABLE character_inventories ADD COLUMN `slot` INT DEFAULT NULL;" },
        { table = "loadout", column = "slot", sql = "ALTER TABLE loadout ADD COLUMN `slot` INT DEFAULT NULL;" },
        { table = "loadout", column = "ammo_total", sql = "ALTER TABLE loadout ADD COLUMN `ammo_total` INT NOT NULL DEFAULT 0;" },
        { table = "loadout", column = "durability", sql = "ALTER TABLE loadout ADD COLUMN `durability` DOUBLE NOT NULL DEFAULT 100;" },
    }
    for _, m in ipairs(migrations) do
        local result = MySQL.query.await("SELECT * FROM Information_Schema.Columns WHERE Table_Name = @table AND Column_Name = @column;", { table = m.table, column = m.column })
        if result and #result > 0 then
            print("^3[vorp_inventory]^7 Column '" .. m.column .. "' already exists in '" .. m.table .. "', skipping.")
        else
            MySQL.query.await(m.sql)
            print("^2[vorp_inventory]^7 Column '" .. m.column .. "' successfully added to '" .. m.table .. "'.")
        end
    end
end)

RegisterServerEvent("syn:stopscene")
AddEventHandler("syn:stopscene", function(x)
    local _source <const> = source
    TriggerClientEvent("inv:dropstatus", _source, x)
end)

CreateThread(function()
    Wait(1000)
    if not Config.Stashes then return end
    for _, stash in ipairs(Config.Stashes) do
        local useWeight = stash.maxWeight and stash.maxWeight > 0
        exports.vorp_inventory:registerInventory({
            id = stash.id,
            name = stash.name,
            limit = useWeight and -1 or (stash.slots or 30),
            useWeight = useWeight,
            weight = stash.maxWeight or 0.0,
            acceptWeapons = true,
            shared = stash.shared or false,
            ignoreItemStackLimit = false,
            whitelistItems = false,
            UsePermissions = false,
            UseBlackList = false,
            whitelistWeapons = false,
        })
        print("^2[vorp_inventory]^7 Registered stash: " .. stash.id)
    end
end)

-- Check stash access
RegisterServerEvent("vorpinventory:openStash", function(stashId)
    local _source = source
    if not Config.Stashes then return end

    local stashConfig = nil
    for _, s in ipairs(Config.Stashes) do
        if s.id == stashId then stashConfig = s break end
    end
    if not stashConfig then return end

    -- Job check
    if stashConfig.allowedJobs ~= "all" and type(stashConfig.allowedJobs) == "table" then
        local user = Core.getUser(_source)
        if not user then return end
        local character = user.getUsedCharacter
        local playerJob = character.job
        local allowed = false
        for _, job in ipairs(stashConfig.allowedJobs) do
            if job == playerJob then allowed = true break end
        end
        if not allowed then
            Core.NotifyRightTip(_source, T("stashNoPermission") or "You don't have permission to access this stash", 3000)
            return
        end
    end

    -- Open stash (same as custom inventory)
    exports.vorp_inventory:openInventory(_source, stashId)
end)

RegisterServerEvent("vorpinventory:netduplog", function()
    local _source <const> = source
    local playername <const> = GetPlayerName(_source)
    local description <const> = Logs.NetDupWebHook.Language.descriptionstart .. playername .. Logs.NetDupWebHook.Language.descriptionend

    if Logs.NetDupWebHook.Active then
        local info <const> = {
            source = _source,
            title = Config.NetDupWebHook.Language.title,
            name = playername,
            description = description,
            webhook = Logs.NetDupWebHook.webhook,
            color = Logs.NetDupWebHook.color
        }
        SvUtils.SendDiscordWebhook(info)
    else
        print('[' .. Logs.NetDupWebHook.Language.title .. '] ', description)
    end
end)

AddEventHandler('playerDropped', function()
    local _source <const> = source
    if _source then
        local user <const>    = Core.getUser(_source)

        local weapons <const> = UsersWeapons.default

        if AmmoData[_source] then
            AmmoData[_source] = nil
        end

        local invId = INVENTORY_IN_USE[_source]

        if invId ~= nil then
            INVENTORY_IN_USE[_source] = nil

            local customInv = CustomInventoryInfos[invId]

            if customInv and customInv:isInUse() then
                customInv:setInUse(false)
            end
        end

        -- Clean up drop locks
        for dropId, lockedBy in pairs(DropInUse) do
            if lockedBy == _source then
                DropInUse[dropId] = nil
            end
        end

        -- Clean up repair
        if RepairingWeapons[_source] then
            RepairingWeapons[_source] = nil
        end

        -- Clean up steal
        if StealTargets[_source] then
            StealTargets[_source] = nil
        end

        if not user then return end

        local charid <const> = user.getUsedCharacter.charIdentifier
        for key, value in pairs(weapons) do
            if value.charId == charid then
                UsersWeapons.default[key] = nil
                break
            end
        end
    end
end)

RegisterServerEvent("vorpinventory:lockDrop", function(dropId)
    local _source = source
    if not dropId then return end
    if DropInUse[dropId] and DropInUse[dropId] ~= _source then
        Core.NotifyRightTip(_source, T("inventoryInUse") or "This inventory is currently in use", 3000)
        return
    end
    DropInUse[dropId] = _source
end)

RegisterServerEvent("vorpinventory:unlockDrop", function(dropId)
    local _source = source
    if not dropId then return end
    if DropInUse[dropId] == _source then
        DropInUse[dropId] = nil
    end
end)

Core.Callback.Register("vorpinventory:isDropLocked", function(source, cb, dropId)
    if not dropId then return cb(false) end
    if DropInUse[dropId] and DropInUse[dropId] ~= source then
        return cb(true)
    end
    return cb(false)
end)

Core.Callback.Register("vorpinventory:get_slots", function(source, cb, _)
    local user <const> = Core.getUser(source)
    if not user then return cb(nil) end

    local character <const>      = user.getUsedCharacter
    local totalItems <const>     = InventoryAPI.getUserTotalCountItems(character.identifier, character.charIdentifier)
    local totalWeapons <const>   = InventoryAPI.getUserTotalCountWeapons(character.identifier, character.charIdentifier, true)
    local totalInvWeight <const> = (totalItems + totalWeapons)
    local effectiveSlots = (BagService and BagService.GetEffectiveCapacity and BagService.GetEffectiveCapacity(source))
        or character.invCapacity
    local containerWeight = (BagService and BagService.GetContainerBackpacksWeight and BagService.GetContainerBackpacksWeight(source)) or 0
    return cb({
        totalInvWeight = totalInvWeight + containerWeight,
        slots = effectiveSlots,
        money = character.money,
        gold = character.gold,
        rol = character.rol,
        charName = getCharacterDisplayName(character),
    })
end)


RegisterServerEvent("vorp_inventory:Server:CloseCustomInventory", function()
    local _source <const> = source
    if not INVENTORY_IN_USE[_source] then
        return print("player:", GetPlayerName(_source), "did not open inventory through the server  but it closed it meaning it opened from the client", "possible Cheat!!")
    end
    local id <const> = INVENTORY_IN_USE[_source]
    if not CustomInventoryInfos[id] then
        return print("player:", GetPlayerName(_source), "tried to close inventory with id:", id, "but it was not found", "possible Cheat!!")
    end

    if not CustomInventoryInfos[id]:isInUse() then
        return print("player:", GetPlayerName(_source), "tried to close inventory with id:", id, "but it was not in use", "possible Cheat!!")
    end

    CustomInventoryInfos[id]:setInUse(false)
    INVENTORY_IN_USE[_source] = nil

    if type(id) == "string" and id:sub(1, 3) == "bp_" and BagService and BagService.UpdateBagLoadMetadata then
        BagService.UpdateBagLoadMetadata(id)
    end
end)

local function getRepairRequirementsFor(weaponName)
    local out = {}
    local rules = Config.WeaponDurability and Config.WeaponDurability.RepairItems
    if not rules or #rules == 0 then return out end
    for _, rule in ipairs(rules) do
        local applies = rule.applies
        local matches = false
        if applies == nil or applies == "all" then
            matches = true
        elseif type(applies) == "table" then
            for _, prefix in ipairs(applies) do
                if type(prefix) == "string" and prefix ~= "" and weaponName:sub(1, #prefix) == prefix then
                    matches = true
                    break
                end
            end
        end
        if matches and rule.item and (rule.amount or 0) > 0 then
            out[#out+1] = { item = rule.item, amount = math.floor(tonumber(rule.amount)) }
        end
    end
    return out
end

RegisterServerEvent("vorpinventory:repairWeapon", function(weaponId, repairTime)
    local _source = source
    local user = Core.getUser(_source)
    if not user then return end
    local character = user.getUsedCharacter
    local identifier = character.identifier
    local charId = character.charIdentifier
    weaponId = tonumber(weaponId)
    if not weaponId then return end

    local weapon = UsersWeapons.default[weaponId]
    if not weapon or weapon:getPropietary() ~= identifier then return end
    if RepairingWeapons[_source] then return end -- already repairing

    local requirements = getRepairRequirementsFor(weapon:getName())
    if #requirements > 0 then
        for _, req in ipairs(requirements) do
            local invItem = exports.vorp_inventory:getItem(_source, req.item)
            if not invItem or (invItem.count or 0) < req.amount then
                Core.NotifyRightTip(_source, T("repairMissingItem", req.amount, req.item), 4000)
                TriggerClientEvent("vorpInventory:repairCompleted", _source)
                return
            end
        end
        for _, req in ipairs(requirements) do
            exports.vorp_inventory:subItem(_source, req.item, req.amount, {})
        end
    end

    local savedSlot = weapon:getSlot()

    RepairingWeapons[_source] = { weaponId = weaponId, slot = savedSlot, identifier = identifier, charId = charId }
    DBService.updateAsync('UPDATE loadout SET identifier = "", dropped = 1, slot = NULL WHERE id = @id', { id = weaponId })
    UsersWeapons.default[weaponId] = nil

    TriggerClientEvent("vorp_inventory:ReloadInv", _source)

    SetTimeout(repairTime, function()
        local repairData = RepairingWeapons[_source]
        if not repairData then return end

        DBService.updateAsync('UPDATE loadout SET identifier = @identifier, charidentifier = @charId, dropped = 0, durability = 100, slot = @slot WHERE id = @id',
            { identifier = repairData.identifier, charId = repairData.charId, slot = repairData.slot, id = repairData.weaponId })

        local result = DBService.queryAwait('SELECT * FROM loadout WHERE id = @id', { id = repairData.weaponId })
        if result and result[1] then
            local db_weapon = result[1]
            local ammo = json.decode(db_weapon.ammo)
            local comp = json.decode(db_weapon.components)
            local comps = db_weapon.comps and json.decode(db_weapon.comps) or {}
            local weight = SvUtils.GetWeaponWeight(db_weapon.name)

            local restoredWeapon = Weapon:New({
                id = db_weapon.id,
                propietary = repairData.identifier,
                name = db_weapon.name,
                ammo = ammo,
                components = comp,
                comps = comps,
                used = false,
                used2 = false,
                charId = repairData.charId,
                currInv = "default",
                dropped = 0,
                group = 5,
                label = db_weapon.custom_label or db_weapon.label,
                serial_number = db_weapon.serial_number,
                custom_label = db_weapon.custom_label,
                custom_desc = db_weapon.custom_desc,
                weight = weight,
                slot = repairData.slot,
                ammo_total = db_weapon.ammo_total or 0,
                durability = 100,
            })
            UsersWeapons.default[repairData.weaponId] = restoredWeapon

            TriggerClientEvent("vorpInventory:receiveWeapon", _source, repairData.weaponId, repairData.identifier,
                restoredWeapon:getName(), restoredWeapon:getAllAmmo(), restoredWeapon:getLabel(),
                restoredWeapon:getSerialNumber(), restoredWeapon:getCustomLabel(), _source,
                restoredWeapon:getCustomDesc(), restoredWeapon:getWeight(), repairData.slot,
                restoredWeapon:getAmmoTotal(), 100)
        end

        TriggerClientEvent("vorpInventory:repairCompleted", _source)
        TriggerClientEvent("vorp_inventory:ReloadInv", _source)
        RepairingWeapons[_source] = nil
    end)
end)

RegisterServerEvent("vorpinventory:updateWeaponDurability", function(weaponId, durability)
    local _source = source
    local user = Core.getUser(_source)
    if not user then return end
    local identifier = user.getUsedCharacter.identifier
    weaponId = tonumber(weaponId)
    if not weaponId then return end
    local weapon = UsersWeapons.default[weaponId]
    if not weapon or weapon:getPropietary() ~= identifier then return end
    weapon:setDurability(durability)
end)

local function refreshStealInventory(_source, targetServerId)
    local targetUser = Core.getUser(targetServerId)
    if not targetUser then return end

    local targetChar = targetUser.getUsedCharacter
    local targetIdentifier = targetChar.identifier
    local targetCharId = targetChar.charIdentifier

    local itemList = {}
    local targetInventory = UsersInventories.default[targetIdentifier]
    if targetInventory then
        for _, item in pairs(targetInventory) do
            if not isStealBlacklistedItem(item:getName()) then
                itemList[#itemList + 1] = item
            end
        end
    end

    for weaponId, weapon in pairs(UsersWeapons.default) do
        if weapon.charId == targetCharId and weapon:getPropietary() == targetIdentifier and weapon.dropped == 0 then
            if not isStealBlacklistedWeapon(weapon.name) then
                itemList[#itemList + 1] = {
                    id = weaponId, count = 1, name = weapon.name, label = weapon.name,
                    limit = 1, type = "item_weapon", desc = weapon.desc, group = 5,
                    serial_number = weapon.serial_number, custom_label = weapon.custom_label,
                    custom_desc = weapon.custom_desc, weight = weapon.weight, slot = weapon.slot,
                    durability = weapon:getDurability(),
                }
            end
        end
    end

    local payload = msgpack.pack({
        action = "setSecondInventoryItems",
        itemList = itemList,
        info = { target = targetServerId, source = _source },
    })
    TriggerClientEvent("vorp_inventory:ReloadCustomInventory", _source, false, payload)
end

RegisterServerEvent("vorpinventory:stealPlayer", function(targetServerId)
    local _source = source
    local targetUser = Core.getUser(targetServerId)
    if not targetUser then return end
    local sourceUser = Core.getUser(_source)
    if not sourceUser then return end

    local targetChar = targetUser.getUsedCharacter
    local targetName = getCharacterDisplayName(targetChar)
    local capacity = targetChar.invCapacity or 200

    StealTargets[_source] = targetServerId

    if targetServerId ~= _source then
        TriggerClientEvent("vorpinventory:forceCloseInventory", targetServerId)
    end

    TriggerClientEvent("vorp_inventory:OpenstealInventory", _source, targetName, targetServerId, capacity)
    refreshStealInventory(_source, targetServerId)
end)

local function findFreeSlotForIdentifier(identifier)
    local usedSlots = {}
    local inv = UsersInventories.default[identifier] or {}
    for _, it in pairs(inv) do
        if it:getSlot() then usedSlots[it:getSlot()] = true end
    end
    for _, weapon in pairs(UsersWeapons.default) do
        if weapon.propietary == identifier and weapon:getSlot() then usedSlots[weapon:getSlot()] = true end
    end
    local s = 1
    while usedSlots[s] do s = s + 1 end
    return s
end

RegisterServerEvent("syn_search:TakeFromsteal", function(dataJson)
    local _source = source
    local data = json.decode(dataJson)
    local targetServerId = StealTargets[_source]
    if not targetServerId then return end
    if targetServerId == _source then return end -- prevent self-steal

    local targetUser = Core.getUser(targetServerId)
    local sourceUser = Core.getUser(_source)
    if not targetUser or not sourceUser then return end

    local targetChar = targetUser.getUsedCharacter
    local sourceChar = sourceUser.getUsedCharacter
    local targetIdentifier = targetChar.identifier
    local sourceIdentifier = sourceChar.identifier
    local sourceCharId = sourceChar.charIdentifier
    local targetCharId = targetChar.charIdentifier

    local item = data.item or {}
    local itemType = item.type or data.type
    local itemId = tonumber(item.id)
    local amount = tonumber(data.number) or 1
    local targetSlot = data.targetSlot
    local itemLabel = item.label or item.name

    if itemType == "item_weapon" then
        local weapon = UsersWeapons.default[itemId]
        if not weapon or weapon:getPropietary() ~= targetIdentifier then return end
        if isStealBlacklistedWeapon(weapon.name) then
            Core.NotifyRightTip(_source, "That weapon is protected and cannot be stolen.", 4000)
            return
        end

        TriggerClientEvent("vorpInventory:removeWeapon", targetServerId, itemId)
        weapon:setUsed(false)
        weapon:setUsed2(false)

        weapon:setPropietary(sourceIdentifier)
        weapon.charId = sourceCharId
        weapon:setSlot(targetSlot)
        DBService.updateAsync(
            'UPDATE loadout SET identifier = @identifier, charidentifier = @charId, slot = @slot, used = 0, used2 = 0 WHERE id = @id',
            { identifier = sourceIdentifier, charId = sourceCharId, slot = targetSlot, id = itemId }
        )
        TriggerClientEvent("vorpInventory:receiveWeapon", _source, itemId, sourceIdentifier, weapon:getName(), weapon:getAllAmmo(), weapon:getLabel(), weapon:getSerialNumber(), weapon:getCustomLabel(), _source, weapon:getCustomDesc(), weapon:getWeight(), targetSlot, weapon:getAmmoTotal(), weapon:getDurability())
        TriggerClientEvent("vorpInventory:itemNotify", _source, "add", weapon:getName(), weapon:getLabel(), 1)
        TriggerClientEvent("vorpInventory:itemNotify", targetServerId, "remove", weapon:getName(), weapon:getLabel(), 1)
    else
        local targetInv = UsersInventories.default[targetIdentifier]
        if not targetInv or not targetInv[itemId] then return end

        local invItem = targetInv[itemId]
        if isStealBlacklistedItem(invItem:getName()) then
            Core.NotifyRightTip(_source, "That item is protected and cannot be stolen.", 4000)
            return
        end
        if amount > invItem:getCount() then amount = invItem:getCount() end
        if amount <= 0 then return end

        -- Check target slot in source inventory (for merge)
        local sourceInv = UsersInventories.default[sourceIdentifier]
        local existingItem = nil
        if sourceInv then
            for _, it in pairs(sourceInv) do
                if it:getSlot() == targetSlot and canStackInventoryItems(it, invItem) then
                    existingItem = it
                    break
                end
            end
        end

        local itemName = invItem:getName()
        local label = invItem:getLabel() or itemName

        -- Subtract from target
        invItem:quitCount(amount)
        if invItem:getCount() <= 0 then
            DBService.deleteAsync('DELETE FROM character_inventories WHERE item_crafted_id = @id', { id = invItem:getId() })
            targetInv[invItem:getId()] = nil
        else
            DBService.SetItemAmount(targetCharId, invItem:getId(), invItem:getCount())
        end

        if existingItem then
            existingItem:addCount(amount, true)
            DBService.SetItemAmount(sourceCharId, existingItem:getId(), existingItem:getCount())
        else
            -- Create new item at target slot
            local svItem = ServerItems[itemName]
            if svItem then
                DBService.CreateItem(sourceCharId, svItem:getId(), amount, invItem:getMetadata() or {}, itemName, invItem:getDegradation() or 0, function(result)
                    if result and result.id then
                        local newItem = Item:New({
                            count = amount, id = result.id, limit = svItem.limit, label = svItem.label,
                            metadata = invItem:getMetadata() or {}, name = itemName, type = svItem.type,
                            canUse = svItem.canUse, canRemove = svItem.canRemove, owner = sourceCharId,
                            desc = svItem.desc, group = svItem.group, weight = svItem.weight,
                            degradation = invItem:getDegradation(), percentage = invItem:getPercentage(),
                            maxDegradation = svItem.maxDegradation, slot = targetSlot,
                        })
                        if not UsersInventories.default[sourceIdentifier] then UsersInventories.default[sourceIdentifier] = {} end
                        UsersInventories.default[sourceIdentifier][result.id] = newItem
                        DBService.UpdateItemSlot(sourceCharId, result.id, targetSlot)
                    end
                end, "default")
            end
        end

        TriggerClientEvent("vorpInventory:itemNotify", _source, "add", itemName, label, amount)
        TriggerClientEvent("vorpInventory:itemNotify", targetServerId, "remove", itemName, label, amount)
    end

    TriggerClientEvent("vorp_inventory:ReloadInv", _source)
    TriggerClientEvent("vorp_inventory:ReloadInv", targetServerId)
    refreshStealInventory(_source, targetServerId)
end)

RegisterServerEvent("syn_search:MoveTosteal", function(dataJson)
    local _source = source
    local data = json.decode(dataJson)
    local targetServerId = StealTargets[_source]
    if not targetServerId then return end
    if targetServerId == _source then return end -- prevent self-steal

    local targetUser = Core.getUser(targetServerId)
    local sourceUser = Core.getUser(_source)
    if not targetUser or not sourceUser then return end

    local sourceChar = sourceUser.getUsedCharacter
    local targetChar = targetUser.getUsedCharacter
    local sourceIdentifier = sourceChar.identifier
    local targetIdentifier = targetChar.identifier
    local sourceCharId = sourceChar.charIdentifier
    local targetCharId = targetChar.charIdentifier

    local item = data.item or {}
    local itemType = item.type or data.type
    local itemId = tonumber(item.id)
    local amount = tonumber(data.number) or 1
    local targetSlot = data.targetSlot

    if itemType == "item_weapon" then
        local weapon = UsersWeapons.default[itemId]
        if not weapon or weapon:getPropietary() ~= sourceIdentifier then return end

        -- Force unequip on source first
        TriggerClientEvent("vorpInventory:removeWeapon", _source, itemId)
        weapon:setUsed(false)
        weapon:setUsed2(false)

        weapon:setPropietary(targetIdentifier)
        weapon.charId = targetCharId
        weapon:setSlot(targetSlot)
        DBService.updateAsync(
            'UPDATE loadout SET identifier = @identifier, charidentifier = @charId, slot = @slot, used = 0, used2 = 0 WHERE id = @id',
            { identifier = targetIdentifier, charId = targetCharId, slot = targetSlot, id = itemId }
        )
        TriggerClientEvent("vorpInventory:itemNotify", _source, "remove", weapon:getName(), weapon:getLabel(), 1)
        TriggerClientEvent("vorpInventory:itemNotify", targetServerId, "add", weapon:getName(), weapon:getLabel(), 1)
    else
        local sourceInv = UsersInventories.default[sourceIdentifier]
        if not sourceInv or not sourceInv[itemId] then return end

        local invItem = sourceInv[itemId]
        if amount > invItem:getCount() then amount = invItem:getCount() end
        if amount <= 0 then return end

        -- Check target slot in target inventory (for merge)
        local targetInv = UsersInventories.default[targetIdentifier]
        local existingItem = nil
        if targetInv then
            for _, it in pairs(targetInv) do
                if it:getSlot() == targetSlot and canStackInventoryItems(it, invItem) then
                    existingItem = it
                    break
                end
            end
        end

        local itemName = invItem:getName()
        local label = invItem:getLabel() or itemName

        -- Subtract from source
        invItem:quitCount(amount)
        if invItem:getCount() <= 0 then
            DBService.deleteAsync('DELETE FROM character_inventories WHERE item_crafted_id = @id', { id = invItem:getId() })
            sourceInv[invItem:getId()] = nil
        else
            DBService.SetItemAmount(sourceCharId, invItem:getId(), invItem:getCount())
        end

        if existingItem then
            existingItem:addCount(amount, true)
            DBService.SetItemAmount(targetCharId, existingItem:getId(), existingItem:getCount())
        else
            local svItem = ServerItems[itemName]
            if svItem then
                DBService.CreateItem(targetCharId, svItem:getId(), amount, invItem:getMetadata() or {}, itemName, invItem:getDegradation() or 0, function(result)
                    if result and result.id then
                        local newItem = Item:New({
                            count = amount, id = result.id, limit = svItem.limit, label = svItem.label,
                            metadata = invItem:getMetadata() or {}, name = itemName, type = svItem.type,
                            canUse = svItem.canUse, canRemove = svItem.canRemove, owner = targetCharId,
                            desc = svItem.desc, group = svItem.group, weight = svItem.weight,
                            degradation = invItem:getDegradation(), percentage = invItem:getPercentage(),
                            maxDegradation = svItem.maxDegradation, slot = targetSlot,
                        })
                        if not UsersInventories.default[targetIdentifier] then UsersInventories.default[targetIdentifier] = {} end
                        UsersInventories.default[targetIdentifier][result.id] = newItem
                        DBService.UpdateItemSlot(targetCharId, result.id, targetSlot)
                    end
                end, "default")
            end
        end

        TriggerClientEvent("vorpInventory:itemNotify", _source, "remove", itemName, label, amount)
        TriggerClientEvent("vorpInventory:itemNotify", targetServerId, "add", itemName, label, amount)
    end

    TriggerClientEvent("vorp_inventory:ReloadInv", _source)
    TriggerClientEvent("vorp_inventory:ReloadInv", targetServerId)
    refreshStealInventory(_source, targetServerId)
end)

-- Helper: find item or weapon at slot in identifier's inventory
local function getItemAtSlot(identifier, slot)
    local inv = UsersInventories.default[identifier]
    if inv then
        for _, it in pairs(inv) do
            if it:getSlot() == slot then return it, "item" end
        end
    end
    for _, w in pairs(UsersWeapons.default) do
        if w.propietary == identifier and w:getSlot() == slot then return w, "weapon" end
    end
    return nil, nil
end

-- Helper: move/clone an entity (item or weapon) to a new owner's slot
local function transferEntityToOwner(entity, entityType, fromIdentifier, fromCharId, toIdentifier, toCharId, toSlot)
    if entityType == "weapon" then
        entity:setPropietary(toIdentifier)
        entity.charId = toCharId
        entity:setSlot(toSlot)
        DBService.updateAsync(
            'UPDATE loadout SET identifier = @identifier, charidentifier = @charId, slot = @slot WHERE id = @id',
            { identifier = toIdentifier, charId = toCharId, slot = toSlot, id = entity.id }
        )
    else
        local invFrom = UsersInventories.default[fromIdentifier]
        if invFrom then invFrom[entity:getId()] = nil end

        local count = entity:getCount()
        local svItem = ServerItems[entity:getName()]
        if not svItem then return end

        DBService.deleteAsync('DELETE FROM character_inventories WHERE item_crafted_id = @id', { id = entity:getId() })

        DBService.CreateItem(toCharId, svItem:getId(), count, entity:getMetadata() or {}, entity:getName(), nil, function(result)
            if result and result.id then
                local newItem = Item:New({
                    count = count, id = result.id, limit = svItem.limit, label = svItem.label,
                    metadata = entity:getMetadata() or {}, name = entity:getName(), type = svItem.type,
                    canUse = svItem.canUse, canRemove = svItem.canRemove, owner = toCharId,
                    desc = svItem.desc, group = svItem.group, weight = svItem.weight,
                    maxDegradation = svItem.maxDegradation, slot = toSlot,
                })
                if not UsersInventories.default[toIdentifier] then UsersInventories.default[toIdentifier] = {} end
                UsersInventories.default[toIdentifier][result.id] = newItem
                DBService.UpdateItemSlot(toCharId, result.id, toSlot)
            end
        end, "default")
    end
end

-- Steal: swap player slot <-> target slot (different items)
RegisterServerEvent("vorpinventory:stealSwapBetween", function(playerSlot, stealSlot)
    local _source = source
    local targetServerId = StealTargets[_source]
    if not targetServerId then return end
    if targetServerId == _source then return end

    local targetUser = Core.getUser(targetServerId)
    local sourceUser = Core.getUser(_source)
    if not targetUser or not sourceUser then return end

    local sourceChar = sourceUser.getUsedCharacter
    local targetChar = targetUser.getUsedCharacter
    local sourceIdentifier = sourceChar.identifier
    local targetIdentifier = targetChar.identifier
    local sourceCharId = sourceChar.charIdentifier
    local targetCharId = targetChar.charIdentifier

    local playerEntity, playerType = getItemAtSlot(sourceIdentifier, playerSlot)
    local stealEntity, stealType = getItemAtSlot(targetIdentifier, stealSlot)

    if stealEntity then
        local stealName = stealType == "weapon" and stealEntity.name or stealEntity:getName()
        local blocked = stealType == "weapon" and isStealBlacklistedWeapon(stealName) or isStealBlacklistedItem(stealName)
        if blocked then
            Core.NotifyRightTip(_source, "That target slot is protected and cannot be swapped.", 4000)
            return
        end
    end

    if playerEntity then
        transferEntityToOwner(playerEntity, playerType, sourceIdentifier, sourceCharId, targetIdentifier, targetCharId, stealSlot)
        if playerType == "weapon" then
            TriggerClientEvent("vorpInventory:removeWeapon", _source, playerEntity.id)
        end
    end
    if stealEntity then
        transferEntityToOwner(stealEntity, stealType, targetIdentifier, targetCharId, sourceIdentifier, sourceCharId, playerSlot)
        if stealType == "weapon" then
            TriggerClientEvent("vorpInventory:receiveWeapon", _source, stealEntity.id, sourceIdentifier, stealEntity:getName(), stealEntity:getAllAmmo(), stealEntity:getLabel(), stealEntity:getSerialNumber(), stealEntity:getCustomLabel(), _source, stealEntity:getCustomDesc(), stealEntity:getWeight(), playerSlot, stealEntity:getAmmoTotal(), stealEntity:getDurability())
        end
    end

    TriggerClientEvent("vorp_inventory:ReloadInv", _source)
    TriggerClientEvent("vorp_inventory:ReloadInv", targetServerId)
    refreshStealInventory(_source, targetServerId)
end)

-- Steal: swap two slots within target inventory
RegisterServerEvent("vorpinventory:stealSwapSlot", function(fromSlot, toSlot)
    local _source = source
    local targetServerId = StealTargets[_source]
    if not targetServerId then return end
    local targetUser = Core.getUser(targetServerId)
    if not targetUser then return end
    local targetChar = targetUser.getUsedCharacter
    local targetIdentifier = targetChar.identifier
    local targetCharId = targetChar.charIdentifier

    local targetInv = UsersInventories.default[targetIdentifier] or {}
    local fromItem, toItem = nil, nil
    for _, it in pairs(targetInv) do
        if it:getSlot() == fromSlot then fromItem = it end
        if it:getSlot() == toSlot then toItem = it end
    end
    local fromWeapon, toWeapon = nil, nil
    for _, w in pairs(UsersWeapons.default) do
        if w.propietary == targetIdentifier and w:getSlot() == fromSlot then fromWeapon = w end
        if w.propietary == targetIdentifier and w:getSlot() == toSlot then toWeapon = w end
    end

    if fromItem then
        fromItem:setSlot(toSlot)
        DBService.UpdateItemSlot(targetCharId, fromItem:getId(), toSlot)
    end
    if fromWeapon then
        fromWeapon:setSlot(toSlot)
        DBService.UpdateWeaponSlot(fromWeapon.id, toSlot)
    end
    if toItem then
        toItem:setSlot(fromSlot)
        DBService.UpdateItemSlot(targetCharId, toItem:getId(), fromSlot)
    end
    if toWeapon then
        toWeapon:setSlot(fromSlot)
        DBService.UpdateWeaponSlot(toWeapon.id, fromSlot)
    end

    refreshStealInventory(_source, targetServerId)
    TriggerClientEvent("vorp_inventory:ReloadInv", targetServerId)
end)

-- Steal: merge two slots within target inventory
RegisterServerEvent("vorpinventory:stealMergeSlot", function(fromSlot, toSlot, amount)
    local _source = source
    local targetServerId = StealTargets[_source]
    if not targetServerId then return end
    local targetUser = Core.getUser(targetServerId)
    if not targetUser then return end
    local targetChar = targetUser.getUsedCharacter
    local targetIdentifier = targetChar.identifier
    local targetCharId = targetChar.charIdentifier

    local targetInv = UsersInventories.default[targetIdentifier] or {}
    local fromItem, toItem = nil, nil
    for _, it in pairs(targetInv) do
        if it:getSlot() == fromSlot then fromItem = it end
        if it:getSlot() == toSlot then toItem = it end
    end
    if not canStackInventoryItems(fromItem, toItem) then return end

    amount = tonumber(amount) or fromItem:getCount()
    if amount > fromItem:getCount() then amount = fromItem:getCount() end

    toItem:addCount(amount, true)
    fromItem:quitCount(amount)

    DBService.SetItemAmount(targetCharId, toItem:getId(), toItem:getCount())
    if fromItem:getCount() <= 0 then
        DBService.deleteAsync('DELETE FROM character_inventories WHERE item_crafted_id = @id', { id = fromItem:getId() })
        targetInv[fromItem:getId()] = nil
    else
        DBService.SetItemAmount(targetCharId, fromItem:getId(), fromItem:getCount())
    end

    refreshStealInventory(_source, targetServerId)
    TriggerClientEvent("vorp_inventory:ReloadInv", targetServerId)
end)

-- Steal: split slot within target inventory
RegisterServerEvent("vorpinventory:stealSplitSlot", function(fromSlot, toSlot, amount)
    local _source = source
    local targetServerId = StealTargets[_source]
    if not targetServerId then return end
    local targetUser = Core.getUser(targetServerId)
    if not targetUser then return end
    local targetChar = targetUser.getUsedCharacter
    local targetIdentifier = targetChar.identifier
    local targetCharId = targetChar.charIdentifier

    local targetInv = UsersInventories.default[targetIdentifier] or {}
    local fromItem = nil
    for _, it in pairs(targetInv) do
        if it:getSlot() == fromSlot then fromItem = it break end
    end
    if not fromItem then return end

    amount = tonumber(amount) or 1
    if amount >= fromItem:getCount() then return end

    fromItem:quitCount(amount)
    DBService.SetItemAmount(targetCharId, fromItem:getId(), fromItem:getCount())

    local svItem = ServerItems[fromItem:getName()]
    if svItem then
        DBService.CreateItem(targetCharId, svItem:getId(), amount, fromItem:getMetadata() or {}, fromItem:getName(), nil, function(result)
            if result and result.id then
                local newItem = Item:New({
                    count = amount, id = result.id, limit = svItem.limit, label = svItem.label,
                    metadata = fromItem:getMetadata() or {}, name = fromItem:getName(), type = svItem.type,
                    canUse = svItem.canUse, canRemove = svItem.canRemove, owner = targetCharId,
                    desc = svItem.desc, group = svItem.group, weight = svItem.weight,
                    maxDegradation = svItem.maxDegradation, slot = toSlot,
                })
                targetInv[result.id] = newItem
                DBService.UpdateItemSlot(targetCharId, result.id, toSlot)
                refreshStealInventory(_source, targetServerId)
                TriggerClientEvent("vorp_inventory:ReloadInv", targetServerId)
            end
        end, "default")
    end
end)
