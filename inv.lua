-- Inventory: the engine side (PROJECT.md). Included by main.lua (no #version line; globals only); the model is
-- inv_core.lua (InvCore). The host owns every inventory and every item lying in the world; clients ask
-- (ServerCall), the host moves, shared.inv shows the result.
--
-- For other mods (host registry; mods cannot call each other):
--   inventory.take.<player> = "id[:n] id ..."           take items back (n: how many, none: all of them; from the
--                                                        grid, the hotkeys and what is worn; missing ones ignored;
--                                                        nothing dropped; read and cleared each tick, host)
--   inventory.give.<player> = "id[:n[:ammo]] id ..."   hand items out (append to the string; read and cleared each
--                                                       tick; what does not fit lands at the player's feet)
--   inventory.items.<id>.name / .kind (tool | clothing | consumable | misc) / .stack / .slot / .armor / .icon
--   inventory.items.<id>.mobility / .noise               clothing: added to the wearer's mobility (walking speed
--                                                        and jump height) / noise as a share (-0.1 = 10 % less,
--                                                        -0.3 = 30 % quieter)
--   inventory.stat.<player>.immunity                     (host) defense / 5: a hit takes max(0, min(damage -
--                                                        immunity, damage * (1 - defense))); elemental: no armour
--   inventory.stat.<player>.defense / .mobility / .noise    (host, written here) what the player wears adds up to:
--                                                        defense 0..1, mobility and noise as factors (1 = unchanged).
--                                                        An enemy mod multiplies the noise it hears by .noise.
--                                                       define an item, on every machine (client init too)
--   a body tagged invitem=<id> (+ n=<count>, ammo=<n>)  is an item lying in the world (maps, spawn menu)
--   inventory.count.<player>.<id>                       how many that player carries (host, written on change)
--   inventory.tools.<tool id>.ammo = n / .spent = bool    a mod's tool: the ammo of one item, gone when used up
--   inventory.tools.<tool id>.icon / .price              a mod's tool: its picture (a file in that mod's folder) and
--                                                        what the store asks (-1: not sold)
--   inventory.items.<id>.drop / .price                   the item's model lying in the world (a .vox in the mod's
--                                                        folder, full-size voxels), what the store asks
--   ....mod = "<mod id>"                                 (tools and items) whose folder .icon / .drop are in; left
--                                                        out, the enabled mod that has the file is found
--   inventory.colors.<id>.name / .text / .rgb / .list / .material / .tinted / .source   (host, synced) every item's
--                                                        colours, read off its model or from its mod's .color key
--                                                        (inv_color.lua)
--   (the guide for other mods: MODDING.md)
--   inventory.punch = 0 / .power / .delay / .cooldown / .reach   (host) the bare-hands punch: off / retuned
--   inventory.gold.<player> = n                          (host, synced) that player's gold coins, the store's money:
--                                                        any mod may add to it (a reward) or take from it; read it
--                                                        back each time, never keep a copy. Every player starts
--                                                        with INV_GOLD_START
--   inventory.free = true                                (host) the store asks no money
--   inventory.scatter = false                           (host) a game mode's: no gold lying around the map (the
--                                                        mod's option; inv_scatter.lua) - the piles out are removed
--   inventory.consumables = false                       (host) a game mode's: consumables can't be used (a note, the
--                                                        item kept) and running speed boosts end; unset or true: allowed
--   inventory.healing = false                           (host) a game mode's: consumables that heal can't be used (a
--                                                        note, the item kept); the others can (Brawl)
--   inventory.items.<id>.heal = 0..1                    a consumable: using it (its hotkey) gives that much health
--   inventory.used.last / .<n % 16>.player / .id        a consumable was used (fields first, the counter last)
--   inventory.price.<id> = n                            the store's price of an item (-1: not sold); unset: a default
--   inventory.store = 0                                 no store (a map or a game mode turns it off)
--   inventory.block.<player> = true                     (host, synced) the inventory is OFF for that player: no screen,
--                                                       HUD, pickups, punch, store, consumables, clothing effects; their
--                                                       tool wheel left alone; what they have is kept (not dropped at
--                                                       death) and back when the key is false or cleared
--   inventory.goldadd.<player> = "n[:reason] ..."       (host) gold paid (+n) or taken (-n), appended by any mod, read
--                                                       and cleared each tick: on the wallet (made first if missing),
--                                                       never below 0, saved; a note "+150 gold: Round won" (_ in a
--                                                       reason shows as a space) unless the player is blocked
--   inventory.present = true                            (synced) the Inventory runs (set again every second)
--   inventory.spend.<player> = "token:n[:reason] ..."   (host) a mod's purchases, read and cleared each tick, each all
--                                                       or nothing; inventory.spent.<token> = "ok" / "no" (host, the
--                                                       buying mod clears it); works while blocked
--   inventory.gold.<player>                             made as soon as a player is seen (not with inventory.free)
--   inventory.key.open = "i"                            (every machine) the key that opens the inventory screen
--   inventory.screenopen = true                         (every machine, local) this player's inventory screen is open:
--                                                       hide world labels / name tags that would draw over it
--   inventory.keep = "session" / "map"                  (synced) the host's option: kept until NEW SESSION, or reset
--                                                       with every map / mode change
--   inventory.session = "s<n>"                          (synced) changes whenever the kept inventories start over
--                                                       (NEW SESSION; "Reset every map": every map) - keep your own
--                                                       per-player things with it and drop them when it changes
--   inventory.tools.<tool id>.takes = "ammo_a ..."      a gun: the ammo items it can be loaded with (drag a stack onto
--                                                       it; a double click unloads); kind "ammo" items, .box per sale
--   inventory.items.<id>.box / .model / .boost / .boostTime   sold by the box of .box; lying in the world as the
--                                                       game tool .model; a consumable: +.boost speed for .boostTime s
--   inventory.ammo.<p>.<tool>                           (host) the rounds loaded in that player's tool
--   inventory.shots.<p>.<tool>                          (host) rounds used from it so far (a counter)
--   inventory.use.<p>.<tool> = n                        (host, a mod's own tool) n rounds / fuel used: taken off what is
--                                                       loaded in it (add to it; read and cleared each tick)
--   inventory.cap.<p>.<tool> = n                        (host, a gun mod) at most n rounds fireable now: the game's
--                                                       count; 0 while it reloads (magazines live in the gun's mod)
--   inventory.dropgold = "x,y,z,n x,y,z,n ..."          (host) gold dropped into the world by another mod (a monster
--                                                       killed: n gold at x,y,z), read and cleared each tick
--   inventory.keepondeath = true                        (host) a game mode's: players keep everything when they die
--                                                       (items, worn clothes, gold: nothing dropped)
--   inventory.startgold = n                             (host) the gold a new wallet starts with (unset: the mod's
--                                                       option, 500 by default, at most 2000)
--   inventory.deathloss = 0..1                          (host) the share of a player's gold dropped where they die
--                                                       (unset: the mod's option, 20 % by default)
--   inventory.keeptools = "id id ..."                   (host) tools the inventory never touches: not items, never
--                                                       enabled / disabled / put away - the mod that hands them out runs them
--   inventory.sell = 0..1                               (host) the share of its price an item sells back for
--                                                       (0.6 when unset; 0: no selling)
--
-- Clients are not trusted: the engine does not tell a server function who called it, so every request carries the
-- caller's key, a random string the host sent to that player alone (ClientCall to one player); a request for
-- another player's inventory needs that player's key. Everything else is decided on the host.
-- A tool is an item when a mod declared it (inventory.tools.<id>); clothing is what any pack registered
-- (inventory.clothing.*, InventoryClothing of inventory_api.lua), and what is worn goes to inventory.wear.<player>.
-- The wear engine (wardrobe_engine.lua, melee.lua - the Wardrobe session's files, in this mod since 2026-11-13: a
-- clothing or weapon pack needs this mod alone) puts the clothes on the character, applies armour and mobility and
-- swings the melee weapons; this file tells it who wears what and what other items add (WardrobeExtra).

Inv = {}

local C = InvCore
INV_REACH = 4.0          -- m from the eye to an item you can take (one on the floor 3.5 m ahead is 3.9 m from the eye)
INV_AIM = 0.6            -- m beside the view line that still counts as looking at an item
INV_SCAN = 2.0           -- s between looks for new tools / item definitions / tagged bodies
INV_KEY = "i"            -- opens the inventory (a controller: the map button)
INV_PAD = 2              -- LastInputDevice() of a gamepad (UI_DEVICE_GAMEPAD is not a global in mod scripts)
INV_GOLD_START = 500     -- gold coins every player starts with (the user, 2026-11-15: 500 at the first release; 99999 before, for testing)

----- shared: item definitions (each machine keeps its own) -----

-- The Inventory is EMPTY by itself (the user, 2026-11-15: "it's a mistake to put any items in the inventory by default
-- ... the inventory mod should be empty by itself"): a game tool is an item only when a mod declared it
-- (inventory.tools.<id>.* or a pack's inventory.weapons.<id>.*); every other tool is taken from everyone. The game's
-- tools, their ammo, BlueTide, magazines and reloading are in the McPuppet Basic Guns / Tools Packs.
-- inventory.block.<player> (bool, a mod on the host, synced; Humans vs Clickers' monsters): the inventory is off for that
-- player - no screen, HUD, pickups, punches, purchases, consumables, clothing effects; the tool wheel left alone - and
-- what they have stays (not dropped at death) for when the key goes false or away
function invBlocked(p)
	return GetBool("inventory.block." .. p)
end
-- inventory.keeptools = "id id ..." (host): game tools the inventory never touches (not items, the wheel left alone):
-- a mod hands them out and spends them itself
local keepStr, keepSet = nil, {}
function invKeptTool(id)
	local s = GetString("inventory.keeptools")
	if s ~= keepStr then
		keepStr, keepSet = s, {}
		for w in string.gmatch(s, "%S+") do keepSet[w] = true end
	end
	return keepSet[id] == true
end
INV_BOOST_MAX, INV_BOOST_FADE = 120, 5    -- s: a consumable's speed boost adds up to this much, fades over the last seconds

-- a tool a mod declared: its .takes ("ammo_a ammo_b") as a list, or nil
local function takesOf(k)
	local s = GetString(k .. ".takes")
	if s == "" then return nil end
	local t = {}
	for w in string.gmatch(s, "%S+") do t[#t + 1] = w end
	return t
end

-- A file of ANOTHER mod (an icon, a drop model): scripts load other mods' files by absolute path, "RAW:<that
-- mod's folder>/<file>". mod: its id, or nil / "" - then the enabled mod whose folder has the file (found once).
-- A path of the game's own ("ui/...") and a full "RAW:" path stay as they are.
local modFileCache = {}
local function modFile(file, mod)
	if file == "" or string.sub(file, 1, 4) == "RAW:" then return file end
	file = string.gsub(file, "^MOD/", "")
	local key = (mod or "") .. "|" .. file
	if modFileCache[key] then return modFileCache[key] end
	local found = nil
	if mod and mod ~= "" then
		local root = GetString("mods.available." .. mod .. ".path")
		if root ~= "" then found = "RAW:" .. root .. "/" .. file end
	else
		for _, id in ipairs(ListKeys("mods.available") or {}) do
			local root = GetString("mods.available." .. id .. ".path")
			if root ~= "" and GetBool("mods.available." .. id .. ".active") then
				local ok, has = pcall(HasFile, "RAW:" .. root .. "/" .. file)
				if ok and has then
					found = "RAW:" .. root .. "/" .. file
					break
				end
			end
		end
	end
	if found then modFileCache[key] = found end
	return found or file
end

-- Selling (the user, 2026-11-13: "whatever item bought from the store can be sold back for 60% of its original
-- price"): what the store sells, it takes back for INV_SELL of its price - the whole stack at once; a tool with
-- ammo for the share of its pack that is left (a pack bought, five of six used, is worth a sixth: no money from
-- using things up). price: the store's for one (< 0: not sold there, so not bought back). -> money, or nil.
INV_SELL = 0.6
function invSellShare()
	if HasKey("inventory.sell") then return math.max(0, math.min(1, GetFloat("inventory.sell"))) end
	return INV_SELL
end
function invSellValue(it, price, share)
	local def = it and C.defs[it.id]
	if not def or not price or price < 0 or share <= 0 then return nil end
	local n = it.n or 1
	if def.kind == "tool" and def.pack then n = math.max(0, math.min(1, (it.ammo or 0) / def.pack)) end
	if def.box then n = n / def.box end                              -- (ammo: priced by the box, sold by the round)
	return math.floor(price * share * n + 0.0001)
end

-- A readable stand-in for an item that has no name (yet): "wardrobe_nightwatch_suit" -> "Nightwatch Suit" (the
-- first word is taken for the mod's prefix when there are more). The user saw ids on screen.
function invPrettyId(id)
	local words = {}
	for w in string.gmatch(id or "", "[^_%.%-]+") do words[#words + 1] = w end
	if #words > 1 then table.remove(words, 1) end
	for i, w in ipairs(words) do words[i] = string.upper(string.sub(w, 1, 1)) .. string.sub(w, 2) end
	local s = table.concat(words, " ")
	return s ~= "" and s or (id or "?")
end

-- gold coins as text: 99999 -> "99,999"
function invGold(n)
	local s = tostring(math.floor((n or 0) + 0.5))
	local k
	repeat s, k = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
	return s
end

-- a definition's name from the registry; a stand-in until the registry has one (looked at again on every scan)
local function nameOf(def, key)
	local name = GetString(key)
	if string.sub(name, 1, 4) == "loc@" then                        -- the game's tools name themselves by a translation
		local k = string.sub(name, 5)                                -- key; UiText translates only a string that IS the
		if HasTranslationByKey(k) then name = GetTranslatedStringByKey(k, name) end  -- key ("E: pick up loc@TOOL_...")
	end
	if name ~= "" then
		def.name, def.namePending = name, nil
	elseif not def.name or def.namePending then
		def.name, def.namePending = invPrettyId(def.id), true
	end
end

-- the game's tools, Wardrobe's clothing, other mods' items -> InvCore.defs
function invScanDefs()
	local tools = ListKeys("game.tool")
	for i = 1, #tools do
		local id = tools[i]
		local k = "inventory.tools." .. id
		local wk0 = "inventory.weapons." .. id                        -- (declared: the key, or keys under it)
		local declared = HasKey(k) or #ListKeys(k) > 0 or HasKey(wk0) or #ListKeys(wk0) > 0
		if invKeptTool(id) or not declared then
			-- (not an item: kept tools are left alone, the rest are taken from everyone by the wheel loop)
		elseif not C.defs[id] then
			local pack, spent = nil, nil
			if HasKey(k .. ".ammo") then pack, spent = GetInt(k .. ".ammo"), GetBool(k .. ".spent") end
			if pack and pack <= 0 then pack = nil end
			C.define({id = id, kind = "tool", tool = id, icon = "ui/terminal/tool/" .. id .. ".png",
				pack = pack, spent = spent or nil, takes = takesOf(k)})
		end
		if C.defs[id] and HasKey(k .. ".takes") then C.defs[id].takes = takesOf(k) end
		if C.defs[id] then
			if not C.defs[id].name or C.defs[id].namePending then nameOf(C.defs[id], "game.tool." .. id .. ".name") end
			-- a pack's melee weapon brings its own icon (the game has none for it): a file in that mod's folder
			local wk = "inventory.weapons." .. id
			if not C.defs[id].modIcon and HasKey(wk .. ".icon") and HasKey(wk .. ".mod") then
				local root = GetString("mods.available." .. GetString(wk .. ".mod") .. ".path")
				if root ~= "" then
					C.defs[id].icon = "RAW:" .. root .. "/" .. GetString(wk .. ".icon")
					C.defs[id].modIcon = true
				end
			end
			-- any mod's tool: inventory.tools.<id>.icon (+ .mod)
			if not C.defs[id].modIcon and HasKey(k .. ".icon") then
				C.defs[id].icon = modFile(GetString(k .. ".icon"), GetString(k .. ".mod"))
				C.defs[id].modIcon = true
			end
		end
	end
	local worn = ListKeys("inventory.clothing")
	for i = 1, #worn do
		local id = worn[i]
		if C.defs[id] and C.defs[id].namePending then nameOf(C.defs[id], "inventory.clothing." .. id .. ".name") end
		if not C.defs[id] then
			local k = "inventory.clothing." .. id
			local slot = GetString(k .. ".slot")
			if slot ~= "" and not GetBool(k .. ".hidden") then
				C.addSlot(slot)
				-- (.icon / .drop are file names in the owning mod's folder, .mod its id: another mod's files load by
				--  absolute path, "RAW:<folder>/<file>")
				local mod = GetString(k .. ".mod")
				local root = mod ~= "" and GetString("mods.available." .. mod .. ".path") or ""
				local function file(key)
					local f = GetString(k .. "." .. key)
					if f == "" or root == "" then return f end
					return "RAW:" .. root .. "/" .. f
				end
				local def = C.define({id = id, kind = "clothing", slot = slot,
					armor = GetFloat(k .. ".armor"), mobility = GetFloat(k .. ".mobility"), noise = GetFloat(k .. ".noise"),
					icon = file("icon"), drop = file("drop"),
					engine = true})                                       -- (the wear engine counts it by itself)
				nameOf(def, k .. ".name")
			end
		end
	end
	local items = ListKeys("inventory.items")
	for i = 1, #items do
		local id = items[i]
		if C.defs[id] and C.defs[id].namePending then nameOf(C.defs[id], "inventory.items." .. id .. ".name") end
		if not C.defs[id] then
			local k = "inventory.items." .. id
			local kind = GetString(k .. ".kind")
			local slot = GetString(k .. ".slot")
			if slot ~= "" then C.addSlot(slot) end
			local def = C.define({id = id, kind = kind ~= "" and kind or "misc",
				stack = math.max(1, GetInt(k .. ".stack")), slot = slot ~= "" and slot or nil,
				armor = GetFloat(k .. ".armor"), mobility = GetFloat(k .. ".mobility"), noise = GetFloat(k .. ".noise"),
				icon = modFile(GetString(k .. ".icon"), GetString(k .. ".mod")),
				drop = modFile(GetString(k .. ".drop"), GetString(k .. ".mod")), heal = GetFloat(k .. ".heal"),
				box = GetInt(k .. ".box") > 1 and GetInt(k .. ".box") or nil,
				model = GetString(k .. ".model") ~= "" and GetString(k .. ".model") or nil,
				boost = GetFloat(k .. ".boost") > 0 and GetFloat(k .. ".boost") or nil,
				boostTime = GetFloat(k .. ".boostTime") > 0 and GetFloat(k .. ".boostTime") or nil})
			nameOf(def, k .. ".name")
		end
	end
end

-- an input this frame; inventory.test.<input> (bool) presses it for every player (autotests only)
function invPressed(name, p)
	if GetBool("inventory.test." .. name) then return true end
	if p == nil then return InputPressed(name) end                  -- (no explicit nil: this machine's own player)
	return InputPressed(name, p)
end

-- The item of a list of bodies a player aims at: the one nearest the view line (within INV_AIM of it), no further
-- than INV_REACH from the eye. Generous on purpose: a small model on the floor is hard to hit with a ray, and in
-- third person the camera's line passes beside it. -> body (0: none)
function invAimed(p, bodies)
	local cam = GetPlayerCameraTransform(p)
	local dir = TransformToParentVec(cam, Vec(0, 0, -1))
	local eye = GetPlayerEyeTransform(p).pos
	local best, bestD = 0, INV_AIM
	for i = 1, #bodies do
		local mn, mx = GetBodyBounds(bodies[i])
		local c = VecLerp(mn, mx, 0.5)
		if VecLength(VecSub(c, eye)) <= INV_REACH then
			local rel = VecSub(c, cam.pos)
			local along = VecDot(rel, dir)
			if along > 0 then
				local d = VecLength(VecSub(rel, VecScale(dir, along)))
				if d < bestD then best, bestD = bodies[i], d end
			end
		end
	end
	return best
end

-- Gold lying in the world (the user, 2026-11-15: dropped from the wallet with a slider, a share of it dropped at death):
-- a world item of this id whose .n is the amount; picked up into the wallet, never into the grid. Its model by amount:
-- a coin, a pile of coins, a pouch, pouches (vox/gold_*.vox, tools/make_gold.py).
INV_GOLD_ITEM = "inventory_gold"
INV_GOLD_TIERS = {{25, "coin"}, {200, "coins"}, {1000, "pouch"}, {math.huge, "pouches"}}
function invGoldModel(n)
	for _, t in ipairs(INV_GOLD_TIERS) do
		if n < t[1] then return "MOD/vox/gold_" .. t[2] .. ".vox" end
	end
end

function invName(it)
	if it.id == INV_GOLD_ITEM then return invGold(it.n or 0) .. " gold" end
	local def = C.defs[it.id]
	local name = def and def.name or invPrettyId(it.id)
	if it.n and it.n > 1 then name = name .. " x" .. it.n end
	return name
end

----- server -----

local invs = {}          -- player -> inventory
local world = {}         -- body -> {it = instance, ents = entities to delete with it}
local live = {}          -- player -> {tool id -> true}: enabled by us, its ammo count set from the instance
local alive = {}         -- player -> alive last tick
local worn = {}          -- player -> the inventory.wear string we wrote
local counts = {}        -- player -> {id -> the inventory.count we wrote}
local toolData = {}      -- tool id -> {scale} or false (no model)
local want = {}          -- player -> {id = the tool a hotkey asked for, n = enforce passes left}
local usedN = 0          -- consumables used (the inventory.used ring)
local keys = {}          -- player -> the secret that player's requests must carry
local money = {}         -- player -> the gold coins last published (false: the store is free)
local stock, stockSig, stockN = {}, "", 0   -- the store's list {id, price}, what it was built from, its number
local seq, dirty, scanT, pubT = 0, true, 0, 0
local pickSnd

local function inv(p)
	if not invs[p] then
		invs[p] = C.new()
		live[p] = {}
		dirty = true
		local k = ""
		for _ = 1, 4 do k = k .. string.format("%08x", math.random(0, 2147483646)) end
		keys[p] = k
		ClientCall(p, "client.invKey", k)
	end
	return invs[p]
end

-- the scale the game's own multiplayer drops use (data/script/mp/lib/tools.lua, _initiateToolPickupData): small
-- tools bigger, long ones smaller
local function toolScale(id)
	if toolData[id] ~= nil then return toolData[id] end
	toolData[id] = false
	local ents = SpawnTool(id, Transform(Vec(0, 500, 0)))
	if ents and #ents > 0 then
		local vox, mn, mx = 0.1, nil, nil
		for _, e in ipairs(ents) do
			local ty = GetEntityType(e)
			if ty == "body" then
				local a, b = GetBodyBounds(e)
				if not mn then
					mn, mx = a, b
				else
					for j = 1, 3 do
						mn[j] = math.min(mn[j], a[j])
						mx[j] = math.max(mx[j], b[j])
					end
				end
			elseif ty == "shape" then
				local _, _, _, s = GetShapeSize(e)
				if s and s > 0 and s < vox then vox = s end
			end
		end
		if mn then
			local size = math.max(mx[1] - mn[1], mx[2] - mn[2], mx[3] - mn[3])
			local scale = vox / 0.1
			if size < 1.5 and scale < 0.7 then
				scale = 1.5
			elseif size > 1.5 and scale > 0.5 then
				scale = 0.5
			end
			toolData[id] = {scale = scale}
		end
		for _, e in ipairs(ents) do Delete(e) end
	end
	return toolData[id]
end

-- pick up into a player's inventory -> how many did not fit. A tool already in the wheel takes the added ammo
-- from the instance again (the game's own count would overwrite it).
local function addTo(p, id, n, ammo, noWear)
	local left = C.add(inv(p), id, n, ammo, noWear)
	if live[p] then live[p][id] = nil end
	return left
end

local function lastBody(ents)
	local body = 0
	for _, e in ipairs(ents or {}) do
		if GetEntityType(e) == "body" then body = e end
	end
	return body
end

-- an instance into the world at a transform, moving at vel -> its body (0: nothing could be spawned)
local function spawnItem(it, t, vel)
	local def = C.defs[it.id]
	local ents
	if it.id == INV_GOLD_ITEM then                                   -- gold: a coin, coins, a pouch or pouches
		ents = Spawn("<body dynamic='true'><vox file='" .. invGoldModel(it.n or 1) .. "'/></body>", t)
	end
	local model = def and (def.kind == "tool" and def.tool or def.model)   -- (BlueTide: the game's bottle)
	if model then
		local data = toolScale(model)
		if data then ents = SpawnTool(model, t, false, data.scale) end
	end
	if def and def.drop and def.drop ~= "" then                    -- the item's own model (a clothing mod's .vox)
		-- (full-size 0.1 m voxels, no scale: a scale < 1 body is static in Teardown 2.2 whatever dynamic says -
		-- the user saw a dead player's clothes hang in the air)
		ents = Spawn("<body dynamic='true'><vox file='" .. def.drop .. "'/></body>", t)
	end
	if not ents or lastBody(ents) == 0 then
		ents = Spawn("<body dynamic='true'><voxbox pos='-0.15 -0.1 -0.15' size='3 2 3' prop='true' material='plastic' color='0.55 0.42 0.25'/></body>", t)
	end
	local body = lastBody(ents)
	if body == 0 then return 0 end
	SetTag(body, "invitem", it.id)
	SetTag(body, "nocull")
	SetDescription(body, invName(it))
	if vel then SetBodyVelocity(body, vel) end
	world[body] = {it = it, ents = ents}
	return body
end

local function removeWorld(body)
	local w = world[body]
	world[body] = nil
	if w then
		for _, e in ipairs(w.ents) do
			if IsHandleValid(e) then Delete(e) end
		end
	end
	if IsHandleValid(body) then Delete(body) end
end

-- bodies a map or the spawn menu tagged invitem=<id>: known tools get their own model, the rest stay as they are
local function adoptTagged()
	local list = FindBodies("invitem", true)
	for i = 1, #list do
		local b = list[i]
		if not world[b] then
			local id = GetTagValue(b, "invitem")
			local def = C.defs[id]
			if def then
				local n = tonumber(GetTagValue(b, "n")) or 1
				local it = {id = id, n = math.max(1, math.min(n, def.stack))}
				if def.kind == "tool" then it.n, it.ammo = 1, def.pack and (tonumber(GetTagValue(b, "ammo")) or def.pack) or nil end
				if def.takes then it.ammo = tonumber(GetTagValue(b, "ammo")) or 0 end   -- (a gun: the rounds loaded in it)
				if def.kind == "tool" and toolScale(def.tool) then
					local t = GetBodyTransform(b)
					Delete(b)
					spawnItem(it, t)
				else
					SetDescription(b, invName(it))
					world[b] = {it = it, ents = {}}
				end
			end
		end
	end
	for b in pairs(world) do                                     -- (broken or deleted by something else)
		if not IsHandleValid(b) then world[b] = nil end
	end
end

-- the item a player looks at: the engine's interact body, else on the camera's ray within reach of the eye
local function itemInView(p)
	local b = GetPlayerInteractBody(p)
	if b ~= 0 and world[b] then return b end
	local list = {}
	for body in pairs(world) do
		if IsHandleValid(body) then list[#list + 1] = body end
	end
	return invAimed(p, list)
end

local function note(p, text)
	ClientCall(p, "client.invNote", text)
end

local function pickUp(p, body)
	local w = world[body]
	local it = w.it
	if it.id == INV_GOLD_ITEM then                                   -- gold: into the wallet
		if GetBool("inventory.free") or not HasKey("inventory.gold." .. p) then return end
		SetInt("inventory.gold." .. p, GetInt("inventory.gold." .. p) + (it.n or 0), true)
		dirty = true
		PlaySound(pickSnd, GetBodyTransform(body).pos, 1)
		note(p, "+" .. invGold(it.n or 0) .. " gold")
		removeWorld(body)
		return
	end
	local left = addTo(p, it.id, it.n, it.ammo)
	if left >= it.n then
		note(p, "Inventory full")
		return
	end
	dirty = true
	PlaySound(pickSnd, GetBodyTransform(body).pos, 1)
	if left > 0 then
		it.n = left
		SetDescription(body, invName(it))
		note(p, "Inventory full")
	else
		removeWorld(body)
	end
end

-- in front of the player, tossed forward
local function dropFrom(p, it, scatter)
	local pt = GetPlayerTransform(p)
	local fwd = TransformToParentVec(pt, Vec(0, 0, -1))
	local pos = VecAdd(pt.pos, VecAdd(Vec(0, 1.2, 0), VecScale(fwd, 0.8)))
	local vel = VecAdd(VecScale(fwd, 1.5), Vec(0, 1, 0))
	if scatter then                                              -- (death: around where they fell)
		local a = math.random() * 6.2832
		pos = VecAdd(pt.pos, Vec(math.cos(a) * 0.5, 1.0, math.sin(a) * 0.5))
		vel = Vec(math.cos(a) * 2, 2.5, math.sin(a) * 2)
	end
	return spawnItem(it, Transform(pos, pt.rot), vel)
end

-- "id[:n[:ammo]] id ..." from another mod
local function giveList(p, list)
	for word in string.gmatch(list, "%S+") do
		local id, n, ammo = string.match(word, "^([^:]+):?(%d*):?(%d*)$")
		local def = id and C.defs[id]
		if def then
			n = tonumber(n) or 1
			if def.takes then                                        -- (a gun: "gun:1:12" = 12 rounds loaded)
				ammo = tonumber(ammo)
			elseif def.kind == "tool" then                           -- (a tool: the count given, else one pack, else
				ammo = tonumber(ammo) or def.pack                    --  none needed; HvC's gun without the Guns Pack)
			else
				ammo = def.pack and (tonumber(ammo) or def.pack) or nil  -- (no ammo given: one pack)
			end
			local left = addTo(p, id, n, ammo)
			dirty = true
			while left > 0 do                                    -- no room: at the feet, a stack per body
				local put = math.min(left, def.stack)
				dropFrom(p, {id = id, n = put, ammo = def.kind == "tool" and ammo or nil})
				left = left - put
			end
		end
	end
end

-- The wheel shows the tools the hotkeys point at and nothing else. Ammo is ours: the instance's count is written
-- into the game's, and what the game takes off it (a shot, a bomb placed) is taken off the instance. The sandbox
-- writes 9999 into every tool each tick: a count just under that is "9999 less what was used since", anything
-- else above ours is not ours and is written over. A tool that is used up (bombs and the like) leaves the inventory.
-- (Seen in game, 2026-11-14, the Wardrobe session's probe inventory/tools/autotest/ammo_probe.lua: under the sandbox
--  NOTHING was ever used up - the user: "consumables and other items are not decrementing at all, nor bullets". The
--  engine takes a shot at the very start of the frame, before any script; the sandbox's tick runs before ours and
--  writes its 9999 over it, so every read of ours saw 9999 or our own count, never the shot. The engine's copy for
--  its HUD, game.tool.<id>.ammo.display, is taken at the start of the frame too and the sandbox does not touch it:
--  on the press frame it said 5 with the count at 9999. So when the sandbox has written its 9999, a display that has
--  just changed (fresh: an old one never eats ammo just picked up) and is under ours is what is left. The HUD is
--  this machine's, so this read is the host's own player's.)
-- A joiner's HUD is on its own machine (seen in a two-window run, 2026-11-14, tools/run_ammo_mp.py): its display
-- flickers between the sandbox's 9999 and our count, and our count reaches it late, so a shot on a stale value
-- looked just like our correction arriving (4 clicks, 3 counted). So under the sandbox a joiner's tools are LEFT at
-- the sandbox's 9999 (0 when the instance is empty: the host fires nothing): everything the host sends is then a
-- jump up to 9999, every step down from it is a use. Its client counts those steps and reports them
-- (server.invShot), and we take them off the instance. Our own hotbar shows the count, not the game's HUD.
local shownWas = {}      -- tool id -> the last game.tool.<id>.ammo.display read (the host's own player)
local shotFrom = {}      -- player -> tool id -> uses a joiner reported, not yet taken off
local function shownLeft(p, id, r, a)
	local key = "game.tool." .. id .. ".ammo.display"
	local d = HasKey(key) and GetFloat(key) or nil
	local fresh = d ~= nil and d ~= shownWas[id]
	shownWas[id] = d
	if r >= 9999 and fresh and d >= 0 and d < a and IsPlayerLocal(p) and GetPlayerTool(p) == id then return d end
	return r
end

-- Rounds for gun mods (magazines and reloading live in the gun's own mod - the user, 2026-11-15: "the logic for
-- reloading lives in the mods that created the weapon"): inventory.ammo.<p>.<tool> = the rounds loaded in that player's
-- tool, inventory.shots.<p>.<tool> = rounds used so far (a counter, host). A gun mod caps what can be fired now with
-- inventory.cap.<p>.<tool> = n (0 while it reloads): the game's count is then min(cap, rounds) less the shots counted
-- since the cap last changed (the mod lowers it a tick after a shot: no free shot in between).
local shotsN = {}         -- player -> tool -> rounds used (inventory.shots)
local ammoPub = {}        -- player -> tool -> rounds last published (inventory.ammo)
local capSeen = {}        -- player -> tool -> {cap, used since it changed}

local function countUsed(p, id, n)
	if n <= 0 then return end
	shotsN[p] = shotsN[p] or {}
	shotsN[p][id] = (shotsN[p][id] or 0) + n
	SetInt("inventory.shots." .. p .. "." .. id, shotsN[p][id])
end

local function publishAmmo(p, id, n)
	ammoPub[p] = ammoPub[p] or {}
	if ammoPub[p][id] ~= n then
		ammoPub[p][id] = n
		SetInt("inventory.ammo." .. p .. "." .. id, n)
	end
end

-- (each pass) a capped tool: the game's count = what the cap and the rounds allow; shots off the rounds
local function capTick(p, id, it, mine, joinerFree, shots, cap)
	capSeen[p] = capSeen[p] or {}
	local cs = capSeen[p][id]
	if not cs or cs.cap ~= cap then
		cs = {cap = cap, used = 0}
		capSeen[p][id] = cs
	end
	local was = type(mine[id]) == "number" and mine[id] or nil     -- (the count last written into the game)
	if not mine[id] then SetToolEnabled(id, true, p) elseif not IsToolEnabled(id, p) then SetToolEnabled(id, true, p) end
	local cur = GetToolAmmo(id, p)
	local used = 0
	if joinerFree then
		used = shots and shots[id] or 0
	elseif was then
		local r = shownLeft(p, id, cur, was)
		if r < was then used = was - math.max(0, r) elseif r > 9000 and r < 9999 then used = 9999 - r end
	end
	used = math.min(used, it.ammo or 0)
	if used > 0 then
		it.ammo, dirty = math.max(0, (it.ammo or 0) - used), true
		cs.used = cs.used + used
		countUsed(p, id, used)
	end
	local allow = math.max(0, math.min(cap - cs.used, it.ammo or 0))
	local write = joinerFree and (allow > 0 and 9999 or 0) or allow
	if cur ~= write then SetToolAmmo(id, write, p) end
	mine[id] = joinerFree and allow or write
end

local function enforceTools(p, v, isAlive)
	if invBlocked(p) then return end                                 -- (the wheel is the other mod's)
	local wheel = isAlive and C.wheel(v) or {}
	local mine = live[p]
	local tools = ListKeys("game.tool")
	local joinerFree = not IsPlayerLocal(p) and GetBool("level.unlimitedammo")   -- (a joiner under the sandbox)
	local shots = shotFrom[p]
	shotFrom[p] = nil
	for i = 1, #tools do
		local id = tools[i]
		local it = wheel[id]
		if it and it.ammo == nil and C.defs[id] and C.defs[id].takes then it.ammo = 0 end   -- (a gun: never unlimited)
		local capK = "inventory.cap." .. p .. "." .. id
		if invKeptTool(id) then
			-- (inventory.keeptools: never enabled or disabled here)
		elseif it and HasKey(capK) then
			capTick(p, id, it, mine, joinerFree, shots, GetInt(capK))
		elseif it then
			if not mine[id] then
				SetToolEnabled(id, true, p)
				SetToolAmmo(id, (joinerFree and it.ammo and it.ammo > 0) and 9999 or it.ammo or 9999, p)
				mine[id] = true
			else
				if not IsToolEnabled(id, p) then SetToolEnabled(id, true, p) end
				if it.ammo and joinerFree then
					local a = math.max(0, it.ammo - (shots and shots[id] or 0))
					if a ~= it.ammo then
						countUsed(p, id, it.ammo - a)
						it.ammo = a
						dirty = true
					end
					local keep = a > 0 and 9999 or 0
					if GetToolAmmo(id, p) ~= keep then SetToolAmmo(id, keep, p) end
				elseif it.ammo then
					local a = it.ammo
					local r = shownLeft(p, id, GetToolAmmo(id, p), a)
					if r < a then
						a = math.max(0, r)
					elseif r > 9000 and r < 9999 then
						a = math.max(0, a - (9999 - r))
					end
					if a ~= it.ammo then
						if a < it.ammo then countUsed(p, id, it.ammo - a) end
						it.ammo = a
						dirty = true
					end
					if r ~= a then SetToolAmmo(id, a, p) end
				end
				if it.ammo then
					local a = it.ammo
					local def = C.defs[id]
					if a <= 0 and def and def.spent then                 -- the last one used: the item is gone
						C.take(v, C.findTool(v, id))
						wheel[id], mine[id] = nil, nil
						SetToolEnabled(id, false, p)
						ClientCall(p, "client.invNote", "Out of " .. def.name)
					end
				end
			end
		else
			mine[id] = nil
			if IsToolEnabled(id, p) then SetToolEnabled(id, false, p) end
		end
		if it and it.ammo then publishAmmo(p, id, math.floor(it.ammo)) end
	end
	-- a tool taken out of the wheel may still be the one in the hands: put it away
	local held = GetPlayerTool(p)
	-- (the game's sledge is no item but the sandbox still puts it in the hands at a respawn: run 2026-11-15, flag 9)
	if held ~= "" and held ~= "none" and not wheel[held] and not invKeptTool(held) then
		SetPlayerTool("none", p)
	end
	-- a hotkey's tool (set for a few passes: the game's own number keys pick by tool group at the same time)
	local w = want[p]
	if w then
		if w.id == "none" or wheel[w.id] then SetPlayerTool(w.id, p) end
		w.n = w.n - 1
		if w.n <= 0 then want[p] = nil end
	end
end

local function publishWorn(p, v)
	local list = ""
	for i = 1, #C.SLOTS do
		local it = v.e[C.SLOTS[i]]
		if it then list = list .. (list == "" and "" or " ") .. it.id end
	end
	if list == "" then list = "none" end
	if invBlocked(p) then list = "own" end                          -- (blocked: the character's own look, no stats)
	if worn[p] ~= list then
		worn[p] = list
		SetString("inventory.wear." .. p, list)
	end
end

-- What the player wears adds up to, for other mods (host keys). The wear engine applies armour (it gives the
-- blocked share of a hit back) and mobility (walking and jump speed) for everything worn and is the only place
-- that does: it knows the clothing packs' pieces by itself (inventory.wear), and is told here what worn items of
-- other kinds (inventory.items with a slot) add. The totals it answers with are published.
local stats = {}         -- player -> the "defense mobility noise" last written
local extras = {}        -- player -> the "defense mobility noise" of non-clothing-pack pieces last told to the engine
local wasBlocked = {}     -- player -> inventory.block as last seen
local boostEnd, boostOf, boostShown = {}, {}, {}   -- BlueTide: player -> when it ends (GetTime), its share, the HUD's seconds
-- inventory.consumables = false (host): a game mode allows none - not used (a note), running boosts end (Brawl)
function invConsumablesOff()
	return HasKey("inventory.consumables") and not GetBool("inventory.consumables")
end
local function publishStats(p, v)
	local own = C.stats(v, true)
	if invConsumablesOff() then boostEnd[p] = nil end
	local boost, left = 0, (boostEnd[p] or 0) - GetTime()               -- BlueTide: extra mobility while it lasts
	if left > 0 and GetPlayerHealth(p) > 0 then
		boost = (boostOf[p] or 0) * math.min(1, left / INV_BOOST_FADE)
	elseif boostEnd[p] then
		boostEnd[p], boostOf[p], left = nil, nil, 0
	end
	local secs = math.max(0, math.ceil(left))
	if boostShown[p] ~= secs then                                     -- (the HUD's timer, whole seconds)
		boostShown[p] = secs
		SetInt("inventory.boost." .. p, secs, true)
	end
	local e = string.format("%.3f %.3f %.3f", own.defense, own.mobility + boost, own.noise)
	if invBlocked(p) then e = "blocked" end
	if extras[p] ~= e then
		extras[p] = e
		if e == "blocked" then WardrobeExtra(p, 0, 0, 0) else WardrobeExtra(p, own.defense, own.mobility - 1 + boost, own.noise - 1) end
	end
	local d, m, n = WardrobeArmor(p), WardrobeMobility(p), WardrobeNoise(p)
	local sig = string.format("%.3f %.3f %.3f", d, m, n)
	if stats[p] ~= sig then
		stats[p] = sig
		SetFloat("inventory.stat." .. p .. ".defense", d)
		SetFloat("inventory.stat." .. p .. ".immunity", d * (WARDROBE_IMMUNITY or 0.2))   -- (a hit loses this first)
		SetFloat("inventory.stat." .. p .. ".mobility", m)
		SetFloat("inventory.stat." .. p .. ".noise", n)
	end
end

local function publishCounts(p, v)
	local now = {}
	local function area(t)
		for _, it in pairs(t) do now[it.id] = (now[it.id] or 0) + it.n end
	end
	area(v.g) area(v.e)
	local old = counts[p] or {}
	for id, n in pairs(now) do
		if old[id] ~= n then SetInt("inventory.count." .. p .. "." .. id, n) end
	end
	for id in pairs(old) do
		if not now[id] then ClearKey("inventory.count." .. p .. "." .. id) end
	end
	counts[p] = now
end

-- a declared tool without a price of its own (inventory.tools.<id>.price) costs this
local TOOL_PRICE = 1000

-- what the store asks for an item (-1: not sold)
local function priceOf(id)
	local def = C.defs[id]
	if not def then return -1 end
	if HasKey("inventory.price." .. id) then return GetInt("inventory.price." .. id) end
	if def.price then return def.price end
	if def.kind == "tool" then
		if HasKey("inventory.tools." .. id .. ".price") then return GetInt("inventory.tools." .. id .. ".price") end
		if HasKey("inventory.weapons." .. id .. ".price") then return GetInt("inventory.weapons." .. id .. ".price") end
		return TOOL_PRICE
	end
	if def.kind == "clothing" then
		if HasKey("inventory.clothing." .. id .. ".price") then return GetInt("inventory.clothing." .. id .. ".price") end
		return 150 + math.floor((def.armor or 0) * 20 + 0.5) * 50
	end
	if HasKey("inventory.items." .. id .. ".price") then return GetInt("inventory.items." .. id .. ".price") end
	return -1
end

local function storeOn()
	return not (HasKey("inventory.store") and GetInt("inventory.store") == 0)
end

-- the store's list for the clients: tools, clothing, the rest, each by name; published when it changes
local KIND_ORDER = {tool = 1, ammo = 1.5, clothing = 2, consumable = 3, misc = 4}
local function publishStock()
	local list = {}
	if storeOn() then
		for id, def in pairs(C.defs) do
			-- (a tool a game mode keeps for itself is not sold: Humans vs Clickers' gun and plank, made items before the
			--  mode wrote inventory.keeptools, were offered with no picture under Items - the user, 2026-11-15)
			local price = (def.kind == "tool" and invKeptTool(id)) and -1 or priceOf(id)
			if price >= 0 then list[#list + 1] = {id = id, price = price} end
		end
	end
	table.sort(list, function(a, b)
		local ka, kb = KIND_ORDER[C.defs[a.id].kind] or 9, KIND_ORDER[C.defs[b.id].kind] or 9
		if ka ~= kb then return ka < kb end
		local na, nb = C.defs[a.id].name, C.defs[b.id].name
		if na ~= nb then return na < nb end
		return a.id < b.id
	end)
	local sig = ""
	for i = 1, #list do sig = sig .. list[i].id .. ":" .. list[i].price .. " " end
	if sig ~= stockSig or stockN == 0 then
		stockSig, stock = sig, list
		stockN = stockN + 1
		shared.invStore = {n = stockN, list = list, sell = invSellShare()}
	end
end

-- the gold a new wallet starts with: inventory.startgold (host, a game mode's), else the mod's option
-- (savegame.mod.startgold, at most 2000 - the user, 2026-11-15: "make the starting money configurable? up to 2000
-- max"), else INV_GOLD_START (500)
function invStartGold()
	if HasKey("inventory.startgold") then return math.max(0, GetInt("inventory.startgold")) end
	if HasKey("savegame.mod.startgold") then return math.max(0, math.min(2000, GetInt("savegame.mod.startgold"))) end
	return INV_GOLD_START
end

-- a player's gold coins (the wallet is made with invStartGold() the first time) -> n, or false: the store is free
local function balance(p)
	if GetBool("inventory.free") then return false end              -- (a host switch: everything free, no wallet)
	local k = "inventory.gold." .. p
	if not HasKey(k) then SetInt(k, invStartGold(), true) end
	return GetInt(k)
end

-- inventory.goldadd.<p> = "n[:reason] n[:reason] ...": gold another mod pays or takes (signed whole numbers), each
-- change on the wallet (made first if missing), never below 0; a note on their screen unless they are blocked
local presentT = 0
function invGoldAdd(p, list)
	if GetBool("inventory.free") then return end
	for part in string.gmatch(list or "", "%S+") do
		local n, reason = string.match(part, "^([%-%+]?%d+):?(.*)$")
		n = tonumber(n)
		local bal = balance(p)
		if n and bal then
			local now = math.max(0, bal + n)
			SetInt("inventory.gold." .. p, now, true)
			dirty = true
			local d = now - bal
			if d ~= 0 and not invBlocked(p) then
				note(p, (d > 0 and "+" or "-") .. invGold(math.abs(d)) .. " gold" .. (reason ~= "" and (": " .. string.gsub(reason, "_", " ")) or ""))
			end
		end
	end
end

-- inventory.spend.<p> = "token:n[:reason] ...": another mod's purchases (Humans vs Clickers' shop), each all or nothing:
-- taken when the balance is at least n (inventory.spent.<token> = "ok"), else nothing ("no"); in order, so of two
-- that do not both fit only the first is paid. inventory.free: "ok", nothing taken.
function invSpend(p, list)
	for part in string.gmatch(list or "", "%S+") do
		local token, n, reason = string.match(part, "^([%w_%-]+):(%d+):?(.*)$")
		n = tonumber(n)
		if token and n then
			local bal = balance(p)
			if not bal then
				SetString("inventory.spent." .. token, "ok")
			elseif bal >= n then
				SetInt("inventory.gold." .. p, bal - n, true)
				dirty = true
				SetString("inventory.spent." .. token, "ok")
				if n > 0 and not invBlocked(p) then
					note(p, "-" .. invGold(n) .. " gold" .. (reason ~= "" and (": " .. string.gsub(reason, "_", " ")) or ""))
				end
			else
				SetString("inventory.spent." .. token, "no")
			end
		end
	end
end

-- is this request the player's own? (the key went to that player's machine alone)
local function own(p, key)
	if type(p) == "number" and invBlocked(p) then return false end
	return type(p) == "number" and type(key) == "string" and keys[p] ~= nil and keys[p] == key and invs[p] ~= nil
end

local function doDrop(p, ref)
	if type(ref) == "string" and string.sub(ref, 1, 1) == "h" then   -- (a hotkey dragged out: the slot is emptied)
		if C.move(invs[p], ref, "g:1") then dirty = true end
		return
	end
	local it = C.take(invs[p], ref)
	if it then
		dirty = true
		if dropFrom(p, it) == 0 then addTo(p, it.id, it.n, it.ammo) end   -- (nothing spawned: keep it)
	end
end

-- use one of a consumable: its health, and a line in the inventory.used ring for other mods
local function doUse(p, ref)
	local it = C.get(invs[p], ref)
	local def = it and C.defs[it.id]
	if not def or def.kind ~= "consumable" then return end
	if invConsumablesOff() then note(p, "Not in this game mode") return end   -- (kept, not used up)
	if def.heal and def.heal > 0 and HasKey("inventory.healing") and not GetBool("inventory.healing") then
		note(p, "No healing in this game mode")                      -- (inventory.healing = false: Brawl - the user: other
		return                                                       --  consumables are fine there)
	end
	C.take(invs[p], ref, 1)
	dirty = true
	if def.heal and def.heal > 0 then SetPlayerHealth(math.min(1, GetPlayerHealth(p) + def.heal), p) end
	if def.boost then                                                -- BlueTide: time added, at most INV_BOOST_MAX
		local now = GetTime()
		boostEnd[p] = math.min(now + INV_BOOST_MAX, math.max(now, boostEnd[p] or now) + (def.boostTime or 40))
		boostOf[p] = def.boost
	end
	usedN = usedN + 1
	local k = "inventory.used." .. (usedN % 16)
	SetInt(k .. ".player", p)
	SetString(k .. ".id", def.id)
	SetInt("inventory.used.last", usedN)
	note(p, "Used " .. def.name)
end

-- hotkey k: the tool in slot k into the hands, a consumable used; an empty slot: empty hands
local function doSelect(p, k)
	if type(k) ~= "number" or k < 1 or k > C.HOTBAR or k ~= math.floor(k) then return end
	local it = C.get(invs[p], "h:" .. k)
	local def = it and C.defs[it.id]
	if def and def.kind == "consumable" then
		doUse(p, "h:" .. k)
		return
	end
	want[p] = {id = def and def.kind == "tool" and def.tool or "none", n = 6}
end

local function doBuy(p, id)
	if type(id) ~= "string" or not storeOn() then return end
	local def = C.defs[id]
	local price = priceOf(id)
	if not def or price < 0 then return end
	local bal = balance(p)
	if bal and bal < price then
		note(p, "Not enough gold")
		return
	end
	local ammo = def.pack                                            -- (a tool: one pack; nil for the rest)
	local n = def.box or 1                                           -- (ammo: a box of rounds)
	if C.add(C.copy(invs[p]), id, n, ammo, true) > 0 then           -- (tried on a copy: all or nothing)
		note(p, "Inventory full")
		return
	end
	if bal then SetInt("inventory.gold." .. p, bal - price, true) end
	addTo(p, id, n, ammo, true)                                      -- (into the grid, not worn)
	dirty = true
	note(p, "Bought " .. (n > 1 and (n .. " ") or "") .. def.name)
end

-- sell what lies at ref (the whole stack) back to the store; only with a wallet to pay into
-- the ammo a gun's rounds are (loaded, else the first it takes)
function invLoadOf(it)
	local def = it and C.defs[it.id]
	return it and (it.load or (def and def.takes and def.takes[1])) or nil
end

local function takes(def, ammoId)
	for _, a in ipairs(def and def.takes or {}) do
		if a == ammoId then return true end
	end
	return false
end

-- a loaded gun's rounds back into the inventory (no room: at the feet)
local function doUnload(p, ref)
	ref = C.resolve(invs[p], ref)
	local gun = ref and C.get(invs[p], ref)
	local def = gun and C.defs[gun.id]
	if not def or not def.takes or (gun.ammo or 0) < 1 then return end
	local ammoId, n = invLoadOf(gun), math.floor(gun.ammo)
	gun.ammo, gun.load = 0, nil
	if live[p] then live[p][gun.id] = nil end                       -- (the game's count is written again)
	local left = addTo(p, ammoId, n)
	if left > 0 then dropFrom(p, {id = ammoId, n = left}) end
	dirty = true
	note(p, "Unloaded " .. n .. " " .. (C.defs[ammoId] and C.defs[ammoId].name or ammoId))
end

-- an ammo stack onto a gun that takes it: all of it loaded (other rounds in it come out first)
local function doLoad(p, from, to)
	local inv = invs[p]
	from, to = C.resolve(inv, from), C.resolve(inv, to)
	local am, gun = from and C.get(inv, from), to and C.get(inv, to)
	local gdef = gun and C.defs[gun.id]
	if not am or not gdef or not gdef.takes then return false end
	local adef = C.defs[am.id]
	if not adef or adef.kind ~= "ammo" then return false end
	if not takes(gdef, am.id) then
		note(p, "The " .. (gdef.name or gun.id) .. " doesn't take " .. (adef.name or am.id))
		return true
	end
	if (gun.ammo or 0) > 0 and invLoadOf(gun) ~= am.id then doUnload(p, to) end
	local n = am.n or 1
	C.take(inv, from)
	gun.ammo, gun.load = (gun.ammo or 0) + n, am.id
	if live[p] then live[p][gun.id] = nil end
	dirty = true
	note(p, "Loaded " .. n .. " " .. (adef.name or am.id))
	return true
end

local function doSell(p, ref)
	if type(ref) ~= "string" or not storeOn() then return end
	local bal = balance(p)
	if not bal then return end
	ref = C.resolve(invs[p], ref)                                    -- (a hotkey: the item it points at)
	do                                                               -- (a loaded gun: its rounds stay yours)
		local g = ref and C.get(invs[p], ref)
		if g and C.defs[g.id] and C.defs[g.id].takes and (g.ammo or 0) > 0 then doUnload(p, ref) end
	end
	local it = ref and C.get(invs[p], ref)
	local value = invSellValue(it, it and priceOf(it.id), invSellShare())
	if not value then
		if it then note(p, "The store does not buy that") end
		return
	end
	local name = invName(it)
	if not C.take(invs[p], ref) then return end
	SetInt("inventory.gold." .. p, bal + value, true)
	dirty = true
	note(p, "Sold " .. name .. " for " .. invGold(value) .. " gold")
end

----- the punch (the user, 2026-11-12: "when nothing is held, attack should punch"; here, not in a weapon mod: it
----- must work with this mod alone)
-- A player who holds no tool (GetPlayerTool "none" or "": what an empty hotkey leaves) punches with the attack
-- input. The HOST does it all: it reads the player's "usetool" itself (no request to forge), keeps the cooldown,
-- and when the wind-up has passed works the hit out from its own view of the player: the nearest other player on
-- the aim line, else the world on the aim ray (a dent in soft things, a push on loose ones). Damage is
-- the wear engine's WardrobeDamage: the victim's armour is taken off first. Clients only show it.
-- Host keys: inventory.punch = 0 switches it off; inventory.punch.power / .delay / .cooldown / .reach retune it.
local PUNCH = {power = 0.10, delay = 0.16, cooldown = 0.30, reach = 1.5, width = 0.35, knock = 2.5, hole = 0.12, glass = 0.35, push = 40}
local PUNCH_BODY = 0.35  -- m: a player's body round its upright axis
local FX_FLESH, FX_WOOD, FX_METAL, FX_STONE, FX_GLASS = 1, 2, 3, 4, 5
local punchAt = {}       -- player -> when the punch under way lands
local punchReady = {}    -- player -> when the next may start
local screenOpen = {}    -- player -> their inventory screen is open (a click there is no punch)

local function punchStat(k)
	if HasKey("inventory.punch." .. k) then return GetFloat("inventory.punch." .. k) end
	return PUNCH[k]
end

local function emptyHanded(p)
	local t = GetPlayerTool(p)
	return t == "" or t == "none"
end

-- how far player v's body axis is from the segment a .. a + dir * len, where along it, and the body point there
local function bodyToLine(v, a, dir, len)
	local feet = GetPlayerTransform(v).pos
	local best, bestS, bestC = 1e9, 0, nil
	for i = 0, 4 do
		local c = Vec(feet[1], feet[2] + 0.2 + i * 0.35, feet[3])
		local s = VecDot(VecSub(c, a), dir)
		if s < 0 then s = 0 elseif s > len then s = len end
		local d = VecLength(VecSub(c, VecAdd(a, VecScale(dir, s))))
		if d < best then best, bestS, bestC = d, s, c end
	end
	return best, bestS, bestC
end

local function punchFx(mat)
	mat = tostring(mat or "")
	if mat == "glass" then return FX_GLASS end
	if mat == "wood" or mat == "foliage" or mat == "plastic" or mat == "plaster" then return FX_WOOD end
	if string.find(mat, "metal", 1, true) then return FX_METAL end
	return FX_STONE
end

local function punchLand(p)
	local reach = punchStat("reach")
	local eye = GetPlayerEyeTransform(p).pos
	-- Where the player aims: the camera's line (in third person the camera is behind the eye), then from the eye
	-- to that point. Our own rays, without the puncher: the game's aim ray met the puncher's own outstretched arm
	-- in third person (the user heard every swing in the air "hit metal", and nothing reached glass).
	local cam = GetPlayerCameraTransform(p)
	local fwd = TransformToParentVec(cam, Vec(0, 0, -1))
	local far = VecLength(VecSub(cam.pos, eye)) + reach + 1
	QueryRequire("physical")
	QueryRejectPlayer(p)
	local seen, seenD = QueryRaycast(cam.pos, fwd, far)
	local dir = VecSub(VecAdd(cam.pos, VecScale(fwd, seen and seenD or far)), eye)
	if VecLength(dir) < 0.3 then dir = fwd end
	dir = VecNormalize(dir)
	-- A thin ray first: its end is ON the surface. Only if it finds nothing a thick one (a fist, not a needle) - and
	-- a thick ray's distance is where the BALL's centre stopped, a radius short of the surface: the point on the
	-- surface is asked for separately. (Taking the ball's centre for the hit point read the material as "" and put
	-- the hole in the air in front of the glass: seen in game, a pane kept all its voxels.)
	QueryRequire("physical")
	QueryRejectPlayer(p)
	local hit, dist, _, ent = QueryRaycast(eye, dir, reach)
	local endp = VecAdd(eye, VecScale(dir, hit and dist or reach))
	local into = dir                                                 -- the way into what was hit
	if not hit then
		local rad = PUNCH.width * 0.4
		QueryRequire("physical")
		QueryRejectPlayer(p)
		hit, dist, _, ent = QueryRaycast(eye, dir, reach, rad)
		if hit then
			local centre = VecAdd(eye, VecScale(dir, dist))
			QueryRequire("physical")
			QueryRejectPlayer(p)
			local near, point, _, shape = QueryClosestPoint(centre, rad + 0.15)
			if near then
				endp, ent = point, shape
				local to = VecSub(point, centre)
				if VecLength(to) > 0.01 then into = VecNormalize(to) end
			else
				hit = false
			end
		end
	end
	if INV_TEST then                                                 -- (TEST builds: every punch's rays, for the test's screen)
		INV_TEST.punches = INV_TEST.punches or {}
		INV_TEST.punches[#INV_TEST.punches + 1] = string.format("%.2f c%s e%s %.2f", GetTime(), seen and "1" or "0", hit and "1" or "0", dist or -1)
	end
	-- the nearest other player on the line, nothing solid between
	local best = nil
	for _, v in ipairs(GetAllPlayers()) do
		if v ~= p and GetPlayerHealth(v) > 0 then
			local off, s, c = bodyToLine(v, eye, dir, reach)
			if off <= PUNCH_BODY + PUNCH.width * 0.5 and (not best or s < best.s) then
				local to = VecSub(c, eye)
				local l = VecLength(to)
				local free = true
				if l > 0.4 then
					QueryRequire("physical")
					QueryRejectPlayer(p)
					QueryRejectPlayer(v)
					local blocked, bd = QueryRaycast(eye, VecScale(to, 1 / l), l)
					free = not blocked or bd > l - 0.3
				end
				if free then best = {v = v, s = s, c = c} end
			end
		end
	end
	if best then
		WardrobeDamage(best.v, punchStat("power"), "fist", p)
		local push = VecSub(best.c, eye)
		push = Vec(push[1], 0, push[3])
		local l = VecLength(push)
		push = l > 0.001 and VecScale(push, 1 / l) or Vec(dir[1], 0, dir[3])
		SetPlayerVelocity(VecAdd(GetPlayerVelocity(best.v), Vec(push[1] * PUNCH.knock, PUNCH.knock * 0.35, push[3] * PUNCH.knock)), best.v)
		ClientCall(0, "client.invPunchHit", p, FX_FLESH, best.c[1], best.c[2], best.c[3])
		return
	end
	-- the world, on the aim ray
	if hit and dist <= reach then
		local body = 0
		if ent and ent ~= 0 and IsHandleValid(ent) then
			local kind = GetEntityType(ent)
			if kind == "shape" then body = GetShapeBody(ent) elseif kind == "body" then body = ent end
		end
		local mat = ""
		if ent and ent ~= 0 and IsHandleValid(ent) and GetEntityType(ent) == "shape" then
			mat = GetShapeMaterialAtPosition(ent, VecAdd(endp, VecScale(into, 0.03))) or ""
		end
		if INV_TEST then INV_TEST.punches[#INV_TEST.punches] = INV_TEST.punches[#INV_TEST.punches] .. " [" .. tostring(mat) .. "]" end
		local shape = (ent and ent ~= 0 and IsHandleValid(ent) and GetEntityType(ent) == "shape") and ent or 0
		if shape ~= 0 and InventoryMeleeEvent then                   -- the melee hit event, as the weapons' (melee.lua):
			InventoryMeleeEvent(p, shape, body, endp, dir, "fist", punchStat("power"), PUNCH.knock or 0)   -- villagers
		end
		if not (body ~= 0 and world[body]) and not (shape ~= 0 and HasTag(shape, "nohole")) then   -- (not an item; not nohole)
			-- glass breaks; the rest: a dent in soft things. The centre a little inside the surface (on it, half
			-- the ball is air and the hole looks tiny - Wardrobe's weapons, seen in game there)
			local r = mat == "glass" and PUNCH.glass or PUNCH.hole
			MakeHole(VecAdd(endp, VecScale(into, r * 0.35)), r, 0, 0, true)
		end
		if body ~= 0 and IsHandleValid(body) and IsBodyDynamic(body) then
			ApplyBodyImpulse(body, endp, VecScale(dir, PUNCH.push))
		end
		ClientCall(0, "client.invPunchHit", p, punchFx(mat), endp[1], endp[2], endp[3])
	end
end

local function punchTick(p, isAlive)
	local now = GetTime()
	if punchAt[p] and now >= punchAt[p] then
		punchAt[p] = nil
		if isAlive and emptyHanded(p) then punchLand(p) end
	end
	if isAlive and not punchAt[p] and now >= (punchReady[p] or 0) and emptyHanded(p) and not screenOpen[p]
		and not (HasKey("inventory.punch") and GetInt("inventory.punch") == 0)
		and GetPlayerVehicle(p) == 0 and GetPlayerGrabBody(p) == 0
		and (InputDown("usetool", p) or GetBool("inventory.test.usetool")) then   -- (the key: autotests, as invPressed)
		local delay, cooldown = punchStat("delay"), punchStat("cooldown")
		punchAt[p] = now + delay
		punchReady[p] = now + delay + cooldown
		ClientCall(0, "client.invPunch", p, delay, cooldown)
	end
end

function Inv.serverInit()
	if INV_TEST then                                                 -- (a hotkey's item, for the tests)
		INV_TEST.drop = function(p, ref) doDrop(p, C.resolve(invs[p], ref) or "") end
	end
	--                      -- (TEST builds: the host's test drives the server)
	ClearKey("inventory.count")
	ClearKey("inventory.give")
	ClearKey("inventory.used")
	ClearKey("inventory.stat")
	ClearKey("inventory.gold")
	ClearKey("inventory.boost")
	ClearKey("inventory.ammo")
	ClearKey("inventory.shots")
	pickSnd = LoadSound("tool_pickup.ogg")
	invScanDefs()
	shared.inv = {n = 0, p = {}}
	publishStock()
	InvColor.serverInit()                                           -- (inventory.colors.*: inv_color.lua)
	InvKeep.serverInit()                                            -- (inventories kept by name: inv_keep.lua)
end

-- the tools only (the last word after other scripts' ticks: the sandbox enables every tool each tick in multiplayer)
function Inv.serverEnforce()
	for _, p in ipairs(GetAllPlayers()) do
		if invs[p] then enforceTools(p, invs[p], GetPlayerHealth(p) > 0) end
	end
end

function Inv.serverTick(dt)
	presentT = presentT - dt
	if presentT <= 0 then                                            -- (other mods: is the Inventory running?)
		presentT = 1
		SetBool("inventory.present", true, true)
	end
	scanT = scanT - dt
	if scanT <= 0 then
		scanT = INV_SCAN
		invScanDefs()
		adoptTagged()
		publishStock()
	end
	InvColor.serverTick(dt)
	if HasKey("inventory.dropgold") then                             -- other mods' gold drops (a monster killed)
		local list = GetString("inventory.dropgold")
		ClearKey("inventory.dropgold")
		for x, y, z, n in string.gmatch(list, "(%-?[%d%.]+),(%-?[%d%.]+),(%-?[%d%.]+),(%d+)") do
			n = math.floor(tonumber(n) or 0)
			if n > 0 then
				local a = math.random() * 6.2832
				spawnItem({id = INV_GOLD_ITEM, n = n}, Transform(Vec(tonumber(x), tonumber(y), tonumber(z))),
					Vec(math.cos(a) * 1.2, 2.5, math.sin(a) * 1.2))
			end
		end
	end
	InvScatter.serverTick(dt, function(n, t) return spawnItem({id = INV_GOLD_ITEM, n = n}, t) end,   -- gold lying around the map
		function(b) return world[b] == nil or not IsHandleValid(b) end, removeWorld)
	local here = {}
	for _, p in ipairs(GetAllPlayers()) do
		here[p] = true
		local v = inv(p)
		if not InvKeep.claimed(p) then                               -- what they had on the last map / before leaving
			local g = InvKeep.claim(p, v)
			if g and g >= 0 then SetInt("inventory.gold." .. p, g, true) end
			if InvKeep.claimed(p) then dirty = true end
		end
		local h = GetPlayerHealth(p)
		local isAlive = h > 0
		if HasKey("inventory.give." .. p) then
			local list = GetString("inventory.give." .. p)
			ClearKey("inventory.give." .. p)
			giveList(p, list)
		end
		if HasKey("inventory.take." .. p) and InvKeep.claimed(p) then     -- a game mode takes back what it gave
			local list = GetString("inventory.take." .. p)                --  (after their kept inventory came back)
			ClearKey("inventory.take." .. p)
			for word in string.gmatch(list, "%S+") do
				local id, n = string.match(word, "^([^:]+):?(%d*)$")
				if id and C.takeId(v, id, tonumber(n)) > 0 then
					if live[p] then live[p][id] = nil end
					dirty = true
				end
			end
		end
		if HasKey("inventory.goldadd." .. p) and InvKeep.claimed(p) then   -- (after their saved gold came back)
			local list = GetString("inventory.goldadd." .. p)
			ClearKey("inventory.goldadd." .. p)
			invGoldAdd(p, list)
		end
		for _, tid in ipairs(ListKeys("inventory.use." .. p)) do          -- a mod's own tool used up some of its rounds / fuel
			local k = "inventory.use." .. p .. "." .. tid
			local n = GetFloat(k)
			ClearKey(k)
			local at = C.findTool(v, tid)
			local it = at and C.get(v, at)
			if it and n > 0 and (it.ammo or 0) > 0 then
				local took = math.min(it.ammo, n)
				it.ammo = it.ammo - took
				countUsed(p, tid, took)
				dirty = true
			end
		end
		if HasKey("inventory.spend." .. p) and InvKeep.claimed(p) then     -- (a mod's purchases: all or nothing)
			local list = GetString("inventory.spend." .. p)
			ClearKey("inventory.spend." .. p)
			invSpend(p, list)
		end
		local off = invBlocked(p)                                    -- (inventory.block: kept as it is, does nothing)
		if off ~= wasBlocked[p] then
			wasBlocked[p] = off
			live[p] = {}                                             -- (unblocked: the wheel is set up again)
			worn[p], extras[p] = nil, nil
			if off then boostEnd[p], boostOf[p] = nil, nil end
		end
		if alive[p] and not isAlive and not off and not GetBool("inventory.keepondeath") then   -- died: everything where they fell
			local all = C.takeAll(v)
			for _, it in ipairs(all) do dropFrom(p, it, true) end
			local bal = balance(p)                                    -- ... and a share of their gold
			local lost = bal and math.floor(bal * invDeathShare() + 0.5) or 0
			if lost > 0 then
				SetInt("inventory.gold." .. p, bal - lost, true)
				dropFrom(p, {id = INV_GOLD_ITEM, n = lost}, true)
			end
			dirty = true
		end
		alive[p] = isAlive
		if isAlive and not off and invPressed("interact", p) then
			local b = itemInView(p)
			if b ~= 0 then pickUp(p, b) end
		end
		enforceTools(p, v, isAlive)
		if not off then punchTick(p, isAlive) end
		publishWorn(p, v)
		publishStats(p, v)
		local bal = balance(p)
		if money[p] ~= bal then money[p], dirty = bal, true end
	end
	for p in pairs(invs) do                                          -- left the game
		if not here[p] then
			InvKeep.left(p, invs[p], HasKey("inventory.gold." .. p) and GetInt("inventory.gold." .. p) or -1)
			invs[p], live[p], alive[p], worn[p], keys[p], money[p] = nil, nil, nil, nil, nil, nil
			ClearKey("inventory.gold." .. p)
			want[p], stats[p], extras[p], wasBlocked[p] = nil, nil, nil, nil
			boostEnd[p], boostOf[p], boostShown[p] = nil, nil, nil
			ClearKey("inventory.boost." .. p)
			shotsN[p], ammoPub[p], capSeen[p] = nil, nil, nil
			ClearKey("inventory.ammo." .. p)
			ClearKey("inventory.shots." .. p)
			punchAt[p], punchReady[p], screenOpen[p] = nil, nil, nil
			ClearKey("inventory.stat." .. p)
			ClearKey("inventory.wear." .. p)
			ClearKey("inventory.count." .. p)
			counts[p] = nil
			dirty = true
		end
	end
	InvKeep.serverTick(dt, invs, function(p)
		return HasKey("inventory.gold." .. p) and GetInt("inventory.gold." .. p) or -1
	end)
	pubT = pubT - dt
	if dirty and pubT <= 0 then
		dirty, pubT = false, 0.1
		seq = seq + 1
		local out = {n = seq, p = {}}
		for p, v in pairs(invs) do
			out.p["p" .. p] = C.copy(v)
			out.p["p" .. p].money = money[p] or nil
			publishCounts(p, v)
		end
		shared.inv = out
	end
end

function Inv.serverDestroy()
	for p in pairs(invs) do ClearKey("inventory.wear." .. p) end
	ClearKey("inventory.count")
end

-- A client's requests: its player id, its key (see the top), then what it asks. A place is a ref of inv_core.lua.
function server.invHello(p)                                          -- "send me my key" (it goes to player p only)
	if type(p) == "number" and keys[p] then ClientCall(p, "client.invKey", keys[p]) end
end

-- the host's "New session" (inventory screen): every inventory empty, every wallet back to the start, nothing kept
function server.invNewSession(p, key)
	if not own(p, key) or not IsPlayerHost(p) then return end
	InvKeep.reset()
	for q, v in pairs(invs) do
		v.g, v.h, v.e = {}, {}, {}
		live[q] = {}
		if HasKey("inventory.gold." .. q) then SetInt("inventory.gold." .. q, invStartGold(), true) end
		note(q, "New session: inventories and gold reset")
	end
	dirty = true
end

function server.invMove(p, key, from, to)
	if not own(p, key) or GetPlayerHealth(p) <= 0 then return end
	if doLoad(p, from, to) then return end                          -- (ammo onto a gun: loaded)
	if C.move(invs[p], from, to) then dirty = true end
end

-- the share of a player's gold dropped where they die: inventory.deathloss (host, 0..1: a game mode's), else the mod's
-- option (savegame.mod.deathloss, percent; 20 when unset - the user, 2026-11-15: "players should lose 20% of money
-- when they die. How much they lose on death should be configurable")
function invDeathShare()
	if HasKey("inventory.deathloss") then return math.max(0, math.min(1, GetFloat("inventory.deathloss"))) end
	if HasKey("savegame.mod.deathloss") then return math.max(0, math.min(100, GetInt("savegame.mod.deathloss"))) / 100 end
	return 0.2
end

-- gold dropped from the wallet (the screen's slider), in front of the player
function server.invDropGold(p, key, n)
	if not own(p, key) or GetPlayerHealth(p) <= 0 then return end
	n = math.floor(tonumber(n) or 0)
	local bal = balance(p)
	if not bal or n < 1 or n > bal then return end
	SetInt("inventory.gold." .. p, bal - n, true)
	dropFrom(p, {id = INV_GOLD_ITEM, n = n})
	dirty = true
	note(p, "Dropped " .. invGold(n) .. " gold")
end

function server.invUnload(p, key, ref)                               -- (a double click on a loaded gun)
	if own(p, key) and GetPlayerHealth(p) > 0 then doUnload(p, ref) end
end

function server.invQuick(p, key, ref)
	if own(p, key) and GetPlayerHealth(p) > 0 and C.quick(invs[p], ref) then dirty = true end
end

function server.invDrop(p, key, ref)
	if own(p, key) and GetPlayerHealth(p) > 0 then doDrop(p, ref) end
end

function server.invSelect(p, key, k)
	if own(p, key) and GetPlayerHealth(p) > 0 then doSelect(p, k) end
end

function server.invScreen(p, key, isOpen)                           -- (their screen is open: clicks there are no punches)
	if own(p, key) then screenOpen[p] = isOpen == true or nil end
end

function server.invSell(p, key, ref)
	if own(p, key) and GetPlayerHealth(p) > 0 then doSell(p, ref) end
end

function server.invBuy(p, key, id)
	if own(p, key) and GetPlayerHealth(p) > 0 then doBuy(p, id) end
end

function server.invShot(p, key, id, n)                               -- a joiner used n of a tool (see enforceTools)
	if not own(p, key) or IsPlayerLocal(p) or type(id) ~= "string" or type(n) ~= "number" or n <= 0 or n > 100 then return end
	shotFrom[p] = shotFrom[p] or {}
	shotFrom[p][id] = (shotFrom[p][id] or 0) + n
end

----- client -----

local CELL, GAP = 76, 6
local SLOT_NAMES = {head = "Head", top = "Upper body", legs = "Lower body", feet = "Feet"}

-- a share as a signed whole percent, rounded half away from zero (-0.1 is "-10%": the stored float is a hair
-- under, and flooring it from below read "-11%" in game). zeroSign: "+0%" rather than "0%".
local function pctText(f, zeroSign)
	local n = math.floor(math.abs(f) * 100 + 0.5)
	if n == 0 then return (zeroSign and "+" or "") .. "0%" end
	return (f > 0 and "+" or "-") .. n .. "%"
end
local open = false
local mine = C.new()     -- my inventory as last published
local myMoney = nil      -- my gold coins (nil: the store is free)
local moneySeen = nil    -- my gold as last seen (a change makes a float)
local moneyFloats = {}   -- {d = change, t = when}: green "+n" / red "-n" rising from the HUD's gold and fading (the user)
INV_FLOAT_TIME = 1.5

-- gold coins drawn as the coin picture and the number, size px high, its vertical middle on the current point;
-- align "left" (default) / "center" / "right" of the current point; col {r, g, b} (default gold)
local function drawGold(n, size, align, col)
	UiPush()
	UiFont("bold.ttf", size)
	local text = invGold(n)
	local tw = UiGetTextSize(text)
	local ic = math.floor(size * 1.0)
	local w = ic + math.floor(size * 0.3) + tw
	if align == "center" then UiTranslate(-w / 2, 0) elseif align == "right" then UiTranslate(-w, 0) end
	UiAlign("left middle")
	UiPush()
	UiColor(1, 1, 1, 1)
	UiScale(ic / 64)
	UiImage("MOD/images/coin.png")
	UiPop()
	UiTranslate(ic + math.floor(size * 0.3), 0)
	col = col or {1, 0.85, 0.35}
	UiColor(col[1], col[2], col[3], 1)
	UiTextOutline(0, 0, 0, 0.7, 0.15)
	UiText(text)
	UiPop()
end
local storePrice, sellShare = {}, 0      -- id -> the store's price; the share an item sells back for

-- the lines of an item's tooltip: {text, kind} - kind "title", "good", "bad", "plain", "dim"
local function tipLines(it, shop, ref)
	local def = C.defs[it.id]
	local out = {{invName(it), "title"}}
	if not def then return out end
	if def.kind == "clothing" or (def.slot and def.kind ~= "tool") then
		out[#out + 1] = {"Worn on: " .. (SLOT_NAMES[def.slot] or def.slot or "?"), "dim"}
		local any = false
		if (def.armor or 0) > 0 then out[#out + 1] = {"Defence  +" .. math.floor(def.armor * 100 + 0.5) .. "%", "good"} any = true end
		if (def.mobility or 0) ~= 0 then out[#out + 1] = {"Mobility  " .. pctText(def.mobility), def.mobility > 0 and "good" or "bad"} any = true end
		-- (louder is worse: creatures hear you)
		if (def.noise or 0) ~= 0 then out[#out + 1] = {"Noise  " .. pctText(def.noise), def.noise < 0 and "good" or "bad"} any = true end
		if not any then out[#out + 1] = {"No effect on your stats", "plain"} end
	elseif def.kind == "tool" then
		local wk = "inventory.weapons." .. it.id
		if HasKey(wk .. ".power") then
			out[#out + 1] = {(GetInt(wk .. ".hands") == 2 and "Two-handed" or "One-handed") .. " melee weapon", "dim"}
			out[#out + 1] = {"Damage  " .. math.floor(GetFloat(wk .. ".power") * 100 + 0.5) .. "% of health", "good"}
			local d, c = GetFloat(wk .. ".delay"), GetFloat(wk .. ".cooldown")
			if d + c > 0 then out[#out + 1] = {string.format("Swing  %.1f s", d + c), "plain"} end
			if HasKey(wk .. ".reach") and GetFloat(wk .. ".reach") > 0 then out[#out + 1] = {string.format("Reach  %.1f m", GetFloat(wk .. ".reach")), "plain"} end
			if GetFloat(wk .. ".knockback") > 0 then out[#out + 1] = {string.format("Knockback  %.0f", GetFloat(wk .. ".knockback")), "plain"} end
		elseif def.takes then                                        -- a gun: what it takes, what is in it
			local names = {}
			for _, a in ipairs(def.takes) do names[#names + 1] = C.defs[a] and C.defs[a].name or a end
			out[#out + 1] = {"Takes: " .. table.concat(names, ", "), "plain"}
			if shop then
				out[#out + 1] = {"Comes empty", "dim"}
			elseif (it.ammo or 0) > 0 then
				local l = invLoadOf(it)
				out[#out + 1] = {"Loaded: " .. math.floor(it.ammo) .. " " .. (C.defs[l] and C.defs[l].name or l), "good"}
				out[#out + 1] = {"Double-click it to unload", "dim"}
			else
				out[#out + 1] = {"Empty: drag its ammo onto it", "bad"}
			end
		elseif def.pack then
			out[#out + 1] = {shop and ("Comes with " .. def.pack) or (math.ceil(it.ammo or 0) .. " left"), "plain"}
		end
	elseif def.kind == "ammo" then                                   -- which guns take it
		local guns = {}
		for gid, gdef in pairs(C.defs) do
			for _, a in ipairs(gdef.takes or {}) do
				if a == it.id then guns[#guns + 1] = gdef.name or gid end
			end
		end
		table.sort(guns)
		out[#out + 1] = {"For: " .. table.concat(guns, ", "), "plain"}
		if shop then out[#out + 1] = {"A box of " .. (def.box or 1), "dim"} else out[#out + 1] = {"Drag onto the gun to load it", "dim"} end
	elseif def.kind == "consumable" then
		out[#out + 1] = {"Use: put it on a hotkey, press the number", "dim"}
		if (def.heal or 0) > 0 then out[#out + 1] = {"Heals  +" .. math.floor(def.heal * 100 + 0.5) .. "%", "good"} end
		if (def.boost or 0) > 0 then
			out[#out + 1] = {"Speed  +" .. math.floor(def.boost * 100 + 0.5) .. "%  for " .. (def.boostTime or 40) .. " s", "good"}
		end
	end
	-- a mod's own lines (inventory.tools.<id>.tip / inventory.items.<id>.tip = "line|line": a gun's magazine and the like)
	local tip = GetString("inventory.tools." .. it.id .. ".tip")
	if tip == "" then tip = GetString("inventory.items." .. it.id .. ".tip") end
	for line in string.gmatch(tip, "[^|]+") do out[#out + 1] = {line, "plain"} end
	if shop then
		out[#out + 1] = {(not myMoney or shop.price == 0) and "Click to buy: free" or ("Click to buy: " .. invGold(shop.price) .. " gold"), "price"}
	else
		local gk = ref and string.sub(ref, 1, 1) == "g" and C.slotOf(mine, tonumber(string.sub(ref, 3)))
		if gk then out[#out + 1] = {"Hotkey " .. gk, "dim"} end
		local price = storePrice[it.id]
		if myMoney and price and price >= 0 and sellShare > 0 then
			local v = invSellValue(it, price, sellShare)
			if v then out[#out + 1] = {"Sells for " .. invGold(v) .. " gold", "price"} end
		end
	end
	return out
end

-- the tooltip box at (x, y) in the panel's frame, kept inside the panel (w, h)
function drawTooltip(it, shop, ref, x, y, w, h)
	local lines = tipLines(it, shop, ref)
	local PADT, LH = 12, 24
	local bw = 0
	for i, l in ipairs(lines) do
		UiFont(l[2] == "title" and "bold.ttf" or "regular.ttf", l[2] == "title" and 24 or 19)
		bw = math.max(bw, (UiGetTextSize(l[1])))
	end
	bw = bw + PADT * 2
	local bh = PADT * 2 + LH * #lines + 4
	if x + bw > w - 8 then x = x - bw - 44 end
	if y + bh > h - 8 then y = h - 8 - bh end
	UiPush()
	UiTranslate(x, y)
	UiAlign("left top")
	UiColor(0.02, 0.03, 0.04, 0.96)
	UiRect(bw, bh)
	UiColor(0.45, 0.68, 0.85, 1)
	UiRectOutline(bw, bh, 1)
	UiTranslate(PADT, PADT)
	for i, l in ipairs(lines) do
		local kind = l[2]
		if kind == "title" then UiFont("bold.ttf", 24) UiColor(1, 1, 1, 1)
		else
			UiFont("regular.ttf", 19)
			if kind == "good" then UiColor(0.55, 0.9, 0.55, 1)
			elseif kind == "bad" then UiColor(1, 0.5, 0.45, 1)
			elseif kind == "price" then UiColor(1, 0.85, 0.35, 1)
			elseif kind == "dim" then UiColor(1, 1, 1, 0.55)
			else UiColor(1, 1, 1, 0.9) end
		end
		UiText(l[1])
		UiTranslate(0, LH + (kind == "title" and 4 or 0))
	end
	UiPop()
end
local seenN = -1
local drag = nil         -- the ref being dragged
local dragT, dragX, dragY = 0, 0, 0   -- when and where the drag began
local clickRef, clickT = nil, 0       -- the last click: on what, when (a second one soon after on it: a double click)
local goldDrag, goldDialog = false, nil   -- the wallet dragged from the header; then {n = amount} while the slider shows
INV_DOUBLE_CLICK = 0.4
-- a click on an item (mouse: press and release on it; controller: A to take it, A to put it back): a double click on
-- a loaded gun unloads it (the user, 2026-11-15: a double click rather than a long press, for controllers)
function invClick(me, ref, key)
	local now = GetTime()
	if clickRef == ref and now - clickT <= INV_DOUBLE_CLICK then
		clickRef = nil
		local it = C.get(mine, ref)
		local def = it and C.defs[it.id]
		if def and def.takes and (it.ammo or 0) > 0 then ServerCall("server.invUnload", me, key, ref) end
	else
		clickRef, clickT = ref, now
	end
end
local noteText, noteT = "", 0
local seen, seenT, seenList = 0, 0, {}   -- the item I look at (for the hint), looked for a few times a second
local scanC = 0
local sentOpen = false   -- the screen state the host was last told
local myKey, helloT = nil, 0   -- the key my requests carry (from the host), asked for until it is here
local shownMine = {}           -- a joiner: the tool in my hands and its ammo display last tick
local storeOpen, storePage = false, 1
local storeCat = 1        -- the store's category tab (STORE_CATS)
local STORE_CATS = {"WEAPONS & TOOLS", "CLOTHING", "ITEMS"}
-- an item's store category: 1 tools (the game's and the packs' weapons), 2 anything worn in a slot, 3 the rest
function invStoreCat(id)
	local def = C.defs[id]
	if not def then return 3 end
	if def.kind == "tool" or def.kind == "ammo" then return 1 end
	if def.kind == "clothing" or def.slot then return 2 end
	return 3
end
local resetAsk = nil      -- the host clicked "New session" once: until when a second click resets everyone

-- what the store pays me for the item at ref (nil: it does not buy it, or there is no wallet)
local function sellOffer(ref)
	if not myMoney or not ref then return nil end
	local r = C.resolve(mine, ref)
	local it = r and C.get(mine, r)
	return it and invSellValue(it, storePrice[it.id], sellShare)
end
local storeList, storeN = {}, -1

function client.invKey(k)
	myKey = k
	if INV_TEST then INV_TEST.key = k end                            -- (TEST builds: the test's own requests)
end

function client.invNote(text)
	noteText, noteT = text, 2.5
end

----- the game's own tool bar: it shows the tools by their groups (game.tool.<id>.group, 1-6 by kind of tool), not
----- by our hotkeys, and it has six groups for our nine hotkeys (the user: "the game's hotkey menu only goes up to
----- 6"). So the bar is our own (drawHotbar: all nine, always on screen), and on this machine each hotkeyed tool's
----- group is moved out of the game's six (GROUP_OFF + its hotkey; put back when the hotkey goes): the game's bar
----- finds nothing to show and its number keys pick nothing against ours. The order stays the hotkeys' order.
local GROUP_OFF = 10
local groupWas = {}      -- tool id -> the game's own group, while we have changed it

local function syncToolGroups(inv)
	local now = {}
	for k = 1, C.HOTBAR do
		local it = C.get(inv, "h:" .. k)
		local def = it and C.defs[it.id]
		if def and def.kind == "tool" and def.tool then now[def.tool] = GROUP_OFF + k end
	end
	for id, k in pairs(now) do
		local key = "game.tool." .. id .. ".group"
		if groupWas[id] == nil then groupWas[id] = GetInt(key) end
		if GetInt(key) ~= k then SetInt(key, k) end
	end
	for id, was in pairs(groupWas) do
		if not now[id] then
			SetInt("game.tool." .. id .. ".group", was)
			groupWas[id] = nil
		end
	end
end

----- the avatar: my own character, seen from the front through the window in the player's panel
-- The game has no way to draw a character into the UI, so while the screen is open the camera of this machine
-- stands in front of the player's real character (clothes and all), placed so that the character lands in the
-- panel's window. Third person is requested for as long (the game does not draw the own body in first person).
local avatar = nil       -- the window on the screen, from the last draw: {cx, cy, h, sw, sh} (UI pixels)
local AV_DIST = 4.0      -- m: where the camera stands when there is room
local AV_FOV_MAX = 120   -- the widest view (a wall close by: the camera comes closer and looks wider)
local AV_TALL = 2.5      -- m of height the window shows
-- degrees off the front that are tried, the front first: a player at a wall or a railing is shown from the side
-- (or the back) at the right size rather than from the front with the camera at the nose
local AV_YAWS = {0, 30, -30, 60, -60, 90, -90, 130, -130, 180}
-- The placing above is geometry on paper; where the character really lands is measured on the screen every draw
-- (UiWorldToPixel of the feet and the top of the head) and the difference is fed back: the aim point moves and the
-- size is scaled until the character stands in the middle of the window (the user: "player is not centered").
local AV_HEAD = 1.85     -- m over the feet: the top of the head
local AV_FILL = 0.78     -- the share of the window's height from feet to head
local avFix = {x = 0, y = 0, s = 1}

local function clampN(v, a, b) return math.max(a, math.min(b, v)) end

-- (in the draw, at the root of the UI: screen pixels)
local function avatarMeasure(me)
	local av = avatar
	if not av then return end
	local pt = GetPlayerTransform(me)
	local fx, fy, fd = UiWorldToPixel(pt.pos)
	local hx, hy, hd = UiWorldToPixel(VecAdd(pt.pos, Vec(0, AV_HEAD, 0)))
	if not (fd and hd) or fd <= 0 or hd <= 0 then return end
	local tall = fy - hy
	if tall < 20 then return end
	avFix.x = clampN(avFix.x + clampN(((fx + hx) / 2 - av.cx) * 0.5, -80, 80), -av.sw / 2, av.sw / 2)
	avFix.y = clampN(avFix.y + clampN(((fy + hy) / 2 - av.cy) * 0.5, -80, 80), -av.sh / 2, av.sh / 2)
	avFix.s = clampN(avFix.s * clampN(math.sqrt(av.h * AV_FILL / tall), 0.8, 1.25), 0.4, 2.5)
end

-- the camera for a distance d on a line yaw degrees off the character's front -> its place, rotation, view, and how
-- much of the way to it is free (1: all)
local function avatarView(me, av, c, fwd, yaw, d)
	local ppm = av.h / AV_TALL * avFix.s                             -- UI pixels a metre at the character
	local cx, cy = av.cx - avFix.x, av.cy - avFix.y                  -- where to aim, so that it lands in the window
	local fov = math.deg(2 * math.atan((av.sw / 2) / (ppm * d)))
	if fov > AV_FOV_MAX then
		fov = AV_FOV_MAX
		ppm = (av.sw / 2) / (d * math.tan(math.rad(fov / 2)))        -- (closer than the widest view allows: bigger)
	end
	local r = math.rad(yaw)
	local dir = Vec(fwd[1] * math.cos(r) + fwd[3] * math.sin(r), 0, fwd[3] * math.cos(r) - fwd[1] * math.sin(r))
	local pos = VecAdd(c, VecScale(dir, d))
	-- The camera stays on that line (room is only needed along it) and TURNS so that the character lands in the
	-- window instead of the middle of the screen: right by the angle the window is left of centre, and likewise up.
	local k = math.tan(math.rad(fov / 2)) / (av.sw / 2)
	local yaw2 = -math.deg(math.atan((av.sw / 2 - cx) * k))
	local pitch2 = -math.deg(math.atan((av.sh / 2 - cy) * k))
	local rot = QuatRotateQuat(QuatLookAt(pos, c), QuatEuler(pitch2, yaw2, 0))
	local to = VecSub(pos, c)
	local l = VecLength(to)
	QueryRequire("physical")
	QueryRejectPlayer(me)
	local hit, dist = QueryRaycast(c, VecScale(to, 1 / l), l, 0.15)
	return pos, rot, fov, (hit and math.max(0, dist - 0.25) / l) or 1
end

local function avatarCamera(me)
	local av = avatar
	if not av then return end
	RequestThirdPerson(false)
	local pt = GetPlayerTransform(me)
	local fwd = TransformToParentVec(pt, Vec(0, 0, -1))
	fwd = Vec(fwd[1], 0, fwd[3])
	if VecLength(fwd) < 0.01 then return end
	fwd = VecNormalize(fwd)
	local c = VecAdd(pt.pos, Vec(0, 0.95, 0))                        -- the middle of the body
	-- the front if it is free, else the freest line near the front; then as far out on it as is free
	local yaw, free = 0, -1
	for i = 1, #AV_YAWS do
		local _, _, _, f = avatarView(me, av, c, fwd, AV_YAWS[i], AV_DIST)
		if f > free + 0.05 then yaw, free = AV_YAWS[i], f end
		if f >= 0.7 then break end                                   -- (room enough: the nearest to the front wins)
	end
	local d = AV_DIST
	local pos, rot, fov
	for _ = 1, 3 do
		local f
		pos, rot, fov, f = avatarView(me, av, c, fwd, yaw, d)
		if f >= 1 then break end
		d = math.max(0.9, d * math.max(0.3, f))
	end
	SetCameraTransform(Transform(pos, rot), fov)
	SetCameraDof(d, 0)                                               -- (sharp: no depth blur on a close character)
	PointLight(VecAdd(c, VecAdd(VecScale(fwd, 1.6), Vec(0, 0.6, 0))), 1, 0.95, 0.88, 0.8)   -- (seen at night too)
end

----- the punch, shown (the host decides it: client.invPunch at the start, client.invPunchHit where it lands)
local punches = {}       -- player -> {t, delay, cooldown, whoosh}
local sndWhoosh, sndFlesh, sndWood, sndMetal, sndStone, sndGlass = {}, {}, {}, {}, {}, {}
local PUNCH_WIND = 0.55  -- the share of the delay that is the wind-up
-- where the punching hand is, in the eye's frame (x right, y up, z back): beside the chest, drawn back, arm's length
local PUNCH_POSE = {rest = {0.22, -0.45, -0.25}, wind = {0.26, -0.32, -0.05}, hit = {0.06, -0.20, -0.72}}

-- The puncher's own first-person view: the game draws no arms there, so a forearm and fist of our own (a body
-- of this machine alone, nothing physical) is held in front of the camera for the length of the punch. The wrist
-- in the camera's frame; the fist reaches 0.2 m further.
local FIST_POSE = {rest = {0.30, -0.50, -0.10}, wind = {0.30, -0.30, -0.15}, hit = {0.10, -0.24, -0.62}}
local FIST_XML = "<body>"
	.. "<voxbox pos='-0.05 -0.05 0.0' size='1 1 5' color='0.74 0.60 0.52' material='unphysical' collide='false'/>"
	.. "<voxbox pos='-0.1 -0.1 -0.2' size='2 2 2' color='0.76 0.62 0.54' material='unphysical' collide='false'/>"
	.. "</body>"
local fist, fistEnts, fistBad = 0, {}, false

local function fistDrop()
	for _, e in ipairs(fistEnts) do
		if IsHandleValid(e) then Delete(e) end
	end
	fist, fistEnts = 0, {}
end

local function loadSet(list, fmt, n)
	for i = 0, n - 1 do list[#list + 1] = LoadSound(string.format(fmt, i)) end
end
local function rnd(a, b) return a + math.random() * (b - a) end
local function oneOf(list) return list[math.random(1, #list)] end

function client.invPunch(p, delay, cooldown)
	if type(p) ~= "number" or type(delay) ~= "number" or type(cooldown) ~= "number" then return end
	punches[p] = {t = 0, delay = delay, cooldown = cooldown, whoosh = false}
end

function client.invPunchHit(p, kind, x, y, z)
	if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then return end
	local pos = Vec(x, y, z)
	if type(p) == "number" and IsPlayerLocal(p) then ShakeCamera(0.2) end
	local set = kind == 1 and sndFlesh or kind == 2 and sndWood or kind == 3 and sndMetal or kind == 5 and sndGlass or sndStone
	if #set > 0 then PlaySound(oneOf(set), pos, 0.7, true, rnd(0.95, 1.15)) end
	ParticleReset()
	if kind == 1 then
		ParticleType("plain")
		ParticleColor(0.45, 0.03, 0.02, 0.2, 0.01, 0.01)
		ParticleRadius(0.02, 0.035)
		ParticleGravity(-9)
		ParticleDrag(0.2)
		for _ = 1, 4 do SpawnParticle(pos, Vec(rnd(-1.5, 1.5), rnd(0.5, 2.5), rnd(-1.5, 1.5)), rnd(0.4, 0.8)) end
	else
		ParticleType("smoke")
		if kind == 2 then ParticleColor(0.45, 0.36, 0.25, 0.3, 0.25, 0.2) else ParticleColor(0.6, 0.6, 0.6, 0.4, 0.4, 0.4) end
		ParticleRadius(0.05, 0.18)
		ParticleAlpha(0.5, 0)
		ParticleGravity(-0.5)
		ParticleDrag(1.5)
		for _ = 1, 3 do SpawnParticle(pos, Vec(rnd(-0.6, 0.6), rnd(0, 0.8), rnd(-0.6, 0.6)), rnd(0.5, 1.0)) end
	end
end

local function punchPos(sw, pose)
	local PUNCH_POSE = pose or PUNCH_POSE
	local t, tw, th = sw.t, sw.delay * PUNCH_WIND, sw.delay
	local te = th + sw.cooldown
	local a, b, u
	if t < tw then
		a, b, u = PUNCH_POSE.rest, PUNCH_POSE.wind, t / tw
	elseif t < th then
		a, b, u = PUNCH_POSE.wind, PUNCH_POSE.hit, (t - tw) / (th - tw)
		u = u * u
	elseif t < th + (te - th) * 0.35 then
		a, b, u = PUNCH_POSE.hit, PUNCH_POSE.hit, 0
	else
		a, b, u = PUNCH_POSE.hit, PUNCH_POSE.rest, (t - th - (te - th) * 0.35) / ((te - th) * 0.65)
		u = u * u * (3 - 2 * u)
	end
	return Vec(a[1] + (b[1] - a[1]) * u, a[2] + (b[2] - a[2]) * u, a[3] + (b[3] - a[3]) * u)
end

-- The hand never leaves the arm's reach (the Wardrobe mod found this on its weapons: a target further from the
-- shoulder than the arm is long cannot be followed by the game's hand IK and the arm snaps about, worst while
-- walking - the user: "the arms flail around like crazy for a moment"). The shoulder in the eye's frame, the
-- arm's length a little short of straight.
local ARM_SHOULDER, ARM_LEN = {0.2, -0.24, 0.02}, 0.54
local function armReach(v)
	local x, y, z = v[1] - ARM_SHOULDER[1], v[2] - ARM_SHOULDER[2], v[3] - ARM_SHOULDER[3]
	local l = math.sqrt(x * x + y * y + z * z)
	if l <= ARM_LEN then return v end
	local k = ARM_LEN / l
	return Vec(ARM_SHOULDER[1] + x * k, ARM_SHOULDER[2] + y * k, ARM_SHOULDER[3] + z * k)
end

-- how much the punch holds the arm (0-1): taken over and given back gradually, not in one frame
local function armWeight(sw)
	local te = sw.delay + sw.cooldown
	return math.max(0, math.min(1, sw.t / 0.06, (te - sw.t) / 0.12))
end

local function punchClientTick(dt)
	for p, sw in pairs(punches) do
		sw.t = sw.t + dt
		if not sw.whoosh and sw.t >= sw.delay * PUNCH_WIND then
			sw.whoosh = true
			if IsPlayerValid(p) then
				-- (the puncher's own swing at the camera: the same sound in first and third person)
				local at = IsPlayerLocal(p) and GetCameraTransform().pos or GetPlayerEyeTransform(p).pos
				if #sndWhoosh > 0 then PlaySound(oneOf(sndWhoosh), at, 0.5, false, rnd(1.1, 1.3)) end
				if IsPlayerLocal(p) then ShakeCamera(0.05) end
			end
		end
		if sw.t >= sw.delay + sw.cooldown or not IsPlayerValid(p) then punches[p] = nil end
	end
end

-- The punching arm, for everyone who sees the puncher's character (not the puncher's own first-person view: the
-- game draws no arms there). Bone work on a player's character only takes effect from client.postUpdate.
function Inv.clientPostUpdate()
	-- my own punch in first person: the fist in front of the camera
	local me = GetLocalPlayer()
	local mine = punches[me]
	if mine and not GetBool("game.thirdperson") and not fistBad then
		if fist == 0 or not IsHandleValid(fist) then
			local ok, ents = pcall(Spawn, FIST_XML, Transform(Vec(0, -500, 0)))
			fist, fistEnts = 0, ok and ents or {}
			for _, e in ipairs(fistEnts) do
				if GetEntityType(e) == "body" then fist = e end
			end
			if fist == 0 then fistBad = true end                       -- (no body of our own on this machine: no fist)
		end
		if fist ~= 0 then
			local cam = GetCameraTransform()
			SetBodyTransform(fist, Transform(TransformToParentPoint(cam, punchPos(mine, FIST_POSE)), cam.rot))
		end
	elseif fist ~= 0 then
		fistDrop()
	end
	for p, sw in pairs(punches) do
		if IsPlayerValid(p) and not (IsPlayerLocal(p) and not GetBool("game.thirdperson")) then
			local anim = GetPlayerAnimator(p)
			if anim and anim ~= 0 then
				local eye = GetPlayerEyeTransform(p)
				SetAnimatorTransformIK(anim, "shoulder_r", "hand_r", Transform(TransformToParentPoint(eye, armReach(punchPos(sw))), eye.rot), armWeight(sw), 0, false, true)
			end
		end
	end
end

function Inv.clientInit()
	loadSet(sndWhoosh, "throw/s%d.ogg", 6)
	loadSet(sndFlesh, "flesh-impact%d.ogg", 5)
	loadSet(sndWood, "wood/hit-m%d.ogg", 6)
	loadSet(sndMetal, "metal/hit-m%d.ogg", 6)
	loadSet(sndStone, "masonry/hit-m%d.ogg", 5)
	loadSet(sndGlass, "glass/hit-m%d.ogg", 4)
	invScanDefs()
end

function Inv.clientTick(dt)
	if GetString("inventory.key.open") ~= INV_KEY then SetString("inventory.key.open", INV_KEY) end   -- (other mods: the key)
	scanC = scanC - dt
	if scanC <= 0 then
		scanC = INV_SCAN
		invScanDefs()
	end
	noteT = math.max(0, noteT - dt)
	local me = GetLocalPlayer()
	seenT = seenT - dt
	if seenT <= 0 then
		seenT = 0.5
		seenList = FindBodies("invitem", true) or {}
	end
	seen = 0
	if not open and GetPlayerHealth(me) > 0 then
		local list = {}
		for i = 1, #seenList do
			if IsHandleValid(seenList[i]) then list[#list + 1] = seenList[i] end
		end
		seen = invAimed(me, list)
	end
	local s = shared.inv
	if s and s.n ~= seenN then
		seenN = s.n
		local v = s.p and s.p["p" .. me]
		mine = v and C.copy({g = v.g or {}, h = v.h or {}, e = v.e or {}}) or C.new()
		myMoney = v and v.money or nil
		if myMoney and moneySeen and myMoney ~= moneySeen then         -- a change: "+150" / "-50" floats up from the gold
			moneyFloats[#moneyFloats + 1] = {d = myMoney - moneySeen, t = GetTime()}
		end
		moneySeen = myMoney
		syncToolGroups(mine)
	end
	local st = shared.invStore
	if st and st.n ~= storeN then
		storeN, storeList, storePrice, sellShare = st.n, {}, {}, st.sell or 0
		for i, e in ipairs(st.list or {}) do
			storeList[i] = {id = e.id, price = e.price}
			storePrice[e.id] = e.price
		end
	end
	if not myKey then                                                -- (the host's first send can come before we run)
		helloT = helloT - dt
		if helloT <= 0 then
			helloT = 1
			ServerCall("server.invHello", me)
		end
	end
	if GetPlayerHealth(me) <= 0 or invBlocked(me) then
		open, drag = false, nil
	elseif (invPressed(INV_KEY) and not GetBool("proxchat.typing." .. me)) or (LastInputDevice() == INV_PAD and InputPressed("map")) then
		open = not open
		drag = nil
	elseif open and InputPressed("pause") then
		open, drag = false, nil
	end
	-- hotkeys 1-9: the slot's tool into the hands (the host does it)
	if not open and myKey and GetPlayerHealth(me) > 0 and not GetBool("proxchat.typing." .. me) then
		for k = 1, C.HOTBAR do
			if InputPressed(tostring(k)) then ServerCall("server.invSelect", me, myKey, k) end
		end
	end
	-- the mouse wheel (LB / RB on a controller): the next / previous hotkey that holds something, round and round
	if not open and myKey and GetPlayerHealth(me) > 0 and GetPlayerGrabBody(me) == 0 and GetPlayerVehicle(me) == 0
		and not GetBool("game.input.locktool") then
		local w = InputValue("mousewheel") or 0
		local dir = (w > 0 and -1) or (w < 0 and 1) or 0
		if dir ~= 0 then
			local held = string.lower(GetString("game.player.tool"))
			local at = dir > 0 and 0 or C.HOTBAR + 1
			for k = 1, C.HOTBAR do
				local it = C.get(mine, "h:" .. k)
				local def = it and C.defs[it.id]
				if def and def.kind == "tool" and def.tool == held then at = k end
			end
			for i = 1, C.HOTBAR do
				local k = (at - 1 + dir * i) % C.HOTBAR + 1
				if C.get(mine, "h:" .. k) then
					ServerCall("server.invSelect", me, myKey, k)
					break
				end
			end
		end
	end
	-- a joiner: under the sandbox the host leaves its tools at 9999, so a step down from there on its own display is
	-- a use - tell the host (see enforceTools)
	if myKey and not IsPlayerHost(me) then
		local id = string.lower(GetString("game.player.tool"))
		local key = "game.tool." .. id .. ".ammo.display"
		local d = id ~= "" and id ~= "none" and HasKey(key) and GetFloat(key) or nil
		local was = shownMine.id == id and shownMine.d or nil
		if d and was and was >= 9000 and d >= 9000 and d < was then
			ServerCall("server.invShot", me, myKey, id, was - d)
		end
		shownMine.id, shownMine.d = id, d
	end
	if open then avatarCamera(me) else avatar = nil end
	if GetBool("inventory.screenopen") ~= open then SetBool("inventory.screenopen", open) end   -- (local: other mods
	-- hide their world labels over the screen - asked for by the Villagers session, for the user)
	if myKey and open ~= sentOpen then                              -- (the host: no punches from clicks in the screen)
		sentOpen = open
		ServerCall("server.invScreen", me, myKey, open)
	end
	punchClientTick(dt)
end

local function iconOf(def)
	local path = def and def.icon or ""
	if path ~= "" and HasFile(path) then return path end
	return nil
end

-- an item drawn into a CELL x CELL box at the cursor
local function drawItem(it, alpha)
	local def = C.defs[it.id]
	local icon = iconOf(def)
	UiPush()
	if icon then
		local w, h = UiGetImageSize(icon)
		local s = (CELL - 12) / math.max(w, h, 1)
		UiTranslate(CELL / 2, CELL / 2)
		UiAlign("center middle")
		UiScale(s)
		UiColor(1, 1, 1, alpha)
		UiImage(icon)
	else
		UiTranslate(CELL / 2, CELL / 2 - 6)
		UiAlign("center middle")
		UiColor(1, 1, 1, alpha)
		UiFont("regular.ttf", 15)
		UiWordWrap(CELL - 8)
		UiText(def and def.name or invPrettyId(it.id))
	end
	UiPop()
	if def and def.takes and (it.ammo or 0) > 0 then              -- a loaded gun: its ammo's icon, small, bottom left
		local l = C.defs[invLoadOf(it)]
		local aicon = l and iconOf(l)
		if aicon then
			UiPush()
			local w, h = UiGetImageSize(aicon)
			UiTranslate(3, CELL - 3)
			UiAlign("left bottom")
			UiScale(22 / math.max(w, h, 1))
			UiColor(1, 1, 1, alpha)
			UiImage(aicon)
			UiPop()
		end
	end
	local label = nil
	if def and def.kind == "tool" and it.ammo then label = tostring(math.ceil(it.ammo)) end
	if it.n and it.n > 1 then label = tostring(it.n) end
	if label then
		UiPush()
		UiTranslate(CELL - 5, CELL - 4)
		UiAlign("right bottom")
		UiColor(1, 1, 1, alpha)
		UiFont("bold.ttf", 17)
		UiText(label)
		UiPop()
	end
end

-- The hotkeys on screen while playing: all nine along the bottom (over the game's own line with the held tool's
-- name), each with its item, its count and its key; the one in the hands marked.
local BAR_SCALE, BAR_UP = 0.8, 96
local function drawHotbar()
	local held = string.lower(GetString("game.player.tool"))
	local step = CELL + GAP
	UiPush()
	UiTranslate(UiCenter() - (C.HOTBAR * step - GAP) * BAR_SCALE / 2, UiHeight() - BAR_UP - CELL * BAR_SCALE)
	UiScale(BAR_SCALE)
	UiAlign("left top")
	for k = 1, C.HOTBAR do
		local it = C.get(mine, "h:" .. k)
		local def = it and C.defs[it.id]
		local sel = def ~= nil and def.kind == "tool" and def.tool == held
		UiPush()
		UiTranslate((k - 1) * step, 0)
		UiColor(0.05, 0.06, 0.07, sel and 0.8 or 0.55)
		UiRect(CELL, CELL)
		if sel then UiColor(1, 0.85, 0.35, 1) else UiColor(0.6, 0.64, 0.68, 0.55) end
		UiRectOutline(CELL, CELL, sel and 3 or 1)
		if it then drawItem(it, 1) end
		UiTranslate(6, 3)
		UiColor(1, 1, 1, sel and 1 or 0.7)
		UiFont("bold.ttf", 16)
		UiTextOutline(0, 0, 0, 0.7, 0.15)
		UiText(tostring(k))
		UiPop()
	end
	UiPop()
end

-- one place at (x, y): the box, its item, the mouse -> the ref when the mouse is over it
local padMode = false    -- a controller drives the screen: a focus cell instead of the mouse
local focus = "h:1"      -- the focused cell's key (a ref, or "s:<id>" for a store entry)
local cells = {}         -- this frame's cells {x, y, key}, for moving the focus

local function drawCell(ref, x, y, hint, num)
	local it = C.get(mine, ref)
	local over
	cells[#cells + 1] = {x = x, y = y, key = ref}
	UiPush()
	UiTranslate(x, y)
	if padMode then over = focus == ref else over = UiIsMouseInRect(CELL, CELL) end
	UiAlign("left top")
	UiColor(0.07, 0.08, 0.09, 0.92)
	UiRect(CELL, CELL)
	if over then UiColor(0.45, 0.68, 0.85, 1) else UiColor(0.28, 0.31, 0.34, 1) end
	UiRectOutline(CELL, CELL, over and 2 or 1)
	if drag == ref and padMode then                                 -- (taken with A: marked where it lies)
		UiColor(1, 0.85, 0.35, 1)
		UiRectOutline(CELL, CELL, 3)
	end
	if num then
		UiPush()
		UiTranslate(5, 3)
		UiColor(1, 1, 1, 0.45)
		UiFont("bold.ttf", 14)
		UiText(tostring(num))
		UiPop()
	end
	if it and (drag ~= ref or padMode) then
		drawItem(it, 1)
		local gk = string.sub(ref, 1, 1) == "g" and C.slotOf(mine, tonumber(string.sub(ref, 3)))
		if gk then                                                   -- (a grid item a hotkey points at: its key)
			UiPush()
			UiTranslate(4, 3)
			UiColor(0.45, 0.68, 0.85, 1)
			UiRect(18, 18)
			UiTranslate(9, 9)
			UiAlign("center middle")
			UiColor(0, 0, 0, 1)
			UiFont("bold.ttf", 14)
			UiText(tostring(gk))
			UiPop()
		end
	elseif not it and hint then
		UiTranslate(CELL / 2, CELL / 2)
		UiAlign("center middle")
		UiColor(1, 1, 1, 0.3)
		UiFont("regular.ttf", 15)
		UiWordWrap(CELL - 8)
		UiTextAlignment("center")
		UiText(hint)
	end
	UiPop()
	return over and ref or nil
end

-- the wallet dragged out of the window, then a slider for how much gold to drop (screen coordinates, after the window)
panelRect = {0, 0, 0, 0}
function invGoldUi(me)
	if not myMoney or myMoney < 1 or not open then goldDrag, goldDialog = false, nil return end
	local mx, my = UiGetMousePos()
	if goldDrag then
		UiPush()
		UiTranslate(mx, my)
		UiAlign("center middle")
		UiScale(44 / 64)
		UiImage("MOD/images/coin.png")
		UiPop()
		if not InputDown("lmb") then
			goldDrag = false
			local r = panelRect
			if mx < r[1] or my < r[2] or mx > r[1] + r[3] or my > r[2] + r[4] then
				goldDialog = {n = math.max(1, math.floor(myMoney / 2))}
			end
		end
		return
	end
	local d = goldDialog
	d.n = math.max(1, math.min(myMoney, d.n))
	local W, H = 560, 230
	UiPush()
	UiTranslate(UiCenter() - W / 2, UiMiddle() - H / 2)
	UiAlign("left top")
	UiColor(0.03, 0.04, 0.05, 0.96)
	UiRect(W, H)
	UiColor(1, 0.85, 0.35, 0.8)
	UiRectOutline(W, H, 2)
	UiPush()
	UiTranslate(30, 26)
	UiColor(1, 1, 1, 0.95)
	UiFont("bold.ttf", 30)
	UiText("DROP GOLD")
	UiPop()
	UiPush()                                                          -- the amount
	UiTranslate(W - 30, 42)
	drawGold(d.n, 30, "right")
	UiPop()
	local bx, by, bw = 40, 110, W - 80                                -- the slider
	UiPush()
	UiTranslate(bx, by)
	UiColor(0.2, 0.22, 0.25, 1)
	UiRect(bw, 8)
	local f = myMoney > 1 and (d.n - 1) / (myMoney - 1) or 1
	UiColor(1, 0.85, 0.35, 1)
	UiRect(bw * f, 8)
	UiTranslate(bw * f, 4)
	UiAlign("center middle")
	UiRect(18, 30)
	UiPop()
	UiPush()
	UiTranslate(bx - 10, by - 20)
	if UiIsMouseInRect(bw + 20, 48) and InputDown("lmb") then
		local lx = UiGetMousePos()
		local u = math.max(0, math.min(1, (lx - 10) / bw))
		d.n = math.max(1, math.floor(1 + u * (myMoney - 1) + 0.5))
	end
	UiPop()
	local function button(x, label, w)
		UiPush()
		UiTranslate(x, H - 66)
		local over = UiIsMouseInRect(w, 42)
		UiColor(1, 0.85, 0.35, over and 1 or 0.6)
		UiRoundedRectOutline(w, 42, 6, 2)
		UiTranslate(w / 2, 21)
		UiAlign("center middle")
		UiColor(1, 1, 1, 0.95)
		UiFont("bold.ttf", 22)
		UiText(label)
		UiPop()
		return over and InputPressed("lmb")
	end
	if button(40, "-", 50) then d.n = d.n - math.max(1, math.floor(myMoney / 20)) end
	if button(100, "+", 50) then d.n = d.n + math.max(1, math.floor(myMoney / 20)) end
	if button(160, "ALL", 80) then d.n = myMoney end
	if button(W - 300, "CANCEL", 120) then goldDialog = nil end
	if button(W - 170, "DROP", 130) then
		ServerCall("server.invDropGold", me, myKey, d.n)
		goldDialog = nil
	end
	UiPop()
end

local function invDrawMain()
	local me = GetLocalPlayer()
	if invBlocked(me) then return end                                -- (inventory.block: nothing of ours on screen)
	if noteT > 0 then
		UiPush()
		UiTranslate(UiCenter(), UiHeight() - 220)
		UiAlign("center middle")
		UiFont("bold.ttf", 26)
		UiColor(1, 1, 1, math.min(1, noteT))
		UiTextOutline(0, 0, 0, 0.8, 0.2)
		UiText(noteText)
		UiPop()
	end
	if not open and seen ~= 0 and IsHandleValid(seen) then
		UiPush()
		UiTranslate(UiCenter(), UiMiddle() + 90)
		UiAlign("center middle")
		UiFont("bold.ttf", 24)
		UiColor(1, 1, 1, 1)
		UiTextOutline(0, 0, 0, 0.8, 0.2)
		UiText("E: pick up " .. GetDescription(seen))
		UiPop()
	end
	if not open then
		-- the key, in the bottom right corner (the user: "one corner of the screen should show a hint saying I for
		-- inventory")
		if GetPlayerHealth(me) > 0 then
			drawHotbar()
			if myMoney then                                          -- (gold coins, over the key hint)
				UiPush()
				UiTranslate(UiWidth() - 36, UiHeight() - 36 - 54)
				drawGold(myMoney, 26, "right")
				UiPop()
			end
			local boostLeft = GetInt("inventory.boost." .. me)       -- BlueTide's seconds, over the gold
			if boostLeft > 0 then
				UiPush()
				UiTranslate(UiWidth() - 36, UiHeight() - 36 - 54 - 40)
				UiAlign("right middle")
				UiFont("bold.ttf", 24)
				UiColor(0.45, 0.7, 1, 1)
				UiTextOutline(0, 0, 0, 0.8, 0.2)
				UiText((C.defs.bluetide and C.defs.bluetide.name or "BlueTide") .. "  " .. math.floor(boostLeft / 60) .. ":" .. string.format("%02d", boostLeft % 60))
				UiPop()
			end
			local pad = LastInputDevice() == INV_PAD
			local key = pad and "MAP" or string.upper(INV_KEY)
			UiPush()
			UiTranslate(UiWidth() - 36, UiHeight() - 36)
			UiAlign("right bottom")
			UiFont("regular.ttf", 22)
			UiColor(1, 1, 1, 0.8)
			UiTextOutline(0, 0, 0, 0.6, 0.15)
			local tw = UiText("Inventory")
			UiTranslate(-(tw or 96) - 10, 3)
			local kw = pad and 62 or 32
			UiColor(0, 0, 0, 0.55)
			UiRoundedRect(kw, 32, 5)
			UiColor(1, 1, 1, 0.8)
			UiRoundedRectOutline(kw, 32, 5, 2)
			UiTranslate(-kw / 2, -16)
			UiAlign("center middle")
			UiFont("bold.ttf", 20)
			UiText(key)
			UiPop()
		end
		return
	end
	UiMakeInteractive()
	padMode = LastInputDevice() == INV_PAD
	cells = {}
	local cols = C.COLS
	local rows = math.ceil(C.GRID / cols)
	local step = CELL + GAP
	local nSlots = #C.SLOTS
	local eRows = 4                                                  -- (slots: columns of four, head to feet)
	local gridW, gridH = cols * step - GAP, rows * step - GAP
	local PAD = 36
	-- the player's panel: the slots (columns of four), the avatar window, the stats; the hotkeys along the bottom
	local slotCols = math.max(1, math.ceil(nSlots / eRows))
	local avX, avW, avH = PAD + slotCols * step + 8, 300, gridH
	local leftW = math.max(avX - PAD + avW + 20 + 150, C.HOTBAR * step - GAP - 60 - gridW)
	local hasStore = #storeList > 0
	if GetBool("inventory.test.store") then storeOpen = true end    -- (autotests)
	if GetInt("inventory.test.storecat") > 0 then storeCat, storePage = GetInt("inventory.test.storecat"), 1 end
	if not hasStore then storeOpen = false end
	-- the store is a tab in place of the equipment (the user, 2026-11-15: "so it saves space"): as many columns as fit
	-- the player's panel, and rows over the grid's height less the page row
	local storeCols = math.max(1, math.floor((leftW + GAP) / step))
	local CAT_H = 46                                                 -- the store's category tabs, over its cells
	local storeRows = math.max(1, math.floor((gridH - 18 - CAT_H) / (step + 22)))
	local storeW = storeCols * step - GAP
	local W = PAD + leftW + 60 + gridW + PAD
	local top = 70
	local hy = top + gridH + 46                                      -- the hotkey row
	local H = hy + CELL + 52 + PAD
	local x0, y0 = UiCenter() - W / 2, UiMiddle() - H / 2
	panelRect = {x0, y0, W, H}
	local hover = nil
	if storeOpen then
		avatar = nil                                                 -- (no window: the store covers it)
	else
		avatar = {cx = x0 + avX + avW / 2, cy = y0 + top + avH / 2, h = avH, sw = UiWidth(), sh = UiHeight()}
		avatarMeasure(me)
	end

	UiPush()
	UiTranslate(x0, y0)
	UiAlign("left top")
	-- the panel, with a window in it: the camera looks at my own character through it (Inv.clientTick)
	UiColor(0.03, 0.04, 0.05, 0.9)
	if storeOpen then
		UiRect(W, H)
	else
		UiRect(W, top)
		UiPush() UiTranslate(0, top) UiRect(avX, avH) UiPop()
		UiPush() UiTranslate(avX + avW, top) UiRect(W - avX - avW, avH) UiPop()
		UiPush() UiTranslate(0, top + avH) UiRect(W, H - top - avH) UiPop()
		UiPush()
		UiTranslate(avX, top)
		UiColor(0.28, 0.31, 0.34, 1)
		UiRectOutline(avW, avH, 1)
		UiPop()
	end
	local inPanel = UiIsMouseInRect(W, H)

	-- headers: the player's panel has two tabs, EQUIPMENT and STORE (a click, or the controller's menu_next)
	local function tab(x, label, on)
		UiPush()
		UiTranslate(x, 22)
		UiFont("bold.ttf", 30)
		local w = UiGetTextSize(label)
		local over = UiIsMouseInRect(w, 34)
		UiColor(1, 1, 1, on and 0.95 or (over and 0.75 or 0.4))
		UiText(label)
		if on then
			UiTranslate(0, 36)
			UiColor(0.45, 0.68, 0.85, 1)
			UiRect(w, 3)
		end
		UiPop()
		return w, over and InputPressed("lmb") and not drag
	end
	local tw, hit = tab(PAD, "EQUIPMENT", not storeOpen)
	if hit then storeOpen = false end
	if hasStore then
		local _, hit2 = tab(PAD + tw + 36, "STORE", storeOpen)
		if hit2 then storeOpen = true end
		if padMode and InputPressed("menu_next") and not drag then storeOpen = not storeOpen end
	end
	UiColor(1, 1, 1, 0.95)
	UiFont("bold.ttf", 30)
	if IsPlayerHost() and shared.invKeep == "session" and myKey then   -- the host's "New session" (inv_keep.lua)
		local asking = resetAsk and GetTime() < resetAsk
		UiPush()
		UiTranslate(PAD + leftW + 60 + gridW - 170, 18)
		local over = UiIsMouseInRect(170, 38)
		if asking then UiColor(0.95, 0.35, 0.3, 1) else UiColor(0.6, 0.62, 0.66, over and 1 or 0.55) end
		UiRoundedRectOutline(170, 38, 6, 2)
		UiTranslate(85, 19)
		UiAlign("center middle")
		UiFont("bold.ttf", 20)
		UiColor(1, 1, 1, 0.95)
		UiText(asking and "RESET ALL?" or "NEW SESSION")
		UiPop()
		if over and not drag and InputPressed("lmb") then
			if asking then
				resetAsk = nil
				ServerCall("server.invNewSession", me, myKey)
			else
				resetAsk = GetTime() + 3
			end
		end
	end
	UiPush()
	UiTranslate(PAD + leftW + 60, 22)
	UiText("INVENTORY")
	UiPop()

	-- equipment: the slots head to feet, left of the avatar (a mod's extra slots in further columns)
	for i = 1, storeOpen and 0 or nSlots do
		local slot = C.SLOTS[i]
		local col, row = math.floor((i - 1) / eRows), (i - 1) % eRows
		hover = drawCell("e:" .. slot, PAD + col * step, top + row * step, SLOT_NAMES[slot] or slot) or hover
	end
	-- what is worn adds up to, right of the avatar
	local st = C.stats(mine)
	local lines = {{"DEFENCE", math.floor(st.defense * 100 + 0.5) .. "%"}, {"IMMUNITY", tostring(math.floor(st.defense * 100 * (WARDROBE_IMMUNITY or 0.2) + 0.5))}, {"MOBILITY", pctText(st.mobility - 1, true)}, {"NOISE", pctText(st.noise - 1, true)}}
	for i = 1, storeOpen and 0 or #lines do
		UiPush()
		UiTranslate(avX + avW + 20, top + (i - 1) * 96 + 8)
		UiColor(1, 1, 1, 0.6)
		UiFont("regular.ttf", 18)
		UiText(lines[i][1])
		UiTranslate(0, 24)
		UiColor(1, 1, 1, 0.95)
		UiFont("bold.ttf", 36)
		UiText(lines[i][2])
		UiPop()
	end

	-- the hotkeys, along the bottom of the panel
	UiPush()
	UiTranslate(PAD, hy - 24)
	UiColor(1, 1, 1, 0.6)
	UiFont("regular.ttf", 18)
	UiText("HOTKEYS 1 - " .. C.HOTBAR .. "  (each points at an item in your inventory)")
	UiPop()
	for i = 1, C.HOTBAR do
		hover = drawCell("h:" .. i, PAD + (i - 1) * step, hy, nil, i) or hover
	end

	-- the grid
	local gx = PAD + leftW + 60
	for i = 1, C.GRID do
		local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
		hover = drawCell("g:" .. i, gx + col * step, top + row * step) or hover
	end

	-- gold, in the header (none: the store is free); dragged out of the window: a slider for how much to drop
	if myMoney then
		UiPush()
		UiTranslate(gx + 175, 20)
		local overGold = UiIsMouseInRect(170, 34)
		if overGold and myMoney > 0 and not drag and not goldDialog and not padMode and InputPressed("lmb") then goldDrag = true end
		UiTranslate(15, 17)
		drawGold(myMoney, 24, nil, (overGold or goldDrag) and {1, 0.95, 0.6} or nil)
		UiPop()
	end

	-- the store tab: what it sells, in the player's panel
	local buy = nil
	local overSell = false                                           -- the dragged item is over the store, and it buys it
	if storeOpen then
		local sx = PAD
		-- three categories (the user, 2026-11-15): weapons and tools / clothing / items, each with its own pages
		local shown, counts = {}, {0, 0, 0}
		for _, e in ipairs(storeList) do
			if C.defs[e.id] then                                     -- (one this machine doesn't know: not shown, not bought)
				local c = invStoreCat(e.id)
				counts[c] = counts[c] + 1
				if c == storeCat then shown[#shown + 1] = e end
			end
		end
		local cx = sx
		for c = 1, #STORE_CATS do
			UiPush()
			UiTranslate(cx, top)
			UiFont("bold.ttf", 20)
			local label = STORE_CATS[c]
			local w = UiGetTextSize(label) + 24
			local over = UiIsMouseInRect(w, 32)
			local on = c == storeCat
			UiColor(0.45, 0.68, 0.85, on and 1 or (over and 0.7 or 0.3))
			UiRoundedRectOutline(w, 32, 6, on and 2 or 1)
			UiTranslate(w / 2, 16)
			UiAlign("center middle")
			UiColor(1, 1, 1, on and 0.95 or (counts[c] > 0 and 0.6 or 0.25))
			UiText(label)
			UiPop()
			if over and InputPressed("lmb") and not drag and not on then storeCat, storePage = c, 1 end
			cx = cx + w + 10
		end
		local ctop = top + CAT_H
		local per = storeCols * storeRows
		local pages = math.max(1, math.ceil(#shown / per))
		if padMode and InputPressed("menu_prev") then                -- (the controller: pages, then the next category)
			if storePage < pages then storePage = storePage + 1 else storeCat, storePage = storeCat % #STORE_CATS + 1, 1 end
		end
		storePage = math.max(1, math.min(storePage, pages))
		for k = 1, per do
			local e = shown[(storePage - 1) * per + k]
			if e then
				local col, row = (k - 1) % storeCols, math.floor((k - 1) / storeCols)
				UiPush()
				UiTranslate(sx + col * step, ctop + row * (step + 22))
				local skey = "s:" .. e.id
				cells[#cells + 1] = {x = sx + col * step, y = ctop + row * (step + 22), key = skey}
				local over
				if padMode then over = focus == skey else over = UiIsMouseInRect(CELL, CELL + 20) end
				local can = not myMoney or myMoney >= e.price
				UiColor(0.07, 0.08, 0.09, 0.92)
				UiRect(CELL, CELL)
				if over then UiColor(0.45, 0.68, 0.85, 1) else UiColor(0.28, 0.31, 0.34, 1) end
				UiRectOutline(CELL, CELL, over and 2 or 1)
				drawItem({id = e.id, n = 1}, can and 1 or 0.35)
				UiTranslate(CELL / 2, CELL + 10)
				UiAlign("center middle")
				UiFont("bold.ttf", 16)
				if can then UiColor(1, 0.85, 0.35, 1) else UiColor(1, 0.4, 0.35, 1) end
				if not myMoney or e.price == 0 then
					UiText("FREE")
				else
					drawGold(e.price, 16, "center", can and {1, 0.85, 0.35} or {1, 0.4, 0.35})
				end
				UiPop()
				if over then buy = e end
			end
		end
		-- something in the hand: the store's column is where it is sold
		local offer = drag and sellOffer(drag)
		if drag and myMoney then
			UiPush()
			UiTranslate(sx - 8, top - 8)
			local zw, zh = storeW + 16, CAT_H + storeRows * (step + 22) + 8
			if not padMode then overSell = UiIsMouseInRect(zw, zh) else overSell = buy ~= nil end
			UiColor(0.03, 0.04, 0.05, 0.88)
			UiRect(zw, zh)
			if offer then UiColor(1, 0.85, 0.35, overSell and 1 or 0.6) else UiColor(1, 1, 1, 0.3) end
			UiRectOutline(zw, zh, overSell and 3 or 2)
			UiTranslate(zw / 2, zh / 2 - 16)
			UiAlign("center middle")
			UiFont("bold.ttf", 30)
			UiText(offer and "SELL" or "NOT BOUGHT")
			if offer then
				UiTranslate(0, 38)
				drawGold(offer, 26, "center")
			end
			UiPop()
			if not offer then overSell = false end
		end
		-- pages
		UiPush()
		UiTranslate(sx, ctop + storeRows * (step + 22) + 6)
		UiFont("bold.ttf", 22)
		local function pageButton(x, label, to)
			UiPush()
			UiTranslate(x, 0)
			local over = UiIsMouseInRect(44, 34)
			UiColor(1, 1, 1, over and 1 or 0.55)
			UiRoundedRectOutline(44, 34, 6, 2)
			UiTranslate(22, 17)
			UiAlign("center middle")
			UiText(label)
			UiPop()
			if over and InputPressed("lmb") and not drag then storePage = math.max(1, math.min(pages, to)) end
		end
		if pages > 1 then
			pageButton(0, "<", storePage - 1)
			pageButton(storeW - 44, ">", storePage + 1)
		end
		UiTranslate(storeW / 2, 17)
		UiAlign("center middle")
		UiColor(1, 1, 1, 0.6)
		UiText(storePage .. " / " .. pages)
		UiPop()
	end

	-- the item under the mouse, the keys
	UiPush()
	UiTranslate(PAD, H - PAD - 8)
	UiFont("regular.ttf", 20)
	do
		UiColor(1, 1, 1, 0.45)
		if padMode then
			UiText(drag and "A: put here (on the store: sell)   X: drop it   B: put back" or "A: take / buy   X: wear / hotkey   B: close   bumpers: store, its pages")
		else
			UiText("Drag to move   Drag onto a hotkey, or 1-" .. C.HOTBAR .. " over an item: its hotkey   Right-click: wear / hotkey   Drag out: drop   Drag onto the store: sell   " .. string.upper(INV_KEY) .. ": close")
		end
	end
	UiPop()

	-- the tooltip: what the mouse (or the controller's focus) is on - its name and what it does
	local tipRef = GetString("inventory.test.hover")                  -- (autotests: a hover without a mouse)
	if tipRef ~= "" then
		if string.sub(tipRef, 1, 2) == "s:" then
			for _, e in ipairs(storeList) do
				if "s:" .. e.id == tipRef then buy = e end
			end
		else
			hover = tipRef
		end
	end
	if not drag then
		local tipIt, tipShop = hover and C.get(mine, hover), nil
		if buy then tipIt, tipShop = {id = buy.id, n = 1, ammo = C.defs[buy.id] and C.defs[buy.id].pack}, buy end
		if tipIt then
			local tx, ty
			if padMode or tipRef ~= "" then
				local key = tipShop and ("s:" .. tipShop.id) or hover
				for i = 1, #cells do
					if cells[i].key == key then tx, ty = cells[i].x + CELL + 8, cells[i].y end
				end
			else
				tx, ty = UiGetMousePos()
				tx, ty = tx + 18, ty + 14
			end
			if tx then drawTooltip(tipIt, tipShop, hover, tx, ty, W, H) end
		end
	end
	UiPop()

	-- what the player does with it: the mouse (drag and drop), or a controller (take with A, put with A)
	if not myKey then
		drag = nil                                                    -- (no key yet: nothing can be asked)
	elseif goldDrag or goldDialog then                               -- gold: dragged, then the slider (drawn and handled
		-- after the window, by invGoldUi: nothing else takes the mouse meanwhile)
	elseif padMode then
		if drag and not C.get(mine, drag) then drag = nil end
		if InputPressed("menu_accept") then
			if drag and overSell then
				ServerCall("server.invSell", me, myKey, drag)
				drag = nil
			elseif buy and not drag then
				ServerCall("server.invBuy", me, myKey, buy.id)
			elseif drag then
				if hover and hover ~= drag then ServerCall("server.invMove", me, myKey, drag, hover) end
				if hover == drag then invClick(me, drag, myKey) end     -- (taken and put back: a click)
				drag = nil
			elseif hover and C.get(mine, hover) then
				drag = hover
				invClick(me, hover, myKey)
			end
		elseif InputPressed("interact") then
			if drag then
				ServerCall("server.invDrop", me, myKey, drag)
				drag = nil
			elseif hover and C.get(mine, hover) then
				ServerCall("server.invQuick", me, myKey, hover)
			end
		elseif InputPressed("menu_cancel") then
			if drag then drag = nil else open = false end
		end
		-- the focus: to the nearest cell in the direction pressed
		local cur = nil
		for i = 1, #cells do
			if cells[i].key == focus then cur = cells[i] end
		end
		if not cur then
			cur = cells[1]
			if cur then focus = cur.key end
		end
		local dx, dy = 0, 0
		if InputPressed("menu_left") then dx = -1
		elseif InputPressed("menu_right") then dx = 1
		elseif InputPressed("menu_up") then dy = -1
		elseif InputPressed("menu_down") then dy = 1 end
		if cur and (dx ~= 0 or dy ~= 0) then
			local best, bestD = nil, 1e9
			for i = 1, #cells do
				local c = cells[i]
				local along = (c.x - cur.x) * dx + (c.y - cur.y) * dy
				local across = math.abs(c.x - cur.x) * math.abs(dy) + math.abs(c.y - cur.y) * math.abs(dx)
				if along > 1 and along + 3 * across < bestD then best, bestD = c, along + 3 * across end
			end
			if best then focus = best.key end
		end
	elseif not drag then
		if buy and InputPressed("lmb") then
			ServerCall("server.invBuy", me, myKey, buy.id)
		elseif hover and C.get(mine, hover) then
			if InputPressed("lmb") then
				drag = hover
				dragT, dragX, dragY = GetTime(), UiGetMousePos()
			elseif InputPressed("rmb") then
				ServerCall("server.invQuick", me, myKey, hover)
			else
				for k = 1, C.HOTBAR do                               -- a number key: the item under the mouse to that hotkey
					if InputPressed(tostring(k)) and hover ~= "h:" .. k then ServerCall("server.invMove", me, myKey, hover, "h:" .. k) end
				end
			end
		end
	else
		local it = C.get(mine, drag)
		if not it then
			drag = nil
		else
			local mx, my = UiGetMousePos()
			UiPush()
			UiTranslate(mx - CELL / 2, my - CELL / 2)
			UiAlign("left top")
			drawItem(it, 0.85)
			UiPop()
			if not InputDown("lmb") then
				if hover == drag and math.abs(mx - dragX) + math.abs(my - dragY) < 10 then invClick(me, drag, myKey) end   -- (a click)
				if overSell then
					ServerCall("server.invSell", me, myKey, drag)
				elseif hover and hover ~= drag then
					ServerCall("server.invMove", me, myKey, drag, hover)
				elseif not inPanel then
					ServerCall("server.invDrop", me, myKey, drag)
				end
				drag = nil
			end
		end
	end
end

-- the gold changes rising from the bottom right corner's gold and fading out (over the screen too: on top)
local function drawMoneyFloats()
	local now = GetTime()
	local keep = {}
	for _, f in ipairs(moneyFloats) do
		local age = now - f.t
		if age < INV_FLOAT_TIME then
			keep[#keep + 1] = f
			UiPush()
			UiTranslate(UiWidth() - 36, UiHeight() - 36 - 54 - 30 - age * 50)
			UiAlign("right middle")
			UiFont("bold.ttf", 28)
			local a = 1 - age / INV_FLOAT_TIME                       -- (fading from the start: the user)
			if f.d > 0 then UiColor(0.35, 1, 0.4, a) else UiColor(1, 0.35, 0.3, a) end
			UiTextOutline(0, 0, 0, 0.8 * a, 0.2)
			UiText((f.d > 0 and "+" or "-") .. invGold(math.abs(f.d)))
			UiPop()
		end
	end
	moneyFloats = keep
end

function Inv.clientDraw()
	if GetBool("inventory.test.golddialog") and not goldDialog and myMoney and myMoney > 0 then   -- (autotests)
		goldDialog = {n = math.floor(myMoney / 2)}
	end
	invDrawMain()
	if not invBlocked(GetLocalPlayer()) then drawMoneyFloats() end      -- (after the window: on top)
	if (goldDrag or goldDialog) and not invBlocked(GetLocalPlayer()) then
		UiPush()
		invGoldUi(GetLocalPlayer())                                   -- (after the window: on top, screen coordinates)
		UiPop()
	end
end
