-- Inventory core: the pure model (no engine calls), included by main.lua and run as is by tools/lua/test_core.lua.
-- An inventory: {g = grid cells, h = hotkey slots, e = equipment by slot id}; a grid cell or an equipment slot holds
-- one instance {id = item id, n = count, ammo = a tool's ammo (nil: a tool that needs none)} or nil. One cell per
-- item. A hotkey slot holds no item: it is a POINTER, the number of the grid cell whose item it uses (a tool or a
-- consumable; one slot per item at most). The item stays in the grid; a pointer follows its item when that moves
-- within the grid and goes when the item leaves the grid. Places are named by a ref string: "g:12" (grid cell),
-- "h:3" (hotkey slot), "e:head" (equipment slot).
-- Interface: the global table InvCore (an included file's locals are invisible to the includer).

InvCore = {}
local C = InvCore

C.GRID = 42                                                  -- 7 x 6
C.COLS = 7
C.HOTBAR = 9                                                 -- hotkey slots 1-9: the tools they point at are the game's wheel
C.SLOTS = {"head", "top", "back", "legs", "feet"}            -- head, upper body, back (backpacks and other back-carried
                                                             -- gear: the user, 2026-11-21), lower body, feet; addSlot for a mod's own
C.defs = {}

-- an equipment slot a clothing mod brings (Wardrobe's slots are free strings)
function C.addSlot(name)
	for i = 1, #C.SLOTS do
		if C.SLOTS[i] == name then return end
	end
	C.SLOTS[#C.SLOTS + 1] = name
end

-- def: {id, kind = "tool" | "clothing" | "consumable" | "misc", name, stack = max per cell (1), slot = equipment
-- slot (clothing), tool = the game's tool id (tools), and what clothing does to its wearer:
-- armor = 0..1, the share of a hit it blocks (defence); mobility = added to the walking speed and jump height as a share (-0.1: 10 %
-- slower); noise = added to the noise the wearer makes as a share (-0.3: 30 % quieter, 0.2: 20 % louder); swim = added
-- to the swimming speed as a share (+0.5: flippers, 50 % faster in water)}
function C.define(def)
	def.stack = def.stack or 1
	def.kind = def.kind or "misc"
	C.defs[def.id] = def
	return def
end

function C.new()
	return {g = {}, h = {}, e = {}}
end

local function isSlot(name)
	for i = 1, #C.SLOTS do
		if C.SLOTS[i] == name then return true end
	end
	return false
end

-- ref -> the area table and its key, or nil for a ref that names no place
function C.place(inv, ref)
	if type(ref) ~= "string" then return nil end
	local a, k = string.match(ref, "^(%a):(.+)$")
	if a == "g" or a == "h" then
		local i = tonumber(k)
		local max = (a == "g") and C.GRID or C.HOTBAR
		if not i or i < 1 or i > max or i ~= math.floor(i) then return nil end
		return inv[a], i
	elseif a == "e" and isSlot(k) then
		return inv.e, k
	end
	return nil
end

-- the hotkey slot that points at grid cell n, or nil
function C.slotOf(inv, n)
	for k = 1, C.HOTBAR do
		if inv.h[k] == n then return k end
	end
	return nil
end

-- a hotkey ref -> the ref of the grid cell it points at (nil: an empty slot); other refs as they are
function C.resolve(inv, ref)
	local t, k = C.place(inv, ref)
	if not t then return nil end
	if t ~= inv.h then return ref end
	if t[k] and inv.g[t[k]] then return "g:" .. t[k] end
	return nil
end

-- the instance at a place (a hotkey slot: the item it points at)
function C.get(inv, ref)
	local t, k = C.place(inv, ref)
	if not t then return nil end
	if t == inv.h then return t[k] and inv.g[t[k]] or nil end
	return t[k]
end

-- may this instance lie at (a hotkey: be pointed at from) ref?
function C.accepts(ref, it)
	if it == nil then return true end
	local def = C.defs[it.id]
	if not def then return false end
	local a, k = string.match(ref, "^(%a):(.+)$")
	if a == "g" then return true end
	if a == "h" then return def.kind == "tool" or def.kind == "consumable" end
	if a == "e" then return def.kind == "clothing" and def.slot == k end
	return false
end

local function firstFree(t, max)
	for i = 1, max do
		if t[i] == nil then return i end
	end
	return nil
end

-- pointers whose item is gone, or is no hotkey item, are dropped
function C.fix(inv)
	for k = 1, C.HOTBAR do
		local it = inv.h[k] and inv.g[inv.h[k]]
		local def = it and C.defs[it.id]
		if inv.h[k] and not (def and (def.kind == "tool" or def.kind == "consumable")) then inv.h[k] = nil end
	end
end

-- where a tool of this id already lies (one ammo count per tool id per player in the game: never two of one tool)
function C.findTool(inv, id)
	for i = 1, C.GRID do
		if inv.g[i] and inv.g[i].id == id then return "g:" .. i end
	end
	return nil
end

-- Pick up n of an item (a tool with its ammo; ammo nil: a tool that needs none). Returns how many did not fit
-- (0 = all taken).
-- Tools: a second one of the same tool adds its ammo to the first; else a grid cell, and the first free hotkey
-- points at it.
-- Clothing: worn at once when its slot is empty (not with noWear: a purchase, the user 2026-11-15 "don't auto equip
-- items when bought"), else into the grid. Stackables fill their stacks first.
function C.add(inv, id, n, ammo, noWear)
	local def = C.defs[id]
	n = n or 1
	if not def or n < 1 then return n end
	if def.kind == "tool" then
		local at = C.findTool(inv, id)
		if at then
			local it = C.get(inv, at)
			if ammo then it.ammo = (it.ammo or 0) + ammo end
			return 0
		end
		local i = firstFree(inv.g, C.GRID)
		if not i then return n end
		if def.takes then                                            -- a gun: its loaded rounds (0: empty, never "unlimited")
			inv.g[i] = {id = id, n = 1, ammo = ammo or 0, load = (ammo or 0) > 0 and def.takes[1] or nil}
		else
			inv.g[i] = {id = id, n = 1, ammo = ammo}
		end
		local k = firstFree(inv.h, C.HOTBAR)
		if k then inv.h[k] = i end
		return 0
	end
	if not noWear and def.kind == "clothing" and def.slot and inv.e[def.slot] == nil and isSlot(def.slot) then
		inv.e[def.slot] = {id = id, n = 1}
		n = n - 1
	end
	if def.stack > 1 then
		for i = 1, C.GRID do
			local it = inv.g[i]
			if n > 0 and it and it.id == id and it.n < def.stack then
				local put = math.min(n, def.stack - it.n)
				it.n = it.n + put
				n = n - put
			end
		end
	end
	while n > 0 do
		local i = firstFree(inv.g, C.GRID)
		if not i then break end
		local put = math.min(n, def.stack)
		inv.g[i] = {id = id, n = put}
		n = n - put
	end
	return n
end

-- Drag from one place to another. Grid and equipment: onto an empty place, onto a stack of the same item (merge),
-- or swap. A grid item onto a hotkey slot: that slot points at it (its old slot is freed). Hotkey onto hotkey: the
-- two swap. A hotkey slot onto anything else: the slot is emptied (the item stays where it is).
-- Returns true when something changed.
function C.move(inv, from, to)
	local ft, fk = C.place(inv, from)
	local tt, tk = C.place(inv, to)
	if not ft or not tt or from == to then return false end
	if ft == inv.h then
		if ft[fk] == nil then return false end
		if tt == inv.h then ft[fk], tt[tk] = tt[tk], ft[fk] else ft[fk] = nil end
		return true
	end
	local a, b = ft[fk], tt[tk]
	if a == nil then return false end
	if tt == inv.h then
		if ft ~= inv.g or not C.accepts(to, a) then return false end
		local old = C.slotOf(inv, fk)
		if old then inv.h[old] = nil end
		inv.h[tk] = fk
		return true
	end
	if not C.accepts(to, a) or not C.accepts(from, b) then return false end
	local def = C.defs[a.id]
	if b and b.id == a.id and def.stack > 1 then
		local put = math.min(a.n, def.stack - b.n)
		if put <= 0 then return false end
		b.n = b.n + put
		a.n = a.n - put
		if a.n == 0 then
			ft[fk] = nil
			local k = ft == inv.g and C.slotOf(inv, fk)             -- (an emptied stack's hotkey goes to the other stack)
			if k then inv.h[k] = (tt == inv.g and not C.slotOf(inv, tk)) and tk or nil end
		end
		return true
	end
	ft[fk], tt[tk] = b, a
	if ft == inv.g and tt == inv.g then                            -- (pointers follow their items)
		local ka, kb = C.slotOf(inv, fk), C.slotOf(inv, tk)
		if ka then inv.h[ka] = tk end
		if kb then inv.h[kb] = fk end
	end
	C.fix(inv)
	return true
end

-- The right-click move: from the grid, clothing goes on (swapping with what is worn), a tool or consumable gets the
-- first free hotkey (or loses the one it has); a hotkey slot is emptied; equipment goes back into the first free
-- grid cell.
function C.quick(inv, ref)
	local it = C.get(inv, ref)
	local def = it and C.defs[it.id]
	if not def then return false end
	local a = string.sub(ref, 1, 1)
	if a == "h" then return C.move(inv, ref, "g:1") end
	if a == "e" then
		local i = firstFree(inv.g, C.GRID)
		return i ~= nil and C.move(inv, ref, "g:" .. i)
	end
	if def.kind == "clothing" and def.slot then return C.move(inv, ref, "e:" .. def.slot) end
	if def.kind == "tool" or def.kind == "consumable" then
		local _, n = C.place(inv, ref)
		local k = C.slotOf(inv, n)
		if k then
			inv.h[k] = nil
			return true
		end
		k = firstFree(inv.h, C.HOTBAR)
		return k ~= nil and C.move(inv, ref, "h:" .. k)
	end
	return false
end

-- Take n (default: all) out of a place (a hotkey slot: out of the cell it points at): the instance removed (to
-- drop into the world), or nil.
function C.take(inv, ref, n)
	ref = C.resolve(inv, ref)
	local t, k = C.place(inv, ref)
	if not t or t[k] == nil then return nil end
	local it = t[k]
	if n == nil or n >= it.n then
		t[k] = nil
		C.fix(inv)
		return it
	end
	if n < 1 then return nil end
	it.n = it.n - n
	return {id = it.id, n = n}
end

-- Take n (nil: all) of an item id out from wherever it lies (grid cells, then what is worn): how many went. For game
-- modes taking back what they gave (inventory.take); nothing is dropped.
function C.takeId(inv, id, n)
	local left = n or math.huge
	local took = 0
	for i = 1, C.GRID do
		local it = inv.g[i]
		if left > 0 and it and it.id == id then
			local k = math.min(left, it.n or 1)
			if k >= (it.n or 1) then inv.g[i] = nil else it.n = it.n - k end
			left, took = left - k, took + k
		end
	end
	for s = 1, #C.SLOTS do
		local it = inv.e[C.SLOTS[s]]
		if left > 0 and it and it.id == id then
			inv.e[C.SLOTS[s]] = nil
			left, took = left - 1, took + 1
		end
	end
	if took > 0 then C.fix(inv) end
	return took
end

-- Everything out (death): the list of instances; the inventory is empty after.
function C.takeAll(inv)
	local out = {}
	inv.h = {}
	for i = 1, #C.SLOTS do
		local s = C.SLOTS[i]
		if inv.e[s] then out[#out + 1] = inv.e[s] inv.e[s] = nil end
	end
	for i = 1, C.GRID do
		if inv.g[i] then out[#out + 1] = inv.g[i] inv.g[i] = nil end
	end
	return out
end

-- The share of a hit that what is worn blocks (0..1): each piece blocks its own share of what the others let through.
-- own = true: without the clothing packs' pieces (def.engine: the wear engine counts those by itself).
function C.armor(inv, own)
	local through = 1
	for i = 1, #C.SLOTS do
		local it = inv.e[C.SLOTS[i]]
		local a = it and C.defs[it.id] and C.defs[it.id].armor or 0
		if own and a > 0 and C.defs[it.id].engine then a = 0 end
		through = through * (1 - math.max(0, math.min(1, a)))
	end
	return 1 - through
end

-- What is worn does to its wearer: {defense = 0..1 (C.armor), mobility = the factor of walking speed and jump height (0.3..2),
-- noise = the factor of the noise made (0..3), swim = the factor of swimming speed (0.3..3)}. own = true: without the
-- clothing packs' pieces (def.engine).
function C.stats(inv, own)
	local mobility, noise, swim = 1, 1, 1
	for i = 1, #C.SLOTS do
		local it = inv.e[C.SLOTS[i]]
		local def = it and C.defs[it.id]
		if def and not (own and def.engine) then
			mobility = mobility + (def.mobility or 0)
			noise = noise + (def.noise or 0)
			swim = swim + (def.swim or 0)
		end
	end
	return {defense = C.armor(inv, own), mobility = math.max(0.3, math.min(2, mobility)), noise = math.max(0, math.min(3, noise)),
		swim = math.max(0.3, math.min(3, swim))}
end

-- game tool id -> the instance, for the tools the hotkeys point at (the ones the wheel shows)
function C.wheel(inv)
	local out = {}
	for i = 1, C.HOTBAR do
		local it = inv.h[i] and inv.g[inv.h[i]]
		local def = it and C.defs[it.id]
		if def and def.kind == "tool" and def.tool then out[def.tool] = it end
	end
	return out
end

-- a plain copy to publish (shared) or to compare
function C.copy(inv)
	local function area(t)
		local o = {}
		for k, it in pairs(t) do o[k] = {id = it.id, n = it.n, ammo = it.ammo, load = it.load} end
		return o
	end
	local h = {}
	for k, n in pairs(inv.h) do h[k] = n end
	return {g = area(inv.g), h = h, e = area(inv.e)}
end
