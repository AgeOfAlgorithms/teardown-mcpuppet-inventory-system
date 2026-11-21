-- The game's sandbox script in multiplayer (data/script/sandbox.lua, server.tick) enables EVERY tool for every player
-- and writes 9999 ammo into it, every tick. The Inventory disables the tools a player doesn't carry (enforceTools), so
-- each of those flipped twice a frame, and every flip is sent to the clients: ~14,000 network messages a second on Lee
-- Chemicals with two players, against ~400 without the mod (measured by the Day & Night session, 2026-11-20,
-- tools/mp_perf.py; the user's report: heavy lag for the clients on plain sandbox maps, none in game modes, where the
-- sandbox script doesn't run).
-- So on a plain sandbox map in multiplayer the Inventory turns the sandbox script's server side off
-- (level.sandbox.disabled: it calls its disableSandbox() once and then returns before the tool loop) and does what
-- that side did itself: level.sandbox back on (the script's client side - HUD, death fade, weather, map markers -
-- runs while it is true), the spawn menu as the map had it, and the respawn 4 s after a death. level.unlimitedammo
-- stays false, as in a game mode: the Inventory counts every tool's ammo anyway.
-- Left alone: single player (the loop there only writes ammo, nothing is sent), the campaign, game modes, maps without
-- the sandbox script, and a level.sandbox.disabled another mod set (or cleared again later: that mod's say).

InvSandbox = {}

local RESPAWN = 4               -- s dead before the respawn (the sandbox script's respawnFadeInTime)
local state = nil               -- nil: not decided yet; false: not ours to touch; {spawn, creative}: taken over
local deadT = {}                -- player -> s dead

function InvSandbox.serverTick(dt)
	if state == false then return end
	if state == nil then
		if not IsMultiplayer() or GetBool("level.campaign") or GetString("game.gamemode") ~= "" then state = false return end
		if not GetBool("level.sandbox") then return end              -- (its init hasn't run yet, or there is none)
		if GetBool("level.sandbox.disabled") then state = false return end   -- (another mod's)
		state = {spawn = GetBool("level.spawn"), creative = GetBool("level.creative")}
		SetBool("level.sandbox.disabled", true)
		return
	end
	if not GetBool("level.sandbox.disabled") then state = false return end   -- (someone gave it back: the sandbox runs)
	if not GetBool("level.sandbox") then                             -- (its disableSandbox() ran: the flags back once)
		SetBool("level.sandbox", true, true)
		SetBool("level.spawn", state.spawn, true)
		SetBool("level.creative", state.creative, true)
	end
	local seen = {}
	for _, p in ipairs(GetAllPlayers() or {}) do
		seen[p] = true
		if GetPlayerHealth(p) <= 0 then
			deadT[p] = (deadT[p] or 0) + dt
			if deadT[p] > RESPAWN then
				RespawnPlayer(p)
				deadT[p] = 0
			end
		else
			deadT[p] = 0
		end
	end
	for p in pairs(deadT) do if not seen[p] then deadT[p] = nil end end
end

-- (tests) taken over? / decide again
function InvSandbox.active() return type(state) == "table" end
function InvSandbox.reset() state, deadT = nil, {} end
