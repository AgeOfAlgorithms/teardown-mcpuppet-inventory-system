-- McPuppet Inventory System's options (Mod Manager). In multiplayer the host's choice counts (the host keeps every
-- inventory). savegame.mod.keep: "" / "session" = inventories and gold carry over to the next map and the next session
-- until the host presses New session in the inventory; "map" = every map or mode change starts everyone empty.
-- Two columns: inventories, death and starting gold on the left; gold lying around the map on the right
-- (inv_scatter.lua, the user 2026-11-16: on by default, 1-20 a pile, 300 at most (500 at first), a respawn time).

local CHOICES = {
	{"session", "Keep", "Inventories and gold carry over to the next map, game mode and session. The host resets them with NEW SESSION in the inventory screen."},
	{"map", "Reset every map", "Every map or game mode change starts everyone with an empty inventory and the starting gold."},
}

-- a row of choice buttons for an int option: its heading, the buttons, a line under it
local function intRow(title, key, values, default, label, note, w)
	w = w or 110
	UiColor(1, 1, 1)
	UiFont("regular.ttf", 26)
	UiText(title)
	UiTranslate(0, 46)
	UiFont("bold.ttf", 26)
	local cur = HasKey(key) and GetInt(key) or default
	for i, v in ipairs(values) do
		UiPush()
		UiTranslate((i - (#values + 1) / 2) * w, 0)
		if v == cur then UiColor(0.75, 0.9, 1) else UiColor(0.55, 0.55, 0.55) end
		if UiTextButton(label(v), w - 10, 42) then SetInt(key, v) end
		UiPop()
	end
	UiTranslate(0, 36)
	UiFont("regular.ttf", 19)
	UiColor(0.6, 0.6, 0.6)
	if note then UiText(note) end
	UiTranslate(0, 50)
end

local function left()
	local cur = GetString("savegame.mod.keep") == "map" and 2 or 1
	UiFont("regular.ttf", 28)
	UiColor(1, 1, 1)
	UiText("Inventories and gold")
	UiTranslate(0, 55)
	UiFont("bold.ttf", 28)
	for i, c in ipairs(CHOICES) do
		UiPush()
		UiTranslate((i - 1.5) * 300, 0)
		if i == cur then UiColor(0.75, 0.9, 1) else UiColor(0.55, 0.55, 0.55) end
		if UiTextButton(c[2], 280, 44) then SetString("savegame.mod.keep", c[1]) end
		UiPop()
	end
	UiTranslate(0, 62)
	UiFont("regular.ttf", 20)
	UiColor(0.8, 0.8, 0.8)
	UiWordWrap(700)
	UiText(CHOICES[cur][3])
	UiTranslate(0, 62)
	UiColor(0.6, 0.6, 0.6)
	UiText("A player who leaves keeps their inventory for when they come back. At most 24 players are remembered.")
	UiTranslate(0, 80)
	-- the gold a player drops where they die (savegame.mod.deathloss, percent; 20 when unset - the user, 2026-11-15)
	intRow("Gold dropped at death", "savegame.mod.deathloss", {0, 10, 20, 30, 50, 100}, 20,
		function(v) return v .. "%" end, "That share of a player's gold falls where they die, for anyone to pick up.")
	-- the gold a new wallet starts with (savegame.mod.startgold; 500 when unset, at most 2000 - the user, 2026-11-15; 9999 added 2026-11-20)
	intRow("Starting gold", "savegame.mod.startgold", {100, 250, 500, 1000, 2000, 9999}, 500, tostring,
		"For new wallets. Kept wallets keep their gold: NEW SESSION gives everyone this amount.", 130)
end

local function right()
	local on = not (HasKey("savegame.mod.scatter") and not GetBool("savegame.mod.scatter"))
	UiFont("regular.ttf", 28)
	UiColor(1, 1, 1)
	UiText("Gold lying around the map")
	UiTranslate(0, 55)
	UiFont("bold.ttf", 28)
	for i, v in ipairs({true, false}) do
		UiPush()
		UiTranslate((i - 1.5) * 220, 0)
		if v == on then UiColor(0.75, 0.9, 1) else UiColor(0.55, 0.55, 0.55) end
		if UiTextButton(v and "On" or "Off", 200, 44) then SetBool("savegame.mod.scatter", v) end
		UiPop()
	end
	UiTranslate(0, 45)
	UiFont("regular.ttf", 20)
	UiColor(0.6, 0.6, 0.6)
	UiWordWrap(700)
	UiText("Piles of gold anywhere on the map, indoors too, for anyone to pick up. A pile taken comes back somewhere else after a while.")
	UiTranslate(0, 70)
	intRow("Smallest pile", "savegame.mod.scattermin", {1, 2, 5, 10, 25}, 1, tostring, nil)
	intRow("Largest pile", "savegame.mod.scattermax", {5, 10, 20, 50, 100}, 20, tostring, "Each pile holds a random amount between the two.")
	intRow("Total lying out", "savegame.mod.scattercap", {100, 300, 500, 1000, 2000}, 300, tostring, "No more gold than this lies around at once.", 130)
	intRow("Comes back after", "savegame.mod.scatterrespawn", {30, 60, 120, 300}, 60,
		function(v) return v < 60 and v .. " s" or (v / 60) .. " min" end, "The time before a pile someone took lies out again.", 130)
end

function draw()
	UiAlign("center middle")
	UiPush()
	UiTranslate(UiCenter(), 70)
	UiColor(1, 1, 1)
	UiFont("bold.ttf", 48)
	UiText("McPuppet Inventory System")
	UiTranslate(0, 50)
	UiFont("regular.ttf", 20)
	UiColor(0.6, 0.6, 0.6)
	UiText("In multiplayer the host's choices count.")
	UiPop()
	UiPush()
	UiTranslate(UiCenter() - 460, 200)
	left()
	UiPop()
	UiPush()
	UiTranslate(UiCenter() + 460, 200)
	right()
	UiPop()
	UiPush()
	UiTranslate(UiCenter(), UiHeight() - 80)
	UiColor(1, 1, 1)
	UiFont("bold.ttf", 32)
	if UiTextButton("Close", 200, 50) then Menu() end
	UiPop()
end
