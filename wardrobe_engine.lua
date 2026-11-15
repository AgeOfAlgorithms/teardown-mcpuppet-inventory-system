-- The clothing engine: clothes and armour on the players' characters, on any map, in multiplayer. An include of the
-- mod that runs it (with wardrobe_rig.lua, inventory_api.lua, the game's "script/toolanimation.lua" and melee.lua
-- included before it). It holds NO garments: clothes come from packs - any mod that includes inventory_api.lua and
-- calls InventoryClothing({...}); the Wardrobe mod is one of them.
--
-- The including script calls, from its own callbacks:
--   server.init        InvWearServerInit()
--   server.tick        InvWearServerTick(dt)
--   client.init        InvWearClientInit()
--   client.tick        InvWearClientTick(dt)          (it calls InventoryClientTick() itself)
--   client.postUpdate  InvWearClientPostUpdate()      (the swinger's lean: bone work only takes effect from here)
-- and may call on the host: WardrobeArmor(p), WardrobeMobility(p), WardrobeNoise(p), WardrobeDamage(victim, d,
-- cause, attacker), WardrobeExtra(p, defense, mobility, noise), WeaponsSwing(p).
--
-- A player whose host registry key inventory.wear.<playerId> is set (by the inventory, or by any other
-- mod's server script: a game mode) is stripped to an underwear body - the character's own torso,
-- arms, legs and feet are taken off, the head, neck and hands stay - and wears the items listed there.
--   "" / unset / "none"   the underwear body: with this mod on, everyone starts naked (the user)
--   "own"                  the character as it is (nothing touched)
--   ids                    the underwear body + those items (space separated; items come from inventory_api.lua, any mod)
-- Armour: every item has an armor value (0-1, the share of a hit it blocks; pieces multiply). The host gives the
-- blocked share of every health loss back (WardrobeArmor(p); shared.invWear.a<p>) - the one place armour is applied.
-- Slots (ids): head, top (upper body), legs (lower body), feet. Stats: defense (armor), mobility (walking speed and
-- jump height), noise: WardrobeArmor / WardrobeMobility / WardrobeNoise(p) on the host, shared.invWear.a / s / q<p>
-- for clients. What the including script adds from elsewhere (an armour item of its own): WardrobeExtra.
-- Characters with no skin (the skeleton, the robot, the space suit) keep their own body: only the parts an item
-- covers are taken off.
-- The server publishes the lists; every machine dresses every player locally: parts are shapes on the character's
-- own bone bodies, so the engine animates them and no script runs per frame for them.

local BODY, BODY_TOP = "wardrobe_body", "wardrobe_body_top"
local SETTLE_FRAMES = 3           -- a new character's bodies are read this many frames after they appear
-- how a character's own part is taken off: "tag" (invisible), "park" (moved to a body far away), "clear" (its
-- voxels copied to a backup shape far away, then removed)
WardrobeStripMode = "clear"           -- (a global: TEST copies try the other ways)

-- the underwear bodies are items of this script (hidden: not for inventories): the template body, the women's, and
-- the own body of every character of the game. Registered from the init hooks (not at file level: an included
-- file's top level may run before the include it needs).
local bodiesDone = false
local function registerBodies()
	if bodiesDone then return end
	bodiesDone = true
	for id, d in pairs(WARDROBE_BUILTIN) do
		InventoryClothing({id = id, name = d.name, slot = d.slot, layer = d.layer, vox = d.vox, parts = d.parts, covers = d.covers,
			voxlayer = d.voxlayer, type = d.type, hidden = true})
	end
	for char, d in pairs(WARDROBE_BODIES) do
		local names = {}
		for part in pairs(d.parts) do names[#names + 1] = part end
		table.sort(names)
		InventoryClothing({id = BODY .. "_" .. char, slot = "body", layer = 0, vox = d.vox, parts = names, hidden = true, type = "body.underwear"})
	end
end

------------------------------------------------------------------------------------------------------------ server
local svWear = {}
local svArmor = {}                -- player -> the share of a hit the worn items block
local svHealth = {}               -- player -> health at the end of the last tick
local svSeq = 0

local svExtra = {}                -- player -> {defense, mobility, noise} the including script adds (WardrobeExtra)

function InvWearServerInit()
	registerBodies()
	WeaponsDamage = WardrobeDamage   -- (the melee engine's blows go through the armour before they land)
	shared.invWear = {n = 0}
	WeaponsServerInit()
end

-- the three stats of what a player wears (the user's): defense (the share of a hit blocked, pieces multiply),
-- mobility (walking speed and jump height, 1 = normal, the items' values added) and noise (how loud the player moves, 1 = normal,
-- added likewise: for mods whose creatures listen - this mod only publishes it)
local svSpeed, svNoise = {}, {}
local WALK_SPEED, JUMP_SPEED = 7.0, 4.0   -- the game's own (read in game by the Dive mod)

local function svStatsOf(w, x)
	local pass, speed, noise = 1, 1, 1
	if x then
		pass, speed, noise = 1 - math.max(0, math.min(x[1] or 0, 0.95)), 1 + (x[2] or 0), 1 + (x[3] or 0)
	end
	for id in string.gmatch(w, "%S+") do
		local k = "inventory.clothing." .. id
		local a = GetFloat(k .. ".armor")
		if a > 0 then pass = pass * (1 - math.min(a, 0.95)) end
		speed = speed + GetFloat(k .. ".mobility")
		noise = noise + GetFloat(k .. ".noise")
	end
	return 1 - pass, math.max(0.5, math.min(1.5, speed)), math.max(0.1, math.min(3, noise))
end

-- the mobility factor and the noise factor of what this player wears (host)
function WardrobeMobility(p) return svSpeed[p] or 1 end
function WardrobeNoise(p) return svNoise[p] or 1 end

-- the share of a hit this player's clothes block (host)
function WardrobeArmor(p)
	return svArmor[p] or 0
end

-- (host) what the including script adds to a player's totals from things that are not clothes: a share of a hit
-- blocked (multiplies with the clothes'), and amounts added to the mobility and noise factors. nil / zeros: nothing.
function WardrobeExtra(p, defense, mobility, noise)
	local x = svExtra[p]
	local d, m, n = defense or 0, mobility or 0, noise or 0
	if x and x[1] == d and x[2] == m and x[3] == n then return end
	svExtra[p] = (d ~= 0 or m ~= 0 or n ~= 0) and {d, m, n} or nil
	svWear[p] = nil                                               -- (the totals are worked out again in the next tick)
end

-- (host) damage that the armour is already taken off: for this mod's weapons, so a blow the armour would have
-- stopped from killing does not kill (the give-back in server.tick cannot undo a death)
function WardrobeDamage(victim, damage, cause, attacker)
	local a = svArmor[victim] or 0
	local d = damage * (1 - a)
	if attacker then ApplyPlayerDamage(victim, d, cause or "", attacker) else ApplyPlayerDamage(victim, d, cause or "") end
	svHealth[victim] = GetPlayerHealth(victim)
	return d
end

function InvWearServerTick(dt)
	WeaponsServerTick(dt)
	local changed = false
	local now = {}
	for _, p in ipairs(GetAllPlayers()) do
		local w = GetString("inventory.wear." .. p)
		if w == "" then w = "none" elseif w == "own" then w = "" end
		now[p] = w
		if svWear[p] ~= w then
			changed = true
			svArmor[p], svSpeed[p], svNoise[p] = svStatsOf(w, svExtra[p])
		end
		-- mobility: walking speed and jump speed are one-frame values, set every tick - only for players whose
		-- clothes change them. The height of a
		-- jump goes with the square of the jump speed: the root, so the HEIGHT follows the factor.
		if svSpeed[p] and svSpeed[p] ~= 1 then
			SetPlayerParam("walkingSpeed", WALK_SPEED * svSpeed[p], p)
			SetPlayerParam("jumpSpeed", JUMP_SPEED * math.sqrt(svSpeed[p]), p)
		end
		-- armour: the blocked share of what was lost since the last tick comes back
		local h = GetPlayerHealth(p)
		local was = svHealth[p]
		if was and h > 0 and h < was and (svArmor[p] or 0) > 0 then
			h = h + (was - h) * svArmor[p]
			SetPlayerHealth(h, p)
		end
		svHealth[p] = h
	end
	for p in pairs(svWear) do
		if now[p] == nil then
			changed = true
			svArmor[p], svHealth[p], svSpeed[p], svNoise[p], svExtra[p] = nil, nil, nil, nil, nil
		end
	end
	if changed then
		svWear = now
		svSeq = svSeq + 1
		local t = {n = svSeq}
		for p, w in pairs(now) do
			t["p" .. p] = w
			t["a" .. p] = svArmor[p] or 0
			t["s" .. p] = svSpeed[p] or 1
			t["q" .. p] = svNoise[p] or 1
		end
		shared.invWear = t
	end
end

------------------------------------------------------------------------------------------------------------ client
local clPlayers = {}              -- player -> {wear, pelvis, wait, hidden, parked, cleared, park, gen}
local clRetagAt = 0
WardrobeStats = {strips = 0, retags = 0, parkFail = 0, clearFail = 0}

local function clWords(s)
	local t = {}
	for w in string.gmatch(s or "", "%S+") do t[#t + 1] = w end
	return t
end

local function clGen(p, st)
	st.gen = (st.gen or 0) + 1
	SetInt("inventory.gen." .. p, st.gen)
end

local function clParkBody(p, st)
	if st.park and IsHandleValid(st.park) then return st.park end
	for _, e in ipairs(Spawn("<body/>", Transform(Vec(p * 40, -500, 0)), true) or {}) do
		if GetEntityType(e) == "body" then st.park = e end
	end
	st.slot = 0
	return st.park
end

-- put back everything clStrip took off (whatever still exists: a replaced character took its shapes with it)
local function clUnstrip(st)
	for _, sh in ipairs(st.hidden) do
		if IsHandleValid(sh) then RemoveTag(sh, "invisible") end
	end
	for _, k in ipairs(st.parked) do
		if IsHandleValid(k.shape) and IsHandleValid(k.body) then SetShapeBody(k.shape, k.body, k.at) end
	end
	for _, k in ipairs(st.cleared) do
		if IsHandleValid(k.backup) then
			if IsHandleValid(k.shape) then CopyShapeContent(k.backup, k.shape) end
			Delete(k.backup)
		end
	end
	st.hidden, st.parked, st.cleared = {}, {}, {}
end

-- take the character's own shapes off these bones, and hide what hangs off them on joints (hoods, backpacks, radios).
-- only(sh): when given, just the shapes it says yes to (a hat on the head bone)
local function clStrip(p, st, anim, bones, only)
	local isBone = {}
	for _, n in ipairs(GetBoneNames(anim) or {}) do
		local b = GetBoneBody(anim, n)
		if b and b ~= 0 then isBone[b] = true end
	end
	local seen = {}
	local function tag(sh)
		SetTag(sh, "invisible")
		st.hidden[#st.hidden + 1] = sh
	end
	local function clear(sh)                                     -- its voxels to a backup shape far away, then gone
		local park = clParkBody(p, st)
		if park then
			st.slot = st.slot + 1
			local ok, backup = pcall(CreateShape, park, Transform(Vec(st.slot * 1.5, 0, 0)), sh)
			if ok and backup and backup ~= 0 then
				CopyShapeContent(sh, backup)
				ClearShape(sh)
				st.cleared[#st.cleared + 1] = {shape = sh, backup = backup}
				return true
			end
		end
		WardrobeStats.clearFail = WardrobeStats.clearFail + 1
		return false
	end
	local hang
	hang = function(b)                                           -- a body that hangs off a stripped bone
		if seen[b] or isBone[b] or not IsHandleValid(b) then return end
		seen[b] = true
		for _, sh in ipairs(GetBodyShapes(b) or {}) do
			for _, j in ipairs(GetShapeJoints(sh) or {}) do
				local other = GetJointOtherShape(j, sh)
				if other and other ~= 0 then hang(GetShapeBody(other)) end
			end
			if not (WardrobeStripMode == "clear" and clear(sh)) then tag(sh) end
		end
	end
	for _, bone in ipairs(bones) do
		local b = GetBoneBody(anim, bone)
		if b and b ~= 0 then
			for _, sh in ipairs(GetBodyShapes(b) or {}) do
				if only and not only(sh) and not HasTag(sh, "invclothing") and not HasTag(sh, "proxy") then
					-- (a hat that swings on a joint off the head - Chris' toque: its own body, hung off the head shape)
					for _, j in ipairs(GetShapeJoints(sh) or {}) do
						local other = GetJointOtherShape(j, sh)
						if other and other ~= 0 and only(other) then hang(GetShapeBody(other)) end
					end
				elseif not HasTag(sh, "invclothing") and not HasTag(sh, "proxy") then
					local jointed = false
					for _, j in ipairs(GetShapeJoints(sh) or {}) do
						local other = GetJointOtherShape(j, sh)
						if other and other ~= 0 then
							jointed = true
							hang(GetShapeBody(other))
						end
					end
					local done = false
					if WardrobeStripMode == "park" and not jointed then
						local park = clParkBody(p, st)
						if park then
							st.slot = st.slot + 1
							st.parked[#st.parked + 1] = {shape = sh, body = b, at = GetShapeLocalTransform(sh)}
							SetShapeBody(sh, park, Transform(Vec(st.slot * 1.5, 0, 0)))
							done = true
						else
							WardrobeStats.parkFail = WardrobeStats.parkFail + 1
						end
					elseif WardrobeStripMode == "clear" then
						done = clear(sh)
					end
					if not done then tag(sh) end
				end
			end
		end
	end
	WardrobeStats.strips = WardrobeStats.strips + 1
end

-- the character's own hat (WARDROBE_HATS: the voxel counts of its pieces) comes off with the rest of its clothes -
-- from the start, with nothing on (the user: "the ones with default hats should have their hats removed from the
-- start. With this mod on, they'll never see their hat"). The biggest shape on the head bone is the head itself
-- and is never touched.
local function clStripHat(p, st, anim, id)
	local hats = WARDROBE_HATS[id]
	if not hats then return end
	local counts = {}
	for _, n in ipairs(hats) do counts[n] = true end
	local b = GetBoneBody(anim, "head")
	if not b or b == 0 then return end
	local biggest, most = 0, -1
	for _, sh in ipairs(GetBodyShapes(b) or {}) do
		local n = GetShapeVoxelCount(sh)
		if n > most then biggest, most = sh, n end
	end
	clStrip(p, st, anim, {"head"}, function(sh)
		return sh ~= biggest and counts[GetShapeVoxelCount(sh)] == true
	end)
end

-- where every template part sits on this player's bones: Sven's place, moved along the bone for the parts that
-- are anchored at the far end (this character's bone length - Sven's)
local function clFit(p, anim, snap)
	local dbg = {}
	for part, r in pairs(WARDROBE_RIG) do
		local pos = Vec(r.pos[1], r.pos[2], r.pos[3])
		if r.child then
			local b, c = GetBoneBody(anim, r.bone), GetBoneBody(anim, r.child)
			if b and c and b ~= 0 and c ~= 0 then
				local lp = TransformToLocalPoint(GetBodyTransform(b), GetBodyTransform(c).pos)
				local len = VecLength(lp)
				dbg[#dbg + 1] = string.format("%s=%.3f", part, len)
				if r.anchor == "distal" and len > 0.01 then
					pos = VecAdd(pos, VecScale(lp, (len - r.len) / len))
				end
			end
		end
		local s = snap and snap[part]                              -- (the grid moved onto this body's middle: wardrobe_rig.lua)
		if s then pos = VecAdd(pos, Vec(s[1], s[2], s[3])) end
		SetString("inventory.fit." .. p .. "." .. part, string.format("%s %.4f %.4f %.4f %.4f %.4f %.4f", r.bone,
			pos[1], pos[2], pos[3], r.rot[1], r.rot[2], r.rot[3]))
	end
	table.sort(dbg)
	SetString("inventory.debug.len." .. p, table.concat(dbg, " "))
end

-- the parts the worn items cover (a character that keeps its own body loses only these)
local function clCovered(wear)
	local set, list = {}, {}
	for _, id in ipairs(clWords(wear)) do
		for _, part in ipairs(clWords(GetString("inventory.clothing." .. id .. ".covers"))) do
			if not set[part] then
				set[part] = true
				list[#list + 1] = part
			end
		end
	end
	return list
end

WardrobeDeath = "keep"            -- (TEST copies: "restore" = a dead player gets the character's own shapes back)

local function clDress(p, st, anim)
	local wear = st.wear
	if st.dead and WardrobeDeath == "restore" then wear = "" end
	clUnstrip(st)
	if wear == "" then
		SetString("inventory.worn." .. p, "")
		clGen(p, st)
		return
	end
	local id = GetPlayerCharacter(p)
	local items = wear == "none" and "" or wear
	-- how clothes are reshaped to this character: the boxes of its own body (none: the template's shape as it is)
	local own = (not WARDROBE_NOBODY[id]) and WARDROBE_BODIES[id] or nil
	clFit(p, anim, own and own.snap)
	for _, part in ipairs(WARDROBE_PARTS) do
		SetString("inventory.morph." .. p .. "." .. part, own and own.morph[part] or "")
	end
	local skin = WARDROBE_SKIN[id] or WARDROBE_SKIN_DEFAULT
	SetString("inventory.skin." .. p, string.format("%.3f %.3f %.3f", skin[1], skin[2], skin[3]))
	if WARDROBE_NOBODY[id] then
		clStrip(p, st, anim, clCovered(items))
		SetString("inventory.worn." .. p, items)
	else
		clStrip(p, st, anim, WARDROBE_STRIP)
		clStripHat(p, st, anim, id)
		-- the body: the character's own without its clothes when the mod has one (the game's characters), else
		-- the template body in the character's skin colour
		local body = WARDROBE_TOP[id] and BODY_TOP or BODY
		if own then
			body = BODY .. "_" .. id
			for part, fit in pairs(own.parts) do
				SetString("inventory.fit." .. p .. "." .. body .. "." .. part, fit)
			end
		end
		SetString("inventory.worn." .. p, items == "" and body or (body .. " " .. items))
	end
	clGen(p, st)
end

function InvWearClientInit()
	registerBodies()
	WeaponsClientInit()
end

function InvWearClientPostUpdate()
	WeaponsClientPostUpdate()
end

function InvWearClientTick(dt)
	WeaponsClientTick(dt)
	local wearAll = shared.invWear or {}
	local seen = {}
	for _, p in ipairs(GetAllPlayers()) do
		seen[p] = true
		local st = clPlayers[p]
		if not st then
			st = {wear = "", pelvis = 0, wait = 0, hidden = {}, parked = {}, cleared = {}, gen = 0}
			clPlayers[p] = st
		end
		local wear = wearAll["p" .. p] or ""
		local anim = GetPlayerAnimator(p)
		local pelvis = 0
		if anim and anim ~= 0 then pelvis = GetBoneBody(anim, "pelvis") or 0 end
		if pelvis ~= st.pelvis then
			st.pelvis = pelvis                                     -- (a new character: its bodies replaced the old ones)
			st.wait = SETTLE_FRAMES
			st.dirty = true
		end
		if wear ~= st.wear then
			st.wear = wear
			st.dirty = true
		end
		local dead = GetPlayerHealth(p) <= 0
		if dead ~= (st.dead or false) then
			st.dead = dead
			if WardrobeDeath == "restore" then st.dirty = true end
		end
		if st.wait > 0 then
			st.wait = st.wait - 1
		elseif st.dirty and pelvis ~= 0 then
			st.dirty = false
			clDress(p, st, anim)
		end
	end
	for p, st in pairs(clPlayers) do
		if not seen[p] then
			clUnstrip(st)
			if st.park and IsHandleValid(st.park) then Delete(st.park) end
			clPlayers[p] = nil
		end
	end
	-- should anything show a hidden shape again, hide it again (twice a second)
	local now = GetTime()
	if now - clRetagAt > 0.5 then
		clRetagAt = now
		for _, st in pairs(clPlayers) do
			for _, sh in ipairs(st.hidden) do
				if IsHandleValid(sh) and not HasTag(sh, "invisible") then
					SetTag(sh, "invisible")
					WardrobeStats.retags = WardrobeStats.retags + 1
				end
			end
		end
	end
	InventoryClientTick()
end

-- (diagnostics) the character's own shapes taken off this player: tagged, parked, cleared, and their voxels now
function WardrobeHidden(p)
	local st = clPlayers[p]
	local n, parked, cleared, vox = 0, 0, 0, 0
	if st then
		for _, sh in ipairs(st.hidden) do
			if IsHandleValid(sh) then
				n = n + 1
				vox = vox + GetShapeVoxelCount(sh)
			end
		end
		for _, k in ipairs(st.parked) do
			if IsHandleValid(k.shape) then parked = parked + 1 end
		end
		for _, k in ipairs(st.cleared) do
			if IsHandleValid(k.shape) then cleared = cleared + 1 end
		end
	end
	return n, parked, cleared, vox
end
