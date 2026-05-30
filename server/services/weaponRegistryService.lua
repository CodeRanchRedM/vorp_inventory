local Core <const> = exports.vorp_core:GetCore()

local function registryEnabled()
	return Config.WeaponRegistry ~= nil and Config.WeaponRegistry.Enabled == true
end

CreateThread(function()
	if not registryEnabled() then return end
	MySQL.query.await([[CREATE TABLE IF NOT EXISTS `vorp_weapon_registry` (
		`id` INT NOT NULL AUTO_INCREMENT,
		`serial` VARCHAR(64) NOT NULL,
		`weapon_name` VARCHAR(100) DEFAULT NULL,
		`owner_name` VARCHAR(120) DEFAULT NULL,
		`owner_charid` INT DEFAULT NULL,
		`registered_by` VARCHAR(120) DEFAULT NULL,
		`registered_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
		PRIMARY KEY (`id`),
		UNIQUE KEY `serial_unique` (`serial`)
	);]])
	print("^2[vorp_inventory]^7 Weapon registry ready.")
end)

local function hasJob(character, jobs)
	if not jobs or not character then return false end
	for _, j in ipairs(jobs) do
		if character.job == j then return true end
	end
	return false
end

local function charDisplayName(character)
	local name = ((character.firstname or "") .. " " .. (character.lastname or "")):gsub("^%s+", ""):gsub("%s+$", "")
	return name ~= "" and name or "Unknown"
end

local function isValidSerial(serial)
	return serial ~= nil and serial ~= "" and serial ~= "Serial Number not set" and serial ~= "NoSerial"
end

local function getDrawnWeapon(identifier)
	if not UsersWeapons or not UsersWeapons.default then return nil end
	for _, weapon in pairs(UsersWeapons.default) do
		if weapon.propietary == identifier and (weapon.used or weapon.used2) then
			return weapon
		end
	end
	return nil
end

RegisterCommand("registerweapon", function(source, args)
	if source == 0 or not registryEnabled() then return end

	local user = Core.getUser(source)
	if not user then return end
	local character = user.getUsedCharacter

	if not hasJob(character, Config.WeaponRegistry.RegisterJobs) then
		return Core.NotifyRightTip(source, "Only lawmen can register weapons.", 4000)
	end

	local targetId = tonumber(args[1])
	if not targetId then
		return Core.NotifyRightTip(source, "Usage: /registerweapon <playerId>", 4000)
	end

	local targetUser = Core.getUser(targetId)
	if not targetUser then
		return Core.NotifyRightTip(source, "Player " .. tostring(targetId) .. " not found.", 4000)
	end
	local targetChar = targetUser.getUsedCharacter

	local weapon = getDrawnWeapon(targetChar.identifier)
	if not weapon then
		return Core.NotifyRightTip(source, "That player has no weapon drawn. Ask them to hold the weapon out.", 5000)
	end

	local serial = weapon:getSerialNumber()
	if not isValidSerial(serial) then
		return Core.NotifyRightTip(source, "This weapon has no serial number and cannot be registered.", 5000)
	end

	local ownerName = charDisplayName(targetChar)
	MySQL.query.await([[INSERT INTO vorp_weapon_registry (serial, weapon_name, owner_name, owner_charid, registered_by)
		VALUES (@serial, @wname, @owner, @charid, @by)
		ON DUPLICATE KEY UPDATE weapon_name = @wname, owner_name = @owner, owner_charid = @charid,
		registered_by = @by, registered_at = CURRENT_TIMESTAMP;]], {
		serial = tostring(serial),
		wname = weapon:getName(),
		owner = ownerName,
		charid = targetChar.charIdentifier,
		by = charDisplayName(character),
	})

	Core.NotifyRightTip(source, ("Registered %s (serial %s) to %s."):format(weapon:getName(), serial, ownerName), 6000)
	Core.NotifyRightTip(targetId, ("Your %s (serial %s) was registered to you by the law."):format(weapon:getName(), serial), 6000)
end, false)

RegisterCommand("checkserial", function(source, args)
	if source == 0 or not registryEnabled() then return end

	local user = Core.getUser(source)
	if not user then return end
	local character = user.getUsedCharacter

	if Config.WeaponRegistry.CheckerJobsOnly and not hasJob(character, Config.WeaponRegistry.RegisterJobs) then
		return Core.NotifyRightTip(source, "Only lawmen can check serial numbers.", 4000)
	end

	local serial = args[1]
	if not serial then
		return Core.NotifyRightTip(source, "Usage: /checkserial <serialNumber>", 4000)
	end

	local result = MySQL.query.await("SELECT * FROM vorp_weapon_registry WHERE serial = @serial;", { serial = tostring(serial) })
	if result and result[1] then
		local r = result[1]
		Core.NotifyObjective(source, ("Serial %s - %s - Owner: %s (registered by %s)"):format(
			r.serial, r.weapon_name or "Unknown", r.owner_name or "Unknown", r.registered_by or "Unknown"), 9000)
	else
		Core.NotifyObjective(source, ("Serial %s is NOT registered to anyone."):format(tostring(serial)), 7000)
	end
end, false)

exports("GetWeaponRegistration", function(serial)
	if not isValidSerial(serial) then return nil end
	local result = MySQL.query.await("SELECT * FROM vorp_weapon_registry WHERE serial = @serial;", { serial = tostring(serial) })
	return result and result[1] or nil
end)


local function getRegistrationMap()
	local map = {}
	local rows = MySQL.query.await("SELECT serial, owner_name, registered_by FROM vorp_weapon_registry;")
	if rows then
		for _, r in ipairs(rows) do
			map[tostring(r.serial)] = r
		end
	end
	return map
end

local function getNearbyPlayersData(_source)
	local srcPed = GetPlayerPed(_source)
	if not srcPed or srcPed == 0 then return {} end
	local srcCoords = GetEntityCoords(srcPed)
	local range = (Config.WeaponRegistry and Config.WeaponRegistry.NearbyRange) or 5.0
	local regMap = getRegistrationMap()
	local players = {}

	for _, pid in ipairs(GetPlayers()) do
		pid = tonumber(pid)
		if pid then
			local ped = GetPlayerPed(pid)
			if ped and ped ~= 0 then
				local dist = #(srcCoords - GetEntityCoords(ped))
				if dist <= range then
					local user = Core.getUser(pid)
					if user then
						local char = user.getUsedCharacter
						local weapons = {}
						for wid, weapon in pairs(UsersWeapons.default or {}) do
							if weapon.propietary == char.identifier then
								local serial = weapon:getSerialNumber()
								local validSerial = isValidSerial(serial) and tostring(serial) or nil
								local reg = validSerial and regMap[validSerial] or nil
								weapons[#weapons + 1] = {
									id = wid,
									name = weapon:getName(),
									label = weapon:getCustomLabel() or weapon:getName(),
									serial = validSerial,
									registeredTo = reg and reg.owner_name or nil,
									registeredBy = reg and reg.registered_by or nil,
								}
							end
						end
						players[#players + 1] = {
							serverId = pid,
							name = charDisplayName(char),
							weapons = weapons,
						}
					end
				end
			end
		end
	end
	return players
end

Core.Callback.Register("vorpinventory:openWeaponRegistry", function(source, cb)
	if not registryEnabled() then return cb(false) end
	local user = Core.getUser(source)
	if not user then return cb(false) end
	if not hasJob(user.getUsedCharacter, Config.WeaponRegistry.RegisterJobs) then
		Core.NotifyRightTip(source, "Only lawmen can use the weapon registry.", 4000)
		return cb(false)
	end
	return cb(getNearbyPlayersData(source))
end)

RegisterServerEvent("vorpinventory:registryRegisterWeapon", function(weaponId, targetServerId)
	local _source = source
	if not registryEnabled() then return end
	local user = Core.getUser(_source)
	if not user then return end
	if not hasJob(user.getUsedCharacter, Config.WeaponRegistry.RegisterJobs) then return end

	weaponId = tonumber(weaponId)
	targetServerId = tonumber(targetServerId)
	if not weaponId or not targetServerId then return end

	local targetUser = Core.getUser(targetServerId)
	if not targetUser then return end
	local targetChar = targetUser.getUsedCharacter

	local weapon = UsersWeapons.default and UsersWeapons.default[weaponId]
	if not weapon or weapon.propietary ~= targetChar.identifier then
		return Core.NotifyRightTip(_source, "That weapon is no longer on that player.", 4000)
	end

	local serial = weapon:getSerialNumber()
	if not isValidSerial(serial) then
		return Core.NotifyRightTip(_source, "This weapon has no serial number and cannot be registered.", 5000)
	end

	local existing = MySQL.query.await("SELECT owner_name FROM vorp_weapon_registry WHERE serial = @serial;", { serial = tostring(serial) })
	if existing and existing[1] then
		Core.NotifyRightTip(_source, ("Serial %s is already registered to %s."):format(serial, existing[1].owner_name or "someone"), 5000)
		TriggerClientEvent("vorpinventory:registryData", _source, getNearbyPlayersData(_source))
		return
	end

	local ownerName = charDisplayName(targetChar)
	MySQL.query.await([[INSERT INTO vorp_weapon_registry (serial, weapon_name, owner_name, owner_charid, registered_by)
		VALUES (@serial, @wname, @owner, @charid, @by)
		ON DUPLICATE KEY UPDATE weapon_name = @wname, owner_name = @owner, owner_charid = @charid,
		registered_by = @by, registered_at = CURRENT_TIMESTAMP;]], {
		serial = tostring(serial),
		wname = weapon:getName(),
		owner = ownerName,
		charid = targetChar.charIdentifier,
		by = charDisplayName(user.getUsedCharacter),
	})

	Core.NotifyRightTip(_source, ("Registered %s (serial %s) to %s."):format(weapon:getName(), serial, ownerName), 6000)
	Core.NotifyRightTip(targetServerId, ("Your %s (serial %s) was registered to you by the law."):format(weapon:getName(), serial), 6000)

	TriggerClientEvent("vorpinventory:registryData", _source, getNearbyPlayersData(_source))
end)

Core.Callback.Register("vorpinventory:refreshWeaponRegistry", function(source, cb)
	if not registryEnabled() then return cb(false) end
	local user = Core.getUser(source)
	if not user or not hasJob(user.getUsedCharacter, Config.WeaponRegistry.RegisterJobs) then return cb(false) end
	return cb(getNearbyPlayersData(source))
end)

Core.Callback.Register("vorpinventory:registrySearchSerial", function(source, cb, serial)
	if not registryEnabled() then return cb(false) end
	local user = Core.getUser(source)
	if not user then return cb(false) end
	if Config.WeaponRegistry.CheckerJobsOnly and not hasJob(user.getUsedCharacter, Config.WeaponRegistry.RegisterJobs) then
		return cb(false)
	end
	if not serial or serial == "" then return cb(nil) end
	local result = MySQL.query.await("SELECT * FROM vorp_weapon_registry WHERE serial = @serial;", { serial = tostring(serial) })
	return cb(result and result[1] or nil)
end)
