-- Example clothes for the McPuppet Inventory System: a striped T-shirt and a cap.
-- The guide: MODDING_CLOTHING.md in the Inventory mod's folder. Painted on vox/template.vox.
--
-- What this file needs in main.lua (delete this file and those lines if your pack has no clothes):
--     #include "inventory_api.lua"          (before this file's #include)
--     #include "clothing.lua"
--     function client.tick(dt) InventoryClientTick() end

-- a skin-tight garment: it IS the body parts it covers, repainted (bare skin left in it takes the wearer's skin
-- colour: tint = true)
InventoryClothing({
	id = "examplepack_striped_tshirt",        -- unique, no dots or spaces: start it with your mod's name
	name = "Striped T-Shirt",
	slot = "top",                             -- head, top, legs or feet
	layer = 1,                                -- 1 = skin tight, 2 = worn over
	vox = "MOD/vox/striped_tshirt.vox",
	parts = "chest stomach shoulder_l shoulder_r arm_upper_l arm_upper_r",       -- the objects in the .vox
	covers = "chest stomach shoulder_l shoulder_r arm_upper_l arm_upper_r",      -- the body parts it replaces
	tint = true,                              -- (keep it for everything made from template.vox)
	armor = 0.02, mobility = 0, noise = 0,
	type = "clothing.upper.stripedtshirt",
	price = 70,
	icon = "icons/striped_tshirt.png",
	drop = "vox/drop_striped_tshirt.vox",
})

-- a head piece: worn over the wearer's own head (covers nothing), fitted to that head with its hair
InventoryClothing({
	id = "examplepack_cap",
	name = "Blue Cap",
	slot = "head",
	layer = 2,
	vox = "MOD/vox/cap.vox",
	parts = "head",
	covers = "",
	tint = true,
	armor = 0.01, mobility = 0, noise = 0,
	type = "clothing.head.cap",
	price = 40,
	icon = "icons/cap.png",
	drop = "vox/drop_cap.vox",
})
