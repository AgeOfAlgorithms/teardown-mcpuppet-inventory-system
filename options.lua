-- McPuppet Inventory System's options (Mod Manager). In multiplayer the host's choice counts (the host keeps every
-- inventory). savegame.mod.keep: "" / "session" = inventories and gold carry over to the next map and the next session
-- until the host presses New session in the inventory; "map" = every map or mode change starts everyone empty.

local CHOICES = {
	{"session", "Keep", "Inventories and gold carry over to the next map, game mode and session. The host resets them with NEW SESSION in the inventory screen."},
	{"map", "Reset every map", "Every map or game mode change starts everyone with an empty inventory and the starting gold."},
}

function draw()
	local cur = GetString("savegame.mod.keep") == "map" and 2 or 1
	UiTranslate(UiCenter(), 80)
	UiAlign("center middle")
	UiColor(1, 1, 1)
	UiFont("bold.ttf", 48)
	UiText("McPuppet Inventory System")
	UiTranslate(0, 90)
	UiFont("regular.ttf", 28)
	UiText("Inventories and gold")
	UiTranslate(0, 60)
	UiFont("bold.ttf", 30)
	for i, c in ipairs(CHOICES) do
		UiPush()
		UiTranslate((i - 1.5) * 300, 0)
		if i == cur then UiColor(0.75, 0.9, 1) else UiColor(0.55, 0.55, 0.55) end
		if UiTextButton(c[2], 280, 46) then SetString("savegame.mod.keep", c[1]) end
		UiPop()
	end
	UiTranslate(0, 70)
	UiFont("regular.ttf", 22)
	UiColor(0.8, 0.8, 0.8)
	UiWordWrap(700)
	UiText(CHOICES[cur][3])
	UiTranslate(0, 70)
	UiColor(0.6, 0.6, 0.6)
	UiText("A player who leaves keeps their inventory for when they come back. In multiplayer the host's choice counts. At most " .. 24 .. " players are remembered.")
	-- the gold a player drops where they die (savegame.mod.deathloss, percent; 20 when unset - the user, 2026-11-15)
	UiTranslate(0, 90)
	UiColor(1, 1, 1)
	UiFont("regular.ttf", 28)
	UiText("Gold dropped at death")
	UiTranslate(0, 55)
	UiFont("bold.ttf", 28)
	local loss = HasKey("savegame.mod.deathloss") and GetInt("savegame.mod.deathloss") or 20
	local LOSS = {0, 10, 20, 30, 50, 100}
	for i, v in ipairs(LOSS) do
		UiPush()
		UiTranslate((i - (#LOSS + 1) / 2) * 110, 0)
		if v == loss then UiColor(0.75, 0.9, 1) else UiColor(0.55, 0.55, 0.55) end
		if UiTextButton(v .. "%", 100, 44) then SetInt("savegame.mod.deathloss", v) end
		UiPop()
	end
	UiTranslate(0, 45)
	UiFont("regular.ttf", 20)
	UiColor(0.6, 0.6, 0.6)
	UiText("That share of a player's gold falls where they die, for anyone to pick up.")
	-- the gold a new wallet starts with (savegame.mod.startgold; 500 when unset, at most 2000 - the user, 2026-11-15)
	UiTranslate(0, 70)
	UiColor(1, 1, 1)
	UiFont("regular.ttf", 28)
	UiText("Starting gold")
	UiTranslate(0, 55)
	UiFont("bold.ttf", 28)
	local start = HasKey("savegame.mod.startgold") and GetInt("savegame.mod.startgold") or 500
	local START = {100, 250, 500, 1000, 2000}
	for i, v in ipairs(START) do
		UiPush()
		UiTranslate((i - (#START + 1) / 2) * 130, 0)
		if v == start then UiColor(0.75, 0.9, 1) else UiColor(0.55, 0.55, 0.55) end
		if UiTextButton(tostring(v), 120, 44) then SetInt("savegame.mod.startgold", v) end
		UiPop()
	end
	UiTranslate(0, 45)
	UiFont("regular.ttf", 20)
	UiColor(0.6, 0.6, 0.6)
	UiText("For new wallets. Kept wallets keep their gold: NEW SESSION (the host's button) gives everyone this amount.")
	UiTranslate(0, 80)
	UiColor(1, 1, 1)
	UiFont("bold.ttf", 32)
	if UiTextButton("Close", 200, 50) then Menu() end
end
