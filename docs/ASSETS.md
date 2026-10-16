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
  daylight colours. Light every sprite from the top-left (D136): a lit face up and left, a darker face
  down and right, and a dark outline round small sprites. The shaders add the sun's edge and a cool form
  shade on top. Keep the value plan: light, calm ground; deep, cool foliage and objects; strong red only
  on the homesteader and a few key things. Paint foliage as lit clumps, not random speckle.

## Sprites

Legend: **M1** = in the game now (placeholder) · **M2–M7** = needed by that milestone.

### Terrain & ground (16×16)

| Id | Variants | Status | Notes |
|---|---|---|---|
| `grass` | 4 | M1 | Base ground. Seasonal versions later (summer dry, autumn, snow). A scattered texture, tufts and broad light/dark patches were tried and dropped (D136). |
| `road` | 2 | M1 | Dirt road. |
| `tilled_dry` / `tilled_wet` | 1 each | M1 | Furrowed soil; wet is darker. |
| `ford_stones` | 1 | M1 | Transparent overlay of stepping stones drawn over water. |
| `plan_marker` | 1 | Retired (D142) | Planned tiles are now a pencil sketch (`src/render/sketch.lua`). |
| Grass→dirt / grass→water transition tiles | autotile set | M7 | Today the creek edge is handled by the water shader's foam. |
| Snow ground, frozen water | — | M3 | Done as shaders (`ground.glsl`, `snowcap.glsl`, `water.glsl` ice) over the normal tiles. |

### Objects

| Id | Size | Status | Notes |
|---|---|---|---|
| `brush` | 16×16 | M1 | Messy-start clutter. |
| `rock` | 16×16 | M1 | |
| `log` | 16×16 | M1 | Fallen log. |
| `junk` | 16×16 | M1 | Crate, tire, sheet metal. Gives scrap + a few dollars. |
| `tree` | 16×32 | M1 | Oak placeholder drawn as lit leaf clumps with an outline (D136). Needs seasonal variants (bare in winter). |
| `pine` | 16×32 | D135 | Conifer: narrow tiers, stays green in winter. Placeholder; needs seasonal art for snow. |
| `birch` | 16×32 | D135 | Pale spotted trunk, light airy crown. Placeholder; needs bare-winter and autumn variants. |
| `truck` | 32×24 | M1 | Electric pickup, 2×1 footprint. Later: charging cable, cargo states, trailer. |
| `trip_marker` | 11×12 | D101 | Gold down-arrow bobbing over the truck cab while a trip is ready and the player is home; static under reduce motion. |
| `folding_panel` | 16×16 | M2 | Starting gear, placed beside the truck. |
| `smoker` | 16×24 | M2 | Smoke puffs are drawn by the renderer while a batch runs. |
| `campfire` | 16×16 | M3 | Starting kit, placed beside the truck. |
| `woodshed` | 32×24 | M3 | 2×1 footprint; dry wood storage (D104). |
| `wood_stove` | 16×24 | M3 | Better heat source than the campfire. |
| Sell crate, delivery drop-off | 16×16 | Later | The crate is only a HUD count for now; deliveries appear instantly. |
| Woodpile / woodshed | 16×16 / 32×32 | M3 | Firewood stock shown visually. |
| `camp` 32×32 (2×2 footprint, canvas lean-to with a bedroll), `shack` 48×32 (3×2, plank walls, tin roof, stove pipe, a window that reads lit), icons `icon_camp`, `icon_shack` 12×12 | M5 (placeholder) | Shelter ladder (#198, D82). Needs: real tent and shack art, smoke from the shack chimney, a lit window at night as input for the night-lights shader (#193), a cabin and workshop later. |
| Cabin | 48×48+ | Later | #198 later tiers. |
| `well` 16×24, `hand_pump`, `dc_pump`, `drip_line` 16×16, `cistern` 32×16 (2×1) | various | M5 (placeholders) | Water ladder (#35). Icons `icon_<object>` are 12×12. Needs: handle and bucket animation, cistern water levels (a code-drawn gauge today), pump on/off art, hose lines for the drip line (a status lamp and zone tint today). See #94. |
| `solar_array` 32x16 (2x1), `battery_bank`, `micro_hydro`, `generator`, `electric_heater`, `lamp`, `chest_freezer` 16x16, `wind_turbine` 16x32 | various | M5 (placeholders) | Power network (#34). The turbine needs blade animation; the generator, heater and freezer need on/off art states (today a status light is drawn over them, see `visuals.powerLamp`). Icons `icon_<object>` and `icon_fuel` are 12x12. |
| Roadside stand `roadside_stand` 32×24 (2×1 footprint, tall awning), icon `icon_roadside_stand` 12×12 (reused for the three upgrade icons) | M5 (placeholder) | Roadside stand (#37). Needs: real awning and table art, goods that show what is on sale, upgrade looks: placeholder overlays stand_sign_look, stand_cooler_look, stand_display_look (32×24, transparent, drawn over the stand while the upgrade is owned, D116; real art in #107). |
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
| `cue_droplet`, `cue_ready_1..2` | D102 | Thirsty droplet (7x9) and ripe sparkle frames (7x7), drawn over the graded world above the tile's top right. |
| `plan_marker` | Retired (D142) | Was a dashed frame with a faint `<crop>_1` ghost; plans are now pencil sketches of the ripe crop. |
| More crops | M6–M7 | Carrots, beans, squash, corn (tall), greenhouse crops. |

**Readability rules for crop and small-sprite art (#20, D102).** Give every crop stage a dark 1-pixel edge and a bright interior (the placeholder `p:outline(C.outline)` does this), keep the sprout at least about 8 pixels wide, and make stages differ by silhouette, not tint alone. The night grade multiplies colour, so contrast must come from the art and from `visuals.cropCues.nightLift`; do not rely on hue. The thirsty droplet and ripe sparkle are separate sprites drawn by the renderer, so real crop art should not paint them in. Tune in `data/tuning/visuals.lua` (`cropCues`) and check with `lovec tools/driver crops`.

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
| `icon_wx_clear`, `icon_wx_cloudy`, `icon_wx_rain`, `icon_wx_windy`, `icon_wx_storm` (12x12 top-bar weather chip glyphs, D112: keep the five silhouettes distinct so a kind is never told by colour alone) | M3 |
| Journal node icons (one per catalog item / perk), Note stamps. Placeholders so far: `icon_note_blank` (unwritten note), `icon_spoiled` (fish gone off); other notes reuse existing icons | M3 |
| `icon_<fish id>` for all 7 species (one tinted placeholder painter), `icon_unknown`, `icon_battery`, `icon_crate`, `icon_rod`, `icon_bait`, `icon_smoked_fish`, `icon_smoker`, `icon_folding_panel` | M2 |
| `bobber` (8×10) for the fishing mini-game | M2 |
| `icon_cold`, `icon_axe`, `icon_campfire`, `icon_woodshed`, `icon_wood_stove` | M3 |

### Interface icons (12×12, D142)

Drawn from rows of palette letters in `placeholders.lua` (`rows`), lit from the top left with a warm dark
outline; tools lie on one diagonal, handle bottom left. `src/ui/icons.lua` picks a tool's icon by the
tier owned and draws icons at whole-pixel scales (1x on the HUD, 2x in the tool wheel).

| Id | What |
|---|---|
| `icon_tool_hand`, `icon_tool_hoe`, `icon_tool_pail`, `icon_tool_pail_big`, `icon_tool_hatchet`, `icon_tool_axe`, `icon_tool_rod`, `icon_tool_rod_sturdy`, `icon_tool_hammer` | Tools and their owned tiers |
| `icon_verb_move`, `icon_verb_pickup`, `icon_verb_demolish`, `icon_verb_untill` | Verbs (Demolish on red) |
| `icon_signal_alert`, `icon_signal_idea` | Round amber decision stamps |
| `icon_book_notebook`, `icon_book_ledger`, `icon_menu` | The two books and Menu |
| `icon_packet`, `icon_packet_<crop>` | Seed packets: the template plus the crop's own icon shrunk onto it (radish, potato) |

### Fonts

`src/ui/pixel_font.lua`: a hand-made pixel font (7 px caps, 2 px descenders, printable ASCII plus
`· × ° → …`), built into a LÖVE ImageFont at load. `src/ui/text.lua` draws it at whole UI pixels per font
pixel (`theme.textScale`: small and body 1, heading 2, title 3) with a warm dark shadow one pixel down and
right. `tests/test_pixel_font.lua` fails if content or tuning text uses a character with no glyph.
Accented letters are still to add.

## Audio

Sounds are cues in `game/data/content/sounds.lua`, played from synthesized placeholders until files are dropped into `game/assets/audio/<bus>/<cue>.ogg`. The cue list, formats, loudness, loop rules and replacement steps are in [AUDIO.md](AUDIO.md) (GDD D100). Audio, like render, never changes the sim and stays outside `src/sim`.

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
| `sway.glsl` | **D84** | Wind sway of crops, brush and tree canopies, drawn in place of the plain sprite (not while a snow cap is on it). Each row is shifted sideways by a whole number of art pixels, growing toward the tip (`root` share of the sprite stays still: a trunk does not bend), on a quad padded a few pixels so the tip is not clipped, with sampling clamped to the sprite's own atlas cell. Strength and speed from `Weather.windStrength` (eased; the sway clock accumulates, so a gust never jumps the pose), per-plant phase from the tile (a gust rolls across the field) carried in the vertex colour so there is no per-plant uniform. Content field `sway = { weight, root }` on objects; crops in `visuals.wind.crop` (`visuals.wind`). |
| `mist.glsl` | **D84** | Morning mist: one translucent quad over the visible tiles after the sprites, before the grade (so dawn warms it). Banks of blocky banded noise drifting downwind, thickest on the creek and within `reach` tiles of it (a per-tile distance map baked in `Renderer:buildWater`). Strength = time of morning (forms `preHours` before sunrise, burns off after `holdHours + fadeHours`) x calm air (gone by `windKill`) x damp (stronger after rain) x frozen creek (`visuals.mist`). |
| `shadow.glsl` | **D127** | Sun shadows: every y-sorted sprite's silhouette, auto-generated (no art), flipped onto the ground and sheared away from the sun, drawn solid into a mask canvas with one texel per world art pixel (so the sheared edges step on the art grid, D132) and composited once by `shadow_composite.glsl` in the shadow colour, so overlapping shadows never double. Sun side and height come from `Lighting.sun` (real hour, season's sunrise and sunset): shadows lean west at dawn, shorten to a squat blob at noon, lean east at dusk, fade near the horizon, thin under cloud and vanish at night. A small stepped contact shadow sits under everything (hens and goats included, D132), goes into the same mask (green channel) so it merges with the cast shadow instead of stacking, and stays at night. Crops cast too (no contact shadow). Content flag `flat = true` (drip line, sprinkler) casts nothing. Drawn after mist, before the sprites (`visuals.shadows`). |
| `shadow_composite.glsl` (D136 changes) | **D136** | The composite now MULTIPLIES the ground toward `shadows.color` (a cool blue-violet) instead of laying a translucent dark tone on it, so shade keeps the ground's hue, and the cast shadow is solid (`dither.shadows.amount = 0`; the editor can bring the stipple back). The mask's contact channel also takes stepped ambient-occlusion rings round each object's base (`shadows.ao`) and a wide ellipse under each tree in a stand (`visuals.forestFloor`), drawn with a max blend so they pool instead of stacking. |
| `rim.glsl`, `sway.glsl` (D136 sun lighting) | **D136** | Every season, plain sprites, crops and canopies catch the sun: a faint warm edge on the sun side (`sunlight.lit`, mixed with the autumn rim when both show) and a cool form shade one or two pixels deep on the side away from the sun and along the bottom (`sunlight.shade` in direct sun, `ambientShade` at night and under cloud). The outline stays dark. `visuals.sunlight`. |
| `shadow_composite.glsl` | **D132** | Lays the shadow mask over the ground in one translucent pass: alpha = max(cast x the sun's strength, contact x `contactStrength`). Blue in the mask marks a tree canopy's cast shadow (content flag `dapple = true`): it is shaded deeper (`dapple.shade`) and sun flecks show through it, two-step pixel blobs from world-anchored noise that shuffle a whole art pixel at a time on the wind-sway clock (still under reduce motion). `visuals.shadows.dapple`. |
| `include/dither.glsl` | **D133** | Shared dither helpers (`ditherQuantize`, `ditherMask`) with seven patterns (none, Bayer 2/4/8, blue noise, interleaved gradient noise, white), used by `light`, `grade` (heat shimmer and vignette), `shadow_composite`, `clouds`, `mist` and `sunbeams`; `#include "dither"` is expanded by `Shaders`. Each effect passes a vec4 from `tuning.visuals.dither.<effect>` (`src/render/dither.lua`). Always feed it a world art-pixel coordinate so the pattern stays on the land. Edit the settings live in the in-game editor (F8). |
| `rim.glsl` (and `sway.glsl`) | **D132** | Autumn rim light: a warm line along the sun side of each sprite on clear afternoons. A pixel is rim when its neighbour toward the sun is empty, or is the dark outline (`inkLuma`) with empty beyond, so the light sits just inside the outline and the outline stays dark. The top edge always catches some (`top`; the sun is up-screen, the way shadows fall), the sunward side more as the sun moves off noon (`sideGain`). Strength by season (`seasons`, autumn only by default), stronger at low sun (`noonShare`), gone under cloud and at night. Plain sprites draw through `rim.glsl` (one shader for the whole y-sorted pass, so they still batch; mirrored hens and goats flip `rimSide`); crops and canopies get the same rim inside `sway.glsl`, worked out on the swayed picture. `visuals.rim`. |
| `sunbeams.glsl`, `ground.glsl` (D131 additions) | **D131** | Sunbeams and sun sparkle. Slanted shafts of warm light run the way the shadows fall (`Renderer:drawSunbeams`, additive over the graded frame before the bloom, world-anchored, snapped to blocks and cut into three bands), strongest at a low sun, gone at noon, in rain and under cloud, thicker in morning mist. Single pixels of snow and puddle flash white in direct sun (`Renderer:sunGlint`, `ground.glsl`), stepping on a few times a second. Morning fog needs nothing new: `mist.glsl` (D84) already hazes the creek bank and low ground. Reduce motion stills the drift and the flashing. Tuning: `visuals.sunbeams`, `visuals.sparkle`. |
| `water.glsl` (D130 additions) | **D130** | Water reflections and sky. Objects standing on the bank (open water within `reflections.reach` tiles below their feet) are drawn flipped, squashed and sprite-exact into a reflection canvas with one texel per world art pixel (`Renderer:drawReflections`, D132); the water shader reads it by world art pixel, so only water shows it, shifted sideways by whole art pixels along rippled rows, tinted darker and bluer, fading toward deep water and with ice. The water also takes on a sky colour on its ripple crests, scaled by daylight. Reflections mirror about the object's feet, so only things on a bank north of the water reflect; the sky tint covers the rest. Tuning: `visuals.reflections`. |
| `bloom_bright.glsl`, `bloom_blur.glsl` | **D129** | Bloom and emissive pass. The graded frame, lit window pixels, a small hot core at the centre of each flame or bulb (`visuals.lights.coreSize/coreGlow`) and the fireflies are drawn into a screen-sized canvas (`Renderer:gradedBuffer`). Bright pixels (brightest channel above `threshold`, soft knee) are cut out at 1/4 size, blurred with a separable 9-tap gaussian at 1/4 and 1/10 size, and added back over the frame (`Renderer:drawBloom`, `visuals.bloom`). Weak in daylight, up to about 6x stronger at night, scaled by the gradeStrength setting. Crop cues, the selection outline, rain and the HUD are drawn after it and never glow. Falls back to the plain path if the shaders do not compile or `bloom.enabled` is off. |
| `grade.glsl` (D128 additions) / `light.glsl` | **D128** | Light buffer and split-toned grade. The night light pools are painted additively into a light buffer with one texel per world art pixel (`Renderer:paintLights`, black where unlit, D132) BEFORE the grade, and the grade reads it: `c * tint*light + grey-pulled(c) * pool*gain + pool*glow` (the lit colour is pulled toward grey by `lights.neutral`, so firelight on grass reads warm, not olive), so a fire brightens and warms the grass, path and walls it reaches with their own texture (the old pass added a flat glow on top). Lit window pixels stay additive after the grade (`drawEmissive`). The grade also does split toning (cool darks, warm brights), an S-curve contrast and a tinted black lift (`visuals.tone`, scaled toward neutral by the gradeStrength setting). |
| `light.glsl` | **D84** | Night lights: one additive quad per lit object, drawn over the GRADED world (after `grade.glsl`) so it glows on top of the night. Banded falloff with a 2x2 ordered dither on the art-pixel grid, slightly flat; radius flickers in whole art pixels. Which objects glow is the content field `light = { on, radius, color, flicker, at, windows }` (`on` = "heat" while the night needs warmth and there is fuel, "power" while a lamp is running, "shelter" for the shelter the homesteader sleeps in); read through `src/render/lights.lua`, never changing the sim. Lit-window pixels (`windows`) are added at full brightness. Fade in with the daylight level (`visuals.lights`). |
| Heat shimmer (`grade.glsl`) | **D85** | Rides in the grade pass: the picture is sampled one whole art pixel left or right in patches that climb (world-anchored on the art-pixel grid: `gridOrigin` + `worldCell` uniforms), over the land on a hot clear summer noon (`Ambient.heatAmount`: season x sky x distance from solar noon x no snow) and in a fading column above each lit stove or campfire (up to 4, `heatSources[4]`, from `Lights.visible`). Nothing is drawn when both are off (the branch is a uniform test). `visuals.heat`. Not limited to ground: the wobble moves sprites too. |
| Fireflies, dust motes (`ambient.lua`) | **D85** | Not shaders: art-pixel squares in world cells, a pure function of the cell hash and the render clock (no `math.random`), so they pan and zoom with the land. **Fireflies**: additive warm dots with a soft 4-pixel halo, wandering and pulsing, on summer (less in spring and autumn) evenings from just before sunset to ~4 h after, on grass only and likelier beside the creek (`Renderer.reach`); not in rain or a gale. **Dust motes**: pale 1-pixel specks (longer streaks in a gale) drifting downwind (`weather_fx` accumulates `dustDrift`), by daylight on dry ground, more in wind, none under rain or snow; they fade along their path so the cell wrap is never seen. `visuals.fireflies`, `visuals.dust`. Cost: a few hundred `rectangle` calls at most, only while active. |
| Depth of field (`grade.glsl`) | **D132** | Optional (Settings > Visuals > Depth of field, off by default). Toward the top and bottom of the view the picture is softened in `steps`, each art pixel averaged with its neighbours one, then two art pixels away, sampled at art-pixel centres, so every screen pixel of an art pixel gets the same colour and the result stays blocky pixel art rather than a smear. `visuals.depthOfField`. A stronger diorama tilt-shift for the planned desktop widget mode can reuse it. |
| Selection outline (`Renderer:drawSelection`) | **D85** | Not a shader: a pixel ring round the selected object's whole footprint (or the tile), a dark ring just outside, an accent ring, brighter corner brackets, and a slow alpha breath. Drawn over the graded world on the art-pixel grid so it reads at every zoom and at night; thickness is `max(thickness, ceil(minScreen / pixelSize))` so it never thins below `minScreen` physical pixels. Replaces the tile box for the selected tile; the hover box (mouse only, never needed) and planning boxes are unchanged. `visuals.selection`. |
| `ui_plate.glsl` | **D142** | HUD, panel and button plates: the graded world, blurred (`src/ui/plate.lua` copies it at 1/`ui.plate.blurDivisor` and blurs it) and cut into levels with the shared dither on the UI pixel grid (`visuals.dither.plate`), pulled toward the plate colour, tinted by `ui.plate.gradeShare` of the grade and dimmed at night (`nightDim`). Dark outline, lit top-left edge, cool bottom-right shade, stepped corners. Frost from the corners on frozen days and snow along the top edge (not on plates under `snowMinSize`), off with Ambient effects. Text and icons are drawn over it, never graded. With no world behind (title, slots) the plate is solid. |
| `sketch.glsl` + `src/render/sketch.lua` | **D142** | Plans in pencil (#292): planned, untilled tiles get a diagonal hatch and every planned area a pencil outline that overshoots its corners, both cut from one small white atlas built from `visuals.sketch` and tinted per tile (graphite, or amber when the crop cannot ripen before winter), so a field is one batch of same-texture draws. The planned crop's ripe sprite, placement ghosts (tinted by the D79 preview: ok, clear first, refused, upgrade) and queued orders go through `sketch.glsl`: the silhouette edge is a pencil line, the art's dark outline a second stroke, the inside a light hatch over a faint wash. At night the plans are drawn again over the graded world in pale chalk, scaled by the crop-cue night lift. |
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
| `sway.glsl`, `mist.glsl`, `light.glsl` | World (sprite cell / `rect` over the texture coordinate; the lights are drawn in the camera transform after the grade) | World | D84. `precision highp` on GL ES (the sway clock and world positions are large). Sway offsets, mist blocks and light pixels all snap to whole art pixels. Lights are additive over the graded image on purpose: they punch through the night grade instead of being darkened by it. |
| `grade.glsl` | Screen | Screen (tint, vignette, grain) | Grain cells are `pixelSize` screen pixels, so they match the art pixels' size but not their phase (deliberate: grain is a lens effect). Fixed: `precision highp` on GL ES (the seed grows with `time * 12 * 13.7` and overflowed mediump). |
| Rain streaks (`weather_fx.lua`) | Screen | Screen (air) | Art-pixel sized and scaled by the zoom (D80). Splash rings are now world cells (D83): they stay on the ground they hit. |
| Action ring, power lamps | Screen / world sprites | by intent | Not shaders. |

Performance (desktop, zoom 2, uncapped, 150 draws of the whole scene incl. the HUD, headless-ish GPU readback): about
0.85 ms per frame clear, 0.8 ms with cloud shadows, 1.1 ms raining, 1.2 ms in snow with caps and frost. The ground shader
only runs when snow, wet or frost is non-zero; while the creek is frozen the frost searches four directions up to `frostReach` pixels (at most 16 taps per ground pixel, only when frost is
non-zero); the snow cap shader is set per object only while it snows.
Not yet profiled on a phone GPU: the tight loops are fixed-bound for GLSL ES, but check F3 on a real device (#193).

### Effect clock (#236, D97)

`src/render/effect_clock.lua` gives the renderer two clocks, both fed in `Renderer:update(dt, speed)` with the session's
`effectiveSpeed()`. **World time** (`renderer.time`, `fx.time`) advances by `dt * min(speed, effectClock.maxSpeed)`: it
stands still while paused (player pause, tip card D92, town D78), runs 1x/2x with the speed button, and is capped at 2x (`maxSpeed = 2`, #265) so 4x play and the
sleep fast-forward (8x) look like 2x and nothing strobes. **Real time** (`renderer.uiTime`) always runs. Only the
rate changes, never the value, so pausing and speed changes cause no jump. Tuning: `visuals.effectClock` (`maxSpeed`,
`wrap`); `Renderer:update` re-reads it every frame, so F6 applies at once.

| Effect | Clock | Why |
|---|---|---|
| Flame, stove, lamp flicker (`light.glsl` flicker step) | World | A fire in a frozen world must freeze |
| Heat shimmer, film grain (`grade.glsl` `time`) | World | Grain refreshes with game time, so a paused frame is perfectly still |
| Water ripples, foam, rain rings (`water.glsl` `time`) | World | |
| Cloud shadows, wind sway, mist drift, dust drift (`weather_fx`) | World (drift and sway integrate `dt * speed`) | Also scaled by the eased wind |
| Rain streaks and splashes (`fx.time`) | World | Rain hangs in the air while paused |
| Fireflies and dust glow (`ambient.lua`, `fx.time`) | World | |
| Smoke puffs, sleep Zs, machine arm wobble, hens and goats | World | |
| Weather look easing (tint, light, wind, wet) | Real | A state blend toward the sim's weather, not an animation; it settles exactly (snaps within 1e-4), so a held frame stops changing |
| Selection ring breath (`drawSelection`) | Real | UI: shows the ring is live and selectable while paused. Kept running rather than frozen: a frozen ring reads as a drawn border and loses the "this is selected" cue |
| Highlight rings (FTUE), button pulses (Routine nudge), toasts | Real | UI, stays alive while the game is held |

Reduce motion and ambient effects (D96) still gate the effects as before; they only change whether an effect draws.
Screenshots `docs/screens/clock-*` (scenario `clock`: paused frames are asserted byte-identical at all three sizes).
