#version 2
#include "inventory_api.lua"
#include "items.lua"
#include "clothing.lua"
#include "weapons.lua"

-- Example Pack for the McPuppet Inventory System. Copy this folder into Documents/Teardown/mods, rename it, change
-- the ids ("examplepack_...") to your own, and replace the files in icons/, vox/ and prefab/.
--
--   items.lua     a bandage (consumable), a gold bar (plain item), extras for the crowbar below
--   clothing.lua  a striped T-shirt and a cap        (guide: MODDING_CLOTHING.md in the Inventory mod's folder)
--   weapons.lua   a frying pan with a swing           (guide: MODDING_WEAPONS.md)
--
-- Keep the files you need. Each one says at its top which lines of this file belong to it. inventory_api.lua is
-- only needed for clothing.lua and weapons.lua (it is a copy of the file in the Inventory mod's folder).

local greeted = {}       -- players who got their welcome present

function server.init()
	-- A tool of your own. The Inventory mod picks up every registered tool as an item, with no more code.
	-- (What the tool DOES when it is used is your mod's own script, as for any Teardown tool.)
	RegisterTool("examplepack_crowbar", "Crowbar", "MOD/vox/crowbar.vox", 1)
	ExamplePackItems()                                               -- (items.lua)
	InventoryServerInit()                                            -- (weapons.lua: the pan becomes a tool)
end

function client.init()
	ExamplePackItems()                                               -- (items.lua)
end

function client.tick(dt)
	InventoryClientTick()                                            -- (clothing.lua and weapons.lua)
end

function server.tick(dt)
	-- Handing items out: append "id:count" to inventory.give.<player> on the host. Here: two bandages and a gold
	-- bar for everyone who joins. (items.lua)
	for _, p in ipairs(GetAllPlayers()) do
		if not greeted[p] then
			greeted[p] = true
			local key = "inventory.give." .. p
			SetString(key, GetString(key) .. " examplepack_bandage:2 examplepack_goldbar:1")
		end
	end
end
