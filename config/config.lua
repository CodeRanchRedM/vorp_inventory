Lang = "en" -- en, tr, fr, it, es, ar, pl

Config = {

    EnablePushToTalk = true, -- If true, the player can use push to talk to talk to other players while inventory is open

    -- ======================= DEVELOPMENT ============================== --
    Debug = false, -- If your server is live set this to false.  to true only if you are testing things

    InventoryOrder = "items", -- Items or weapons what should should first in inventory --- [REMOVED]

    DevMode = false, -- If your server is live set this to false.  to true only if you are testing things (auto load inventory when script restart and before character selection. Alos add /getInv command)

    dbupdater = true,
    -- ======================= CONFIGURATION ============================= --
    ShowCharacterNameOnGive = true, -- When giving an item, show the character name of nearby players instead of their player ID. if set to false, show the player ID
    ShowCharacterNameInTitle = true, -- If true, inventory title shows "[Character Name] - ID" instead of "Inventory [ID]"

    DoubleClickToUse = true, -- If toggled to false, items in inventory will right click then left click "use"

    NewPlayers = false, -- If you dont want new players to give money or items then set to true. this can avoid cheaters giving stuff on first join

    CoolDownNewPlayer = 120, -- In seconds how long they have to wait before they can give items or money

    -- GOLD ITEM LIKE DOLLARS
    UseRolItem = false, -- To show rol in inventory

    UseGoldItem = true,

    AddGoldItem = true, -- Should there be an item in inventory to represent gold

    AddDollarItem = true, -- Should there be an item in inventory to represent dollars

    AddAmmoItem = true, -- Should there be an item in inventory to represent the gun belt

    PlayerInventorySlots = 50, -- Number of slots in player inventory

    DisableDeathInventory = true, -- Prevent the ability to access inventory while dead

    OpenKey = 0xC1989F95, -- I

    discordid = true, -- Turn to true if ur using discord whitelist

    DeleteOnlyDontDrop = false, -- If true then dropping items only deletes from inventory and box on the floor is not created

    UseLanternPutOnBelt = true, -- If true then lanterns will be put on belt

    WeightMeasure = "kg", -- Weight measure (kg, lbs, etc)

    DeleteItemOnUseWhenExpired = false, -- if true items on use that are expired will be deleted -- [Removed]

    DeletePickups = {
        Enable = false, -- if true it will add timer to delete pickups
        Time = 10 -- after this time pick up wll be deleted, IN MINUTES
    },

    DropInventory = {
        MaxWeight = 50.0, -- Max weight for drop inventory
        Slots = 35, -- Number of slots in drop inventory
        UsePropMarker = true, -- If true, spawn a prop instead of drawing the marker below
        PropMarker = {
            Model = "p_cottonbox01x",
            ZOffset = -1.0
        },
        Marker = {
            Sprite = 0x6903B113, -- Marker type hash (halo)
            Scale = {
                x = 0.8,
                y = 0.8,
                z = 0.3
            }, -- Marker size
            Color = {
                r = 202,
                g = 165,
                b = 128,
                a = 120
            }, -- RGBA color
            DrawDistance = 5.0, -- Distance to start drawing marker
            InteractDistance = 2.0 -- Distance to interact with drop
        }
    },

    -- stashType (optional): nil = normal stash, "cooler" or "refrigerator" =
    -- preserving stash. Items inside a preserving stash decay slower (cooler)
    -- or not at all (refrigerator). See Config.Preservation below.
    Stashes = {{
        id = "stash_valentine_sheriff",
        name = "Valentine Sheriff Stash",
        coord = vector3(-278.46, 805.17, 119.38),
        maxWeight = 100.0,
        slots = 30,
        shared = true,
        allowedJobs = {"police", "sheriff"} -- "all" or job list
    }, {
        id = "stash_personal",
        name = "Personal Stash",
        coord = vector3(-303.51, 777.42, 118.72),
        maxWeight = 50.0,
        slots = 20,
        shared = false,
        allowedJobs = "all"
    }, {
        id = "cooler_valentine",
        name = "Cooler",
        coord = vector3(-310.86, 802.51, 118.93),
        maxWeight = 30.0,
        slots = 12,
        shared = true,
        allowedJobs = "all",
        stashType = "cooler" -- slows food decay
    }, {
        id = "refrigerator_valentine",
        name = "Refrigerator",
        coord = vector3(-281.30, 808.45, 119.38),
        maxWeight = 70.0,
        slots = 24,
        shared = true,
        allowedJobs = "all",
        stashType = "refrigerator" -- fully halts food decay
    }},

    StashPrompt = {
        Key = 0xCEFD9220, -- E key
        HoldDuration = 500, -- ms
        DrawDistance = 2.0
    },

    -- Modulates the decay speed of degradable items (anything with maxDegradation
    -- in the items database). Works with the existing durability/freshness system.
    Preservation = {
        Enabled = true,
        TickMinutes = 1, -- how often decay is recalculated (minutes)

        -- Decay multiplier while an item sits inside a stash of this stashType.
        -- 0.0 = item never decays, 1.0 = normal decay.
        StashDecayMultipliers = {
            cooler = 0.15, -- coolers greatly slow decay
            refrigerator = 0.0 -- refrigerators fully halt decay
        },

        -- Weather / temperature. Cold weather preserves food better, heat rots it.
        Weather = {
            -- Set to false to disable and only use GlobalState / DefaultWeather.
            SyncResource = "weathersync",
            DefaultWeather = "OVERCAST",
            Multipliers = {
                default = 1.0,
                SUNNY = 1.35, -- hot: food rots faster
                HIGHPRESSURE = 1.35,
                SANDSTORM = 1.4,
                CLEAR = 1.2,
                CLEARING = 1.2,
                OVERCAST = 1.0,
                CLOUDS = 1.0,
                MISTY = 0.95,
                MIST = 0.95,
                FOG = 0.95,
                RAIN = 0.85,
                DRIZZLE = 0.85,
                SHOWERS = 0.85,
                SHOWER = 0.85,
                THUNDER = 0.85,
                THUNDERSTORM = 0.85,
                HAIL = 0.6,
                SLEET = 0.5,
                SNOWLIGHT = 0.5,
                SNOW = 0.4, -- cold: food preserved well
                BLIZZARD = 0.3,
                GROUNDBLIZZARD = 0.3,
                WHITEOUT = 0.3
            }
        },

        -- Cured / salted food keeps longer. Either list item names here or set
        -- metadata.salted = true on the item when you create it.
        SaltedMultiplier = 0.5,
        SaltedItems = {
            -- ["consumable_saltedmeat"] = true,
        },

        -- Raw / perishable food (meat, fish) spoils faster.
        PerishableMultiplier = 1.6,
        PerishableItems = {
            -- ["consumable_meat"] = true,
            -- ["consumable_rawfish"] = true,
        },

        -- Rotten food. When a degradable consumable is used at or below this
        -- freshness %, vorp_inventory fires 'vorp_inventory:Server:OnRottenItemUse'
        -- so your consumable scripts can apply extra hunger/thirst/sickness.
        AllowEatingRotten = true, -- if true, expired/rotten food can still be eaten
        RottenThreshold = 35 -- freshness % at or below which food counts as rotten
    },

    -- Lawmen open a registry UI at a station: they see weapons on nearby players
    -- and can register them, and can look up any serial number by search.
    -- Also available as commands: /registerweapon <playerId>  and  /checkserial <serial>
    WeaponRegistry = {
        Enabled = true,
        RegisterJobs = {"police", "sheriff"}, -- jobs allowed to register / open the registry
        CheckerJobsOnly = false, -- true = only RegisterJobs can /checkserial
        NearbyRange = 5.0, -- how close a player must be to show in the registry UI
        PromptKey = 0xCEFD9220, -- E key — opens the registry UI at a station
        PromptDistance = 2.0,
        -- Registry station locations. Lawmen press the prompt key here.
        -- Adjust to a sheriff-office desk on your map.
        Stations = {vector3(-278.95, 803.86, 119.38)}
    },

    DuelWield = true, -- If true duel wielding will be allowed.

    StealRequiresWeapon = true, -- If true, player must have a weapon equipped to steal

    -- Items / weapons the victim is allowed to keep when being robbed.
    -- Any name listed here is hidden from the steal panel and cannot be taken,
    -- even if the would-be thief crafts a request server-side.
    StealBlacklist = {
        -- Item names match the `name` column of character_inventories.
        Items = {
            -- ["consumable_raspberrywater"] = true,
        },
        -- Weapon hash names match the `name` column of loadout.
        Weapons = {
            WEAPON_MELEE_KNIFE = true -- starter knife
        }
    },

    -- ============================ CONTEXT MENU ACTIONS ==========================
    -- The right-click context menu can show Use/Give action buttons alongside the
    -- existing item-info panel. When enabled, you can optionally hide the larger
    -- Use/Give buttons in the right-side column so all interactions go through
    -- the context menu.
    ContextMenuActions = {
        Enabled = true, -- show Use/Give inside the right-click context menu
        HideRightColumnButtons = true -- also hide the existing Use/Give buttons next to the inventory
    },

    -- DONOT EDIT FOR NOW
    WeaponWheel = {
        Enabled = false
    },

    -- ============================ HOLSTERING ====================================
    -- Visual weapon attachment: when a player has a weapon equipped (selected) but
    -- not currently in hand, spawn a prop of that weapon and attach it to the body
    -- so it's visible on the hip / back. Pure cosmetic — does not affect mechanics.
    WeaponHolstering = {
        Enabled = false, -- master switch
        PollInterval = 500, -- ms between checks
        -- Bone + offset per weapon category (categories from Config.WeaponCategories).
        -- BoneHash from PedBones (try IDs from RDR3 ped skeletons). Offsets are
        -- relative (forward / right / up); rotations in degrees.
        Bones = {
            Sidearm = {
                bone = 23553,
                offsetX = 0.10,
                offsetY = -0.07,
                offsetZ = -0.03,
                rotX = 0.0,
                rotY = 0.0,
                rotZ = 0.0
            }, -- right hip
            Long = {
                bone = 24818,
                offsetX = -0.08,
                offsetY = -0.18,
                offsetZ = 0.16,
                rotX = 0.0,
                rotY = 180.0,
                rotZ = 0.0
            }, -- back / spine
            Melee = {
                bone = 23553,
                offsetX = 0.05,
                offsetY = -0.20,
                offsetZ = -0.05,
                rotX = -90.0,
                rotY = 0.0,
                rotZ = 0.0
            }, -- left hip
            Bow = {
                bone = 24818,
                offsetX = -0.10,
                offsetY = -0.20,
                offsetZ = 0.20,
                rotX = 0.0,
                rotY = 180.0,
                rotZ = 0.0
            }
            -- Throwable/Lasso/Other not attached by default — add entries to enable.
        },
        -- Override per-weapon prop models if the default joaat("w_"..name) doesn't load.
        -- Most weapons have a corresponding `w_<weaponname>` model that works.
        ModelOverrides = {
            -- WEAPON_REVOLVER_CATTLEMAN = "w_pistol_cattleman",
        }
    },

    WeaponDurability = {
        Enabled = true,
        DurabilityLossPerShot = 0.5, -- durability loss per bullet fired (percentage)
        MinDurabilityToUse = 0, -- weapon cannot be used below this value ()
        MaxRepairTime = 60000, -- ms, max repair time when durability is 0 (60s)
        RepairLocations = {{
            coord = vector3(-279.49, 783.75, 119.5)
        } -- Valentine
        },

        -- Items the player must have in inventory to repair a weapon. Consumed on repair.
        -- Each entry: { item = "<db item name>", amount = <int>, applies = <list|"all"|nil> }
        --   `applies` can be:
        --     "all" or nil  → required for every weapon
        --     { "WEAPON_REVOLVER_", "WEAPON_PISTOL_" } → required only for weapons whose
        --                     name starts with any of these prefixes. Use the full hash
        --                     name for an exact match (e.g. "WEAPON_BOW").
        -- Multiple entries can apply to the same weapon — all of them are required.
        -- Leave the list empty {} to keep the legacy behavior (no items required).
        RepairItems = {
            -- { item = "gun_oil",   amount = 1, applies = { "WEAPON_REVOLVER_", "WEAPON_PISTOL_", "WEAPON_RIFLE_", "WEAPON_REPEATER_", "WEAPON_SHOTGUN_", "WEAPON_SNIPERRIFLE_" } },
            -- { item = "gun_cloth", amount = 1, applies = "all" },
            -- { item = "whetstone", amount = 1, applies = { "WEAPON_MELEE_", "WEAPON_THROWN_" } },
            -- { item = "bowstring", amount = 1, applies = { "WEAPON_BOW" } },
        }
    },

    SpamDelay = 2000, -- ms | The minimum time that must elapse between using one item and being able to use another item in the inventory.

    -- ==================== ANIMATION ==================== --
    OpenInventoryAnimation = {
        Enabled = true,
        Dict = "script_camp@cash_box",
        Anim = "open_satchel"
    },

    -- ==================== SOUND CONFIGURATION ==================== --
    SFX = { -- Inventory Sound Effects
        OpenInventory = true, -- The sound effect when open the inventory
        CloseInventory = true, -- The sound effect when close the inventory
        ItemHover = true, -- The sound effect when hovering the mouse cursor over an item/choose the item in the inventory

        ItemDrop = true, -- The sound effect when drop the item
        MoneyDrop = true, -- The sound effect when drop the money
        GoldDrop = true, -- The sound effect when drop the gold
        PickUp = true -- The sound effect when pick up the item
    },

    -- =================== CLEAR ITEMS WEAPONS MONEY GOLD ===================== --

    UseClearAll = false, -- If you want to use the clear item function

    OnPlayerRespawn = {
        Money = {
            JobLock = {"police", "doctor"}, -- Wont remove from these jobs
            ClearMoney = true, -- If true then removes all money from player
            MoneyPercentage = false -- If false wont use percentage if you add number   0.1 = 10% of money user have instead of all
        },
        Items = {
            JobLock = {"police", "doctor"},
            itemWhiteList = {"consumable_raspberrywater", "ammorevolvernormal"}, -- Dont delete these items
            AllItems = true -- If true then removes all items from player
        },
        Weapons = {
            JobLock = {"police", "doctor"},
            WeaponWhitelisted = {"WEAPON_MELEE_KNIFE", "WEAPON_BOW"}, -- Dont delete these weapons
            AllWeapons = true -- If true then removes all weapons from player
        },
        Ammo = {
            JobLock = {"police", "doctor"}, -- Wont remove from these jobs
            AllAmmo = true -- If true then removes all ammo from player
        },
        Gold = {
            JobLock = {"police", "doctor"},
            ClearGold = false,
            GoldPercentage = false
        }
    },

    -- HOW MANY WEAPONS ALLOWED PER PLAYER FOR ITEMS IS IN VORP CORE CONFIG
    MaxItemsInInventory = {
        -- Either a single number (total cap, legacy behavior):
        --   Weapons = 6,
        -- Or a table for per-category caps + optional total:
        --   Weapons = { Sidearm = 2, Long = 2, Melee = 2, Throwable = 2, Bow = 1, Other = 2, Total = 6 },
        -- Categories are defined by WeaponCategories below.
        -- -1 = unlimited, 0 = blocked entirely.
        Weapons = 6
    },

    -- HERE YOU CAN SET THE MAX AMOUNT OF WEAPONS PER JOB (IF YOU WANT)
    -- Same shape as MaxItemsInInventory.Weapons — either a number (total cap) or a table.
    JobsAllowed = {
        police = 10 -- Job name and max weapons allowed dont allow less than the above
    },

    -- Maps weapon-name prefixes (or full hash names) to a category. Used by
    -- per-category limits above and by the repair-item filter (config.WeaponDurability.RepairItems).
    -- Weapons whose name doesn't match any prefix fall into "Other".
    WeaponCategories = {
        Sidearm = {"WEAPON_REVOLVER_", "WEAPON_PISTOL_"},
        Long = {"WEAPON_RIFLE_", "WEAPON_REPEATER_", "WEAPON_SHOTGUN_", "WEAPON_SNIPERRIFLE_"},
        Melee = {"WEAPON_MELEE_"},
        Throwable = {"WEAPON_THROWN_"},
        Bow = {"WEAPON_BOW"},
        Lasso = {"WEAPON_LASSO"}
    },

    -- FIRST JOIN
    startItems = {
        consumable_raspberrywater = 2, -- ITEMS SAME NAME AS IN DATABASE
        ammorevolvernormal = 1 -- AMMO SAME NAME AS IN THE DATABASE
    },

    startWeapons = {"WEAPON_MELEE_KNIFE" -- WEAPON HASH NAME
    },

    -- Items that dont get added up torwards your max weapon count
    notweapons = {
        WEAPON_KIT_BINOCULARS_IMPROVED = true,
        WEAPON_KIT_BINOCULARS = true,
        WEAPON_FISHINGROD = true,
        WEAPON_KIT_CAMERA = true,
        WEAPON_KIT_CAMERA_ADVANCED = true,
        WEAPON_MELEE_LANTERN = true,
        WEAPON_MELEE_DAVY_LANTERN = true,
        WEAPON_MELEE_LANTERN_HALLOWEEN = true,
        WEAPON_KIT_METAL_DETECTOR = true,
        WEAPON_MELEE_HAMMER = true,
        WEAPON_MELEE_KNIFE = true
    },

    -- Weapons that are considered non throwables
    nonAmmoThrowables = {
        WEAPON_MELEE_CLEAVER = true,
        WEAPON_MELEE_HATCHET = true,
        WEAPON_MELEE_HATCHET_HUNTER = true
    },

    -- Weapons that dont need serial numbers
    noSerialNumber = {
        WEAPON_MELEE_KNIFE = true,
        WEAPON_MELEE_KNIFE_JAWBONE = true,
        WEAPON_MELEE_KNIFE_TRADER = true,
        WEAPON_MELEE_KNIFE_CIVIL_WAR = true,
        WEAPON_MELEE_KNIFE_HORROR = true,
        WEAPON_MELEE_KNIFE_MINER = true,
        WEAPON_MELEE_KNIFE_RUSTIC = true,
        WEAPON_MELEE_KNIFE_VAMPIRE = true,
        WEAPON_MELEE_MACHETE = true,
        WEAPON_MELEE_MACHETE_COLLECTOR = true,
        WEAPON_MELEE_HAMMER = true,
        WEAPON_MELEE_TORCH = true,
        WEAPON_MELEE_CLEAVER = true,
        WEAPON_MELEE_HATCHET = true,
        WEAPON_MELEE_HATCHET_HUNTER = true,
        WEAPON_MELEE_HATCHET_DOUBLE_BIT = true,
        WEAPON_KIT_BINOCULARS_IMPROVED = true,
        WEAPON_KIT_BINOCULARS = true,
        WEAPON_KIT_CAMERA = true,
        WEAPON_KIT_CAMERA_ADVANCED = true,
        WEAPON_KIT_METAL_DETECTOR = true,
        WEAPON_MELEE_LANTERN = true,
        WEAPON_MELEE_DAVY_LANTERN = true,
        WEAPON_MELEE_LANTERN_HALLOWEEN = true,
        WEAPON_FISHINGROD = true,
        WEAPON_BOW = true,
        WEAPON_BOW_IMPROVED = true,
        WEAPON_LASSO = true,
        WEAPON_LASSO_REINFORCED = true,
        WEAPON_MOONSHINEJUG_MP = true
    },

    UseWeaponModels = true, -- If true, weapons will spawn with a model other wise they default to the default_box prop
    -- for dropped weapons , some will spawn standing so we modify their rotation
    weaponAdjustments = {
        WEAPON_MELEE_KNIFE = 90.0,
        WEAPON_BOW = 90.0,
        WEAPON_BOW_IMPROVED = 90.0,
        WEAPON_MELEE_KNIFE_RUSTIC = 90.0,
        WEAPON_MELEE_KNIFE_HORROR = 90.0,
        WEAPON_MELEE_KNIFE_CIVIL_WAR = 90.0,
        WEAPON_MELEE_KNIFE_JAWBONE = 90.0,
        WEAPON_MELEE_KNIFE_MINER = 90.0,
        WEAPON_MELEE_KNIFE_VAMPIRE = 90.0,
        WEAPON_MELEE_HATCHET = 90.0,
        WEAPON_MELEE_HATCHET_HUNTER = 90.0,
        WEAPON_MELEE_HATCHET_DOUBLE_BIT = 90.0,
        WEAPON_MELEE_MACHETE_COLLECTOR = 90.0,
        WEAPON_MELEE_MACHETE = 90.0,
        WEAPON_MELEE_CLEAVER = 90.0,
        WEAPON_MELEE_HAMMER = 90.0,
        WEAPON_FISHINGROD = 90.0
        -- add here if more need to change rotation
    },

    -- Cinderwake custom ammo HUD
    -- Shows loaded / reserve ammo while a compatible weapon is equipped.
    AmmoHud = {
        Enabled = true -- set false to disable the ammo HUD completely
    },

    -- dropp items can have a diferent model added them here item name and object
    spawnableProps = {
        default_box = "p_cottonbox01x", -- default when object is not found will always spawn this object for weapon or items
        money_bag = "p_moneybag02x", -- prop for the money pickup
        gold_bag = "s_pickup_goldbar01x" -- prop for the gold pickup
        -- add more here
    }
}
