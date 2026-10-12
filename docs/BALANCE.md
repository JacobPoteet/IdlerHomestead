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
| `out=file.csv` / `out=file.json` | CSV: one row per seed per morning (money, food, warmth, notes, known...). JSON: summaries plus one record per run | none |
| `set=domain.key=value` | override a tuning number for what-if runs, repeatable, e.g. `set=needs.dailyWarmth.winter=6` | none |
| `trace=1` | print the first seed of each policy day by day | off |
| `quiet=1` | no progress lines | off |

Speed: about 1 s per seed-year for `idle`, 3 s for `scripted`, 5 s for `active` (30 seeds x 2 years x 3 policies is about 5 minutes). Runs are deterministic per seed and tuning. The harness is not part of `lovec tests`, but `tests/test_balance_smoke.lua` runs one seed for a season so it cannot rot.

Files: `tools/balance/main.lua` (CLI), `balance.lua` (run loop, aggregation, reports), `policies.lua` (the three policies, with every player-behaviour knob in one `POLICY` table).

### Policies

- **idle**: the player never acts. The idle routine runs from the first second. It plans no field, so it never plants.
- **scripted**: day 1 plans one field tile per starting seed near the creek, then the routine runs. Each morning it makes a truck trip when the truck is charged and the crate is worth selling, orders the next item from a fixed buy list (woodshed, wood stove, axe, smoker, big bucket, sturdy rod, used panel), places delivered objects near the truck, and fills the study queue from a fixed list. It never gives a direct order.
- **active**: everything `scripted` does, plus direct orders like an engaged player: harvest, water (bucket hauling), plant, till, load the smoker/woodshed, split wood, fell trees for the winter's fuel (worst-case severity plus the longest snap), clear junk for cash, hand-fish with the rod, grow the field as seeds come in, buy seeds and bait. It sleeps at night (no orders at bedtime) so study progresses, and hands control to the routine after the takeover delay when it has nothing to order. The fishing mini-game is a dice roll (75 percent landed) plus plausible game time. This is a diligent player with perfect execution, so treat it as an upper bound on what a human achieves.

Metrics are sampled at the start of each morning. "Alive at season end" means the run reached the first morning after that season. "Fuel (winter nights covered)" is warmth in stock divided by the base winter need per night (4), before severity and cold snap.

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

- **idle** fails far sooner than winter: the starting kit is 4 canned food (2 days) and the routine never plans a field, so everyone is dead by day 6. That is a floor, not a pacing signal (nobody plays that way). It does show that an unattended start is fatal; see the follow-up issue on a default field plan.
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

Harness effect: `lovec tools/balance policy=scripted,active seeds=5 years=1` gives the same survival before and after (0 of 5 fail for both policies), with money and fuel medians within noise and about 3 percent more run time. The policies never buy power items, so the harness does not measure them; see the follow-up issue to teach them a power buy list.

## Water ladder (#35, D50)

Per in-game day a field of N crops wants N waterings (`farming.moistureDays` = 1). One cistern unit is one watering by bucket, or two by drip line (`water.dripUnitsPerWatering` 0.5).

| thing | number | note |
|---|---|---|
| solar pump (0.4 kW, 5 units/h) | up to ~50 units on a sunny summer day, ~20 in winter | scaled by `Power.sinkRatio`; it draws nothing once the cistern is full |
| cistern (60 units) | a full day for about 60 crops by bucket, 120 by drip | stock is shared and capacity adds up per cistern |
| bucket fill | creek 1.5 s, dug well 1.2 s, hand pump 0.6 s, cistern 0.4 s | a bucket holds 6 waterings (10 with the big bucket) |

Prices: dug well $20, hand pump $40, cistern $55, solar pump $70, drip line $25 (unvalidated against play). Harness effect: `lovec tools/balance policy=scripted,active seeds=5 years=1` gives identical survival, money, food and fuel numbers before and after, because no policy buys the rungs yet (#90); only the "journal nodes learned" and "ideas waiting" medians move by about one, because the well becomes a new idea once the bucket-hauling note is written and the policies study whatever is waiting.

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
