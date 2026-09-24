RegisterNetEvent("vorpInventory:giveItemsTable", InventoryService.processItems)
RegisterNetEvent("vorpInventory:giveInventory", InventoryService.getInventory)
RegisterNetEvent("vorpCoreClient:SetItemMetadata", InventoryApiService.SetItemMetadata)
RegisterNetEvent("vorpInventory:giveLoadout", InventoryService.getLoadout)
RegisterNetEvent("vorpInventory:receiveItem", InventoryService.receiveItem)
RegisterNetEvent("vorpInventory:removeItem", InventoryService.removeItem)
RegisterNetEvent("vorpInventory:receiveWeapon", InventoryService.receiveWeapon)
RegisterNetEvent("vorpInventory:setWeaponSerialNumber", InventoryService.setWeaponSerialNumber)
RegisterNetEvent("vorpInventory:setWeaponCustomLabel", InventoryService.setWeaponCustomLabel)
RegisterNetEvent("vorpInventory:setWeaponCustomDesc", InventoryService.setWeaponCustomDesc)
RegisterNetEvent("vorpInventory:removeWeapon", function(weaponId)
	weaponId = tonumber(weaponId)
	if weaponId and UserWeapons[weaponId] then
		if Config.WeaponWheel and Config.WeaponWheel.Enabled then
			RemoveWeaponFromPed(PlayerPedId(), joaat(UserWeapons[weaponId]:getName()), true, 0)
		elseif UserWeapons[weaponId]:getUsed() or UserWeapons[weaponId]:getUsed2() then
			UserWeapons[weaponId]:UnequipWeapon()
		end
		UserWeapons[weaponId] = nil
		if InventoryService.SyncWeaponWheel then
			InventoryService.SyncWeaponWheel()
		end
		NUIService.LoadInv()
	end
end)

RegisterNetEvent("vorpInventory:repairCompleted", function()
	SendNUIMessage({ action = "repairCompleted" })
	local Core = exports.vorp_core:GetCore()
	Core.NotifyRightTip(T("weaponRepaired") or "Weapon repaired", 3000)
end)

RegisterNetEvent("vorpinventory:forceCloseInventory", function()
	if InInventory then
		NUIService.CloseInv()
		local Core = exports.vorp_core:GetCore()
		Core.NotifyRightTip(T("inventoryForceClosed") or "Your inventory was closed", 3000)
	end
end)

RegisterNetEvent("vorp:SelectedCharacter")
AddEventHandler("vorp:SelectedCharacter", InventoryService.onSelectedCharacter)
