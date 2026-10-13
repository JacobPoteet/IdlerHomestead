# Plan: one wood currency, heat as the winter bill (Frostpunk-style)

Status: **Phase 1 built** (D104, #247). Phases 2 and 3 are dropped by the user's answers in section 9 (heated spaces, stoke levels, woodlot, dismantle-for-fuel). Sections 1 to 8 are the original proposal and kept for the reasoning; where they differ from D104, D104 wins (for example campfire efficiency stays 1 and the stove 1.6, wood heat is 0.75, and the nightly need is read from the curve in tuning/needs.lua).

## 1. Why
Today wood has three forms and three jobs (GDD D36, `tuning/firewood.lua`, `content/resources.lua`):

| Form | Made by | Heat | Other use |
|---|---|---|---|
| `wood` (logs) | clearing trees/logs | none | building, smoker fuel, truck cargo |
| `firewood` (green) | chopping block, 3 s per batch of 2 | 0.5 | sells at wood price |
| `seasoned_firewood` | woodshed seasons green firewood | 1.0 | sells at 2x |

Plus a routine category (split), a `keepWood` reserve, a chopping block, a woodshed, two caps, two pantry rows, and keep/spare targets (D75). That is three numbers to watch for one need. The user wants one wood currency and a warmth need that is small in summer and large in winter, with expenses that feel like Frostpunk.

## 2. What Frostpunk does (and what we take)
Sources: [Frostpunk guide on resources](https://gamingbolt.com/frostpunk-complete-guide-scenarios-collecting-and-managing-resources-book-of-laws-hope-and-discontent-and-more), [PC Gamer tips](https://www.pcgamer.com/frostpunk-guide/), [Slant review](https://www.slantmagazine.com/games/review/frostpunk), [Xbox Wire on the society system](https://news.xbox.com/en-us/2019/10/11/frostpunk-society-system-available-today/), [critical play report](https://lab.indienova.com/indie-game-review/critical-play-report-frostpunk/). The numbers on fan sites vary by version; I only use the structure.

| Frostpunk idea | How it works there | Our version |
|---|---|---|
| **One dominant fuel, one standing bill** | Coal feeds the generator and heaters; consumption is continuous and rises with the cold. Running out is the loss condition. | Wood is the only fuel. Every night has a wood bill = warmth need / stove efficiency. |
| **Demand scales with the cold** | Colder days and nights raise heat demand; cold snaps spike it. | Warmth need becomes a smooth curve of the season's temperature (tiny in summer, large in winter) times severity (D37) times shelter insulation (D82). |
| **Every heated space adds to the bill** | More buildings, more heaters, more coal; expansion has a running cost, not just a build cost. | Each heated space pays a nightly wood bill in the cold months: your shelter, the coop/pen (animals), a pump house/cellar (ties to #91, #211), a workshop later. Growth raises the winter bill. |
| **Push the generator, at a risk** | Overdrive for more heat, with strain that can blow it up. | Stove heat level: Low / Normal / Stoke. Stoke gives more warmth (cold snaps) for roughly double the wood and a small chimney-fire chance (seeded). Optional, phase 3. |
| **Storage caps stop extraction** | Hitting the depot limit halts gathering. | Already built (D59: hold, don't destroy). A woodshed raises the cap and keeps the wood dry. |
| **Running costs are always on screen** | Resource bar shows stock and net per hour. | Add "Wood: N, burning M a night, X nights left" to the wood chip/readiness (D70). The key readout. |
| **Emergency choices when it goes wrong** | Desperate laws and measures, each with a cost. | Dismantle-for-fuel: break down a placed object (uses D98 pick-up) for wood, losing the object. Always available, always painful. No hope/discontent meter: our equivalents are condition and the journal. |
| **Scouting and forecast** | A cold snap is forecast; you prepare or suffer. | Already built (D51, D70 forecast pieces). Keep. |
| **Finite local deposits** | Coal piles run out; you invest in better extraction. | Trees on a plot are finite. Add a woodlot (plant saplings, slow regrowth) as the sustainable rung, replacing the split/season rungs. |

What we deliberately do not copy: the hope/discontent bars and laws (they model a population; we have one homesteader and a journal), forced-labour trade-offs, and the heavy city-sim UI.

## 3. What it would look like in play
- **Summer:** wood is for building and the smoker. The stove is off. A few logs a night at most (light cooking/smoking fire). Clearing trees is about making room and money.
- **Autumn:** the forecast says how hard winter is. You count the bill: "Need ~120 wood for the cold months; have 70." Every tree you fell, every dismantled crate, every woodlot row is a decision.
- **Winter:** each night the stove burns the night's bill automatically from the stock (the routine does not decide *whether* to heat; D36 stays). Cold snaps spike the bill. Heated animals and a heated pump house add to it. When stock runs low the chip turns amber then red, and the emergency option appears.
- **Choices that matter:** where to put the shelter (insulation, heater slot radius, D82), whether to heat the coop, whether to plant a woodlot early, whether to stoke through a snap, whether to sell wood for money or keep it.

## 4. Mechanics
1. **Resources:** keep `wood`. Remove `firewood` and `seasoned_firewood`. `wood` gets `heat = 0.75` (a log's old green+seasoned average) so total heat per tree is roughly unchanged at first.
2. **Warmth need:** `need(day) = baseNeed * tempCurve(season, day) * severity * snap` (curve data in `tuning/needs.lua`; summer near 0.05, deep winter 1). Wood burned = need * shelterInsulation / (heat * stoveEfficiency).
3. **Heat sources** (data on the object): campfire efficiency 0.5 (open, wasteful), wood stove 1.0, later a heat pump/electric (D49). Efficiency replaces the old x1 / x1.6 multipliers.
4. **Removed:** chopping block, split task and routine category, `keepWood`, seasoning timers. Smoker fuel reads `wood` directly.
5. **Woodshed** becomes dry storage: raises the wood cap; unsheltered stacks lose a small seeded share to rot each season (so it still matters, without a minigame).
6. **Heated spaces:** objects get `heatBill` (wood per cold night at severity 1); shelters, coop/pen and later buildings declare one. The nightly burn sums them.
7. **Display:** wood chip shows stock and "N nights" at the forecast severity; readiness (D70) uses the same accessor; Pantry shows one wood row with keep target (D75) and a "burning M per cold night" line.
8. **Ladder (replaces §5.3 fuel row):** deadfall + campfire -> axe -> wood stove -> woodshed -> woodlot -> heat pump/electric. Log splitter is dropped.
9. **Emergency:** "Dismantle for fuel" on any placed object's card (pick-up flow, D98), yields its build wood value.

## 5. Impact (what has to change)
- Content/data: `resources.lua`, `objects.lua` (chopping block, woodshed, stove, campfire, coop), `catalog.lua`, `ftue.lua`, notes/ideas text, `tuning/firewood.lua` and `needs.lua`, `shelter.lua`.
- Sim: `needs.lua` (warmth burn), `readiness.lua`, task categories (split removed), routine defaults, `market.lua` (keep/spare/cargo rows), `idle` priorities, `spoilage`/caps, threats text (cold snap), the harness policies.
- UI: Pantry rows, chips, tooltips, tip cards, journal nodes.
- Tests: firewood tests, readiness, pantry, keep targets, determinism; fingerprint/`SAVE_COMPAT` bump (saved resources change).
- Docs: new GDD decision superseding D36 (and the firewood parts of D59, D70, D75, D82), §4.2, §5.3 fuel row.
- Balance: the harness will shift (winter 1 fuel coverage, scripted/active income). Recalibrate after the change; fits D95 (MVP-first, balance later) as long as survival stays sane in the smoke test.

## 6. Phasing
1. **Phase 1 (core, one agent):** single `wood`, smooth warmth curve, stove efficiency, remove split/season/chopping block, nightly burn, readout "N nights", `SAVE_COMPAT` bump, harness smoke.
2. **Phase 2:** woodshed as dry storage with seeded rot; heated spaces bill (shelter + coop); emergency dismantle.
3. **Phase 3 (optional):** woodlot saplings, stoke level, cooking/smoker fire in summer, heat pump rung.

## 7. Where it fits
Phase 1 removes UI and tasks, so it reduces clutter. If done before the MVP polish it avoids re-tuning pantry and tips twice; if after, it forces a second pass over tip cards and the harness. Recommendation: do Phase 1 inside the MVP window (it simplifies what the player must learn and removes redundant work), Phases 2-3 Post-MVP.

## 8. Decisions needed from the user
1. One resource: drop green and seasoned firewood completely? (Recommended yes.)
2. Keep the woodshed as dry storage with a small seasonal rot loss, or remove it as well?
3. Finite trees plus a woodlot (replant) as the sustainable rung, or leave wood as it is: clear what's on the plot?
4. Heated spaces (coop/pen, pump house) paying wood bills in winter: yes, in Phase 2?
5. Stove heat level (Low / Normal / Stoke) with a small chimney-fire risk: yes or keep the stove simple?
6. Emergency "dismantle for fuel": yes?
7. Summer fuel use: a small year-round cooking/smoking burn, or truly zero until the cold months?

## 9. Decisions (user answers)
1. One resource: green and seasoned firewood dropped completely. **Yes.**
2. Woodshed kept as dry storage; it is **required to raise the max wood count** (without one the cap stays at the base value).
3. Trees: **leave as is** (no woodlot for now).
4. Heated spaces for coop/pump house: **no.**
5. Stove heat levels: **no, keep it simple.**
6. Dismantle for fuel: **dropped** (not wanted for now).
7. Summer fire: **none.** Spring and fall have a real (partial) warmth need: an uncovered night costs health. Winter is the large need. The need is a seasonal curve, not on/off.

Resulting Phase 1 scope: single `wood`; seasonal warmth curve (summer 0, spring/fall partial, winter full, times severity and shelter insulation); stove/campfire efficiency; remove chopping block, split task/category, `keepWood`, seasoning; woodshed = dry storage and the only way to raise the wood cap; readout of stock, nightly burn and nights left; `SAVE_COMPAT` bump. Phases 2-3 are dropped or deferred (heated spaces, stoke, woodlot, dismantle).
