#version 2
-- Inventory: a full inventory on any map, multiplayer (PROJECT.md). A global mod. The model is inv_core.lua, the
-- engine side inv.lua. The wear engine (clothes on the character, armour, mobility, melee weapons) is the next
-- five files: written and owned by the Wardrobe session, not edited here; its hooks run before ours.

#include "wardrobe_rig.lua"
#include "inventory_api.lua"
#include "script/toolanimation.lua"
#include "melee.lua"
#include "wardrobe_engine.lua"
#include "inv_core.lua"
#include "inv.lua"
#include "inv_color.lua"
#include "inv_keep.lua"
#include "inv_scatter.lua"

-- (test builds add their modules here)

-- INV_PASSIVE (a global a test build of the wear engine sets): the inventory itself does nothing - no screen, no
-- input, nothing written for the players - so that the engine's own scenes decide who wears and holds what.
-- Weapons are handed out by the inventory, not put into everyone's wheel (unless passive).
if not INV_PASSIVE then WeaponsAuto = false end

function server.init()
	InvWearServerInit()
	if INV_PASSIVE then return end
	Inv.serverInit()
	if INV_TEST then INV_TEST.serverInit() end
end

function server.tick(dt)
	InvWearServerTick(dt)
	if INV_PASSIVE then return end
	Inv.serverTick(dt)
	if INV_TEST then INV_TEST.serverTick(dt) end
end

function server.update(dt)
	if INV_PASSIVE then return end
	Inv.serverEnforce()
end

function server.postUpdate()
	if INV_PASSIVE then return end
	Inv.serverEnforce()
end

function server.destroy()
	if INV_PASSIVE then return end
	Inv.serverDestroy()
end

function client.init()
	InvWearClientInit()
	if INV_PASSIVE then return end
	Inv.clientInit()
	if INV_TEST then INV_TEST.clientInit() end
end

function client.tick(dt)
	InvWearClientTick(dt)
	if INV_PASSIVE then return end
	if INV_TEST then INV_TEST.clientTick(dt) end
	Inv.clientTick(dt)
end

function client.postUpdate()
	InvWearClientPostUpdate()
	if INV_PASSIVE then return end
	Inv.clientPostUpdate()
end

function client.draw()
	if INV_PASSIVE then return end
	Inv.clientDraw()
	if INV_TEST then INV_TEST.clientDraw() end
end
