# Performance and save size (#19, #77, #132, #21; D103)

What is measured, the numbers before and after the first optimisation pass, the budget, and what still has to
be measured on a phone. Source of truth for the budget numbers is `game/data/tuning/perf.lua`.

## How to measure

| Tool | What it gives |
|---|---|
| `lovec tools/perf [policy=active] [warm=84] [ticks=2000] [set=world.mapWidth=192 set=world.mapHeight=128]` | Plays a harness policy to a mid-game state, then reports the sim's wall ms per tick (mean, p50, p95, p99, max, ticks over 1 and 4 ms), the per-system split, allocation per tick (GC stopped, per system), object counts, and the save file's size and write/read time. Headless. Timing is wall-clock: compare only runs from one machine. Allocation and size are deterministic. |
| `lovec tools/driver perf size=both` | CPU time of a busy homestead frame (update, and draw = submit time, not GPU) at each zoom, clear and rainy, for desktop, phone and landscape views. Needs a window. |
| F3 overlay (in the game) | Three lines under FPS: `Sim` ms per tick and ticks per frame, `Worst tick`, `Update` and `Draw` ms. A figure over the budget below gets "OVER". The probes only run while the overlay is open (`src/core/perf.lua`). |
| `lovec tools/balance ... profile=1` | LuaJIT sampling profile of whole runs (see BALANCE.md). |
| `lovec tests perf_budget` | Allocation budget and the equivalence tests for everything below. |

The warm-up state of `tools/perf` (default `warm=84`, three years of the `active` policy, seed 1) has 1099 objects
(954 trees, a coop, pump, cistern, two drip lines, solar, wind turbine, battery, freezer, smoker, lamp). The big
map is 192x128 (9 times the tiles, 9275 objects) from `set=world.mapWidth=192 set=world.mapHeight=128 warm=42`.
Goats and the auto-harvester are not bought by any harness policy yet, so they are not in the measured state.

## Baseline and result (desktop, Windows, one thread)

Sim, 12000 ticks (about 10 in-game minutes) of the typical state; 6000 ticks of the big map:

| | typical before | typical after | big map before | big map after |
|---|---|---|---|---|
| mean ms per tick | 0.037 | 0.023 | 0.027 | 0.015 |
| p95 ms per tick | 0.072 | 0.032 | 0.158 | 0.022 |
| ticks over 1 ms | 62 | 41 | 4 | 3 |
| worst tick ms | 7.0 | 4.2 | 12.9 | 8.6 |
| mean allocation KB per tick | 6.5 | 0.58 | 5.9 | 0.47 |
| worst tick allocation KB | 329 | 190 | 1226 | 33 |

Timing varies run to run (the worst tick moves by several ms between identical runs: it is the idle job search
on a recheck tick and the new-day work, not a steady cost), so read the means, p95 and allocation, which are
stable. The sim was never the bottleneck at 20 ticks a second: even 8x sleep is 160 ticks a second at
about 0.03 ms. The mean is about 1 percent of a 60 fps frame at 1x.

Balance harness, `policy=scripted,active seeds=5 years=1 jobs=1`: 52.8 s before, 28.9 s after (1.8x), results
byte-identical (below).

Frame, desktop window 1280x720, CPU milliseconds per frame (150 frames after a warm-up, busy homestead, day 1
afternoon): update 0.15 to 0.2; draw at zoom 1 (the widest view, about 1000 trees on screen) 1.9 clear and 2.5 in
rain, at zoom 2 about 0.9 to 1.1, at zoom 3 about 0.75 to 0.85. Phone and landscape views are the same within
noise at zoom 1 (1.8 to 2.9); the one 100+ ms "worst" is the first rainy frame compiling the weather shader.
Before the pass, zoom 1 draw was 2.65 clear, 3.65 rain; the gain is `Needs.heatEfficiency` (the HUD asked it every
frame by scanning all objects, now the cached index) and a per-frame definition cache in the renderer.

Save file, `Save:write` and `Save:read` of the typical state (mean of 5):

| | before | after |
|---|---|---|
| typical map 64x48, bytes | 297,992 | 101,758 (-66 percent) |
| typical write / read ms | 9.2 / 6.6 | 5.4 / 2.1 |
| big map 192x128, bytes | 2,217,178 | 655,491 (-70 percent) |
| big write / read ms | 55.8 / 25.1 | 32.7 / 12.5 |

The grid arrays were 74 percent of the file (terrain 34 KB, soil 62 KB, water table 62 KB at 64x48). What is
left is mostly `grid.objects` (37 KB at 64x48, 330 KB at 192x128, mostly trees): see follow-ups.

## Homestead depth check (M8, #392, D203), desktop

`lovec tools/perf ticks=12000` (active, seed 1, warm 84 days) after the M8 systems (soil fertility per tile, pest
pressure, weeds, compost, quality, perennials, night threats, dog, lantern, contracts, tiers). The default map is now
128x80 (10,240 tiles, 3363 objects), so the 64x48 row (`set=world.mapWidth=64 set=world.mapHeight=48`) is the one to
read against the D103 "typical after" column above. The probe now keeps the harness policy's morning (an event handler
inside the calendar's tick) out of the sim figures; before, up to 4 ms and 65 KB of the "calendar" worst tick were
the policy, not the sim.

| | D103 typical (64x48) | M8, 64x48 | M8, default 128x80 |
|---|---|---|---|
| mean ms per tick | 0.023 | 0.022 | 0.070 |
| p95 / p99 ms per tick | 0.032 / - | 0.037 / 0.119 | 0.085 / 2.3 |
| ticks over 1 ms (of 12000) | 41 | 5 | 212 |
| worst tick ms | 4.2 | 1.8 | 4.3 |
| mean allocation KB per tick | 0.58 | 0.75 | 0.78 |
| worst tick allocation KB | 190 | 73 | 172 |
| save bytes on disk | 101,758 | 115,690 | 307,233 |
| save write / read ms | 5.4 / 2.1 | 6.5 / 3.0 | 16.4 / 7.5 |

All inside the budget below. No M8 system is a hot spot: of the new per-tick and per-day work, threats is 0.003 ms a
tick and the heaviest new-day handler (soil) 0.22 ms and 12 KB; the night threats, dog and cat stay under 1 ms at worst.
What grows with the bigger map is the idle job search (`actors`: 0.045 ms a tick mean at 128x80 against 0.003 at
64x48, and the 212 ticks over 1 ms), the follow-up below, not an M8 cost.

Save size: the M8 grid array `fertility` packs like `soil` and `waterTable` (Gridpack, whole hundredths): 8 KB of
the 64x48 file and 26 KB of the 128x80 one. The 64x48 file grew 14 KB (14 percent) since D103, about 8 KB of it
fertility. The biggest part now is `grid.objects` (118 KB of 307 KB at 128x80, 28 KB of 116 KB at 64x48, almost all
trees, brush and rocks holding only an id), which is what #248 (object packing) targets: anchor lists per id would
leave a few KB, so about a third of the 128x80 file. `tools/perf` now prints every grid part over 1 KB both plain and
as the file holds it, and the largest sections of the file, the run and the meta as written.

The F3 overlay shows the same sim figures in a window; it was not read for this check (headless only).

## Lighting and shader pass (D127-D131), desktop

Wall-clock ms per frame with vsync off and every frame presented (so the GPU is in the number), 300 frames, busy
homestead, clear sky, 1280x720, before the pass (commit 4715bf9) and after. `lovec tools/driver wall size=desktop`;
`lovec tools/driver perf` also prints the same with each pass switched off in turn (`wall ...` and `cost ...`
lines; `visuals.<pass>.enabled`), and CPU submit time at dusk.

| | before | after | added |
|---|---|---|---|
| noon, zoom 1 / 2 / 3 | 5.29 / 2.75 / 2.48 | 6.15 / 3.84 / 3.68 | 0.9 / 1.1 / 1.2 |
| dusk, zoom 1 / 2 / 3 | 5.05 / 3.83 / 3.00 | 6.11 / 4.45 / 3.67 | 1.1 / 0.6 / 0.7 |
| night, zoom 1 / 2 / 3 | 5.32 / 3.35 / 2.76 | 6.76 / 4.06 / 3.51 | 1.4 / 0.7 / 0.8 |

So the whole pass costs about 1 ms a frame on this desktop GPU and the game still runs at 150 to 300 fps. The
per-pass split is below the noise of the measurement (each pass is 0.2 to 1 ms and the order changes between
runs), so read it as: the full-screen canvases (shadow mask, light buffer, graded frame, bloom at 1/4 and 1/10
size) are a roughly fixed cost that does not shrink when zoomed in. CPU submit time at zoom 1 rose from about
2.3 to 3.6 ms (clear), mostly the one extra pass over the objects for the shadows and reflections and the
canvas switches; the sway shader's per-sprite draws (1.4 ms of it) were already there. On a phone expect the
canvases to matter most: `bloom.enabled`, `bloom.tightDivisor` and `bloom.wideDivisor`, `reflections.enabled`
and `shadows.enabled` are the levers; none of this has been measured on a phone. (D132 has since shrunk the shadow
mask, light buffer and reflection canvas to art resolution; see below.)

## Lighting polish (D132, #283), desktop

The shadow mask, light buffer and reflection canvas went from one texel per screen pixel to one per world art pixel
(`Renderer:artGrid`). On a 1280x720 window at UI scale 2 that is 921,600 texels each before, and about 232,000 /
58,000 / 26,000 at zoom 1 / 2 / 3 after (pixelSize² fewer). Same wall probe, same machine, before (this branch's
base, 9622cfd) and after, which also adds leaf dapple, animal shadows and the pool and rim changes:

| | before | after |
|---|---|---|
| noon, zoom 1 / 2 / 3 | 6.03 / 3.24 / 3.13 | 6.13 / 3.40 / 3.26 |
| dusk, zoom 1 / 2 / 3 | 5.88 / 4.05 / 3.30 | 6.38 / 3.99 / 3.39 |
| night, zoom 1 / 2 / 3 | 6.55 / 4.04 / 3.46 | 6.76 / 4.01 / 3.59 |

Within run-to-run noise (0.1 to 0.5 ms): this desktop GPU is not limited by fill rate, so smaller canvases do not
show, and the extra work (the composite, rim and dapple) costs about as little. The win is for phones, where fill
rate and memory bandwidth are the limit: three of the five full-screen canvases are gone. What is left at screen
size is the world canvas, the graded canvas for the bloom (`bloom.enabled` off removes it) and the bloom layers at
1/4 and 1/10. The autumn rim light keeps the plain sprites on one shader for the whole y-sorted pass, so they still
batch. Still to do on a device: the checklist below, with `bloom.enabled` on and off.

## What changed (no behaviour change)

1. **Shared walking flood for the idle job search** (#77): `Pathfind.flood(world, start)`. A goal-free Dijkstra
   pops tiles in an order that depends only on the grid and the start tile, so the standing-order search and
   every routine category's search (one flood each before) are now answered by one lazily extended flood:
   a query first scans tiles already popped, in pop order, then keeps expanding until a goal pops. The result is
   exactly what a fresh search would give (proved by `tests/test_perf_budget.lua` against `Pathfind.find` on random
   maps and target sets). The flood uses reused per-tile scratch arrays validated by a stamp, so a search
   allocates next to nothing; the per-search `targets` and `taskAt` tables in `Tasks` are reused too. `Pathfind.nearest`
   keeps its signature.
2. **Power flow reused** (#132): `Power.tick` no longer builds a new `flow` table with sub-tables every tick; it
   refills the saved one in place (entries for picked-up sinks and unknown tiers are dropped). Per-tick scratch
   (`demanded`, generators, thermostat) is reused.
3. **`Calendar.now` cached** (#132) per calendar state while the clock stands still. The table is shared: read
   it, do not write to it. `Calendar.compute` is the uncached version.
4. **`Stats.modifier` allocation-free** (#132): reused sorted equipment id list (`Inventory.fillEquipmentIds`)
   and a per-registry list of perks that carry modifiers; the sum is taken in the same order, so floats are identical.
   A revision-cached version was not built: tests and the harness write `journal.known` directly.
5. **HUD scan**: `Needs.heatEfficiency` uses `Grid.anchorsWith(world, "heatSource")`.
6. **Renderer**: objects' definitions looked up once per frame. The per-frame sort and closure per visible
   sprite are measured (about 1 to 2.5 ms at the widest zoom on desktop) and left alone; see follow-ups.
7. **Save** (#21): `src/core/gridpack.lua`. In memory the grid stays plain arrays; in the file `terrain` is a
   palette plus run-lengths (`"ids:grass,water;a12b3..."`), and `soil` and `waterTable` are runs of whole
   hundredths (`"hundredths:45*3,46,47*12"`). Exact by construction: a numeric array is packed only when every
   value divides back to the same double (`n / 100 == v`), a terrain array only when dense strings fit the
   52-letter palette; anything else is written as the plain array and read back as it was. `SAVE_COMPAT`
   is 7 (D74: no migration; older saves get the "can't be loaded" prompt). Round trips are tested on random maps
   up to 512x400 and on a real run; a damaged map string makes the slot unreadable (the backup is tried).
8. **Probes**: `src/core/perf.lua`, the F3 lines, `tools/perf`, driver scenario `perf`.

Determinism: `lovec tools/balance` old code versus new, report text and `out=` CSV byte-identical on six
commands (`policy=all seeds=3`, `policy=scripted,active seeds=5`, `features=none seeds=4 seed0=4`,
`runs=3 years=0.5 set=needs.coldDamage=30 seeds=6`, `policy=scripted,active years=2 seeds=2 seed0=20`,
`features=water,power seeds=3 seed0=30`), all years=1 unless shown, default threads.

## Budget

Targets for a mid-range phone (about 3 to 4 times slower per thread than the desktop above):

| | target | desktop now | note |
|---|---|---|---|
| sim per tick, mean | 0.5 ms | 0.02 (64x48) to 0.07 (128x80, D203) | `tuning.perf.simMsPerTick` |
| worst single tick | 8 ms | 4 to 9 | `worstTickMs`; idle search on a big map, new-day work |
| draw (CPU submit), per frame | 8 ms | 0.8 to 2.5 | `drawMs`; leaves the rest of 16.6 ms for update and the GPU |
| frame | 16.6 ms (60 fps), floor 33 ms | | `frameMs` |
| allocation per tick, mean | 4 KB | 0.75 (D203) | enforced by `tests/test_perf_budget.lua` (`testAllocKbPerTick`) |
| worst tick allocation | 512 KB | about 150 KB in the test | `testAllocKbWorstTick` |

The headless test counts allocation, not time, so it cannot flake on a slow CI machine; time is checked by
looking at the F3 overlay and `tools/perf` on a real device.

## Measure on a phone (not possible here)

1. Install a build on a mid-range Android phone, open F3 (double tap, see the overlay hint), start a new game and
   let the Routine run. Read, at zoom 1, 2 and 3 and at speeds 1x, 4x and during sleep (8x): FPS, the
   `Sim`, `Worst tick`, `Update` and `Draw` lines. Report any "OVER".
2. Note the same with rain and with winter snow (the ground and weather shaders), at night (lights), and with the
   Pantry/Journal open.
3. The GPU is not in the `Draw` number (submit time only). Judge it by FPS at zoom 1 in rain: if FPS drops
   while `Draw` stays small, the shader passes (ground, water, mist, lights, clouds, grade) are the cost; see the
   "phone GPU profile" shader follow-ups.
4. Load time and autosave hitch: time from tapping a slot to the homestead, and note a stutter every 60 s when
   the autosave writes (about 5 ms on desktop for a 64x48 map; a 20 to 30 ms hitch on a phone would show).
5. Memory (RAM and VRAM lines) after an hour of play, and whether the OS kills the app in the background.
6. A longer run: 3 in-game years at 4x, watching the `Worst tick` line.

## Follow-ups

- `grid.objects` is now the largest part of a save (every tree is a table). A packed form for objects that hold
  only an id would take the file down by another third to a half.
- Renderer per-frame work: a closure and a table per visible sprite plus a sort, a shader switch per swaying
  sprite (batched sway is in the shader follow-ups), and the remaining all-object scans in `food.lua`,
  `inventory.lua` (`owns`, `refreshStorage`), `finds.lua`, `clearing.lua`, `firewood.lua` and `processing.lua`.
- The idle search is still one flood per decision per actor every `idle.recheckInterval` when nothing is
  reachable; a cache keyed on a grid/plan revision would make it free, at the cost of a revision counter every
  writer must bump.
