# Making melee weapons

This guide shows how to add your own melee weapon to the McPuppet Inventory System from a mod of your own. The
Inventory mod swings your weapon, uses the weapon itself as the hit box, and deals the damage, knockback and holes.
You supply the model, a tool prefab and the numbers. You need MagicaVoxel and a text editor.

Start from the folder **`example pack`** inside the Inventory mod: copy it into `Documents/Teardown/mods`, rename it
and change it. Its frying pan (`vox/pan.vox`, `prefab/pan.xml`, `weapons.lua`) is a finished weapon. For the mod
folder itself and the store see `MODDING.md`; for clothes see `MODDING_CLOTHING.md`.

Players need the Inventory mod and your mod enabled, nothing else. In multiplayer every player needs both.

## Step 1. Model it

In MagicaVoxel, build the weapon **standing up**: the bottom of the grip at the bottom of the model, the tip at the
top. Use half-size voxels as the game's tools do (one voxel = 5 cm), so a 60 cm weapon is 12 voxels high.

- Make the model an odd number of voxels wide and deep, with the handle on the middle voxel.
- The wide side (a blade's flat, an axe head) goes along the model's x axis.
- Save it as `vox/<name>.vox`, one object.

The example's frying pan is 7 wide, 3 deep, 13 high.

## Step 2. Copy the prefab

Copy `prefab/pan.xml` from the example pack and change three things:

1. `file="MOD/vox/pan.vox"`: your model.
2. The `pos` of that line, its middle number. It decides where the hand holds the weapon:
   `(model height / 2, rounded down, minus the voxels from the bottom up to the hand) x 0.05`.
   The pan is 13 high and held 2 voxels up: `(6 - 2) x 0.05 = 0.2`.
3. The `tip` location, its middle number: `(model height - voxels up to the hand) x 0.05`. The pan: `(13 - 2) x 0.05
   = 0.55`. This is also the `length` you give in `weapons.lua`.

Also change the name in `instance=MOD/prefab/pan.xml` to your file. If an axe or hammer head should point forward
instead of sideways, set `rot="0 90 0"` on the vox line.

Leave the `eye_space` block as it is. It says how the weapon is carried, and the swings start from it. The example
is for a **one-handed** weapon. For the other kinds, replace the six `eye_space` lines with one of these:

Two-handed, carried upright (`smash`, `sweep`):

```xml
<location name="fp_action" tags="name=fp_action" pos="0.30 -0.56 -0.55" rot="-16 0 -10"/>
<location name="tp_action" tags="name=tp_action" pos="0.14 -0.56 -0.32" rot="-22 0 14"/>
<location name="tp_action_crouch" tags="name=tp_action_crouch" pos="0.18 -0.64 -0.3" rot="-22 0 14"/>
<location name="tp_run" tags="name=tp_run" pos="0.16 -0.7 -0.22" rot="-35 0 30"/>
<location name="tp_jump" tags="name=tp_jump" pos="0.16 -0.62 -0.25" rot="-30 0 25"/>
<location name="tp_crouch" tags="name=tp_crouch" pos="0.2 -0.74 -0.2" rot="-40 0 30"/>
```

Two-handed, carried level and pointing forward (`thrust`):

```xml
<location name="fp_action" tags="name=fp_action" pos="0.26 -0.34 -0.10" rot="-88 0 0"/>
<location name="tp_action" tags="name=tp_action" pos="0.24 -0.48 -0.05" rot="-88 0 0"/>
<location name="tp_action_crouch" tags="name=tp_action_crouch" pos="0.28 -0.55 -0.05" rot="-88 0 0"/>
<location name="tp_run" tags="name=tp_run" pos="0.26 -0.6 0.0" rot="-70 0 0"/>
<location name="tp_jump" tags="name=tp_jump" pos="0.26 -0.55 0.0" rot="-75 0 0"/>
<location name="tp_crouch" tags="name=tp_crouch" pos="0.3 -0.62 0.0" rot="-80 0 0"/>
```

A two-handed weapon also needs the left hand. Add these three lines next to the `_rh` lines in `tool_space`. The
middle number is `(voxels up to the left hand - voxels up to the right hand) x 0.05`; it is negative when the left
hand is below the right:

```xml
<location name="tp_action_lh" tags="name=tp_action_lh ik_hand" pos="0.0 -0.45 0.0" rot="0.0 270.0 0.0"/>
<location name="tp_run_lh" tags="name=tp_run_lh ik_hand" pos="0.0 -0.45 0.0" rot="0.0 270.0 0.0"/>
<location name="tp_crouch_lh" tags="name=tp_crouch_lh ik_hand" pos="0.0 -0.45 0.0" rot="0.0 270.0 0.0"/>
```

## Step 3. List it in weapons.lua

```lua
InventoryWeapon({
	id = "mymod_pan",                         -- unique; no dots or spaces; start it with your mod's name
	name = "Frying Pan",
	prefab = "MOD/prefab/pan.xml",
	hands = 1,                                -- 1 or 2
	style = "chop",                           -- see the table below
	length = 0.55,                            -- metres from the hand to the tip (the prefab's "tip")
	power = 0.22,                             -- share of full health a hit takes (0 to 1)
	delay = 0.30,                             -- seconds from the click to the blow
	cooldown = 0.40,                          -- seconds after the blow before the next swing
	knockback = 6,                            -- how hard a hit player is thrown back (metres per second)
	hole = {0.2, 0.1, 0},                     -- optional: size of the hole in soft, medium and hard materials (m)
	multi = false,                            -- optional: true = hits every player it passes through
	price = 120,                              -- optional
	icon = "icons/pan.png",                   -- optional: PNG, 128 x 128, transparent
	type = "weapon.melee.onehanded.fryingpan",-- optional tag for other mods
})
```

Your `main.lua` needs these lines for it (the example pack's has them):

```lua
#version 2
#include "inventory_api.lua"
#include "weapons.lua"

function server.init()
	InventoryServerInit()                     -- makes your weapons real tools
end

function client.tick(dt)
	InventoryClientTick()
end
```

`inventory_api.lua` must be included before `weapons.lua`.

| style | hands | the swing |
|---|---|---|
| `slash` | 1 | from over the right shoulder diagonally down to the left |
| `chop` | 1 | straight down from above the head |
| `stab` | 1 | a short jab forward |
| `smash` | 2 | a big overhead blow, slow to load |
| `sweep` | 2 | a wide level swing at shoulder height, slow to load |
| `thrust` | 2 | a long jab forward at shoulder height |

The reach is worked out from your `length` and the swing.

## Step 4. Try it

Enable the Inventory mod and your mod, start a map and get the weapon from the store. Check that the hand sits on
the grip (the `pos` number) and that hits land where the weapon is (the `tip` number and `length`).

## Advanced: your own swing

A swing is three poses of the weapon, played one after the other: the end of the wind-up, the blow, and the
follow-through. Instead of a style you can give your own three:

```lua
	swing = {
		wind = {0.02, 0.60, 0.42, 70, 0, 0},   -- raised above and behind the head
		hit  = {-0.06, 0.20, -0.22, -62, 0, 0}, -- arm straight out in front, weapon about level
		thru = {-0.10, -0.12, -0.06, -105, 0, 0},-- carried on downwards
	},
```

Each pose is six numbers, measured from the carried pose, as seen by the player holding the weapon:

| number | meaning |
|---|---|
| 1 | metres to the right (negative: to the left) |
| 2 | metres up |
| 3 | metres back towards the player (negative: forward) |
| 4 | pitch in degrees: negative tips the weapon forward, positive back |
| 5 | roll in degrees: positive tips it to the left |
| 6 | yaw in degrees: positive turns it to the left |

Things to know:

- The hit box follows your poses, so hits land where your swing goes.
- The time between the poses comes from `delay` and `cooldown`: the wind-up ends about halfway through `delay`
  (later for two-handed weapons), the blow lands at `delay`.
- The hand is kept within arm's reach of the shoulder. A pose further away than that is pulled in.
- For the longest reach, make the `hit` pose an arm straight out in front with the weapon level.
- Keep positions within 1.5 m. If a number is missing or out of range, the `style` is used instead, so keep a
  `style` line as the fallback.

The numbers above are the `chop` style. Start from them and change one number at a time.

## Checklist before you publish

- `info.txt` has `version = 2`; `main.lua` starts with `#version 2`.
- `inventory_api.lua` is in your folder, unchanged.
- Every id starts with your mod's name and has no dots or spaces.
- The prefab's `tip` and your `length` are the same number.
- The Workshop page says your mod requires the McPuppet Inventory System.
