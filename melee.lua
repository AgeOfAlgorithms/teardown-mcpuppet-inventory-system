-- The melee engine: swings, hit boxes, damage, knockback and effects for every weapon a mod registered with
-- InventoryWeapon (inventory_api.lua). An include of the mod that runs the engine, which also includes the game's
-- "script/toolanimation.lua". There is NO weapon list in this file: a weapon is whatever has
-- inventory.weapons.<id>.* keys with .ext = 1 on this machine (written by the include in the weapon's own mod, which
-- also registers the tool with its own prefab). WeaponsScan (once a second) turns the keys into an entry of WEAPONS.
--
-- Every weapon is a real tool with
--   power     share of full health (0..1) taken off an unarmoured player it hits
--   delay     seconds from the click to the moment the hit lands (wind-up + swing)
--   cooldown  seconds after the hit before the next swing can start
--   reach     metres from the eye (measured on its swing here, published as inventory.weapons.<id>.reach)
--   knockback m/s a player it hits is thrown back with
--   hands     1 or 2
-- A host's own numbers in inventory.weapons.<id>.power / .delay / .cooldown / .reach / .knockback are read at every
-- swing (the include never overwrites a key that exists).
--
-- Multiplayer: the HOST does everything that counts. It reads each player's "usetool" itself (no request from a
-- client: nothing to forge), holds the cooldown, and while the weapon is on its way THE WEAPON IS THE HIT BOX: the
-- host follows the same swing the clients draw (the same keyframes, in the swinger's eye frame) and every tick
-- casts the weapon's own length, grip to tip, where it is at that moment. What that line meets is hit: a player
-- once a swing (ApplyPlayerDamage(victim, power, id, attacker), the armour taken off first), the world where the
-- blade crosses it (a hole, a push on loose things). Clients only show: one ClientCall per swing and one per hit,
-- the swing drawn through the game's tool animator (first and third person, every player's weapon on every
-- machine).
--
-- WeaponsAuto (global, default true): every player gets every weapon in their tool wheel. The including script sets
-- it to false when it hands weapons out itself (an inventory).
--
-- A PACK'S OWN SWING: next to the six styles a weapon may bring three poses of its own (InventoryWeapon's swing =
-- {wind = {...}, hit = {...}, thru = {...}}, published as inventory.weapons.<id>.swing: 18 numbers) and its own
-- carried pose (carry = {...}: 6 numbers, the same as its prefab's tp_action). The hit box follows whatever poses
-- the weapon has, the grip is kept within the arm's reach and the body leans into the blow as for the styles.
--
-- Hooks (the engine calls them): WeaponsServerInit(), WeaponsServerTick(dt), WeaponsClientInit(),
-- WeaponsClientTick(dt), WeaponsClientPostUpdate(). For tests / other server code in this mod: WeaponsSwing(p) -> ok, reason.

-- style: slash (one hand: from over the shoulder diagonally down across the body), stab, chop (one hand,
-- overhead), smash (two hands, overhead), sweep (two hands, wide and level), thrust. multi: every player the weapon
-- passes through (else the first). hole: MakeHole radii (soft, medium, hard materials) - about the size of the
-- weapon's head: the weapon makes one wherever it crosses something, all along its way, so big ones took out whole
-- walls. push: impulse on a loose body. bite: s the weapon stays in what it hit. kick: camera shake on the swinger's
-- machine at a hit. reach (m, from the eyes): how far the tip gets in the swing - what the model can touch; a host
-- that changes it stretches the hit line by the same share.
WEAPONS = {}                       -- the weapons this machine knows (WeaponsScan fills it): {id, name, hands, style, len, ...}
WEAPON_BY_ID = {}
-- the carried pose in the eye's frame (the tool prefabs' "tp_action" location: keep them the same - MODDING.md gives
-- the prefab blocks; tools/make_weapons.py writes Wardrobe's)
local CARRY = {up1 = {0.22, -0.50, -0.30, -25, 0, 8}, up2 = {0.14, -0.56, -0.32, -22, 0, 14}, level2 = {0.24, -0.48, -0.05, -88, 0, 0}}
local function carryOf(w)
	return CARRY[w.style == "thrust" and "level2" or (w.hands == 2 and "up2" or "up1")]
end

local STAT_KEYS = {"power", "delay", "cooldown", "reach", "knockback"}
local BODY_R = 0.35                -- m: a player's body round its upright axis
local FX_FLESH, FX_WOOD, FX_METAL, FX_STONE = 1, 2, 3, 4

-- the numbers of a weapon on this machine: the registry's when another mod wrote them, else the table's
local function stat(w, k)
	local key = "inventory.weapons." .. w.id .. "." .. k
	if HasKey(key) then
		local v = GetFloat(key)
		if v > 0 then return v end
	end
	return w[k]
end

------------------------------------------------------------------------------------------------------- server

local svReady, svPending, svSeen = {}, {}, {}
WeaponsStats = {cut = 0, hits = 0, mat = "", dist = 0}   -- the last blow on the world: voxels cut, places hit, the nearest one's material and distance

-- how a blow is dealt (main.lua replaces this with its armour-aware WardrobeDamage)
function WeaponsDamage(victim, d, cause, attacker)
	ApplyPlayerDamage(victim, d, cause, attacker)
end

-- The Inventory mod's melee hit event (MODDING.md, "Melee hits on things that are not players"; asked for by the
-- Villagers mod, whose NPCs are invisible hitbox shapes): every place a blow lands on a shape that is not a player's,
-- on the host, fields first and the counter last:
--   inventory.melee.hit.<n % 16>.shape / .body / .x .y .z / .attacker / .weapon / .power / .knockback / .dir.x .dir.y .dir.z
--     / .swing (the same number for every place one swing lands: a blade crosses a shape in several places - 4 to 12
--     events a swing on a box in game - so a reader counts the power once per swing and shape)
--   inventory.melee.hit.last = n          inventory.melee.hits = true: the event exists
-- A shape tagged "nohole" gets no hole.
local meleeHitN, meleeSwingN = 0, 0
local function meleeHitEvent(e, p, w, sh, body, at, d)
	for _, v in ipairs(GetAllPlayers()) do                           -- (a player's own bodies: the player hit above)
		for _, b in ipairs(GetPlayerBodies(v) or {}) do
			if b == body then return end
		end
	end
	if not e.swingN then
		meleeSwingN = meleeSwingN + 1
		e.swingN = meleeSwingN
	end
	meleeHitN = meleeHitN + 1
	local k = "inventory.melee.hit." .. (meleeHitN % 16) .. "."
	SetInt(k .. "shape", sh)
	SetInt(k .. "body", body)
	SetFloat(k .. "x", at[1])
	SetFloat(k .. "y", at[2])
	SetFloat(k .. "z", at[3])
	SetInt(k .. "attacker", p)
	SetString(k .. "weapon", w.id)
	SetFloat(k .. "power", stat(w, "power"))
	SetFloat(k .. "knockback", stat(w, "knockback"))
	SetFloat(k .. "dir.x", d[1])
	SetFloat(k .. "dir.y", d[2])
	SetFloat(k .. "dir.z", d[3])
	SetInt(k .. "swing", e.swingN)
	SetInt("inventory.melee.hit.last", meleeHitN)
end

-- (added by the Inventory session, 2026-11-15, announced: the bare-hand punch in inv.lua publishes the same event -
-- the Villagers session asked, for the user) one hit with given numbers, on the same ring and counters; swing nil: a
-- fresh swing number. -> the swing number used
function InventoryMeleeEvent(p, sh, body, at, d, weaponId, power, knockback, swing)
	for _, v in ipairs(GetAllPlayers()) do
		for _, b in ipairs(GetPlayerBodies(v) or {}) do
			if b == body then return swing end
		end
	end
	if not swing then
		meleeSwingN = meleeSwingN + 1
		swing = meleeSwingN
	else
		meleeSwingN = math.max(meleeSwingN, swing)                   -- (no later swing reuses a caller's number)
	end
	meleeHitN = meleeHitN + 1
	local k = "inventory.melee.hit." .. (meleeHitN % 16) .. "."
	SetInt(k .. "shape", sh)
	SetInt(k .. "body", body)
	SetFloat(k .. "x", at[1])
	SetFloat(k .. "y", at[2])
	SetFloat(k .. "z", at[3])
	SetInt(k .. "attacker", p)
	SetString(k .. "weapon", weaponId)
	SetFloat(k .. "power", power)
	SetFloat(k .. "knockback", knockback)
	SetFloat(k .. "dir.x", d[1])
	SetFloat(k .. "dir.y", d[2])
	SetFloat(k .. "dir.z", d[3])
	SetInt(k .. "swing", swing)
	SetInt("inventory.melee.hit.last", meleeHitN)
	return swing
end

function WeaponsServerInit()
	svReady, svPending, svSeen = {}, {}, {}
	ClearKey("inventory.melee.hit")
	meleeHitN, meleeSwingN = 0, 0
	SetBool("inventory.melee.hits", true)
end

-- Start a swing for player p with the weapon in their hands. -> true, or false and why not.
function WeaponsSwing(p)
	if type(p) ~= "number" or not IsPlayerValid(p) then return false, "player" end
	local w = WEAPON_BY_ID[GetPlayerTool(p)]
	if not w then return false, "tool" end
	if GetPlayerHealth(p) <= 0 then return false, "dead" end
	if GetPlayerVehicle(p) ~= 0 or not GetPlayerCanUseTool(p) then return false, "busy" end
	local now = GetTime()
	if now < (svReady[p] or 0) then return false, "cooldown" end
	local delay, cooldown = stat(w, "delay"), stat(w, "cooldown")
	svReady[p] = now + delay + cooldown
	svPending[#svPending + 1] = {p = p, w = w, t0 = now, delay = delay, cooldown = cooldown, hurt = {}, holes = {}, pushed = {},
		fx = 0, cut = 0, scale = stat(w, "reach") / w.reach}
	ClientCall(0, "client.wpnSwing", p, w.id, delay, cooldown)
	return true
end

local function flat(v)
	local f = Vec(v[1], 0, v[3])
	local l = VecLength(f)
	if l < 0.001 then return nil end
	return VecScale(f, 1 / l)
end

-- how far player v's body axis is from the segment a .. a + dir * len, and the point of the axis nearest to it
local function bodyToLine(v, a, dir, len)
	local feet = GetPlayerTransform(v).pos
	local best, bestC = 1e9, feet
	for i = 0, 4 do
		local c = Vec(feet[1], feet[2] + 0.2 + i * 0.35, feet[3])
		local s = VecDot(VecSub(c, a), dir)
		if s < 0 then s = 0 elseif s > len then s = len end
		local d = VecLength(VecSub(c, VecAdd(a, VecScale(dir, s))))
		if d < best then best, bestC = d, c end
	end
	return best, bestC
end

local function fxKind(mat)
	mat = tostring(mat or "")
	if mat == "wood" or mat == "foliage" or mat == "plastic" or mat == "plaster" then return FX_WOOD end
	if string.find(mat, "metal", 1, true) then return FX_METAL end
	return FX_STONE
end

local svSweep                      -- (defined below the swing's keyframes: it follows them)
WeaponsAuto = true
local scanAt = -100

function WeaponsServerTick(dt)
	local now = GetTime()
	if now - scanAt > 1 then
		scanAt = now
		local n = #WEAPONS
		WeaponsScan()
		-- (another mod's weapon found: into the wheel of the players already here)
		if #WEAPONS > n and WeaponsAuto then
			for p in pairs(svSeen) do
				if IsPlayerValid(p) then
					for i = n + 1, #WEAPONS do SetToolEnabled(WEAPONS[i].id, true, p) end
				end
			end
		end
	end
	for _, p in ipairs(GetAllPlayers()) do
		if not svSeen[p] then
			svSeen[p] = true
			if WeaponsAuto then
				for _, w in ipairs(WEAPONS) do SetToolEnabled(w.id, true, p) end
			end
		end
		if WEAPON_BY_ID[GetPlayerTool(p)] and InputDown("usetool", p) and now >= (svReady[p] or 0) then
			WeaponsSwing(p)
		end
	end
	if #svPending > 0 then
		for i = #svPending, 1, -1 do
			if svSweep(svPending[i], now) then table.remove(svPending, i) end
		end
	end
end

------------------------------------------------------------------------------------------------------- client

local clOn = false
local clScanAt = -100
local clState = {}               -- player -> {a = the tool animator, sw = the running swing}
local sndWhoosh, sndFlesh, sndWood, sndMetal, sndStone, sndThud = {}, {}, {}, {}, {}, {}

-- the swing's poses in the eye's frame, on top of the carried pose: {x, y, z (m: right, up, back), pitch (round
-- x: < 0 tips the weapon forward), roll (round the view axis: > 0 tips it to the left), yaw (round up: > 0 turns
-- it to the left)}. wind = the end of the wind-up, hit = where it lands, thru = the follow-through.
local SWINGS = {
	-- AT THE BLOW the arm is straight out in front and the weapon about level (its tip as far ahead as it gets): the
	-- first blows ended with a bent arm and the weapon pointing at the ground - their reach was "pathetic" (the user:
	-- "I literally have to stand centimetres away from the wall"). The follow-through takes it on down.
	-- slash: from over the right shoulder diagonally down to the left (a level swing looked horrendous)
	slash = {wind = {0.12, 0.48, 0.44, 60, -25, 0}, hit = {-0.17, 0.18, -0.20, -62, 15, 20}, thru = {-0.40, -0.08, 0.00, -100, 25, 50}},
	stab = {wind = {0.02, 0.16, 0.40, -62, 0, 0}, hit = {-0.06, 0.20, -0.24, -62, 0, 0}, thru = {-0.06, 0.20, -0.20, -62, 0, 0}},
	chop = {wind = {0.02, 0.60, 0.42, 70, 0, 0}, hit = {-0.06, 0.20, -0.22, -62, 0, 0}, thru = {-0.10, -0.12, -0.06, -105, 0, 0}},
	-- (the two-handers swing BIG - the user: the first ones looked like "chicken arms". Overhead: the hands go up
	--  above the head with the weapon hanging back behind it, then all the way over and down in front. The sweep:
	--  the blade starts behind the right hip and goes round to the left, through more than 150 degrees.)
	smash = {wind = {-0.04, 0.84, 0.42, 75, 0, 0}, hit = {-0.06, 0.26, -0.26, -63, 0, 0}, thru = {-0.08, -0.10, -0.08, -110, 0, 0}},
	-- (the sweep and the thrust go at SHOULDER height, the hands about 0.2 m under the eyes: at 0.4 m under them the
	--  user found the greatsword "swinging way too low" and the spear "stabbing too low")
	sweep = {wind = {0.24, 0.44, 0.52, -70, 0, -125}, hit = {-0.14, 0.42, -0.26, -68, 0, 15}, thru = {-0.42, 0.36, -0.04, -68, 0, 95}},
	thrust = {wind = {0.03, 0.26, 0.40, 0, 0, 0}, hit = {-0.04, 0.30, -0.53, 0, 0, 0}, thru = {-0.04, 0.30, -0.50, 0, 0, 0}},
}
-- (The swinger's own first-person view plays the SAME swing. It had smaller poses of its own for a while, so
--  the weapon stayed in the picture - they "looked super weird" (the user): one animation for everybody.)
local WIND = 0.55                -- the share of the delay that is wind-up; the rest is the swing itself
-- the heavy two-handers load up slowly and long, then come down fast (the user)
local function windOf(w)
	if w.hands == 2 and w.style ~= "thrust" then return 0.7 end
	return WIND
end
local REST = {0, 0, 0, 0, 0, 0}

local function keyT(k)
	local q = QuatRotateQuat(QuatAxisAngle(Vec(0, 1, 0), k[6]),
		QuatRotateQuat(QuatAxisAngle(Vec(0, 0, 1), k[5]), QuatAxisAngle(Vec(1, 0, 0), k[4])))
	return Transform(Vec(k[1], k[2], k[3]), q)
end

local function mix(a, b, u)
	return Transform(VecLerp(a.pos, b.pos, u), QuatSlerp(a.rot, b.rot, u))
end

-- where the weapon is t seconds into a swing (eye frame, on top of the carried pose)
local function swingPose(sw, t)
	local s = sw.w.swing or SWINGS[sw.w.style]
	local tw, th = sw.delay * windOf(sw.w), sw.delay
	local tf = th + math.min(0.12, sw.cooldown * 0.3)
	local te = th + sw.cooldown
	if t < tw then
		local u = t / tw
		if windOf(sw.w) > WIND then                              -- a heavy weapon: heaved up, slow to start and to stop
			return mix(keyT(REST), keyT(s.wind), u * u * (3 - 2 * u))
		end
		u = 1 - u                                                -- a light one: quick off the mark, settling
		return mix(keyT(REST), keyT(s.wind), 1 - u * u * u)
	elseif t < th then                                         -- the swing: accelerating into the hit
		local u = (t - tw) / (th - tw)
		return mix(keyT(s.wind), keyT(s.hit), u * u * (0.4 + 0.6 * u))
	elseif t < tf then                                         -- follow-through
		local u = 1 - (t - th) / (tf - th)
		return mix(keyT(s.hit), keyT(s.thru), 1 - u * u)
	elseif t < te then                                         -- back to the carried pose
		local u = (t - tf) / (te - tf)
		return mix(keyT(s.thru), keyT(REST), u * u * (3 - 2 * u))
	end
	return keyT(REST)
end

-- THE BODY GOES INTO THE BLOW: from the end of the wind-up the swinger leans forward from the waist (stomach and
-- chest bones, client.postUpdate), most at the blow, and straightens again in the cooldown. The shoulders come
-- LEAN_FWD m forward and LEAN_DOWN m down with it, and so does the weapon: more reach without a longer arm.
local LEAN_DEG, LEAN_FWD, LEAN_DOWN = 26, 0.22, 0.05
local function leanOf(sw, t)
	local tw, th = sw.delay * windOf(sw.w), sw.delay
	local te = th + sw.cooldown
	if t < tw then return -0.25 * math.min(1, t / (tw * 0.6)) * (1 - math.max(0, (t - tw * 0.6) / (tw * 0.4))) end   -- (a little back first)
	if t < th then
		local u = (t - tw) / (th - tw)
		return u * u
	end
	local u = math.min(1, (t - th) / (te - th))
	return 1 - u * u * (3 - 2 * u)
end
-- the hit line goes this far beyond the weapon's tip (m): what a player expects to connect, connects
local function extraOf(w)
	return w.extra or (w.style == "thrust" and 0.45 or 0.3)
end

-- The hand never leaves the arm's reach: the grip (carried place + the swing's offset, eye frame) is kept within
-- ARM m of the right shoulder. Beyond it the game's hand IK cannot follow and the arm snaps about - worst while
-- walking, when the shoulder moves as well (the user: "my arm glitches"). -> the offset to use.
local SHOULDER, ARM = {0.2, -0.24, 0.02}, 0.56
local function inReach(c, pos, two)
	local x, y, z = c[1] + pos[1] - SHOULDER[1], c[2] + pos[2] - SHOULDER[2], c[3] + pos[3] - SHOULDER[3]
	local l = math.sqrt(x * x + y * y + z * z)
	local arm = two and ARM + 0.08 or ARM                       -- (both arms and the turn of the shoulders)
	if l <= arm then return pos end
	local k = arm / l
	return Vec(SHOULDER[1] + x * k - c[1], SHOULDER[2] + y * k - c[2], SHOULDER[3] + z * k - c[3])
end

-- The weapon as it is t seconds into the swing e, in the world: the grip and the tip. The clients' tool animator
-- puts the tool at (carried pose) x (swing offset) in the swinger's eye frame; the same here, with the
-- third-person keyframes (what everybody else sees).
local function bladeAt(e, t, eyeT)
	local w = e.w
	local c = w.carry
	local D = swingPose(e, t)
	local rot = QuatRotateQuat(D.rot, QuatEuler(c[4], c[5], c[6]))
	local dp = inReach(c, D.pos, w.hands == 2)
	local lean = math.max(0, leanOf(e, t))
	local grip = Vec(c[1] + dp[1], c[2] + dp[2] - LEAN_DOWN * lean, c[3] + dp[3] - LEAN_FWD * lean)
	local tip = VecAdd(grip, QuatRotateVec(rot, Vec(0, (w.len + extraOf(w)) * e.scale, 0)))
	return TransformToParentPoint(eyeT, grip), TransformToParentPoint(eyeT, tip)
end

-- How far ahead of the eyes the weapon's tip gets in its swing (m), and how high over the eyes it is there:
-- measured on the swing itself (from the end of the wind-up to the end of the follow-through).
function WeaponsReach(w)
	local e = {w = w, delay = w.delay, cooldown = w.cooldown, scale = 1}
	-- (with the forgiveness beyond the tip: this is what connects)
	local tw, tf = w.delay * windOf(w), w.delay + math.min(0.12, w.cooldown * 0.3)
	local best, high = 0, 0
	for i = 0, 40 do
		local _, tip = bladeAt(e, tw + (tf - tw) * i / 40, Transform())
		if -tip[3] > best then best, high = -tip[3], tip[2] end
	end
	return best, high
end

-- The weapons mods registered (inventory_api.lua's InventoryWeapon wrote inventory.weapons.<id>.* with .ext = 1):
-- each becomes an entry of WEAPONS on this machine, with the numbers of its keys. The reach is measured on the
-- swing, to 5 cm. A number that is missing or
-- nonsense gets a sane one; a style this file does not know swings as a slash (one hand) or a smash (two).
function WeaponsScan()
	for _, id in ipairs(ListKeys("inventory.weapons") or {}) do
		local k = "inventory.weapons." .. id .. "."
		if not WEAPON_BY_ID[id] and GetInt(k .. "ext") == 1 and GetFloat(k .. "length") > 0 then
			local function num(key, default, lo, hi)
				local v = HasKey(k .. key) and GetFloat(k .. key) or default
				if v ~= v or v < lo then v = lo elseif v > hi then v = hi end
				return v
			end
			local hands = GetInt(k .. "hands") == 2 and 2 or 1
			local style = GetString(k .. "style")
			if not SWINGS[style] then style = hands == 2 and "smash" or "slash" end
			local snd = GetString(k .. "sound")
			if snd ~= "s" and snd ~= "m" and snd ~= "l" then snd = hands == 2 and "l" or "m" end
			local w = {id = id, key = id, name = GetString(k .. "name"), hands = hands, style = style,
				len = num("length", 0.7, 0.2, 2.5), power = num("power", 0.3, 0.01, 1), delay = num("delay", 0.35, 0.1, 3),
				cooldown = num("cooldown", 0.4, 0.1, 5), knockback = num("knockback", 3, 0, 20),
				hole = {num("hole1", 0.2, 0, 0.6), num("hole2", 0.12, 0, 0.6), num("hole3", 0.04, 0, 0.6)},
				push = num("push", 80, 0, 1000), bite = num("bite", 0.06, 0, 0.3), kick = num("kick", 0.3, 0, 1.5),
				multi = GetInt(k .. "multi") == 1, snd = snd}
			if HasKey(k .. "extra") then w.extra = num("extra", 0.3, 0, 1) end   -- (how far beyond the tip the hit line goes)
			w.carry = carryOf(w)
			-- the pack's own poses: numbers in the eye's frame (m and degrees), all of them or none
			local function nums(key, n)
				local t = {}
				for v in string.gmatch(GetString(k .. key), "[^%s]+") do t[#t + 1] = tonumber(v) end
				if #t ~= n then return nil end
				for i = 1, n do
					local lim = ((i - 1) % 6 < 3) and 1.5 or 360
					if not t[i] or t[i] ~= t[i] or math.abs(t[i]) > lim then return nil end
				end
				return t
			end
			local c, sp = nums("carry", 6), nums("swing", 18)
			if c then w.carry = c end
			if sp then
				w.swing = {wind = {sp[1], sp[2], sp[3], sp[4], sp[5], sp[6]}, hit = {sp[7], sp[8], sp[9], sp[10], sp[11], sp[12]},
					thru = {sp[13], sp[14], sp[15], sp[16], sp[17], sp[18]}}
			end
			w.reach = math.floor(WeaponsReach(w) / 0.05 + 0.5) * 0.05
			w.n = #WEAPONS + 1
			w.type = GetString(k .. "type")
			WEAPONS[w.n] = w
			WEAPON_BY_ID[id] = w
			-- (what this machine works out for it, for inventories: the reach measured on its swing)
			SetFloat(k .. "reach", w.reach)
			SetString(k .. "style", style)
		end
	end
end

-- One tick of a swing on the host: the weapon's line, grip to tip, at up to four moments since the last tick
-- (about 25 ms apart), from the end of the wind-up to the end of the follow-through. -> true when the swing is over.
svSweep = function(e, now)
	local p, w = e.p, e.w
	if not IsPlayerValid(p) or GetPlayerHealth(p) <= 0 or GetPlayerTool(p) ~= w.id then return true end
	local t = now - e.t0
	local tw = e.delay * windOf(e.w)
	local tf = e.delay + math.min(0.12, e.cooldown * 0.3)
	if t < tw then return false end
	local from, to = e.last or tw, math.min(t, tf)
	e.last = to
	local n = math.min(4, math.max(1, math.ceil((to - from) / 0.025)))
	local eyeT = GetPlayerEyeTransform(p)
	local tool = GetToolBody(p)
	for i = 1, n do
		local a, b = bladeAt(e, from + (to - from) * i / n, eyeT)
		local d = VecSub(b, a)
		local len = VecLength(d)
		d = VecScale(d, 1 / len)
		-- the world on the weapon's line (not the swinger's own body, clothes or the weapon itself)
		QueryRequire("physical")
		QueryRejectPlayer(p)
		if tool and tool ~= 0 then QueryRejectBody(tool) end
		local hit, hd, _, sh = QueryRaycast(a, d, len, 0.06)
		local free = hit and hd or len
		-- (a wall between the swinger and the weapon's grip - nose to the wall, the hand is already through it:
		--  the weapon stops there)
		local toGrip = VecSub(a, eyeT.pos)
		local gl = VecLength(toGrip)
		if gl > 0.05 then
			QueryRequire("physical")
			QueryRejectPlayer(p)
			if tool and tool ~= 0 then QueryRejectBody(tool) end
			local gh, gd, _, gs = QueryRaycast(eyeT.pos, VecScale(toGrip, 1 / gl), gl)
			if gh then
				hit, sh, free = true, gs, 0
				a, d, hd = VecAdd(eyeT.pos, VecScale(toGrip, gd / gl)), VecScale(toGrip, 1 / gl), 0
			end
		end
		-- the players the free part of the weapon passes through: once a swing each
		if not e.spent then
			for _, v in ipairs(GetAllPlayers()) do
				if v ~= p and not e.hurt[v] and not e.spent and GetPlayerHealth(v) > 0 then
					local dist, c = bodyToLine(v, a, d, free)
					if dist < BODY_R then
						e.hurt[v] = true
						if not w.multi then e.spent = true end
						WeaponsDamage(v, stat(w, "power"), w.id, p)
						local push = flat(VecSub(c, eyeT.pos)) or flat(TransformToParentVec(eyeT, Vec(0, 0, -1))) or Vec(0, 0, -1)
						local kb = stat(w, "knockback")
						SetPlayerVelocity(VecAdd(GetPlayerVelocity(v), Vec(push[1] * kb, kb * 0.35, push[3] * kb)), v)
						ClientCall(0, "client.wpnHit", p, w.id, FX_FLESH, c[1], c[2], c[3])
					end
				end
			end
		end
		-- the world where the weapon meets it: a hole there (one per place), loose bodies pushed once
		if hit then
			local at = VecAdd(a, VecScale(d, hd))
			local fresh = true
			for _, o in ipairs(e.holes) do
				if VecLength(VecSub(o, at)) < math.max(0.1, w.hole[1] * 0.5) then fresh = false end
			end
			if fresh then
				e.holes[#e.holes + 1] = at
				-- (what it is made of, read before the hole takes it away)
				local m = ""
				if sh and sh ~= 0 then m = GetShapeMaterialAtPosition(sh, VecAdd(at, VecScale(d, 0.03))) end
				local body = 0
				local real = sh and sh ~= 0 and IsHandleValid(sh)
				if real then
					body = GetShapeBody(sh)
					meleeHitEvent(e, p, w, sh, body, at, d)                     -- (before the hole: it may take the shape)
				end
				if w.hole[1] > 0 and not (real and HasTag(sh, "nohole")) then
					-- (the hole's middle a little inside the surface: centred on it, half the ball was air)
					e.cut = e.cut + (MakeHole(VecAdd(at, VecScale(d, w.hole[1] * 0.35)), w.hole[1], w.hole[2], w.hole[3], false) or 0)
				end
				if body ~= 0 and not e.pushed[body] and IsHandleValid(body) and IsBodyDynamic(body) then
					e.pushed[body] = true
					ApplyBodyImpulse(body, at, VecScale(d, w.push))
				end
				if e.fx < 2 then                                        -- (sound and particles for the first two places)
					e.fx = e.fx + 1
					ClientCall(0, "client.wpnHit", p, w.id, fxKind(m), at[1], at[2], at[3])
				end
				if #e.holes == 1 then WeaponsStats.mat, WeaponsStats.dist = tostring(m), VecLength(VecSub(at, eyeT.pos)) end
			end
		end
	end
	WeaponsStats.cut, WeaponsStats.hits = e.cut, #e.holes
	return t >= tf
end

local function loadSet(list, fmt, n)
	for i = 0, n - 1 do list[#list + 1] = LoadSound(string.format(fmt, i)) end
end

function WeaponsClientInit()
	clOn = true
	clState = {}
	sndWhoosh = {s = {}, m = {}, l = {}}
	loadSet(sndWhoosh.s, "throw/s%d.ogg", 6)
	loadSet(sndWhoosh.m, "throw/m%d.ogg", 6)
	loadSet(sndWhoosh.l, "throw/l%d.ogg", 6)
	sndFlesh, sndWood, sndMetal, sndStone, sndThud = {}, {}, {}, {}, {}
	loadSet(sndFlesh, "flesh-impact%d.ogg", 5)
	loadSet(sndWood, "wood/hit-m%d.ogg", 6)
	loadSet(sndMetal, "metal/hit-m%d.ogg", 6)
	loadSet(sndStone, "masonry/hit-m%d.ogg", 5)
	loadSet(sndThud, "tools/sledge%d.ogg", 6)
end

local function rnd(a, b) return a + math.random() * (b - a) end
local function oneOf(list) return list[math.random(1, #list)] end

local function state(p)
	local st = clState[p]
	if not st then
		st = {a = ToolAnimator()}
		clState[p] = st
	end
	return st
end

-- the host: player p starts a swing with weapon n
function client.wpnSwing(p, id, delay, cooldown)
	if not WEAPON_BY_ID[id] then WeaponsScan() end                 -- (another mod's weapon this machine has not met yet)
	local w = WEAPON_BY_ID[id]
	if not clOn or not w or type(p) ~= "number" then return end
	state(p).sw = {w = w, t = 0, delay = delay or w.delay, cooldown = cooldown or w.cooldown, bite = 0, whoosh = false,
		fp = IsPlayerLocal(p) and not GetBool("game.thirdperson")}       -- (the swinger's own eyes: the first-person poses)
end

-- the host: player p's weapon n struck something at this point
function client.wpnHit(p, id, kind, x, y, z)
	local w = WEAPON_BY_ID[id]
	if not clOn or not w then return end
	local pos = Vec(x, y, z)
	local heavy = w.hands == 2
	local st = clState[p]
	if st and st.sw then st.sw.bite = w.bite end
	if IsPlayerLocal(p) then ShakeCamera(w.kick) end
	local set = kind == FX_FLESH and sndFlesh or kind == FX_WOOD and sndWood or kind == FX_METAL and sndMetal or sndStone
	PlaySound(oneOf(set), pos, heavy and 1.0 or 0.75, true, rnd(heavy and 0.75 or 0.95, heavy and 0.9 or 1.15))
	if heavy and kind ~= FX_FLESH then PlaySound(oneOf(sndThud), pos, 0.6, false, rnd(0.8, 0.95)) end
	ParticleReset()
	if kind == FX_FLESH then
		ParticleType("plain")
		ParticleColor(0.45, 0.03, 0.02, 0.2, 0.01, 0.01)
		ParticleRadius(0.02, 0.035)
		ParticleGravity(-9)
		ParticleDrag(0.2)
		for _ = 1, heavy and 9 or 5 do SpawnParticle(pos, Vec(rnd(-1.5, 1.5), rnd(0.5, 2.5), rnd(-1.5, 1.5)), rnd(0.4, 0.8)) end
	else
		ParticleType("smoke")
		if kind == FX_WOOD then ParticleColor(0.45, 0.36, 0.25, 0.3, 0.25, 0.2) else ParticleColor(0.6, 0.6, 0.6, 0.4, 0.4, 0.4) end
		ParticleRadius(0.06, heavy and 0.4 or 0.22)
		ParticleAlpha(0.5, 0)
		ParticleGravity(-0.5)
		ParticleDrag(1.5)
		for _ = 1, heavy and 5 or 3 do SpawnParticle(pos, Vec(rnd(-0.6, 0.6), rnd(0, 0.8), rnd(-0.6, 0.6)), rnd(0.6, 1.2)) end
		if kind == FX_METAL or kind == FX_STONE then                 -- sparks / chips
			ParticleReset()
			ParticleType("plain")
			if kind == FX_METAL then
				ParticleColor(1, 0.8, 0.4, 1, 0.4, 0.1)
				ParticleEmissive(4, 0)
			else
				ParticleColor(0.5, 0.5, 0.5)
			end
			ParticleRadius(0.012, 0.02)
			ParticleGravity(-10)
			for _ = 1, 5 do SpawnParticle(pos, Vec(rnd(-2.5, 2.5), rnd(0.5, 3), rnd(-2.5, 2.5)), rnd(0.25, 0.5)) end
		end
	end
end

-- The swinger's body leans into the blow, for everyone who sees the character (bone work on a player's character
-- only takes effect from client.postUpdate). Only players in a swing are touched.
function WeaponsClientPostUpdate()
	if not clOn then return end
	for p, st in pairs(clState) do
		local sw = st.sw
		if sw and not sw.fp and GetPlayerHealth(p) > 0 then
			local anim = GetPlayerAnimator(p)
			if anim and anim ~= 0 then
				local deg = LEAN_DEG * leanOf(sw, sw.t)
				RotateBone(anim, "stomach", QuatEuler(0, 0, deg * 0.45))
				RotateBone(anim, "chest", QuatEuler(0, 0, deg * 0.55))
				RotateBone(anim, "neck", QuatEuler(0, 0, -deg * 0.5))      -- (the head stays up, looking at the target)
			end
		end
	end
end

function WeaponsClientTick(dt)
	if not clOn then return end
	local now = GetTime()
	if now - clScanAt > 1 then                                     -- (another mod's weapons: see WeaponsScan)
		clScanAt = now
		WeaponsScan()
	end
	for _, p in ipairs(GetRemovedPlayers()) do clState[p] = nil end
	for _, p in ipairs(GetAllPlayers()) do
		local w = WEAPON_BY_ID[GetPlayerTool(p)]
		-- (not for the dead: the tool animation held a dead player's body up - corpses stood, the user saw it)
		if w and GetPlayerHealth(p) <= 0 then w = nil end
		if w then
			local st = state(p)
			local a = st.a
			local sw = st.sw
			if sw and sw.w ~= w then sw = nil end
			local off = nil
			if sw then
				if sw.bite > 0 then sw.bite = sw.bite - dt else sw.t = sw.t + dt end      -- (the weapon stays in what it hit)
				if not sw.whoosh and sw.t >= sw.delay * windOf(w) then
					sw.whoosh = true
					PlaySound(oneOf(sndWhoosh[w.snd]), GetPlayerEyeTransform(p).pos, 0.7, false, rnd(0.9, 1.1))
					if IsPlayerLocal(p) then ShakeCamera(w.kick * 0.25) end
				end
				-- a pale streak where the tip goes while the weapon is fast (the swing itself and the follow-through)
				if sw.t >= sw.delay * windOf(w) and sw.t < sw.delay + 0.1 and sw.bite <= 0 then
					local tip = GetToolLocationWorldTransform("tip", p)
					if tip then
						ParticleReset()
						ParticleType("plain")
						ParticleColor(1, 1, 1, 0.8, 0.85, 0.9)
						ParticleRadius(0.035, 0.005)
						ParticleAlpha(0.45, 0)
						ParticleGravity(0)
						ParticleDrag(0)
						ParticleCollide(0)
						SpawnParticle(tip.pos, Vec(0, 0, 0), 0.16)
					end
				end
				if sw.t >= sw.delay + sw.cooldown then
					sw = nil
				else
					-- the swing is given in the eye's frame (D), the animator wants it in the carried pose's own
					-- frame (P): offset = P^-1 * (D * P)
					local P = Transform(Vec(), a.poseTransform.rot)
					local D = swingPose(sw, sw.t)
					D.pos = inReach(w.carry, D.pos, w.hands == 2)
					local lean = math.max(0, leanOf(sw, sw.t))                  -- (the weapon goes forward with the body)
					D.pos = Vec(D.pos[1], D.pos[2] - LEAN_DOWN * lean, D.pos[3] - LEAN_FWD * lean)
					off = TransformToLocalTransform(P, TransformToParentTransform(D, P))
					-- My own first-person view: the weapon RESTS low on the right (fp_action, out of the middle of the
					-- picture - the user: "the weapons can't be right in my face"), but the swing is the very one the
					-- others see (from the third-person carried pose; one animation for everybody, the user). From
					-- the rest pose into it over the first half of the wind-up, back at the end of the cooldown.
					if IsPlayerLocal(p) and not GetBool("game.thirdperson") then
						local c = w.carry
						local want = Transform(VecAdd(Vec(c[1], c[2], c[3]), D.pos), QuatRotateQuat(D.rot, QuatEuler(c[4], c[5], c[6])))
						local tw, te = sw.delay * windOf(w), sw.delay + sw.cooldown
						local b = math.max(0, math.min(1, sw.t / (0.5 * tw), (te - sw.t) / (0.4 * sw.cooldown)))
						b = b * b * (3 - 2 * b)
						off = TransformToLocalTransform(a.poseTransform, mix(a.poseTransform, want, b))
					end
				end
			end
			st.sw = sw
			a.offsetTransform = off or Transform()
			a.forceActionPose = sw ~= nil
			tickToolAnimator(a, dt, nil, p)
		elseif clState[p] then
			clState[p].sw = nil
		end
	end
end
