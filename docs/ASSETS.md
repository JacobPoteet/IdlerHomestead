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
| Snow ground, frozen water | — | M3 | Done as shaders (`ground.glsl`, `snowcap.glsl`, `water.glsl` ice) over the normal tiles. |

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
| `camp` 32×32 (2×2 footprint, canvas lean-to with a bedroll), `shack` 48×32 (3×2, plank walls, tin roof, stove pipe, a window that reads lit), icons `icon_camp`, `icon_shack` 12×12 | M5 (placeholder) | Shelter ladder (#198, D82). Needs: real tent and shack art, smoke from the shack chimney, a lit window at night as input for the night-lights shader (#193), a cabin and workshop later. |
| Cabin | 48×48+ | Later | #198 later tiers. |
| `well` 16×24, `hand_pump`, `dc_pump`, `drip_line` 16×16, `cistern` 32×16 (2×1) | various | M5 (placeholders) | Water ladder (#35). Icons `icon_<object>` are 12×12. Needs: handle and bucket animation, cistern water levels (a code-drawn gauge today), pump on/off art, hose lines for the drip line (a status lamp and zone tint today). See #94. |
| `solar_array` 32x16 (2x1), `battery_bank`, `micro_hydro`, `generator`, `electric_heater`, `lamp`, `chest_freezer` 16x16, `wind_turbine` 16x32 | various | M5 (placeholders) | Power network (#34). The turbine needs blade animation; the generator, heater and freezer need on/off art states (today a status light is drawn over them, see `visuals.powerLamp`). Icons `icon_<object>` and `icon_fuel` are 12x12. |
| Roadside stand `roadside_stand` 32×24 (2×1 footprint, tall awning), icon `icon_roadside_stand` 12×12 (reused for the three upgrade icons) | M5 (placeholder) | Roadside stand (#37). Needs: real awning and table art, goods that show what is on sale, upgrade looks (sign, cooler, display rack). |
| Cat actors `cat` 14×10 (sitting) and `cat_nap` 14×10 (curled up), icon `icon_cat` 12×12 (also `icon_shelter_cat`) | M5 (placeholder) | Mice and the cat (#36). Needs a real walk cycle, grooming, night sleep, a mouse. See #116. |
| Auto-harvester `auto_harvester` 16×24 (1×1 footprint), icon `icon_auto_harvester` 12×12 | M6 (placeholder) | Machines (#42, D65). The picking arm is a code-drawn line to the target (`visuals.machine`), the status lamp a 3 px square, the reach a tinted 7×7 patch with an outline. Needs: real body art, an animated arm that lifts the crop, a crate that fills, working/idle/unpowered looks. See #146. |
| Chicken coop `chicken_coop` 32×24 (2×1 footprint), hen actor `hen` 10×9 (facing right, flipped in code), icons `icon_hen`, `icon_egg`, `icon_chicken_coop`, `icon_chicken_feed`, `icon_chicken_fence` 12×12 | M6 (placeholder) | Chickens (#40, D63). Needs: a real hen walk, peck and roost cycle, a chick, coop door open/closed art, a visible feeder and waterer, fence art around the run, eggs in the nest box (cream dots today, `visuals.hens`). |
| Goat pen `goat_pen` 32×32 (2×2 footprint), cheese press `cheese_press` 16×16, goat actor `goat` 14×11 (facing right, flipped in code), icons `icon_goat`, `icon_milk`, `icon_hay`, `icon_cheese`, `icon_goat_pen`, `icon_goat_trailer`, `icon_cheese_press` 12×12 | M6 (placeholder) | Goats (#139, D71). Needs: goat walk, graze and sleep cycle, kids, hay in the manger, a gate, milk dots in the pail (`visuals.goats`), the trailer, a running cheese press (issue #179). |
| Goat shed, barn | various | M6–M7 | Goats are a follow-up to #40. |

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
| `water.glsl` | **M1** | Creek: depth shading from a per-tile depth map, pixel-snapped ripples drifting downstream, banding, daylight sparkles, foam along the banks. **M3:** `ice` blends to a pale frozen surface with crack lines; ice holes are drawn on top by the renderer. **D83:** `rain` adds flat pixel rain rings in world cells and a few more crests (#98); `precision highp` on GL ES. |
| `grade.glsl` | **M1** | Whole-world post-process: time-of-day tint & light (dawn warm, night blue), saturation, vignette, film grain on the art-pixel grid at 12 fps. **M3:** the lighting keys stretch to each season's sunrise/sunset, and a per-season tint/saturation (`visuals.seasonGrade`) sits on top. |
| `ground.glsl` (was `snow.glsl`) | **M3, D83** | The ground canvas's weather coat in one pass: **snow** (clumpy pixel coverage that ramps in after the freeze and melts after the thaw, `visuals.snow*`), **wet ground** (darker, richer, banded sky-coloured puddles with a glint pixel on their upper edge; `visuals.weather.wet`) and **frost** creeping up to `frostReach` pixels in from the creek bank in ragged steps, over bare ground and snow (`visuals.frost*`; it follows the creek's ice amount). World-anchored (D80): every position comes from the texture coordinate times `groundSize`, never `vertex_position` (LÖVE transforms streamed vertices on the CPU, so it is already screen space). `precision highp` on GL ES. |
| `snowcap.glsl` | **D83** | Snow resting on the tops of objects: drawn instead of the sprite while it snows. A pixel is "top" when a transparent pixel (or the edge of its atlas cell, passed as `bounds`) is within `capDepth` pixels straight above; coverage follows the ground's snow amount, ragged by a per-pixel hash (`visuals.snowCapDepth`). Needs no art: it reads the sprite's own silhouette. |
| `clouds.glsl` | **D83** | Cloud shadows: one translucent quad over the visible tiles after the y-sorted pass, before the grade. Position from the texture coordinate over `rect` (world art pixels), snapped to `block`-pixel blocks and cut into three bands. Cover from the weather kind's `cloud` (the same number that dims solar), drift from `Weather.windStrength` (eased, so a gust never jumps the pattern), faded out at night (`visuals.weather.clouds`). |
| Rain (`weather_fx.lua`) | **M3** | Not a shader: streaks and splash rings drawn as art-pixel squares on the world grid, scaled by camera zoom, so size, speed and density match at every zoom and window size (`visuals.weather.rain`, all in art pixels; D80). D83: splash rings sit in world cells on the ground (none on water: the creek shader draws its own). |
| Wind sway | Planned | Vertex shader bending crops, brush and tree canopies with gusts; strength from weather. |
| Night lights | Planned (M3) | Light-map canvas: lamp/window/stove/campfire glows that punch through the night grade. |
| Morning mist | Planned | Low fog band over the creek and fields at dawn. |
| Heat shimmer | Planned | Summer midday distortion near the horizon/fields. |
| Fireflies / dust motes | Planned | Particle + glow on summer evenings. |
| Tilt-shift | Planned (widget mode) | Blur toward the top/bottom of the frame for a diorama feel on the desktop companion. |
| Selection outline | Planned | Pixel outline for hovered/selected objects instead of tile boxes. |
| Fishing water | Planned (M2) | Close-up underwater view for the tension mini-game (cutaway, light rays, fish silhouettes). |

### Shader audit (#193, D83)

Camera correctness is the main trap. In LÖVE 11 a **streamed** draw (`rectangle`, `draw(image)`, `draw(canvas)`)
has its vertices transformed by the current transform **on the CPU**, so `vertex_position` in a vertex shader is
already screen space; a **SpriteBatch or Mesh** is transformed on the GPU, so `vertex_position` is the local (world)
position. Verified with a test draw under a translate (batch gave world, rectangle gave screen). Anything that must
move with the land takes its position from a texture coordinate over a known world rectangle instead.

| Effect | Anchoring | Intent | Notes |
|---|---|---|---|
| `water.glsl` | **World** (SpriteBatch, so `vertex_position` is world space; the ripples, foam and rain rings pan with the creek) | World | Fixed: added `precision highp` on GL ES (world pixels reach the thousands). Snapped to art pixels, banded. |
| `ground.glsl`, `snowcap.glsl`, `clouds.glsl` | World (texture coordinate over the ground canvas / sprite cell / `rect`) | World | `precision highp` on GL ES. All snap to the art-pixel grid. |
| `grade.glsl` | Screen | Screen (tint, vignette, grain) | Grain cells are `pixelSize` screen pixels, so they match the art pixels' size but not their phase (deliberate: grain is a lens effect). Fixed: `precision highp` on GL ES (the seed grows with `time * 12 * 13.7` and overflowed mediump). |
| Rain streaks (`weather_fx.lua`) | Screen | Screen (air) | Art-pixel sized and scaled by the zoom (D80). Splash rings are now world cells (D83): they stay on the ground they hit. |
| Action ring, power lamps | Screen / world sprites | by intent | Not shaders. |

Performance (desktop, zoom 2, uncapped, 150 draws of the whole scene incl. the HUD, headless-ish GPU readback): about
0.85 ms per frame clear, 0.8 ms with cloud shadows, 1.1 ms raining, 1.2 ms in snow with caps and frost. The ground shader
only runs when snow, wet or frost is non-zero; while the creek is frozen the frost searches four directions up to `frostReach` pixels (at most 16 taps per ground pixel, only when frost is
non-zero); the snow cap shader is set per object only while it snows.
Not yet profiled on a phone GPU: the tight loops are fixed-bound for GLSL ES, but check F3 on a real device (#193).
