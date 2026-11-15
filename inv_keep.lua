-- Inventories and gold kept by player name (the user, 2026-11-15): through map and mode changes (the default, until
-- the host's "New session" button), or only within one map (the mod's Options: savegame.mod.keep = "map"); a player
-- who leaves keeps theirs for when they come back ("no don't reset leavers").
-- Why savegame.mod: a map change wipes every plain registry key and level.* (measured in game, Villa Gordon ->
-- Isla, tools/autotest/persist_probe.lua); savegame.mod survives, also a server restart (the disk), and no mod can see
-- when a server starts - hence the host's button. At most KEEP_MAX players (the least recently seen go first).
--   savegame.mod.keep            "" / "session": kept until the host resets; "map": a new map starts everyone empty
--   savegame.mod.saved.level     a counter of maps loaded (for "least recently seen")
--   savegame.mod.saved.p.<i>.name / .data / .gold / .seen
-- .data: "g:<cell>=<id>,<n>,<ammo>[,<loaded ammo id>];e:<slot>=...;h:<k>=<cell>" (ammo "" = none)

InvKeep = {}
KEEP_MAX = 24

local S = "savegame.mod.saved"
local entries = {}         -- name -> {data, gold, seen}
local names = {}           -- player -> name (kept: a player who left has none to ask)
local claimed = {}         -- player -> true once their entry was looked for
local lastSig = ""
local saveT = 0
local level = 0

function InvKeep.mode()
	return GetString("savegame.mod.keep") == "map" and "map" or "session"
end

local function enc(inv)
	local o = {}
	local function item(a, k, it)
		o[#o + 1] = a .. ":" .. k .. "=" .. it.id .. "," .. (it.n or 1) .. "," .. (it.ammo and string.format("%.4g", it.ammo) or "") ..
			(it.load and ("," .. it.load) or "")
	end
	for k, it in pairs(inv.g) do item("g", k, it) end
	for k, it in pairs(inv.e) do item("e", k, it) end
	for k, n in pairs(inv.h) do o[#o + 1] = "h:" .. k .. "=" .. n end
	table.sort(o)
	return table.concat(o, ";")
end

local function dec(s)
	local inv = {g = {}, h = {}, e = {}}
	for part in string.gmatch(s or "", "[^;]+") do
		local a, k, v = string.match(part, "^(%a):([^=]+)=(.*)$")
		if a == "h" then
			local kk, n = tonumber(k), tonumber(v)
			if kk and n then inv.h[kk] = n end
		elseif a == "g" or a == "e" then
			local id, n, ammo, load = string.match(v, "^([^,]+),([^,]*),([^,]*),?(.*)$")
			if id then
				local key = a == "g" and tonumber(k) or k
				if key then inv[a][key] = {id = id, n = tonumber(n) or 1, ammo = tonumber(ammo), load = load ~= "" and load or nil} end
			end
		end
	end
	return inv
end

local function load()
	entries = {}
	for _, i in ipairs(ListKeys(S .. ".p")) do
		local k = S .. ".p." .. i
		local name = GetString(k .. ".name")
		if name ~= "" then entries[name] = {data = GetString(k .. ".data"), gold = GetInt(k .. ".gold"), seen = GetInt(k .. ".seen")} end
	end
end

local function write()
	local list = {}
	for name, e in pairs(entries) do list[#list + 1] = {name = name, e = e} end
	table.sort(list, function(a, b) return a.e.seen > b.e.seen end)        -- (the most recently seen first)
	ClearKey(S .. ".p")
	for i = 1, math.min(#list, KEEP_MAX) do
		local k = S .. ".p." .. i
		SetString(k .. ".name", list[i].name)
		SetString(k .. ".data", list[i].e.data)
		SetInt(k .. ".gold", list[i].e.gold)
		SetInt(k .. ".seen", list[i].e.seen)
	end
	for i = KEEP_MAX + 1, #list do entries[list[i].name] = nil end
end

-- inventory.session (synced): changes whenever the kept inventories start over (NEW SESSION; with "Reset every map",
-- every map), so other mods can keep their own per-player things exactly as long (Humans vs Clickers' upgrades)
local function newSession()
	local n = GetInt(S .. ".session") + 1
	SetInt(S .. ".session", n)
	return n
end
local function publishSession()
	SetString("inventory.session", "s" .. math.max(1, GetInt(S .. ".session")), true)
end

function InvKeep.serverInit()
	level = GetInt(S .. ".level") + 1
	SetInt(S .. ".level", level)
	if InvKeep.mode() == "map" then                                        -- (a new map: everyone starts empty)
		ClearKey(S .. ".p")
		newSession()
	end
	if GetInt(S .. ".session") < 1 then newSession() end
	publishSession()
	SetString("inventory.keep", InvKeep.mode(), true)                     -- (the host's option, for other mods)
	load()
	names, claimed, lastSig, saveT = {}, {}, "", 0
	shared.invKeep = InvKeep.mode()
end

-- a player's saved inventory into a fresh one (when it is still empty: a give that came first keeps its place) ->
-- the gold to start with, or nil
function InvKeep.claim(p, inv)
	if claimed[p] then return nil end
	local name = GetPlayerName(p)
	if not name or name == "" then return nil end                         -- (not known yet: asked again next tick)
	claimed[p], names[p] = true, name
	local e = entries[name]
	if not e then return nil end
	local saved = dec(e.data)
	if next(inv.g) == nil and next(inv.e) == nil then
		inv.g, inv.h, inv.e = saved.g, saved.h, saved.e
	else
		for _, it in pairs(saved.g) do InvCore.add(inv, it.id, it.n, it.ammo) end
		for _, it in pairs(saved.e) do InvCore.add(inv, it.id, it.n, it.ammo) end
	end
	return e.gold
end

function InvKeep.claimed(p)
	return claimed[p] == true
end

-- every tick (throttled): the players here into the store when anything changed
function InvKeep.serverTick(dt, invs, goldOf)
	saveT = saveT - dt
	if saveT > 0 then return end
	saveT = 2
	local sig = {}
	for p, inv in pairs(invs) do
		if claimed[p] and names[p] then
			local data, gold = enc(inv), goldOf(p)
			sig[#sig + 1] = names[p] .. "|" .. data .. "|" .. gold
			local e = entries[names[p]]
			if not e or e.data ~= data or e.gold ~= gold or e.seen ~= level then
				entries[names[p]] = {data = data, gold = gold, seen = level}
			end
		end
	end
	table.sort(sig)
	local s = table.concat(sig, "\n")
	if s ~= lastSig then
		lastSig = s
		write()
	end
end

-- a player leaves: what they had, kept for when they come back
function InvKeep.left(p, inv, gold)
	if claimed[p] and names[p] and inv then
		entries[names[p]] = {data = enc(inv), gold = gold, seen = level}
		write()
	end
	names[p], claimed[p] = nil, nil
end

-- the host's "New session": every saved inventory gone
function InvKeep.reset()
	entries = {}
	ClearKey(S .. ".p")
	lastSig = ""
	newSession()
	publishSession()
end

InvKeep.enc, InvKeep.dec = enc, dec                                    -- (offline checks)
