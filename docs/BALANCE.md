# Balance harness and winter findings

Tracks issue #31 (GDD §11, §12.5). The harness plays whole runs headless with the real World, Session, tuning and content (no mocks), so numbers here move when the tuning files move. Re-run it after any balance change.

## Running it

```
lovec tools/balance [key=value ...]          # from the repo root; Windows: "C:\Program Files\LOVE\lovec.exe"
lovec tools/balance help=1                    # option list
```

| option | meaning | default |
|---|---|---|
| `policy=all\|idle\|scripted\|active\|a,b` | policies to play | all |
| `seeds=N`, `seed0=N` | number of seeds and the first one | 20, 1 |
| `years=N` | span per run (fractions work: `years=0.25` is one season) | 1 |
| `runs=N` | career length: a failed run is followed by recovery (the policy picks the free study) and a new run on new land with knowledge kept | 1 |
| `features=all\|none\|a,b` | optional policy behaviours, see "Policy features" below; `none` plays the harness as it was before they existed | all |
| `out=file.csv` / `out=file.json` | CSV: one row per seed per morning (money, food, warmth, notes, known...). JSON: summaries plus one record per run | none |
| `set=domain.key=value` | override a tuning number for what-if runs, repeatable, e.g. `set=needs.warmthPeak=6` | none |
| `jobs=N` | worker threads that play (policy, seed) pairs in parallel; `jobs=1` plays them one after another in the main thread. The report and `out=` files are byte-identical either way | CPU count, at most 16 |
| `profile=1` / `profile=N` | sample the run with LuaJIT's profiler (forces `jobs=1`) and print the top 25 (or N) lines and functions | off |
| `trace=1` | print the first seed of each policy day by day | off |
| `quiet=1` | no progress lines | off |

Speed (since #123, one thread): about 0.4 s per seed-year for `idle` (it dies in the first week), 2 s for `scripted` and `active`; with the default `jobs` on a 12-CPU machine, the default run (all policies, 20 seeds, 1 year) takes about 15 s. Runs are deterministic per seed and tuning. The harness is not part of `lovec tests`, but `tests/test_balance_smoke.lua` runs one seed for a season so it cannot rot, and checks that worker threads return exactly what an in-thread run does.

Files: `tools/balance/main.lua` (CLI), `balance.lua` (run loop, aggregation, reports), `policies.lua` (the three policies, with every player-behaviour knob in one `POLICY` table), `features.lua` (the optional behaviours below, shopping list, placement, find scoring), `parallel.lua` and `worker.lua` (the `jobs=` thread pool), `profile.lua` (`profile=`).

## Harness speed (#123, D58)

**Parallel seeds.** Each (policy, seed) pair is independent (a fresh Session per seed), so `jobs=N` starts N `love.thread` workers, each its own Lua state with its own registry, tuning and `set=` overrides, and hands them the pairs through a channel. Results come back as Lua data with every number written to 17 significant digits (exact round trip) and the report is built from them in the same order as the plain loop, so the text report and `out=` CSV/JSON are byte-identical to `jobs=1` (only the progress and `Total:` lines differ). Threads rather than child `lovec` processes: no command-line quoting on Windows, no temp files, and a real work queue (idle seeds are short, so fixed chunks would leave CPUs idle). A worker error stops the run with the worker's traceback.

**Profile first.** `profile=1` on `policy=scripted seeds=1 years=1` (before): `Power.tick` 51 percent of samples, almost all in its per-tick scan of every placed object (trees, rocks and clutter included) for sources, sinks and batteries; `Water.tick` 36 percent for the same scan for pumps and drip lines; content lookups behind those scans (`Registry:get` and the strict-field guard) 15 percent; the idle job search (#77) only 4 percent. So #77 was not the hot spot; the per-tick object scans were.

Fixes (sim, no result change):

1. `Grid.anchorsWith(world, field)`: a runtime index (`world.objectIndex`, never saved) of placed objects whose definition has a field (`source`, `sink`, `battery`, `pump`, `drip`, `shelter`, `stand`, `waterSource`), sorted by anchor as the old scans were. It is dropped by `placeObject`, `removeObject` and `rebuildOccupancy` and rebuilt when the `grid.objects` table is replaced. Power, water, sleep (shelters) and the stand use it instead of scanning every tick.
2. `Pathfind.find`: the heap is two parallel arrays (no table per push) with the same sift order and comparisons, and walkability is memoized per search. Paths and tie-breaks are unchanged.
3. #77, first half: task types may declare `canDoCandidate`, the idle search's per-tile check minus what `candidates` already checked once. Fishing skips the per-tile rod check (`Stats.modifier`), bucket filling the per-tile bucket-capacity check. The second half of #77 (a full Dijkstra per category on every recheck when nothing is reachable) is not changed: with the faster search it is about a fifth of a scripted run, and caching a failed search exactly is fiddly.
4. Small: `Power.tick` reuses its per-tier scratch tables and computes the sun from the tick's own date and weather.
5. #78: terrain writes go through `Grid.setTerrain`, which drops the bank-tile cache for that grid (tested), so the cache cannot go stale if terrain becomes mutable.

Timings (wall seconds, Windows, 12 CPUs, default features):

| run | before | after (`jobs=1`) | after (default `jobs`) |
|---|---|---|---|
| `policy=scripted seeds=1 years=1` | 12.5 | 2.0 | 2.0 |
| `policy=idle seeds=3 years=1` | 7.8 | 1.2 | |
| `policy=scripted seeds=3 years=1` | 35.4 | 5.8 | |
| `policy=active seeds=3 years=1` | 33.0 | 5.5 | |
| `policy=all seeds=3 years=1 out=...` | 78 | about 13 | 4.2 (9 threads) |

The issue's "about 17 s" single seed-year was measured before D57; at the merge base (4506fc9) it was 12.5 s. Speed-up from the sim fixes alone is about 6x; with threads, a 3-seed all-policy year goes from 78 s to 4 s (about 18x). After the fixes the profile is spread out: `Power.tick` about a third (mostly the garbage of its per-tick flow tables), the idle search and pathfinding about a fifth, the active policy's own order planning about a seventh. Follow-ups: allocation churn and `Stats.modifier` caching (#132), the rest of #77, and a repo tool for the determinism check below (#133).

**Later speed work (D103, #19 #77 #132).** A shared walking flood for the idle job search, a reused power flow, a cached date and an allocation-free `Stats.modifier`: the scripted + active 5-seed year went from 52.8 s to 28.9 s (`jobs=1`), results byte-identical on six commands. Numbers and method in docs/PERF.md. Run the determinism check below again after any sim speed change.

**Determinism checks** (all byte-identical, report text minus timing lines and `out=` files): the merge base and this change on `policy=all seeds=3 years=1` with `out=` CSV and JSON (both `jobs=1` and default `jobs`); and four variants played by the merge base single-threaded and this change with threads: `features=none seeds=4 seed0=4`, `runs=3 years=0.5 set=needs.coldDamage=30` (careers with failures), `policy=scripted,active years=2 seeds=2 seed0=20`, and `features=water,power seeds=3 seed0=30`. Repeat after any sim speed work: run the same commands on the old and new code and `cmp` the files.

**Fast mode: not added.** A coarser tick is already one override away, `set=time.tickRate=5` (default 20), so no `fast=1` option was added. On 20 seeds x 1 year (scripted, active) it is about 1.8x faster in one thread; survival is identical (1 of 20 fails in each policy, same season and cause) and most medians move within noise, but some move visibly: scripted winter-1 fuel cover 0.79 to 0.83 with 26 to 37 percent fully covered, active 0.60 to 0.54, money medians by up to $4. Use it for smoke runs only, never for numbers in this file.

### Policies

- **idle**: the player never acts. The idle routine runs from the first second. Since D61 the routine plans a starter field when nothing is planned, so it plants (before D61 it never did).
- **scripted**: day 1 plans one field tile per starting seed near the creek, then the routine runs. Keep targets stay automatic. Each morning, when the truck is charged, it presses Auto-load and makes the trip if the load is worth selling (else it empties the truck again), orders the next item from a fixed buy list (woodshed, wood stove, axe, smoker, big bucket, sturdy rod, used panel), places delivered objects near the truck, and fills the study queue from a fixed list. It never gives a direct order.
- **active**: everything `scripted` does, plus a keep target on wood (what its worst-case winter plan still needs, D75, D104) and direct orders like an engaged player: harvest, water (bucket hauling), plant, till, load the smoker, fell trees for the winter's fuel (worst-case severity plus the longest snap), clear junk for cash, hand-fish with the rod, grow the field as seeds come in, buy seeds and bait. It sleeps at night (no orders at bedtime) so study progresses, and hands control to the routine after the takeover delay when it has nothing to order. The fishing mini-game is a dice roll (75 percent landed) plus plausible game time. This is a diligent player with perfect execution, so treat it as an upper bound on what a human achieves.

Metrics are sampled at the start of each morning. "Alive at season end" means the run reached the first morning after that season. "Fuel (winter nights covered)" is warmth in stock divided by the full winter night (`needs.warmthPeak`, 8 since D104), before severity and cold snap.

## Findings (baseline tuning)

Command: `lovec tools/balance policy=all seeds=30 years=2 quiet=1` (seeds 1-30), commit that adds the harness.

Alive when the season ends (share of 30 seeds):

| policy | Sp1 | Su1 | Au1 | Wi1 | Sp2 | Su2 | Au2 | Wi2 |
|---|---|---|---|---|---|---|---|---|
| idle | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% |
| scripted | 97% | 97% | 80% | 77% | 73% | 73% | 73% | 73% |
| active | 100% | 97% | 97% | 97% | 93% | 93% | 93% | 93% |

Other results:

| policy | days survived p10 / median | failures | causes |
|---|---|---|---|
| idle | 6 / 6 | 30 of 30, all in spring Y1 | hunger 30 |
| scripted | 20 / 56 (cap) | 8 of 30: spring Y1 1, autumn Y1 3, winter Y1 2, spring Y2 2 | cold 5, hunger 3 |
| active | 56 / 56 (cap) | 2 of 30: summer Y1 1, spring Y2 1 | hunger 2 |

Winter 1, first day: fuel warmth in stock divided by that winter's total warmth need (the world's own severity and snap roll): scripted median 0.36 (8 percent fully covered), active median 0.66 (0 percent fully covered). Food in stock then: scripted 16 days, active 14 days; at the end of winter active has about 1.4 days left (median) and scripted 0.

Condition is the survival bar: active medians are 100 at every season end. Scripted drops to 86 at the end of winter 1.

### Does it match GDD §11 ("first run usually fails around the first winter")?

Partly, and not for the player who engages.

- **idle** (before D61, #66) failed far sooner than winter: the starting kit is 4 canned food (2 days) and the routine never planned a field, so everyone was dead by day 6. With the starter field (D61) 10 of 10 seeds live through autumn (median 26 days survived of 28 tracked, still dying of hunger in winter because the idle player never sells, buys or chops fuel). The older table rows below are from before D61.
- **scripted** (a fixed opening, then routine) fails 23 percent of the time by the end of the first winter, mostly in autumn and winter from cold, and fuel at winter start covers only about a third of the need. That is the right neighbourhood but too low a failure rate to call "usually fails".
- **active** survives the first winter 97 percent of the time and two years 93 percent. This is the main mismatch: a diligent first-run player is not gated by winter. The two failures are hunger (empty larder at the end of winter), not cold.

Why winter does not bite the active player: fuel is not stockpiled before winter (0.66 coverage at winter start), it is chopped on demand during winter (trees yield 6-9 wood each, there is plenty of clutter), and the cold snap is only one to three nights at x2.

### What-if checks of the recent guesses (30 seeds, 1 year, scripted and active)

| change | scripted alive at Wi1 | active alive at Wi1 | notes |
|---|---|---|---|
| baseline (`dailyWarmth.winter` 4, autumn 2, `coldDamage` 20) | 77% | 97% | |
| `needs.dailyWarmth.winter=6` | 77% | 97% | active unchanged |
| `dailyWarmth.winter=8`, `dailyWarmth.autumn=3` | 63% | 90% | scripted: cold 9, hunger 4, both 4 |
| above plus `needs.coldDamage=30` | 40% | 90% | scripted deaths are almost all cold (19 of 22); active unchanged |
| winter 8, autumn 3, `landgen.treeThreshold=0.72` (fewer trees) | n/a | 90% | active unchanged |

So: the winter warmth numbers and `coldDamage` move the scripted/routine player a lot, but the engaged player is barely affected, because wood on demand removes the pressure. `seasoned_firewood` 3 in the starting kit is only 3 warmth against a winter need near 37 (median), so it is a minor cushion rather than the problem. The severity and snap rolls are fine (year 1 severity 0.9-1.3, median need 37 warmth, year 2 median 44).

## Recommended tuning changes (not applied)

1. **Make winter a stockpiling problem, not a chopping problem.** Raise the winter and autumn warmth (`needs.dailyWarmth` winter 4 to 6-8, autumn 2 to 3) only together with a limit on on-demand wood: fewer trees (`landgen.treeThreshold`, tested alone it is not enough), smaller yields in `content/objects.lua` (tree 6-9 to 3-5), or a cap on how much wood can be split during winter. Re-run the harness for `active`; the goal is roughly 40-60 percent first-winter failure for `active` and 60-80 percent for `scripted`.
2. **Winter food is the real second wall.** The active player ends winter with about 1 day of food and its only deaths are hunger at winter's end. Keep it: it is the "stockpile" pressure the GDD wants. If winter warmth is raised, check that hunger does not become the only killer.
3. **Do not rely on `coldDamage` alone.** 20 to 30 changes scripted outcomes sharply but not active ones; leave it at 20 until the wood supply is limited.
4. **Cold-snap length** (`snapDaysMax` 3, `snapMultiplier` 2) is unlikely to matter with on-demand wood. Revisit after item 1.
5. **Autumn warmth** (2 per night) already killed 3 of 30 scripted runs in autumn Y1; do not raise it past 3 without a stove and woodshed being reachable by then (study plus purchase takes until about summer).

Caveats: the `active` policy executes perfectly and instantly, so a human will do worse. A first-run human with no journal knowledge is the real target; use `active` as an upper bound and `scripted` as a lower-middle bound, and judge against both. The harness starts every career with an empty journal; use `runs=3` to look at runs 2-3 with carried knowledge (GDD says runs 3-5 should be the first to clear year 1).

## Power network (issue #34)

The network (GDD §7.5, D46-D49) adds sources, a battery bank, sinks and a priority list. Numbers live in `data/content/objects.lua` (kW, kWh), `catalog.lua` (prices) and `data/tuning/power.lua`.

Energy budget per in-game day (1 kW for one hour = 1 kWh; seasons are 7 days, `time.daylight` gives the sun hours):

| thing | summer | winter | note |
|---|---|---|---|
| folding panel (0.8 kW) | ~8 kWh | ~2.3 kWh | the early game: all of it goes to the truck (a trip costs 20 kWh) |
| solar array (3 kW) | ~31 kWh | ~8.6 kWh | winter sun: 9 h of daylight x `seasonalOutput` 0.5 |
| wind turbine (1.2 kW) | ~8 kWh | ~17 kWh | mean wind factor 0.6 x the seasonal curve; best when the sun is worst |
| micro-hydro (0.6 kW) | ~7 kWh | ~8.6 kWh | steady, but needs a creek-side tile |
| generator (2 kW) | fuel-limited | fuel-limited | 0.5 fuel per kWh; a fuel x5 pack is 10 kWh for $15 |
| electric heater (1.5 kW) | 0 (idle) | up to ~21 kWh | dark hours of cold seasons, until the night's warmth is made |
| chest freezer (0.15 kW) | 3.6 kWh | 3.6 kWh | always on |
| work lamp (0.1 kW) | ~0.8 kWh | ~1.5 kWh | dark hours only |

The squeeze (design goal): in winter an array plus a bank, heater, freezer and lamp wants about 26 kWh and the array alone makes under 9, so something is shed every night. The player's levers are the priority order (heating first, then the freezer), a turbine or micro-hydro, a generator and fuel, firewood (the heater only makes most of a mild night's warmth; `needs.dailyWarmth.winter` is 8 x severity since D56, 4 before), or leaving the truck uncharged. A winter truck trip (20 kWh) is a real choice against heating. `tests/test_power.lua` asserts the summer-versus-winter shape ("winter squeeze").

Prices are meant to put each power item a few trips out: array $110, bank $80, turbine $140, hydro $160, generator $90, heater $50, lamp $15, freezer $90, fuel x5 $15. They are unvalidated against real play.

Harness effect: `lovec tools/balance policy=scripted,active seeds=5 years=1` gives the same survival before and after (0 of 5 fail for both policies), with money and fuel medians within noise and about 3 percent more run time. The policies never buy power items, so the harness does not measure them; they learned one in D57 (see "Policy features" below).

## Water ladder (#35, D50)

Per in-game day a field of N crops wants N waterings (`farming.moistureDays` = 1). One cistern unit is one watering by bucket, or two by drip line (`water.dripUnitsPerWatering` 0.5).

| thing | number | note |
|---|---|---|
| solar pump (0.4 kW, 5 units/h) | up to ~50 units on a sunny summer day, ~20 in winter | scaled by `Power.sinkRatio`; it draws nothing once the cistern is full |
| cistern (60 units) | a full day for about 60 crops by bucket, 120 by drip | stock is shared and capacity adds up per cistern |
| bucket fill | creek 1.5 s, dug well 1.2 s, hand pump 0.6 s, cistern 0.4 s | a bucket holds 6 waterings (10 with the big bucket) |

Prices: dug well $20, hand pump $40, cistern $55, solar pump $70, drip line $25 (unvalidated against play). Harness effect: `lovec tools/balance policy=scripted,active seeds=5 years=1` gives identical survival, money, food and fuel numbers before and after, because no policy bought the rungs then (they do since D57, see "Policy features"); only the "journal nodes learned" and "ideas waiting" medians move by about one, because the well becomes a new idea once the bucket-hauling note is written and the policies study whatever is waiting.

## Longer days and fast sleep (#112, D56)

`time.dayLength` went from 128 to 320 game seconds. The harness drives the sim in game time, so it sees the full effect of the extra labour per day (walk speed and task times are still in seconds); it does not model the fast-sleep speed, which only changes how quickly the sim ticks, not what happens (tests assert an identical morning).

Command: `lovec tools/balance policy=scripted,active seeds=10 years=1` (seeds 1-10), medians, all 10 of 10 seeds alive at the cap in every row. Fuel is warmth in stock divided by the *base* winter need, so after the change one "night" is 8 warmth, not 4.

| metric (Sp1 / Su1 / Au1 / Wi1) | before (128 s days) | days only (320 s) | after (320 s, calories 3000, warmth x2) |
|---|---|---|---|
| active: food days in stock | 11.3 / 22.4 / 16.3 / 3.3 | 16.4 / 42.2 / 47.8 / 27.6 | 9.6 / 26.5 / 31.6 / 12.6 |
| active: money $ | 14.5 / 34 / 106 / 54.5 | 10.5 / 17 / 62.5 / 71.5 | 7.5 / 20 / 47 / 54 |
| active: Wi1 first day fuel / need, fully covered | 0.69, 20% | 1.51, 80% | 0.75, 20% |
| active: journal nodes learned | 2 / 5 / 9 / 13 | 3 / 6 / 11.5 / 16.5 | 3 / 7 / 12 / 17 |
| scripted: food days in stock | 9.4 / 14.2 / 11.2 / 0.5 | 13.1 / 13.0 / 13.2 / 4.1 | 8.3 / 10.1 / 9.1 / 0.7 |
| scripted: money $ | 15.5 / 31.5 / 68.5 / 78 | 33.5 / 75.5 / 84.5 / 93.5 | 21.5 / 31.5 / 15 / 15 |
| scripted: Wi1 first day fuel / need, fully covered | 1.13, 60% | 2.63, 100% | 0.97, 40% |
| scripted: journal nodes learned | 1 / 4 / 8 / 11 | 1 / 4 / 10 / 14 | 2 / 5 / 11 / 15 |

Reading it:

- Lengthening the day alone makes the first year clearly easier: a day holds about 2.5x the work (the routine and the policies do the same jobs, in the same seconds), while food and fuel are still eaten and burned once per day. Fuel cover at the start of winter doubled to tripled.
- Doubling the nightly warmth need and raising calories by half brings active back to the old fuel cover (0.75 against 0.69, 20 percent fully covered, same as before) and scripted close (0.97 against 1.13, 40 against 60 percent). Both policies still survive all 10 seeds, as before. A 2x calorie variant starved 2 of 10 scripted seeds in autumn and winter and left the early game too tight (the starting 4 cans last about a day), so 3000 was chosen.
- Money is lower (more of the harvest is eaten) and journal progress is slightly higher (not from study yield, which is per in-bed hour and unchanged; more notes are written per day because the homesteader does more).
- Still true from the findings above: the engaged player is not gated by winter. The goal of 40 to 60 percent first-winter failure for `active` is not met; this change aimed at preserving the old balance, not at fixing it. Scripted at 0.97 cover is nearer the "winter bites" target than before.

Real-time pacing: a day is about 213 s awake plus about 13 s asleep (8x) at 1x, so a season is about 27 minutes, against about 15 before (the awake share of a day was about 85 s of 128). The harness runs on game time, so this is arithmetic, not a measurement. This is a first pass; revisit from play (follow-up issues cover trimming season length and re-tuning from human play).

## Policy features (#80, #90, #101, #105, #111, #115, D57)

The scripted and active policies can now use the M5 content, switched by `features=` (default `all`; `features=none` is the harness as it was). Features: `cat`, `stand`, `water`, `power`, `finds`, `weather`; the rules are in D57 and `tools/balance/features.lua`. Every run now also prints a "Features" block: income by source per year (truck vs stand), kWh made / wanted / served / shed / wasted, nights heated electrically, waterings by hand and drip, cistern units pumped and rained, mice raids and losses, finds picked, kit owned at the end. The same numbers are in the `out=file.json` summaries (`totals`, `income`, `owned`, `finds`).

Note: **D56 doubled the nightly warmth need and lengthened days**, so none of the figures below compare with the older tables above (winter 1 need is now a median 69.5 warmth, was 37). Re-baselined here: `features=none`.

Command: `lovec tools/balance policy=scripted,active seeds=10 years=2 features=<set>` (seeds 1-10, D56 tuning, one process per set, about 10 minutes each).

### Active policy, 10 seeds, 2 years

| features | alive at end | trips / run | truck $ y1 / y2 (median) | stand $ y1 / y2 | winter-1 fuel cover | notes |
|---|---|---|---|---|---|---|
| none | 100% | 12.2 | 205 / 260 | 0 / 0 | 0.75 | baseline; cat owned 70% (from the stray-cat find or an order) |
| stand | 100% | 12.0 | 205 / 283 | 8 / 219 | 0.75 | stand does not cut trips; total y2 income 260 to 502 |
| power | 100% | 20.5 | 210 / 884 | 0 / 0 | 0.67 | kWh made 252 to 649 per run; y2 truck income p25 265, p75 1238 |
| water | 100% | 12.1 | 202 / 260 | 0 / 0 | 0.75 | hand waterings 1118 to 1125 (no change), rained 37 units |
| cat | 100% | 12.2 | 208 / 263 | 0 / 0 | 0.75 | mice food lost 64.6 to 45.5 units, raids caught 4.2 to 8.0 |
| finds, weather | 100% | 11.9 | 207 / 244 | 0 / 0 | 0.75 | within noise; picks shift to split stacks, junk, jump packs, away from bait and cans |
| all | 100% | 17.5 | 213 / 675 | 16 / 134 | 0.67 | survival unchanged; money at the end of year 2 is lower (87 against 249) because of the kit |

Reading it:

- **Power (#80)** is the large effect. The truck trip is gated by 20 kWh of charge, so an array, turbine or micro-hydro lifts the trip cap and the crate sells out more often: 20.5 trips against 12.2, year-2 truck income 3.4x. Owned at the end: solar array 50%, bank 50%, turbine 70%, micro-hydro 40%, freezer 100%, lamp 50%. Brownout days 9.5, 17 kWh shed, 122 kWh wasted. Nothing reached the heater (0% owned): the "Cold night" note needs a night with a warmth shortfall, which a prepared player never has. Nothing power-related was unlocked at all until the policy held its trips once so the truck battery could fill (the "Full battery" note, `POLICY.holdTripsUntilDay`). Both are gate problems, see below.
- **Stand (#105)**: the truck still earns more than the stand (56 against 44 percent in year 2) and trips do not drop, but the stand and its three upgrades nearly double year-2 income.
- **Water (#90)**: the rungs are bought (well 100%, cistern 90%, hand pump 90%) but whole runs hardly change: about 1100 hand waterings either way, rain adds about 37 cistern units in two years. With the solar pump and drip lines (features=all: pump 50%, drip 40%) drip does 4 waterings and the pump moves 21 units. The unlock chain is long (well, then well water, then cistern, then a pump needs the Full battery note, then drip needs the pump to have run).
- **Sprinklers (#278, D118)**: the water feature buys up to two before the solar pump (75 percent of `policy=active years=2 seeds=4` runs own one), but they never water: the cistern is almost always under a unit, so waterings stay by hand (876 either way) and survival matches the build before (1 of 4 failed both ways). The smoke test only; no tuning conclusions.
- **Cat (#115)**: mice are about 3 percent of a 1970-unit harvest, the cat recovers about 1 percent, and eats a fish a day.
- **Finds (#111)**, **weather (#101)**: no visible effect on survival or income within the noise of 10 seeds; picking by need moves the pick mix. Rain days: 9.7 of 56 are rain (and 19.4 cloudy). First truck trip across seeds 1-9: 3,3,4,4,5,5,5,5,6 days (median 5, was 2-5 before clouds), the test now sweeps seeds and judges the median.

### Scripted policy, 10 seeds, 2 years

The scripted player earns about 70 dollars in year 1 and 155 in two years, so the features hardly start: alive at the end of winter 2 is 20 percent (none) against 30 percent (all); winter 2 fuel cover 0.28 against 0.37; the stand makes 4 dollars in year 2; the cat is owned by 100 percent and cuts food lost from 43.5 to 26.9 units. Treat scripted as the "not engaged" floor: it dies in winter 2 whichever way it plays. Part of that "failure" is the span edge (see the harness issue).

### Chickens (#40, D63, D64)

A seventh feature, `chickens`, is on by default: the policies buy the coop and the feed refill when known, the trip buys hens (three at a time) while the coop has room, the fence is bought after a raid takes hens, the scripted policy tends the coop through the routine's `animals` category, and the active one orders `tend_coop` itself. The report gains a "Chickens per run" line (eggs collected, hens lost, raids the coop turned back). Check, `policy=scripted,active seeds=3 years=1`: no failures either way, eggs collected 0 (scripted) and 2 (active) in year 1, because the coop sits behind the cat and stand in the shopping list and money is the limit (#143). Active, `seeds=6 years=2`: 52 eggs per run, 1.8 hens lost per run (foxes), 3.2 raids turned back, 0 of 6 failed, coop owned by 100 percent and the fence by 67. Unit-level sanity (tests): a six-hen flock earns in summer, about breaks even in winter at the catalog feed price.

An eighth feature, `goats` (D71, #139), is on by default but sits last in the shopping list: pen, trailer, goats (on a truck trip), hay when the herd has under six days, and the cheese press; the active policy orders `tend_pen`. The report gains a "Goats per run" line (milk collected, goats lost). Check, `policy=scripted,active seeds=3 years=2`: active unchanged (0 of 3 failed, 53 eggs a run), no goats reached by either policy (milk 0), because money goes to the stand, water and power first; scripted failed 3 of 3 against 2 of 3 on the commit before, from shifted market specials (adding catalog items changes the seeded daily specials), not from goats. Unit-level sanity (tests): a three-goat herd earns in summer (about $77 a week before spoilage), gives under a quarter of the milk in winter, eats several times the hay, and a winter herd runs at a small loss the player plans for.

### Machines (#42, D65)

An eighth feature, `machines`, is on by default: the auto-harvester ($150) is the last entry of the shopping list (so saving for it never holds back survival kit) and is placed where its 7x7 reach covers the most field. The report's "Per run" line adds "crops picked by machines", and `auto_harvester` joins the owned list. Check, `policy=scripted,active seeds=3 years=1` (and `years=2`): it is never bought, so the output is identical to `features` without `machines` (byte for byte apart from the feature label and timing). Unit-level sanity (tests/test_machines.lua): a full reach of 48 ripe crops is cleared inside ten daylight hours for under 0.15 kWh a crop and well under a third of a truck trip's charge. Whole-run payoff is open (#144).

### Threats (#41, #97, D67)

Threats are part of the sim, not a feature switch: every run gets its yearly schedule. The policies buy no countermeasures (#153), so the harness shows them at full force. The report gains a "Threats per run" line (came, struck, crops lost, knocked back). `set=` now accepts list entries, so `set=threats.count.1=0 set=threats.count.2=0 set=threats.count.3=0` turns threats off for a comparison.

`policy=scripted,active seeds=6 years=3`, before (no threats) and after:

| | scripted alive end of Sp2 / Wi2 / Sp3 | active alive end of Wi3 | active truck income Y1 / Y2 / Y3 | active stand Y1 / Y2 / Y3 |
| --- | --- | --- | --- | --- |
| before | 100% / 50% / 0% | 83% (1 hunger death) | $197 / $314 / $986 | $12 / $119 / $315 |
| after | 83% / 67% / 17% | 100% | $193 / $287 / $882 | $8 / $113 / $224 |

Scripted truck income Y1 $59 to $48, Y2 $67 to $67. Per run: scripted 2.8 threats came, 2.3 struck, 8 crops lost; active 5.0 came, 4.3 struck, 56 crops lost and 13 knocked back. With 20 seeds x 2 years and a first-pass year-1 strength of 0.5, threats on against off: scripted alive at the end of Sp2 85% vs 95%, end of Wi2 40% both; active 95% both; active year-2 truck income $346 vs $280 (noise: the runs diverge as soon as a crop is lost). Year-1 strength was then lowered to 0.4 to keep year 1 gentle; the 6-seed table above is at 0.4.

### Automatic pantry and the gentler start (#151, #163, #161, D68)

Changes: the automatic pantry holds a fresh food only for `autoPantryHorizon` (0.5) of its `spoilDays`, so surplus fish and radishes go to the sell crate for the stand or the truck instead of sitting in the pantry; the starting kit gains 2 cans (4 to 6) and $6. The report gained a "Food per run: N units spoiled" counter.

`policy=scripted,active seeds=6 years=1`, before and after (same seeds):

| | scripted before | scripted after | active before | active after |
| --- | --- | --- | --- | --- |
| failed in year 1 | 1/6 (spring Y2) | 0/6 | 0/6 | 0/6 |
| alive end of Wi1 | 100% | 100% | 100% | 100% |
| money at end of Sp1 / Su1 / Au1 / Wi1 (median $) | 21 / 21 / 9.5 / 9.5 | 36.5 / 26 / 9 / 15 | 6 / 6 / 23.5 / 9.5 | 13 / 7.5 / 16.5 / 8.5 |
| truck income Y1 (median $) | 48 | 69 | 193 | 196 |
| trips per run | 3.3 | 4.0 | 5.5 | 5.5 |
| stand units per run | 2 | 7 | 13 | 14 |
| fresh food spoiled per run (units) | 151.7 | 142.5 | 435.3 | 411.3 |
| harvested per run | 380 | 380 | 820 | 790 |
| food in stock at end of Wi1 (days, median) | 0.3 | 0.6 | 10.0 | 9.3 |

Reading: the early money is the visible change (the $6 and the crate that sells), survival is not worse anywhere and the one scripted failure became a survivor (6 seeds, so within noise). Spoilage fell only 6 percent: moving food to the crate does not stop it spoiling (D31, the crate is a reservation), it only gets sold when the stand or a truck trip runs, and the policies make a trip every 5 to 8 days. The real fix for the 410 units a run in the active policy is more sales channels or earlier preserving (smoker, freezer), and the visibility in the pantry (D68) so a player acts on it. The harness policies do not read the new warnings.

### Shelf-life batches (#183, D73)

Changes: spoilage is per batch with a shelf life (fish 2 days, milk 2, radish 7, egg 14, potato 21; `tuning.food.shelfLife`) instead of `1/spoilDays` of the whole stock a night; past its shelf life a batch loses half a night (`rotShare`). Food is eaten and sold oldest first. The report gained a "Spoiled per run by food" line.

`policy=scripted,active seeds=6 years=2`, before and after (same seeds, 56 days):

| | scripted before | scripted after | active before | active after |
| --- | --- | --- | --- | --- |
| failed in 2 years | 5/6 (winter Y2 2, spring Y3 3) | 1/6 (winter Y2) | 0/6 | 0/6 |
| alive end of Wi2 | 67% | 83% | 100% | 100% |
| money end of Sp1 / Su1 / Au1 / Wi1 (median $) | 36.5 / 30 / 8.5 / 11.5 | 34 / 27.5 / 23.5 / 18 | 13.5 / 8.5 / 15 / 7 | 7.5 / 7.5 / 19 / 12 |
| money end of Sp2 / Su2 / Au2 / Wi2 (median $) | 11 / 22 / 19.5 / 14.5 | 32.5 / 22 / 31.5 / 29 | 17.5 / 34.5 / 50.5 / 24.5 | 29 / 37 / 67 / 26 |
| truck income Y1 / Y2 (median $) | 62 / 80 | 161 / 323 | 196 / 285 | 207 / 304 |
| stand income Y1 / Y2 (median $) | 3 / 15 | 0 / 10 | 10 / 123 | 11 / 97 |
| trips per run | 10.0 | 14.3 | 12.5 | 13.5 |
| fresh food spoiled per run (units) | 269.2 | 5.8 (potato 5.5, egg 0.3) | 881.3 | 671.7 (radish 540, potato 102, egg 30) |
| food in stock on the first day of winter 1 / 2 (days, median) | 8.8 / 9.3 | 16.9 / 17.7 | 25.9 / 34.2 | 65.5 / 67.4 |

Reading: the playtest complaint is gone (`tests/test_spoilage.lua`, "the playtest complaint": 40 radishes picked at 20:00 lose nothing by morning, where the old rate took about 10). The scripted policy keeps almost all of its food: it goes into the winter stock and the truck (Y2 truck income four times higher), and four of the five winter-2 deaths become survivors. The active policy still loses about 670 units, almost all surplus radishes waiting in the crate longer than a week: it harvests 1780 units a run and the truck (40 cargo a trip) and the stand cannot sell them in time (#169). Stand income fell a little: with less produce rotting, the "Produce rots" note that gates the stand, the freezer and the cheese press comes later (#164). The game is now easier for a food-focused player; winter fuel, not food, decides the scripted failures.

### Keep targets and the truck load (#196, #195, D75)

Changes: the sell crate is gone. Every good has a keep target (automatic: 3 days of fresh food, 10 days for winter, fuel to the end of winter at the cautious forecast, the whole woodpile; or set by hand); stock above it is spare. The truck sells only what is loaded, up to 40 units: the policies call `Market.autoLoad` (best price per unit first, then what spoils soonest, never below a keep) before deciding on a trip, sell the load in town, and empty the truck again when the trip is not worth it so the stand can sell. The stand sells spare goods not on the truck, cheapest first, equal prices spoil-soonest first. Wood, stone, green and seasoned firewood can now be sold ($1, $1, $1, $2; scrap stays $2). The active policy sets one keep target: the wood its own worst-case winter plan still needs as firewood. The report gained "Sold per run by good, truck and stand".

`policy=scripted,active seeds=10 years=2`, before and after (same seeds, 56 days):

| | scripted before | scripted after | active before | active after |
| --- | --- | --- | --- | --- |
| failed in 2 years | 3/10 (winter Y2 1, spring Y3 2; all cold) | 3/10 (winter Y2 1, spring Y3 2; all cold) | 0/10 | 0/10 |
| fuel on the first day of winter 1 / 2 (warmth / need, median) | 1.03 / 0.52 | 1.16 / 0.40 | 0.67 / 0.94 | 0.67 / 0.92 |
| truck income Y1 / Y2 (median $) | 178 / 312 | 244 / 287 | 207 / 284 | 308 / 735 |
| stand income Y1 / Y2 (median $) | 0 / 12 | 0 / 27 | 5 / 94 | 15 / 134 |
| truck $ per run (mean), trips per run | 503, 16.5 | 545, 15.6 | 565, 13.0 | 1068, 19.8 |
| fresh food spoiled per run (units) | 5.0 | 8.4 | 737.9 (radish 577, potato 131, egg 29) | 621.6 (radish 619, potato 2) |
| sold per run, truck and stand (units) | (not counted) | radish 172, egg 91, potato 87, stone 72, scrap 14, firewood 1 | (not counted) | radish 579, potato 238, egg 88, wood 41, scrap 19, stone 1 |

Reading: survival is unchanged. **Big shift: active truck income almost doubles** (Y2 median $284 to $735, $565 to $1068 a run, 13 to 20 trips). The old crate quote filled the 40 units in content order, so $1 radishes crowded out potatoes, eggs and fish; Auto-load takes the best price first, so each trip is worth more, the money buys power items sooner and the truck drives more often (#124 already tracks truck income growing with power). Potatoes no longer rot in the active run (131 to 2 a run): they now sell. Radish spoilage is about the same (the truck prefers dearer goods, so radishes still wait, #169). The scripted policy earns more in year 1 from stone it clears (72 units a run) and the same in year 2. One finding shaped the design: an earlier version kept only the wood the coming winter's fuel lacked; the scripted policy then sold about 9 wood a run in its first autumn and failed 5/10 instead of 3/10, because the leftover woodpile was its winter-2 fuel. The automatic keep now holds the whole woodpile (selling wood asks first), and a fuel keep made in winter also covers the next winter (#202 to revisit).

### Shelter ladder: camp and shack (#198, D82)

Changes: the camp (insulation 0.85, recovery 1.3, 40 $) and the shack (0.6, 1.6, desk, 110 $) join the harness shopping lists (`buyList`, `studyList`: camp after the wood stove, shack after the sturdy rod); heat sources are placed around the best shelter (the heater slot) instead of by the truck. `policy=scripted,active seeds=10 years=2`, before and after (same seeds, 56 days):

| | scripted before | scripted after | active before | active after |
| --- | --- | --- | --- | --- |
| failed in 2 years | 3/10 (winter Y2 1, spring Y3 2; all cold) | 0/10 | 0/10 | 0/10 |
| fuel nights covered, winter 1 / winter 2 end of season (median) | 6.7 / 0.0 | 8.1 / 0.1 | 5.2 / 6.3 | 6.1 / 10.4 |
| winter 1 fuel / raw need on its first day (median, share fully covered) | 1.16 (60%) | 1.14 (80%) | 0.67 (10%) | 0.69 (10%) |
| winter 2 fuel / raw need on its first day (median, share fully covered) | 0.40 (0%) | 0.54 (0%) | 0.92 (30%) | 1.05 (70%) |
| condition at winter 2 end (median) | (3 runs lost) | 100 | 100 | 100 |
| owned at the end | | camp 100%, shack 90% | | camp 100%, shack 100% |

Reading: every seed buys the camp in its first year and nearly every seed the shack by its first or second winter, so **the scripted policy's three cold deaths disappear** (a 40% cut in the night's warmth need through the shack is worth more than any wood the policy can gather); the active player was already surviving, and its fuel margin grows (winter 2 fully covered 30% to 70%). Note the harness readiness lines divide by the *raw* winter need (`needs.dailyWarmth.winter` x severity), not the insulated one, so a shack run reads about 1/0.6 lower than it feels: scripted winter 2 at 0.54 is about 0.9 of the insulated need. Fuel use per night falls by the insulation factor (15% in a camp, 40% in a shack), so the first-winter pressure to chop, season and buy a stove is lower once the shack stands; the first winter is still not skippable (the shack needs the camp's note and 110 $, bought on the first trips of summer to autumn). **Tuning to watch**: if the ladder makes winter too soft, raise `shack.insulation` toward 0.7 or its price, rather than weakening the heater slot. The policies' own fuel targets (`urgentFuelNights`, `warmthDeficit`) still use the raw need and so stockpile a little more wood than a shack run needs; left alone.

### Follow-up issues

- #202 revisit the automatic wood keep (whole woodpile vs next winter's fuel)
- #199 a bed rack upgrade for the truck's cargo
- #153 harness policies do not prepare for threats
- #144 harness policies never reach the auto-harvester
- #124 power items make truck income unbounded
- #125 the stand adds 44 percent of active year-2 income
- #126 progression gates reward neglect ("Full battery", "Cold night")
- #127 water ladder saves almost no hauling
- #128 the cat saves about 1 percent of the harvest
- #129 first truck trip median 5 days
- #130 harness counts a death on the span's last rollover as a failure of the span
- #131 feature policies are shallow (switching, rain use, find scoring)

## Early money (#161, D88)

Run starts with $6 (D68; bait is $3 + $3 delivery, so the first order is possible at once). The first junk pays $2 to $6. 20 seeds, 1 year, money median at the end of spring: idle $24.5, scripted $17.5, active $7.0 (p25-p75 3.8-9.0; the active player spends it on seeds and bait). Truck income year 1: scripted $239, active $284.

D88 changes only what the player is told (tip card, Catalog line) and the starter field's layout; starting cash and junk pay are unchanged. The compact starter field moves idle from 17 to 19 failures of 20 (a seed or two, within noise); scripted and active are identical.

Recommendation (not applied, the user decides): leave $6 and $2-$6 alone. If the first Catalog order still feels out of reach, the cheapest lever is 	uning.run.money 6 to 9 (one extra seed or bait order before any junk sells, no effect on the year-1 income of the truck, which is $240 to $280). Raising junk pay would also lift the early curve but changes how fast the first truck trip (#129, median day 5) is reached, so test it with the harness first.

## Meal order: eat what spoils first (#189, D94)

`lovec tools/balance policy=scripted,active seeds=6 years=2`, before and after the change (all runs alive both times, 0/6 failed in each policy; nothing was retuned):

| | scripted before | scripted after | active before | active after |
|---|---|---|---|---|
| Spoiled per run (units) | 10.8 | 11.5 | 809 | 752 |
| by food | potato 5.0, radish 5.8 | potato 0.2, radish 11.3 | potato 5.5, radish 803.7 | potato 2.5, radish 748.0, fish 1.0 |
| Truck income | $502 | $555 | $755 | $983 |

Read: the older potatoes are eaten instead of rotting (scripted potato spoilage 5.0 to 0.2) and the big active radish surplus is slightly smaller; scripted radishes rot a little more because fresh radishes now wait behind fish and milk. Six seeds is noisy (the per-seed spread is wide); treat the direction, not the decimals, as the finding.

## One wood and the seasonal curve: smoke test (#247, D104)

`lovec tools/balance policy=scripted,active seeds=5 years=2`, before (main at D103) and after. A **smoke test only** (D95: balance is deferred): nothing was tuned beyond making it sane. The changes: wood is the one fuel (heat 0.75, base cap 60, woodshed +60), the stove and campfire keep their 1.6 and 1 efficiency, and the nightly warmth is a curve over the year (`needs.warmthPeak` 8, `warmthCurve`) instead of 1 / 0 / 4 / 8 by season, so spring and autumn nights now cost wood and an uncovered one costs health.

| | scripted before | scripted after | active before | active after |
|---|---|---|---|---|
| Alive at the end of winter 2 | 5/5 | 5/5 | 5/5 | 5/5 |
| Wood/fuel coverage of the winter need, first day of winter 1 | 1.07 | 1.41 | 0.69 | 1.36 |
| same, first day of winter 2 | 0.55 | 0.63 | 1.10 | 0.97 |
| Winter need (warmth), winter 1 / 2 | 68 / 94 | 60 / 81 | 68 / 94 | 60 / 81 |
| Wood sold per run (units) | firewood 10, seasoned 3 | 0 | wood 7, seasoned 2 | wood 11 |

Read: survival is unchanged. The winter need is about 12 percent lower because the curve ramps in and out (the first and last winter nights are below the peak). One fix came out of the first smoke run: with the automatic keep covering one winter only, the scripted player sold wood the second winter needed and 2 of 5 runs died of cold in winter 2 (the D75 lesson again), so the keep now covers `tuning.food.keepWinters` = 2 winters. The scripted player is still thin in winter 2 (coverage 0.63, as it was at 0.55: the routine only clears brush and logs, never trees), which is the existing finding below under "Recommended tuning changes", not a new one.
