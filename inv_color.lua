-- Item colours for other mods (the user, 2026-11-14: "I need the villager mod to be able to see the colors of the
-- items"). Included by main.lua after inv.lua; globals only (InvColor). The host works out every known item's colours
-- once and writes them (synced) under
--   inventory.colors.<id>.name      the main colour, one word: black grey white red pink orange brown beige yellow
--                                   olive green cyan blue purple gold (orange or yellow metal)
--   inventory.colors.<id>.text      how a person would say it: "red", "red and grey", "red, grey and black"
--   inventory.colors.<id>.rgb       the main colour "r g b" (0..1)
--   inventory.colors.<id>.list      the colours with their share of the surface: "red:0.62 grey:0.30"
--   inventory.colors.<id>.material  what most of it is made of (the game's material: metal, wood, plastic, ...)
--   inventory.colors.<id>.tinted    true: mostly in the owner's player colour (the game's tint palette)
--   inventory.colors.<id>.source    written last: "mod" (the item's mod said), "model" (read off its model),
--                                   "none" (no model to read: the other keys are empty)
-- An item's own mod can say instead: inventory.items.<id>.color (or .tools. / .clothing. / .weapons.) = "r g b" or
-- words ("red", "red and grey"); that wins, also when it comes later.
-- Read off the model: a tool's world model (SpawnTool), else the item's drop model (.drop), spawned out of sight
-- (a shape's voxels can read empty in its spawn frame: read from the next tick on, a few thousand cells a tick); the
-- colours of its OUTER voxels, each counted by its face area. A gun of grey metal with a red grip is "grey and red":
-- the list keeps the smaller colours.

InvColor = {}

local C = InvCore
local AWAY = Vec(0, 700, 0)           -- where models are spawned to be read (toolScale uses 500)
local MAXCELLS = 40000                -- cells read per shape at most (bigger shapes are read on a coarser grid)
local BUDGET = 3000                   -- cells read per tick
local MINSHARE = 0.08                 -- a colour with less of the surface is left out of .list / .text

-- a reference colour per word (a mod that gives only words gets this .rgb)
local RGB = {black = {0.08, 0.08, 0.08}, grey = {0.5, 0.5, 0.5}, white = {0.92, 0.92, 0.92}, red = {0.75, 0.12, 0.1},
	pink = {0.92, 0.55, 0.7}, orange = {0.92, 0.5, 0.12}, brown = {0.45, 0.28, 0.15}, beige = {0.8, 0.7, 0.52},
	yellow = {0.92, 0.82, 0.2}, olive = {0.45, 0.45, 0.15}, green = {0.2, 0.6, 0.2}, cyan = {0.2, 0.7, 0.75},
	blue = {0.15, 0.3, 0.8}, purple = {0.5, 0.2, 0.65}, gold = {0.85, 0.65, 0.2}}
local METAL = {metal = true, heavymetal = true, hardmetal = true}
local WORDS = {gray = "grey", violet = "purple", tan = "beige", golden = "gold", silver = "grey",
	navy = "blue", maroon = "red", teal = "cyan", magenta = "pink", khaki = "beige"}

-- r, g, b (0..1) -> a colour word
function InvColor.word(r, g, b)
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local v, c = mx, mx - mn
	local s = mx > 0 and c / mx or 0
	if v < 0.16 then return "black" end
	if s < 0.2 or c < 0.07 then
		if v > 0.8 then return "white" end
		if v < 0.28 then return "black" end
		return "grey"
	end
	local h
	if mx == r then
		h = 60 * (((g - b) / c) % 6)
	elseif mx == g then
		h = 60 * ((b - r) / c + 2)
	else
		h = 60 * ((r - g) / c + 4)
	end
	if h < 15 or h >= 340 then
		if s < 0.5 and v > 0.7 then return "pink" end
		return "red"
	elseif h < 45 then
		if s < 0.45 and v > 0.6 then return "beige" end
		if v < 0.62 then return "brown" end
		return "orange"
	elseif h < 70 then
		if v < 0.55 then return "olive" end
		return "yellow"
	elseif h < 165 then
		return "green"
	elseif h < 195 then
		return "cyan"
	elseif h < 255 then
		return "blue"
	elseif h < 290 then
		return "purple"
	end
	return "pink"
end

-- the names in share order -> "red", "red and grey", "red, grey and black"
local function sayList(names)
	if #names <= 1 then return names[1] or "" end
	if #names == 2 then return names[1] .. " and " .. names[2] end
	return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

function InvColor.newTally()
	return {words = {}, mats = {}, tint = 0, total = 0}
end

-- one outer voxel into a tally
function InvColor.add(t, mat, r, g, b, e, area)
	local w = InvColor.word(r, g, b)
	if (w == "orange" or w == "yellow") and METAL[mat] then w = "gold" end   -- (the gold bar read "orange" in game)
	local bk = t.words[w]
	if not bk then
		bk = {w = 0, r = 0, g = 0, b = 0}
		t.words[w] = bk
	end
	bk.w, bk.r, bk.g, bk.b = bk.w + area, bk.r + r * area, bk.g + g * area, bk.b + b * area
	if mat and mat ~= "" then t.mats[mat] = (t.mats[mat] or 0) + area end
	if e >= 241 and e <= 248 then t.tint = t.tint + area end
	t.total = t.total + area
end

-- a tally -> the keys' values {name, text, rgb, list, material, tinted} (nil: nothing counted)
function InvColor.summarize(t)
	if not t or (t.total or 0) <= 0 then return nil end
	local all = {}
	for w, b in pairs(t.words) do all[#all + 1] = {w = w, share = b.w / t.total, b = b} end
	table.sort(all, function(a, b) return a.share > b.share or (a.share == b.share and a.w < b.w) end)
	local names, list = {}, {}
	for i, e in ipairs(all) do
		if i == 1 or (e.share >= MINSHARE and #names < 3) then
			names[#names + 1] = e.w
			list[#list + 1] = string.format("%s:%.2f", e.w, e.share)
		end
	end
	if all[1].share >= 0.75 then names = {names[1]} end              -- (mostly one colour: say just that)
	local top = all[1].b
	local mat, mw = "", 0
	for m, w in pairs(t.mats) do
		if w > mw or (w == mw and m < mat) then mat, mw = m, w end
	end
	return {name = all[1].w, text = sayList(names),
		rgb = string.format("%.2f %.2f %.2f", top.r / top.w, top.g / top.w, top.b / top.w),
		list = table.concat(list, " "), material = mat, tinted = t.tint / t.total > 0.3}
end

-- a mod's own words or "r g b" -> the same values (nil: nothing usable)
function InvColor.parse(s)
	s = string.lower(s or "")
	local r, g, b = string.match(s, "^%s*([%d%.]+)[%s,]+([%d%.]+)[%s,]+([%d%.]+)%s*$")
	r, g, b = tonumber(r), tonumber(g), tonumber(b)
	if r and g and b then
		if r > 1 or g > 1 or b > 1 then r, g, b = r / 255, g / 255, b / 255 end
		local w = InvColor.word(r, g, b)
		return {name = w, text = w, rgb = string.format("%.2f %.2f %.2f", r, g, b), list = w .. ":1.00", material = ""}
	end
	local names, seen = {}, {}
	for word in string.gmatch(s, "%a+") do
		word = WORDS[word] or word
		if RGB[word] and not seen[word] then
			seen[word] = true
			names[#names + 1] = word
		end
	end
	if #names == 0 then return nil end
	local list = {}
	for i, w in ipairs(names) do list[i] = string.format("%s:%.2f", w, 1 / #names) end
	local c = RGB[names[1]]
	return {name = names[1], text = sayList(names), rgb = string.format("%.2f %.2f %.2f", c[1], c[2], c[3]),
		list = table.concat(list, " "), material = ""}
end

----- reading a shape, a slice at a time -----

-- a reader of one shape's outer voxels (on a coarser grid when the shape is big)
function InvColor.reader(sh)
	local sx, sy, sz, vs = GetShapeSize(sh)
	if not sx or sx <= 0 or sy <= 0 or sz <= 0 then return nil end
	vs = (vs and vs > 0) and vs or 0.1
	local step = math.max(1, math.ceil((sx * sy * sz / MAXCELLS) ^ (1 / 3)))
	return {sh = sh, step = step, area = (vs * step) * (vs * step), xi = 0,
		nx = math.ceil(sx / step), ny = math.ceil(sy / step), nz = math.ceil(sz / step)}
end

local function readSlice(j, xi)
	if xi < 0 or xi >= j.nx then return nil end
	local s = {e = {}, m = {}, r = {}, g = {}, b = {}}
	for yi = 0, j.ny - 1 do
		for zi = 0, j.nz - 1 do
			local mat, r, g, b, _, e = GetShapeMaterialAtIndex(j.sh, xi * j.step, yi * j.step, zi * j.step)
			local i = yi * j.nz + zi + 1
			s.e[i] = e or 0
			if e and e ~= 0 then s.m[i], s.r[i], s.g[i], s.b[i] = mat, r, g, b end
		end
	end
	return s
end

-- read on until about `budget` cells are read -> cells read, true when the shape is done
function InvColor.readSome(j, t, budget)
	local used = 0
	local per = j.ny * j.nz
	while j.xi < j.nx and used < budget do
		local cur = j.nxt or readSlice(j, j.xi)
		local nxt = readSlice(j, j.xi + 1)
		used = used + per * (j.nxt and 1 or 2)
		local prev, ny, nz = j.prev, j.ny, j.nz
		for yi = 0, ny - 1 do
			for zi = 0, nz - 1 do
				local i = yi * nz + zi + 1
				local e = cur.e[i]
				if e ~= 0 and e ~= 255 then
					local outer = not prev or prev.e[i] == 0 or not nxt or nxt.e[i] == 0
						or yi == 0 or yi == ny - 1 or zi == 0 or zi == nz - 1
						or cur.e[i - nz] == 0 or cur.e[i + nz] == 0 or cur.e[i - 1] == 0 or cur.e[i + 1] == 0
					if outer then InvColor.add(t, cur.m[i], cur.r[i], cur.g[i], cur.b[i], e, j.area) end
				end
			end
		end
		j.prev, j.nxt, j.xi = cur, nxt, j.xi + 1
	end
	return used, j.xi >= j.nx
end

----- the host's queue -----

local done = {}           -- id -> the source written ("mod" / "model" / "none")
local busy = nil          -- {id, ents, shapes, k (the shape being read), job, t, ticks}: a model spawned away
local scanT = 0

local function write(id, v, source)
	local k = "inventory.colors." .. id
	ClearKey(k)
	if v then
		SetString(k .. ".name", v.name, true)
		SetString(k .. ".text", v.text, true)
		SetString(k .. ".rgb", v.rgb, true)
		SetString(k .. ".list", v.list, true)
		SetString(k .. ".material", v.material or "", true)
		SetBool(k .. ".tinted", v.tinted and true or false, true)
	end
	SetString(k .. ".source", source, true)                          -- (last: readers may wait for this)
	done[id] = source
end

local function modColor(id)
	for _, ns in ipairs({"items", "tools", "clothing", "weapons"}) do
		local key = "inventory." .. ns .. "." .. id .. ".color"
		if HasKey(key) then
			local v = InvColor.parse(GetString(key))
			if v then return v end
		end
	end
	return nil
end

local function close(v)
	for _, e in ipairs(busy.ents) do
		if IsHandleValid(e) then Delete(e) end
	end
	if not done[busy.id] then write(busy.id, v, v and "model" or "none") end
	busy = nil
end

-- a tick's reading; the spawn frame itself is skipped (its voxels can read empty)
local function step()
	busy.ticks = busy.ticks + 1
	if busy.ticks < 2 then return end
	local left = BUDGET
	while left > 0 do
		if not busy.job then
			local sh = busy.shapes[busy.k]
			if not sh then                                              -- every shape read
				if busy.t.total <= 0 and busy.ticks < 5 then             -- (nothing readable yet: again, later)
					busy.k, busy.t = 1, InvColor.newTally()
					return
				end
				close(InvColor.summarize(busy.t))
				return
			end
			busy.k = busy.k + 1
			busy.job = IsHandleValid(sh) and InvColor.reader(sh) or nil
		end
		if busy.job then
			local used, fin = InvColor.readSome(busy.job, busy.t, left)
			left = left - math.max(1, used)
			if fin then busy.job = nil end
		end
	end
end

local function start(id, def)
	local ents
	local model = def.kind == "tool" and def.tool or def.model          -- (a consumable with a game tool's model: BlueTide)
	if model then ents = SpawnTool(model, Transform(AWAY)) end
	if (not ents or #ents == 0) and def.drop and def.drop ~= "" then
		ents = Spawn("<body><vox file='" .. def.drop .. "'/></body>", Transform(AWAY))
	end
	if not ents or #ents == 0 then
		write(id, nil, "none")
		return
	end
	-- (the shapes of every spawned body: a tool can be several)
	local shapes, seen = {}, {}
	local function addShape(sh)
		if not seen[sh] then
			seen[sh] = true
			shapes[#shapes + 1] = sh
		end
	end
	for _, e in ipairs(ents) do
		local ty = GetEntityType(e)
		if ty == "body" then
			SetBodyDynamic(e, false)
			for _, sh in ipairs(GetBodyShapes(e)) do addShape(sh) end
		elseif ty == "shape" then
			addShape(e)
		end
	end
	busy = {id = id, ents = ents, shapes = shapes, k = 1, t = InvColor.newTally(), ticks = 0}
end

function InvColor.serverInit()
	ClearKey("inventory.colors")
	done, busy, scanT = {}, nil, 0
end

-- one model at a time; the mods' own colours looked at every 2 s
function InvColor.serverTick(dt)
	scanT = scanT - dt
	if scanT <= 0 then
		scanT = 2
		for id in pairs(C.defs) do
			if done[id] ~= "mod" then
				local v = modColor(id)
				if v then write(id, v, "mod") end
			end
		end
	end
	if busy then
		step()
		return
	end
	for id, def in pairs(C.defs) do
		if not done[id] then
			start(id, def)
			return
		end
	end
end
