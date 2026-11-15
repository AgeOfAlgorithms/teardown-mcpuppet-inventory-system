# Making items for the McPuppet Inventory System

This guide is for modders who want their own mod's things to show up in the inventory: weapons and tools,
consumables, loot, clothing and armour. You do not edit the Inventory mod. Your mod stays its own mod and tells the
inventory about its items.

**The fastest start:** copy the folder `example pack` (next to this file) into `Documents/Teardown/mods`, enable it
together with the Inventory mod, and look at what it does. It adds a bandage, a gold bar, a crowbar, a T-shirt, a
cap and a frying pan, one short file per kind of thing. Then keep the files you need, rename things and replace
its models and pictures with yours.

## Which section do I need?

| I want to add... | Read | You also need |
|---|---|---|
| a weapon or tool (a gun, a gadget, anything held in the hands) | [A tool](#a-tool-or-weapon) | nothing else |
| something you carry and use up (food, a medkit) | [A consumable](#a-consumable) | nothing else |
| loot, keys, quest items, money bags | [A plain item](#a-plain-item) | nothing else |
| clothing or armour you can SEE on the character | [Clothing](#clothing-and-armour) | one file to copy |
| a melee weapon with a swing (sword, axe) | [Melee weapons](#melee-weapons) | one file to copy |

Everything here needs only the Inventory mod. No other mod has to be installed.

## How it works (two rules)

1. **You talk to the inventory through the registry.** Teardown mods cannot call each other's functions, so
   everything is a line like `SetString("inventory.items.myitem.name", "My Item")`. Nothing to include, nothing to
   copy.
2. **Say it on every machine.** In multiplayer the host and every player keep their own registry. Put your lines in
   one function and call it from both `server.init()` and `client.init()`:

```lua
#version 2

function MyItems()
    SetString("inventory.items.mymod_apple.name", "Apple")
    -- ... more lines
end

function server.init() MyItems() end
function client.init() MyItems() end
```

Your mod needs `version = 2` in its `info.txt` and `#version 2` as the first line of every script, or the game
switches it off in multiplayer. The order in which mods load does not matter: the inventory looks for new items
every two seconds.

**Choosing ids.** An id is a short name without spaces or dots. Start it with your mod's name
(`mymod_apple`, not `apple`) so that two mods never use the same one.

## A tool or weapon

Every tool that any mod registers is an inventory item automatically. If your mod already has a working tool, you
are done: it can be picked up, dropped, put on a hotkey and sold in the store.

```lua
function server.init()
    RegisterTool("mymod_crowbar", "Crowbar", "MOD/vox/crowbar.vox", 1)
end
```

What the tool does when the player uses it is your own script, as for any Teardown tool.

Optional extras, set on every machine (`inventory.tools.<your tool id>.<key>`):

| Key | Type | Meaning |
|---|---|---|
| `.icon` | string | Picture in the inventory: a PNG in your mod's folder, e.g. `"icons/crowbar.png"`. Without it the item shows its name as text. |
| `.price` | int | What the store asks. `-1` = not sold. Without it: 1000. |
| `.ammo` | int | The tool uses ammo: one item is a pack of this many. The count is shown on the item and goes down as it is used. Without it the tool needs no ammo. |
| `.spent` | bool | `true` = the item disappears when its last one is used (a grenade). `false` = it stays, empty (a gun). |

```lua
SetString("inventory.tools.mymod_crowbar.icon", "icons/crowbar.png")
SetInt("inventory.tools.mymod_crowbar.price", 300)
```

Ammo is counted with the game's own tool ammo (`SetToolAmmo` / `GetToolAmmo`): use one unit of it per shot in your
tool's script and the inventory follows.

## A consumable

Something that stacks and is used up. The player puts it on a hotkey (drag, or right-click) and presses that
number to use one. Keys under `inventory.items.<id>`:

```lua
SetString("inventory.items.mymod_bandage.name", "Bandage")
SetString("inventory.items.mymod_bandage.kind", "consumable")
SetInt("inventory.items.mymod_bandage.stack", 5)                      -- how many fit in one cell
SetFloat("inventory.items.mymod_bandage.heal", 0.25)                  -- health given when used (1 = full health)
SetInt("inventory.items.mymod_bandage.price", 40)                     -- leave out: not sold in the store
SetString("inventory.items.mymod_bandage.icon", "icons/bandage.png")
SetString("inventory.items.mymod_bandage.drop", "vox/bandage.vox")
```

**Doing your own thing when it is used** (a speed boost, a spawn, a sound). Leave `.heal` out and watch the "used"
list on the host. Each use adds one entry and raises the counter `inventory.used.last`:

```lua
local seen = 0
function server.tick(dt)
    local last = GetInt("inventory.used.last")
    while seen < last do
        seen = seen + 1
        local k = "inventory.used." .. (seen % 16)
        if GetString(k .. ".id") == "mymod_coffee" then
            local player = GetInt(k .. ".player")
            -- your effect on that player here
        end
    end
end
```

## A plain item

Loot, keys, anything that is only carried. The same keys with `kind` = `"misc"`:

```lua
SetString("inventory.items.mymod_goldbar.name", "Gold Bar")
SetString("inventory.items.mymod_goldbar.kind", "misc")
SetInt("inventory.items.mymod_goldbar.stack", 10)
SetString("inventory.items.mymod_goldbar.icon", "icons/goldbar.png")
SetString("inventory.items.mymod_goldbar.drop", "vox/goldbar.vox")
```

To ask how many a player carries (on the host): `GetInt("inventory.count." .. player .. ".mymod_goldbar")`.

### All keys of `inventory.items.<id>`

| Key | Type | Meaning |
|---|---|---|
| `.name` | string | The name players see. |
| `.kind` | string | `"consumable"` or `"misc"`. |
| `.stack` | int | How many fit in one cell (1 if left out). |
| `.icon` | string | A PNG in your mod's folder. |
| `.drop` | string | A `.vox` in your mod's folder: the item lying in the world. Without it a small brown box. |
| `.price` | int | The store's price. Left out or `-1`: not sold. |
| `.heal` | float | Consumables: health given when used, 0 to 1. |
| `.color` | string | Optional: the item's colours, as words (`"red"`, `"red and black"`) or `"r g b"` (0 to 1, or 0 to 255). Left out, the inventory reads them off the `.drop` model. See [Item colours](#item-colours). Tools and clothing take the same key: `inventory.tools.<id>.color`, `inventory.clothing.<id>.color`. |
| `.mod` | string | Only if two enabled mods have a file with the same path: the id of the mod that owns `.icon` and `.drop`. Normally leave it out; the file is found by itself. |

## The files

**Icon.** A PNG, 128 x 128 pixels, transparent background, the item filling most of the picture. Give the path
inside your mod's folder, without `MOD/`: `"icons/bandage.png"`.

**Drop model.** A small `.vox` (MagicaVoxel) of the item lying on the floor, one object, at the normal voxel size
(1 voxel = 10 cm). A bandage is about 3 x 3 x 2 voxels. Two things to know:

- Teardown decides what a voxel is made of by its palette index, not its colour. Paint in the plastic row (palette
  slots 153-168) for light things and the metal rows (121-152) for heavy ones. Stay away from slots 1-8: those are
  glass.
- Do not shrink the model with a scale. A scaled-down model stays frozen in the air instead of falling.

Tools need no drop model: the inventory uses the tool's own model.

## Giving items to players

On the host, add to the string `inventory.give.<player>`. Each entry is `id`, `id:count`, or for a tool with ammo
`id:1:ammo`. Entries are separated by spaces. What does not fit in the inventory lands at the player's feet.

```lua
function server.tick(dt)
    -- (once per player, when you decide to)
    local key = "inventory.give." .. player
    SetString(key, GetString(key) .. " mymod_bandage:2 mymod_crowbar")
end
```

Always append to what is already there, as above: another mod may have written to it in the same frame.

## Items in a map or a spawn

Any body with the tag `invitem=<id>` is an item lying in the world that players can pick up. In a map's XML:

```xml
<body tags="invitem=mymod_goldbar n=3" dynamic="true">
    <vox file="MOD/vox/goldbar.vox"/>
</body>
```

`n=3` is a stack of three. For a tool with ammo add `ammo=6`. For a tool, the body is replaced by the tool's own
model.

## The store and gold coins

Players buy from the store column in the inventory screen, with gold coins.

- **Your price** is `.price` on your tool or item (above).
- **The host can override** any price: `SetInt("inventory.price.<id>", 250)`, or `-1` to take an item off sale.
- **Selling.** Whatever the store sells, it buys back for 60 % of its price: the player drags the item onto the
  store. A stack is sold whole. A tool with ammo sells for the share of its pack that is left (half the ammo, half
  the money). An item without a price cannot be sold. The host can change the share:
  `SetFloat("inventory.sell", 0.5)`, or `0` for no selling.
- **Money is gold coins**, the inventory's own: one number per player on the host, `inventory.gold.<player>`,
  shown in the bottom right corner of the screen and in the inventory. Every player starts with 500. The store takes the price from it and pays sales into it. Your mod can reward or charge a player
  with it; read it back each time, never keep a copy:

  ```lua
  local k = "inventory.gold." .. player
  SetInt(k, GetInt(k) + 50, true)      -- 50 gold coins for the player
  ```
- A map or game mode can switch the store off (`SetInt("inventory.store", 0)`) or make everything free
  (`SetBool("inventory.free", true)`), both on the host.

## Clothing and armour

The Inventory mod puts clothing on the player's character, fits it to each of the game's characters, and gives it
a slot, an icon, a price and its stats. Your pack brings the garment.

You paint ONE garment, on a template body, in MagicaVoxel. The mod reshapes it to fat, thin, tall and short
characters by itself; you do not make one model per character.

**The step-by-step guide for making a garment is `MODDING_CLOTHING.md`, next to this file. The `example pack`
folder has the template body and a finished T-shirt and cap.** In short, your clothing pack:

1. copies one file from the Inventory mod's folder (`inventory_api.lua`) into its own folder,
2. brings one `.vox` per garment, painted over the template body,
3. registers it with one call:

```lua
#version 2
#include "inventory_api.lua"

InventoryClothing({id = "mymod_tshirt", name = "Red T-Shirt", slot = "top", layer = 1,
                   vox = "MOD/vox/tshirt.vox",
                   parts = "chest stomach shoulder_l shoulder_r arm_upper_l arm_upper_r",
                   covers = "chest stomach shoulder_l shoulder_r arm_upper_l arm_upper_r",
                   tint = true, armor = 0, mobility = 0, noise = 0, price = 60,
                   icon = "icons/tshirt.png", drop = "vox/drop_tshirt.vox"})

function client.tick(dt) InventoryClientTick() end
```

What the fields mean to the player:

| Field | Meaning |
|---|---|
| `slot` | Where it is worn: `"head"`, `"top"` (upper body), `"legs"` (lower body), `"feet"`. One item per slot. |
| `armor` | Defence, 0 to 1: the share of a hit it blocks. Pieces multiply: two pieces of 0.5 block 0.75. |
| `mobility` | Added to the wearer's walking speed and jump: `-0.10` = 10 % slower. |
| `noise` | Added to how loud the wearer moves: `0.35` = 35 % louder, `-0.25` = quieter. |
| `price` | The store's price. `-1` = not sold. Left out: 150, plus 50 for every 5 % of armour. |
| `icon`, `drop` | As in [The files](#the-files). |

The other fields (`layer`, `vox`, `parts`, `covers`, `tint`) describe the model and are explained in the clothing
guide.

## Melee weapons

A weapon that is an ordinary tool (your own script does the hitting) already works: see
[A tool](#a-tool-or-weapon).

For a sword, an axe, a frying pan, the Inventory mod has a ready-made melee system: wind-up, swing, a hit box that
follows the weapon, damage, knockback, armour. Your pack brings the model and one call:

```lua
#version 2
#include "inventory_api.lua"

InventoryWeapon({id = "mymod_pan", name = "Frying Pan", prefab = "MOD/prefab/pan.xml", hands = 1,
                 style = "chop", length = 0.55, power = 0.22, delay = 0.30, cooldown = 0.40, knockback = 6,
                 price = 120, icon = "icons/pan.png"})

function server.init() InventoryServerInit() end
function client.tick(dt) InventoryClientTick() end
```

| Field | Meaning |
|---|---|
| `hands` | 1 or 2. |
| `style` | The swing. One hand: `slash`, `stab`, `chop`. Two hands: `smash`, `sweep`, `thrust`. |
| `length` | Metres from the grip to the tip. |
| `power` | The share of full health a hit takes, 0 to 1. |
| `delay` | Seconds from the click to the blow. |
| `cooldown` | Seconds after the blow before the next swing. |
| `knockback` | How hard the victim is pushed, in m/s. |

**Do I have to animate it?** No. Pick a `style` and the swing is done for you. If none of the six fits, you can
give your own swing as three poses of the weapon (end of the wind-up, the blow, the follow-through); the hit box
follows whatever you give. Teardown has no way to load a hand-animated clip for a held tool, so three poses are
the limit.

The prefab, the model, the optional fields and the custom swing are in `MODDING_WEAPONS.md`, next to this file,
with a working frying pan in the `example pack` folder.

## For mods that react to the player's gear

On the host, the inventory publishes what each player's worn items add up to:

| Key | Meaning |
|---|---|
| `inventory.stat.<player>.defense` | 0 to 1, the share of a hit blocked. |
| `inventory.stat.<player>.mobility` | A factor, 1 = normal. |
| `inventory.stat.<player>.noise` | A factor, 1 = normal. A creature mod multiplies the sound it hears from that player by it. |

### Melee hits on things that are not players

Melee weapons damage players by themselves. Everything else a blow lands on is announced, so a mod with its own
creatures (NPCs made of invisible hitbox shapes, monsters) can take the damage itself. On the host, for every place
a swing lands on a shape that is not a player's, the fields are written first and the counter last:

| Key | Meaning |
|---|---|
| `inventory.melee.hits` | `true` once this event exists (check it before relying on the keys below). |
| `inventory.melee.hit.last` | int: the number of the latest hit, n. Read the hits from your last n up to this one. |
| `inventory.melee.hit.<n % 16>.shape` / `.body` | int: the shape hit and its body. |
| `inventory.melee.hit.<n % 16>.x` / `.y` / `.z` | float: the point where the weapon met it. |
| `inventory.melee.hit.<n % 16>.attacker` | int: the player who swung. |
| `inventory.melee.hit.<n % 16>.weapon` | string: the weapon's id. |
| `inventory.melee.hit.<n % 16>.power` | float: the weapon's power, the share of full health it takes off an unarmoured player (0 to 1). |
| `inventory.melee.hit.<n % 16>.knockback` | float: m/s a player it hits is thrown back with. |
| `inventory.melee.hit.<n % 16>.dir.x` / `.dir.y` / `.dir.z` | float: the direction of the weapon at that moment, unit length. |
| `inventory.melee.hit.<n % 16>.swing` | int: the swing's number, the same for every place one swing lands. |

One swing lands in several places, one event each: the blade crosses a shape all along its way (4 to 12 events
for one swing at a box, seen in game). **Count the power once per swing and target**, by `.swing`. Tag a shape `nohole` and the weapon cuts no hole in it (for
hitbox shapes that should not be damaged).

```lua
local seen = GetInt("inventory.melee.hit.last")         -- (at init)
local hurtBy = {}                                       -- swing number -> true: already counted
-- each tick on the host:
local last = GetInt("inventory.melee.hit.last")
for n = math.max(seen + 1, last - 15), last do
	local k = "inventory.melee.hit." .. (n % 16) .. "."
	local sh = GetInt(k .. "shape")
	local swing = GetInt(k .. "swing")
	if IsHandleValid(sh) and HasTag(sh, "mymonster") and not hurtBy[swing] then
		hurtBy[swing] = true
		-- hurt it by GetFloat(k .. "power")
	end
end
seen = last
```

### Item colours

Every item the inventory knows (tools, clothing, other mods' items) gets its colours, written by the host and synced to
every machine, keyed by the item's id (the tool id, the clothing id, the item id):

| Key | Meaning |
|---|---|
| `inventory.colors.<id>.name` | The main colour, one word: `black grey white red pink orange brown beige yellow olive green cyan blue purple gold` (gold: orange or yellow metal). |
| `inventory.colors.<id>.text` | How a person would say it: `"red"`, `"grey and red"`, `"blue, white and black"`. |
| `inventory.colors.<id>.rgb` | The main colour as `"r g b"`, 0 to 1. |
| `inventory.colors.<id>.list` | Each colour with its share of the item's surface: `"grey:0.70 red:0.30"`. |
| `inventory.colors.<id>.material` | What most of it is made of, the game's material name (`metal`, `wood`, `plastic`, ...). |
| `inventory.colors.<id>.tinted` | `true`: mostly drawn in the owner's player colour. |
| `inventory.colors.<id>.source` | Written last. `"mod"`: the item's own mod said (its `.color` key). `"model"`: read off the item's model. `"none"`: no model to read, the other keys are missing. |

Where the colours come from: the item's own `.color` key if its mod set one (it wins, also when set later). Otherwise
the inventory reads the colours off the item's model: a tool's world model, else the item's `.drop` model. It
counts the colours on the outside of the model by area. The main colour is not always what a person would call the
item's colour (a gun of grey metal with a red grip is mostly grey), so use `.text` or `.list` when that matters.
The colours appear a few seconds after the map loads, one item every few frames.

```lua
local id = GetPlayerTool(player)
if GetString("inventory.colors." .. id .. ".source") ~= "" then
	DebugPrint("a " .. GetString("inventory.colors." .. id .. ".text") .. " " .. id)
end
```

## Checklist when something does not show up

- Is the Inventory mod enabled, and your mod too?
- `version = 2` in `info.txt`, `#version 2` on the first line of every script?
- Are your lines run on the client as well (`client.init`)? An item defined only on the host has no name or icon
  for the players.
- Is the id free of spaces and dots, and the same everywhere?
- Icon missing: is the path given without `MOD/`, and spelled as the file is (capitals count)?
- Not in the store: does it have a `.price` (items) that is not `-1`?
- Testing with friends: multiplayer only runs mods from the Workshop, and everyone needs the same version.
