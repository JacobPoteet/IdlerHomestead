# Assets: art & shader list

> **Status:** first pass (M1). Everything currently on screen is a procedural placeholder drawn by
> [`game/src/render/placeholders.lua`](../game/src/render/placeholders.lua). This list is the shopping
> list for asset packs / custom art, and the plan for shaders.

## How art plugs in

All sprites are looked up by id through [`game/assets/manifest.lua`](../game/assets/manifest.lua).
To replace a placeholder, put the image in `game/assets/sprites/` and change its entry from
`{ placeholder = ... }` to `{ file = "assets/sprites/<sheet>.png", x, y, w, h }`. No game code changes.

- **Tile size:** 16×16 (tentative, GDD §9.2). Virtual screen is ≥ 640×360, integer-scaled.
- **Perspective:** top-down 3/4, so buildings and objects show a front face.
- **Anchoring:** object sprites sit bottom-left on their footprint and may extend upward (trees are
  16×32). Actor sprites are drawn bottom-centre at the feet.
- **Variants:** `variants = n` gives ids `name_1..name_n`; in a sheet they're laid out left to right.
- **Palette:** the colour grade shader tints everything by time of day, so author art in neutral
  daylight colours. Avoid baked-in lighting direction beyond a soft top-left highlight.

## Sprites

Legend: **M1** = in the game now (placeholder) · **M2–M7** = needed by that milestone.

### Terrain & ground (16×16)

| Id | Variants | Status | Notes |
|---|---|---|---|
| `grass` | 4 | M1 | Base ground. Seasonal versions later (summer dry, autumn, snow). |
| `road` | 2 | M1 | Dirt road. |
| `tilled_dry` / `tilled_wet` | 1 each | M1 | Furrowed soil; wet is darker. |
| `ford_stones` | 1 | M1 | Transparent overlay of stepping stones drawn over water. |
| `plan_marker` | 1 | M1 | Corner ticks on planned field tiles. |
| Grass→dirt / grass→water transition tiles | autotile set | M7 | Today the creek edge is handled by the water shader's foam. |
| Snow ground, frozen water | — | M3 | Done as shaders (`snow.glsl`, `water.glsl` ice) over the normal tiles. |

### Objects

| Id | Size | Status | Notes |
|---|---|---|---|
| `brush` | 16×16 | M1 | Messy-start clutter. |
| `rock` | 16×16 | M1 | |
| `log` | 16×16 | M1 | Fallen log. |
| `junk` | 16×16 | M1 | Crate, tire, sheet metal. Gives scrap + a few dollars. |
| `tree` | 16×32 | M1 | Needs 2–3 species and seasonal variants (bare in winter). |
| `truck` | 32×24 | M1 | Electric pickup, 2×1 footprint. Later: charging cable, cargo states, trailer. |
| `folding_panel` | 16×16 | M2 | Starting gear, placed beside the truck. |
| `smoker` | 16×24 | M2 | Smoke puffs are drawn by the renderer while a batch runs. |
| `campfire`, `chopping_block` | 16×16 | M3 | Starting kit, placed beside the truck. |
| `woodshed` | 32×24 | M3 | 2×1 footprint; seasons firewood (no smoke). |
| `wood_stove` | 16×24 | M3 | Better heat source than the campfire. |
| Sell crate, delivery drop-off | 16×16 | Later | The crate is only a HUD count for now; deliveries appear instantly. |
| Woodpile / woodshed | 16×16 / 32×32 | M3 | Firewood stock shown visually. |
| Shack / cabin | 32×32+ | M3 | |
| `well` 16×24, `hand_pump`, `dc_pump`, `drip_line` 16×16, `cistern` 32×16 (2×1) | various | M5 (placeholders) | Water ladder (#35). Icons `icon_<object>` are 12×12. Needs: handle and bucket animation, cistern water levels (a code-drawn gauge today), pump on/off art, hose lines for the drip line (a status lamp and zone tint today). See #94. |
| `solar_array` 32x16 (2x1), `battery_bank`, `micro_hydro`, `generator`, `electric_heater`, `lamp`, `chest_freezer` 16x16, `wind_turbine` 16x32 | various | M5 (placeholders) | Power network (#34). The turbine needs blade animation; the generator, heater and freezer need on/off art states (today a status light is drawn over them, see `visuals.powerLamp`). Icons `icon_<object>` and `icon_fuel` are 12x12. |
| Roadside stand | 32×24 | M5 | |
| Chicken coop, goat shed, barn | various | M6–M7 | |

### Crops (16×16, 3 growth stages: sprout, growing, ready)

| Id | Status | Notes |
|---|---|---|
| `radish_1..3` | M1 | Ready stage shows the red root. |
| `potato_1..3` | M1 | Ready stage flowers. |
| More crops | M6–M7 | Carrots, beans, squash, corn (tall), greenhouse crops. |

### Actors (16×20)

| Id | Status | Notes |
|---|---|---|
| `homesteader` | M1 (static) | Needs 4-direction walk (4 frames), work animations: hoe, water, harvest, chop, fish. Carry states: bucket, armful. |
| Cat | M5 | Walk, sit, sleep, pounce, being petted. |
| Chickens, goats, cattle | M6–M7 | |
| Mice, birds, deer | M5+ | Pests and ambient life. |

### UI icons (12×12)

| Id | Status |
|---|---|
| `icon_money`, `icon_food`, `icon_heart`, `icon_water`, `icon_wood`, `icon_stone`, `icon_scrap`, `icon_seed_radish`, `icon_seed_potato` | M1 |
| Journal node icons (one per catalog item / perk), Note stamps. Placeholders so far: `icon_note_blank` (unwritten note), `icon_spoiled` (fish gone off); other notes reuse existing icons | M3 |
| `icon_<fish id>` for all 7 species (one tinted placeholder painter), `icon_unknown`, `icon_battery`, `icon_crate`, `icon_rod`, `icon_bait`, `icon_smoked_fish`, `icon_smoker`, `icon_folding_panel` | M2 |
| `bobber` (8×10) for the fishing mini-game | M2 |
| `icon_firewood`, `icon_seasoned_firewood`, `icon_cold`, `icon_axe`, `icon_campfire`, `icon_woodshed`, `icon_wood_stove` | M3 |

### Fonts

Currently LÖVE's default font, rendered crisp at every scale. A pixel font with good small sizes and
accented characters is wanted before the art pass.

## Shaders

Shaders live in [`game/shaders/`](../game/shaders/) and are managed by
[`game/src/render/shaders.lua`](../game/src/render/shaders.lua). Parameters live in
[`game/data/tuning/visuals.lua`](../game/data/tuning/visuals.lua). **F6 reloads shaders and tuning live.**
A shader that fails to compile keeps the last good version and shows the error in the F1 overlay.

Guidelines: stay pixel-art friendly (snap to the art-pixel grid, quantize into bands rather than smooth
gradients), avoid `sin()`-based hashes (precision on mobile), and keep everything GLSL ES-compatible.

| Shader | Status | What it does |
|---|---|---|
| `water.glsl` | **M1** | Creek: depth shading from a per-tile depth map, pixel-snapped ripples drifting downstream, banding, daylight sparkles, foam along the banks. **M3:** `ice` blends to a pale frozen surface with crack lines; ice holes are drawn on top by the renderer. |
| `grade.glsl` | **M1** | Whole-world post-process: time-of-day tint & light (dawn warm, night blue), saturation, vignette, film grain on the art-pixel grid at 12 fps. **M3:** the lighting keys stretch to each season's sunrise/sunset, and a per-season tint/saturation (`visuals.seasonGrade`) sits on top. |
| `snow.glsl` | **M3** | Snow over the ground canvas: clumpy pixel coverage that ramps in after the freeze and melts after the thaw (`visuals.snow*`). |
| Wind sway | Planned | Vertex shader bending crops, brush and tree canopies with gusts; strength from weather. |
| Cloud shadows | Planned | Soft noise shadows drifting across the land; ties into solar output on cloudy days. |
| Night lights | Planned (M3) | Light-map canvas: lamp/window/stove/campfire glows that punch through the night grade. |
| Rain & wet ground | Planned | Rain streaks + ripple rings on water + darkened, glossier ground. |
| Snow on objects & frost | Planned | Snow on tops of objects and trees, frost creeping over edges (ground snow and the frozen creek are done). |
| Morning mist | Planned | Low fog band over the creek and fields at dawn. |
| Heat shimmer | Planned | Summer midday distortion near the horizon/fields. |
| Fireflies / dust motes | Planned | Particle + glow on summer evenings. |
| Tilt-shift | Planned (widget mode) | Blur toward the top/bottom of the frame for a diorama feel on the desktop companion. |
| Selection outline | Planned | Pixel outline for hovered/selected objects instead of tile boxes. |
| Fishing water | Planned (M2) | Close-up underwater view for the tension mini-game (cutaway, light rays, fish silhouettes). |
