-- Gold lying around the map (the user, 2026-11-16: "random amounts of money (1 to 20 - where min and max amount
-- are configurable) are randomly spread out across the map for players to pick up? the total amount should be
-- capped (500 - configurable) and they should respawn after some time. Lets have this on by default").
-- Host only. Piles of a random amount (min..max) on floors with headroom anywhere inside the map's boundary (indoor
-- floors too: each vertical line is followed down through every floor), until the gold lying out reaches the cap.
-- A pile picked up frees its amount again after the respawn time; a pile nobody took for MOVE_AFTER seconds is put
-- somewhere else (one on a roof nobody reaches would block its share of the cap for good).
-- Settings (the host's mod options, savegame.mod.*): scatter (on unless false), scattermin 1, scattermax 20,
-- scattercap 300 (500 at first; the user 2026-11-16: 300), scatterrespawn 60 (s). A game mode switches it off with inventory.scatter = false (its piles go).

InvScatter = {}

local MOVE_AFTER = 600          -- s a pile may lie before it moves elsewhere
local PER_STEP = 4              -- piles spawned at most per step (0.25 s): the first fill of 300 takes ~2 s
local TRIES = 10                -- vertical lines tried per pile
local pieces = {}               -- body -> {n = gold, t = when it was put}
local waits = {}                -- {t = when the amount is free again, n = gold}
local lying = 0                 -- gold in pieces
local stepT = 0
-- (tests) vertical lines tried, piles that found no floor, and why hits were no floor
local stats = {lines = 0, misses = 0, out = 0, nohit = 0, hits = 0, leaf = 0, dyn = 0, slope = 0, room = 0, water = 0}
function InvScatter.stats() return stats end
local NOT_FLOOR = {foliage = true, glass = true}   -- (hedges, tree tops, windows: on through, to the floor below)

function InvScatter.settings()
	if HasKey("inventory.scatter") and not GetBool("inventory.scatter") then return nil end
	if HasKey("savegame.mod.scatter") and not GetBool("savegame.mod.scatter") then return nil end
	local function int(k, def, lo, hi)
		local v = HasKey("savegame.mod." .. k) and GetInt("savegame.mod." .. k) or def
		return math.max(lo, math.min(hi, v))
	end
	local mn, mx = int("scattermin", 1, 1, 1000), int("scattermax", 20, 1, 1000)
	if mn > mx then mn, mx = mx, mn end
	return {min = mn, max = mx, cap = int("scattercap", 300, 0, 100000), respawn = int("scatterrespawn", 60, 0, 3600)}
end

-- a floor somewhere on the map: a random vertical line, every floor on it with 1.9 m of room above, one of them
-- the map's box: x / z from the boundary, the heights from the world (a boundary's own heights can miss the ground:
-- 807 of 956 lines hit nothing on the sandbox map, 2026-11-16)
function InvScatter.box()
	local lo, hi = GetBoundaryBounds()
	if not lo or not hi then return nil end
	local w = GetWorldBody()
	if w and w ~= 0 then
		local wlo, whi = GetBodyBounds(w)
		lo, hi = Vec(lo[1], math.min(lo[2], wlo[2]), lo[3]), Vec(hi[1], math.max(hi[2], whi[2]), hi[3])
	end
	return lo, hi
end

local function spot()
	local lo, hi = InvScatter.box()
	if not lo or not hi then return nil end
	for _ = 1, TRIES do
		stats.lines = stats.lines + 1
		local x = lo[1] + math.random() * (hi[1] - lo[1])
		local z = lo[3] + math.random() * (hi[3] - lo[3])
		local y, above = hi[2] + 2, math.huge
		local found = {}
		if not IsPointInBoundaries(Vec(x, lo[2], z)) then           -- (outside the play area: another line)
			stats.out = stats.out + 1
		else
			for _ = 1, 30 do                                    -- (floors, and steps through foliage)
				local hit, dist, normal, shape = QueryRaycast(Vec(x, y, z), Vec(0, -1, 0), y - lo[2] + 1)
				if not hit then stats.nohit = stats.nohit + 1 break end
				local fy = y - dist
				if dist > 0.05 then                              -- (a start inside a floor: step on through it)
					stats.hits = stats.hits + 1
					local body = shape and shape ~= 0 and GetShapeBody(shape) or 0
					local at = Vec(x, fy, z)
					local mat = body ~= 0 and GetShapeMaterialAtPosition(shape, VecAdd(at, Vec(0, -0.05, 0))) or ""
					local why = nil
					if NOT_FLOOR[mat] then why = "leaf"                  -- (no floor, but no room under it either: no
					elseif body == 0 or IsBodyDynamic(body) then why = "dyn"   --  coins hidden in a hedge)
					elseif not normal or normal[2] < 0.75 then why = "slope"
					elseif above - fy < 1.9 then why = "room"
					elseif IsPointInWater(VecAdd(at, Vec(0, 0.3, 0))) then why = "water" end
					if why then stats[why] = stats[why] + 1 else found[#found + 1] = at end
					above = fy
				end
				y = fy - 0.3
				if y < lo[2] then break end
			end
		end
		if #found > 0 then return found[math.random(1, #found)] end
	end
	stats.misses = stats.misses + 1
	return nil
end

-- (host, every tick) spawn(n, transform) -> body, gone(body) -> picked up or lost, remove(body)
function InvScatter.serverTick(dt, spawn, gone, remove)
	stepT = stepT - dt
	if stepT > 0 then return end
	stepT = 0.25
	local s = InvScatter.settings()
	local now = GetTime()
	if not s then                                                -- off (the options, or a game mode): the piles go
		for b in pairs(pieces) do remove(b) end
		pieces, waits, lying = {}, {}, 0
		return
	end
	for b, p in pairs(pieces) do
		if gone(b) then                                          -- taken (or lost): its amount comes back later
			pieces[b] = nil
			lying = lying - p.n
			waits[#waits + 1] = {t = now + s.respawn, n = p.n}
		elseif now - p.t > MOVE_AFTER then                       -- nobody came: somewhere else, at once
			remove(b)
			pieces[b] = nil
			lying = lying - p.n
		end
	end
	local held = 0
	for i = #waits, 1, -1 do
		if waits[i].t <= now then table.remove(waits, i) else held = held + waits[i].n end
	end
	for _ = 1, PER_STEP do
		local room = s.cap - lying - held
		if room < 1 then break end
		local n = math.min(room, math.random(s.min, s.max))
		local at = spot()
		local b = at and spawn(n, Transform(VecAdd(at, Vec(0, 0.12, 0)), QuatEuler(0, math.random() * 360, 0)))
		if b and b ~= 0 then
			pieces[b] = {n = n, t = now}
			lying = lying + n
		end
	end
end

-- (tests) the gold lying out now and held back for respawns
function InvScatter.state()
	local held = 0
	for _, w in ipairs(waits) do held = held + w.n end
	local count = 0
	for _ in pairs(pieces) do count = count + 1 end
	return lying, held, count, stats.lines, stats.misses
end
