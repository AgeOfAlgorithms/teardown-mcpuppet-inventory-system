# Making clothes and armour

This guide shows how to add your own clothing and armour to the McPuppet Inventory System from a mod of your own.
You need MagicaVoxel and a text editor. No programming beyond filling in a list.

Start from the folder **`example pack`** inside the Inventory mod: copy it into `Documents/Teardown/mods`, rename it
and change it. It holds a finished T-shirt, a finished cap and the template you paint on. Every step below refers to
its files. For the mod folder itself, items that are not clothes, and the store, see `MODDING.md`. For melee weapons
see `MODDING_WEAPONS.md`.

## How it works, in short

- You paint **one** garment, on the template body. The Inventory mod reshapes it to whoever wears it: tall, short,
  fat or thin characters all get your garment fitted to their own body. You do not make a model per character.
- Your mod tells the Inventory mod about your items. It does the rest: it puts the parts on the character's bones
  and applies the armour and movement stats.
- Players need the Inventory mod and your mod enabled, nothing else. In multiplayer every player needs both
  (publish your mod on the Workshop).

## The files of a clothing pack

```
my clothes/
    info.txt            name, author, description, and the line  version = 2
    main.lua            starts with  #version 2  (see Step 3)
    inventory_api.lua   copied from the Inventory mod's folder, unchanged
    clothing.lua        the list of your clothes
    vox/                your .vox files
    icons/              your inventory icons (optional)
```

## Step 1. Open the template

Open `vox/template.vox` from the example pack in MagicaVoxel. You see a mannequin in a T-pose. It is made of
separate objects, one per body part:

| object | what it is |
|---|---|
| `head` | the head (the light blue head is only there to paint around) |
| `chest`, `stomach`, `pelvis` | the torso, top to bottom |
| `shoulder_l`, `shoulder_r` | the small blocks between chest and arm |
| `arm_upper_l`, `arm_upper_r` | upper arms |
| `arm_lower_l`, `arm_lower_r` | forearms (the hands are not part of clothes) |
| `leg_upper_l`, `leg_upper_r` | thighs |
| `leg_lower_l`, `leg_lower_r` | shins |
| `foot_l`, `foot_r`, `toes_l`, `toes_r` | feet |

Colours in the template:

- **White** is bare skin. In the game it takes the wearer's own skin colour.
- **Dark grey** is the underwear.
- **Magenta**, one voxel in two opposite corners of every object, are markers. They pin the object in place. The
  game removes them when the garment is worn.

Save the file under a new name (for example `vox/jacket.vox`) before you change anything.

## Step 2. Paint the garment

Select a body part and press Tab to edit it. Then:

- **Clothes that sit on the skin** (shirts, trousers, shoes, most armour): recolour the mannequin's own voxels with
  the Paint tool. A T-shirt is the chest, stomach, shoulders and upper arms painted in cloth colours. Do not build a
  layer around the body: a shell around the torso looks like a box.
- **Skin that shows** (below a short sleeve, below shorts): leave those voxels white.
- **Thick pieces** (a breastplate, shoulder pads, pouches, a hood): add voxels one layer outside the body, only
  where the piece really is.
- **Head wear**: in the `head` object, build the hat or helmet around the light blue head, then **delete the light
  blue head** (keep the two magenta corners). The wearer keeps their own head and hair; your piece is fitted over it.

Rules that must hold, or the garment lands in the wrong place:

1. Keep the two magenta corner voxels of every object you use.
2. Do not resize, move, rotate or rename the objects.
3. Do not paint with the magenta of the markers (palette slot 240). Use the white skin slots (241 to 248) only for
   skin.
4. Keep the clothes symmetric unless you mean otherwise: left and right objects are separate, paint both.

You can delete the objects your garment does not use, or leave them: only the objects you list are worn.

Tip for colours: the example clothes use palette slots 153 to 168 for cloth and leather and 121 to 136 for metal.

## Step 3. List it in clothing.lua

```lua
InventoryClothing({
	id = "mymod_jacket",                      -- unique; no dots or spaces; start it with your mod's name
	name = "Leather Jacket",
	slot = "top",                             -- head, top, legs or feet
	layer = 1,                                -- 1 = on the skin, 2 = worn over other clothes (helmets, vests)
	vox = "MOD/vox/jacket.vox",
	parts = "chest stomach shoulder_l shoulder_r arm_upper_l arm_upper_r arm_lower_l arm_lower_r",
	covers = "chest stomach shoulder_l shoulder_r arm_upper_l arm_upper_r arm_lower_l arm_lower_r",
	tint = true,                              -- keep this for everything made from template.vox
	armor = 0.10,                             -- 0 to 1: the share of a hit it blocks
	mobility = 0,                             -- -0.10 = 10 % slower and lower jumps, 0.05 = 5 % faster
	noise = 0.05,                             -- 0.35 = 35 % louder steps, -0.25 = quieter
	type = "clothing.upper.jacket",           -- a tag other mods can read
	price = 250,                              -- what the store asks; -1 = not for sale; leave out = the store decides
	icon = "icons/jacket.png",                -- optional
	drop = "vox/drop_jacket.vox",             -- optional
})
```

Your `main.lua` needs these lines for it (the example pack's has them):

```lua
#version 2
#include "inventory_api.lua"
#include "clothing.lua"

function client.tick(dt)
	InventoryClientTick()
end
```

`inventory_api.lua` must be included before `clothing.lua`.

What the fields mean:

- **`parts`**: the objects of your .vox file that make up the garment.
- **`covers`**: the body parts your garment replaces. For clothes painted on the mannequin, list the same parts as
  in `parts`: the body underneath is then not drawn, and your object must hold the whole part, skin included. For a
  piece that only adds something (a hat, a shoulder pad on its own), leave the part out of `covers` and keep only
  the added voxels in the object.
- **`slot`**: a player wears one item per slot. `top` is the upper body, `legs` the lower body.
- **`layer`**: a layer 2 item hides the parts of layer 1 items it covers (a vest over a shirt).
- **`tint`**: `true` makes the white skin voxels take the wearer's skin colour. It needs the objects to be on a
  MagicaVoxel layer named `$TINT`. Every object of the template already is, so keep `tint = true` for anything
  made from the template, with or without skin in it.
- **`armor`**: pieces multiply. Two pieces of 0.5 block 0.75 of a hit.

## Step 4. Icon and drop model (optional)

- **Icon**: a PNG, 128 x 128 pixels, transparent background.
- **Drop model**: what lies on the ground when the item is dropped. A small .vox with **one object**, in normal
  full-size voxels (not the half-size voxels of the template), the garment lying flat. Do not rely on a scaled-down
  model: scaled models hang in the air.

Without them the inventory shows its own placeholder.

## Step 5. Try it

Enable the Inventory mod and your mod, start any map, get the item from the store and put it on.

If the garment sits shifted or floats: a marker voxel is missing or an object was resized. If a body part is
missing: it is in `covers` but your object does not contain it.

## Checklist before you publish

- `info.txt` has `version = 2`; `main.lua` starts with `#version 2`.
- `inventory_api.lua` is in your folder, unchanged.
- Every id starts with your mod's name and has no dots or spaces.
- Every clothing object still has its two magenta corner voxels.
- The Workshop page says your mod requires the McPuppet Inventory System.
