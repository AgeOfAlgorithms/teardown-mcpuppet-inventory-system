-- An example melee weapon for the McPuppet Inventory System: a frying pan.
-- The guide: MODDING_WEAPONS.md in the Inventory mod's folder. Its model is vox/pan.vox, its tool prefab prefab/pan.xml.
-- The Inventory mod swings it, follows it as the hit box and deals the damage.
--
-- What this file needs in main.lua (delete this file and those lines if your pack has no weapons):
--     #include "inventory_api.lua"          (before this file's #include)
--     #include "weapons.lua"
--     InventoryServerInit()                 (in server.init: your weapons become tools)
--     function client.tick(dt) InventoryClientTick() end

InventoryWeapon({
	id = "examplepack_pan",
	name = "Frying Pan",
	prefab = "MOD/prefab/pan.xml",
	hands = 1,                                -- 1 or 2
	style = "chop",                           -- one hand: slash, stab, chop; two hands: smash, sweep, thrust
	length = 0.55,                            -- m from the grip to the tip (the "tip" location in the prefab)
	power = 0.22,                             -- share of full health a hit takes
	delay = 0.30,                             -- s from the click to the blow
	cooldown = 0.40,                          -- s after the blow
	knockback = 6,                            -- m/s
	hole = {0.2, 0.1, 0},                     -- MakeHole radii (m): soft, medium, hard materials
	type = "weapon.melee.onehanded.fryingpan",
	price = 120,
	icon = "icons/pan.png",
})
