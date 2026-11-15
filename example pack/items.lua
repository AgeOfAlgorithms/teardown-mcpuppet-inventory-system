-- Example items for the McPuppet Inventory System: a bandage, a gold bar, extras for a tool.
--
-- What this file needs in main.lua (delete this file and those lines if your pack has no such items):
--     #include "items.lua"
--     ExamplePackItems()                    (in server.init AND in client.init)
-- Everything is said through the registry
-- (SetString / SetInt / SetFloat / SetBool): mods cannot call each other. See MODDING.md in the Inventory mod.
--
-- Call this once on EVERY machine: from server.init (the host) and from client.init (each player).

function ExamplePackItems()
	-- A consumable: stacks to 5, heals a quarter of the health when used (put it on a hotkey, press the number).
	SetString("inventory.items.examplepack_bandage.name", "Bandage")
	SetString("inventory.items.examplepack_bandage.kind", "consumable")
	SetInt("inventory.items.examplepack_bandage.stack", 5)
	SetFloat("inventory.items.examplepack_bandage.heal", 0.25)
	SetInt("inventory.items.examplepack_bandage.price", 40)                    -- the store sells it for 40
	SetString("inventory.items.examplepack_bandage.icon", "icons/bandage.png") -- a file in THIS mod's folder
	SetString("inventory.items.examplepack_bandage.drop", "vox/bandage.vox")   -- how it looks lying in the world

	-- A plain item: stacks to 10, not sold in the store (no price), only found or handed out.
	SetString("inventory.items.examplepack_goldbar.name", "Gold Bar")
	SetString("inventory.items.examplepack_goldbar.kind", "misc")
	SetInt("inventory.items.examplepack_goldbar.stack", 10)
	SetString("inventory.items.examplepack_goldbar.icon", "icons/goldbar.png")
	SetString("inventory.items.examplepack_goldbar.drop", "vox/goldbar.vox")

	-- A tool (registered with RegisterTool in main.lua) is an item by itself. These lines are optional extras:
	SetString("inventory.tools.examplepack_crowbar.icon", "icons/crowbar.png")
	SetInt("inventory.tools.examplepack_crowbar.price", 300)
end
