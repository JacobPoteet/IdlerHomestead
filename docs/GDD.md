# Idler Homestead — Game Design Document

> **Status:** v1.0, ready for implementation. See [§15 Decision log](#15-decision-log).
> Remaining **[OPEN]** items (§14) are non-blocking and get decided when their milestone comes up.

---

## 1. Elevator pitch

You drove your electric pickup as far from everything as its battery would take you, and it died on a messy, overgrown patch of land in early spring. You have no money, a few seeds, and basic tools. Clear the land, haul water, plant, fish, and build up solar and wind power: first to survive the winter, then to grow the homestead into a self-sustaining, automated place that can take whatever the next year brings.

You start out knowing nothing. Everything you experience goes into your **Field Journal**, and that knowledge outlasts every failed winter.

Play hands-on, or step away and the homesteader keeps working. Over time the homestead turns from a chore-driven survival scramble into a quiet machine that mostly runs itself, small enough to sit in a corner of your desktop.

**Genre:** Idle / incremental with roguelite meta-progression and survival pressure.
**Setting:** Modern off-grid. Solar panels, wind turbines, battery banks, a dead electric truck.
**Mood:** Quiet, solitary, natural. Cozy in the warm months, tense when winter comes.
**Platforms:** Windows first. Mac, Linux, Android, iOS, and web kept viable from day one.

---

## 2. Reference games: what to take from each

| Game | Take | Avoid |
|---|---|---|
| **Scritchy Scratchy** | Every action starts manual, then gets bought away (Scratch Bot, gadgets). Even once automated, doing it yourself still helps. Each run starts faster than the last. | Players report a plateau late in the game and say moving cards onto the auto-scratcher is tedious. Automation should never create *new* busywork. |
| **Cast n Chill** | Active and idle play are both first-class. Leave the controls alone and the game plays itself. A satisfying fishing loop with a fish guide to complete. Sparse music, nature soundscape. | Can feel empty once everything is found. Escalating years keep goals fresh. |
| **The Farmer Was Replaced** | Automation is the progression. It's satisfying to watch your system run. | Full programming is a steep wall. Borrow the *feeling* of building a system, not a code editor (§7.4). |
| **Ropuka's Idle Island** | Desktop ornament. Idling earns steadily, but *improving* the rate requires manual upgrades. | Weeks-long pacing. |
| **Frostpunk / Age of Empires** | Top-down settlement view. A known catastrophe on the horizon; the storm tests every earlier decision. | Grim moral choices, large populations. We're one person. |
| **Stardew Valley** *(contrast)* | Farming rhythms people already know. Top-down 3/4 view. | Social sim and town life. **We are isolated.** |

---

## 3. Design pillars

1. **Hands-on → hands-off.** Every chore starts as manual work. Progression means automating chores away: first by priorities, then by machines.
2. **Winter is the gate.** The first winter is the big test. Surviving it moves the game into its second half: scaling, automation, and harder years.
3. **Knowledge is the only thing you keep.** Gear, money, and land reset. What you've *learned* persists, and it's what lets you get back to where you were faster.
4. **Quiet isolation.** Nature, weather, solitude, a cat. Town is far away and getting there costs power.
5. **Idle anytime, active is better.** Let go at any time and the homestead keeps earning. Playing actively earns more, and only the player makes decisions.
6. **Lean into randomness.** Land, weather, threats, catalog specials, and finds all vary per run. Pull back where it hurts.
7. **Layout matters.** The homesteader walks everywhere, and the land is different every run.
8. **Show, don't tell.** Menus are icons, short labels, and visual links. No walls of text. Flavor text is always optional.
9. **Modular by construction.** Systems talk through shared interfaces; content and tuning are data. *(See §12.)*

---

## 4. Core structure: the run

### 4.1 Shape of a run: years with escalating challenge

A run lasts as many years as you survive. There is no "win screen". Each year asks more of you.

```
 YEAR 1: survival
 SPRING ─► SUMMER ─► AUTUMN ─► WINTER (the gate) ─┬─ fail ─► Rescue ─► Field Journal ─► new land, new run
                                                  │
 YEAR 2+: scaling                                 ▼
 SPRING ─► SUMMER (+ threat) ─► AUTUMN ─► WINTER (harsher) ─► ... until you fail
```

| Phase | Player focus | Pressure |
|---|---|---|
| **Year 1** | Survive. Clear the land, water, first crops, fishing, firewood, charge the truck, first sales. | The first winter is the big wall. Many first runs end here. |
| **Year 2+** | Grow and scale: more fields, livestock, a bigger power grid, machines, longer chains (smoking, canning, dairy, cattle). | Each year adds a **growing-season threat** (drought, locusts, blight, hail, early frost) and a harsher winter. |

| Season | Role |
|---|---|
| **Spring** | Clear the land, establish, plant. |
| **Summer** | Grow. Long days = strong solar = more truck trips. Year 2+: threats hit here. |
| **Autumn** | Harvest and stockpile: smoke fish, preserve, cut and season firewood, insulate. The **winter forecast** is revealed in pieces. |
| **Winter** | Survive: daily draw on food, heat, and water. No outdoor crops. Weak solar, so truck trips are rare and deliveries can be delayed by snow. Ice fishing. Long nights = **study season**. A **cold-snap peak**, like Frostpunk's storm. |

**Pacing:** ~15 real minutes per season at 1× was the original target (~1 hour for Year 1); since D56 a day is 320 s and a season about 27 min with fast sleep. All season lengths are tuning values (§12.3).

### 4.2 Surviving vs. failing

- **Needs** draw from stockpiles every day, all year: **Food** always, **Warmth** in the cold months (firewood / electric heat), **Water** (pipes and wells freeze without heat or insulation). Animals add their own needs.
- *Built (M3):* food and warmth are drawn each morning for the day/night just passed (`src/sim/systems/needs.lua`); the winter's severity and cold snap scale the warmth need (D36, D37). A drinking-water need is not in yet.
- If a need runs out, **Condition** (health bar) starts falling. If Condition hits zero, the run ends.

### 4.3 Failure: search & rescue → new land

1. **Rescue.** A search & rescue team finds you. Short scene: lights in the snow. You wake up recovering in town.
2. **Field Journal.** Review what you learned this run. Pick what to study during recovery (one free study, §8.3).
3. **New land.** You head out to a **new, randomly generated plot**. Nothing carries over except your knowledge and the starting gear and head starts it grants.
4. **Messy start.** Every new plot starts overgrown and cluttered: brush, rocks, fallen trees, junk. Clearing it is the run's natural **tutorial** and gives **starting resources** (wood, stone) and a **little money** (scrap and junk are worth a few dollars). Otherwise you start with **$0**.

**No salvage carries over from a failed run.** You get back faster because of what you've learned, and you only have that knowledge because the previous run got far.

*Built (M3):* `src/meta/run.lua` records each run in `meta.career` (run number, history of summaries), finishes the study in progress, and sets `meta.recovery` until the player heads out, so quitting mid-recovery resumes there. Scenes: `rescue` (lights in the snow; the rescuer's line changes after the first rescue) → `recovery` (run summary, notes earned this run, one free study) → `homestead` on new land.

---

## 5. Core loop

### 5.1 Moment to moment

```
 Do things ─► Harvest / catch ─► Eat · Preserve · Sell ─► $ ─► Buy from catalog ─► Better / automated work
     │                                                            ▲
     └─► Notes ─► Ideas ─► Study at night ─► Known ───────────────┘
```

### 5.2 Active vs. idle

**The rule:** idling grows you *linearly*. Active play is *more efficient*, and only the player can *raise the line*.

| | Active play | Idle |
|---|---|---|
| **Trigger** | Any input | After **N seconds** with no input (e.g. 30s; shortened by upgrades) |
| **Control** | **Click / tap** a target. The homesteader walks there and does it. | Homesteader follows the **priority list** (§7.4). |
| **Chores** | Faster, plus active bonuses (e.g. hand-watered crops grow a bit faster). | Done automatically at the base idle rate. |
| **Fishing** | The **tension mini-game** (§7.10). Rare fish possible. | Auto-fishes at a lower rate, common fish only. |
| **Decisions** (build, choose study, buy, food rules, plan fields beyond the starter, truck trips) | Player | **Never automated**, except the starter field when nothing is planned (D61). Pending decisions show as gentle notifications. |
| **Efficiency** | Base × active multiplier | Base × idle multiplier (raised by upgrades) |

Any input instantly hands control back. A **Start routine** button (key R) skips the wait and hands over at once (D43). Browsing a panel is not "input" for this timer, and a routine that was running at bedtime resumes at sunrise (D55). All multipliers live in tuning (§12.3) and will be iterated on heavily. When the routine takes over and nothing is planned, tilled or growing, it plans a small starter field (4 radish, 2 potato tiles by default) near the truck and water, so an unattended start does not starve (D61); it never touches a player-made plan.

### 5.3 Chores → automation ladder

| Chore | Rung 0 (manual) | Rung 1 | Rung 2 | Rung 3 (machines) |
|---|---|---|---|---|
| **Water** | Haul buckets from the creek | Dug well + hand pump | Solar DC pump → cistern | Drip irrigation |
| **Crops** | Hoe, sow, water, harvest by hand | Better tools, raised beds | Irrigated beds, greenhouse | **Auto-harvester** (radius), **mini-tractor** |
| **Fishing** | Basic rod, mini-game | Better rods, reels, bait | Fish trap / trotline (passive) | Pond stocking |
| **Fuel / heat** | Gather deadfall, campfire | Axe, wood stove | Woodshed (seasoning), insulation | Log splitter; heat pump (power-hungry in winter!) |
| **Food preservation** | Eat fresh, cooler | Root cellar, **smoker** | Solar dehydrator, canning | Chest freezer (power) |
| **Animals** | Hand-feed, hand-water | Feeders, waterers | Heated automatic waterer | Auto-feeder, egg collector |
| **Selling** | Truck trips only | **Roadside stand** (capped sales/day) | Stand upgrades (higher cap, cooler) | — |
| **Power** | Folding solar panel (trickle-charges the truck) | Fixed solar array | Battery bank, more panels | Wind turbine; micro-hydro; backup generator |
| **Shelter** | Sleep in the truck | Shack / shed | Cabin, insulation | Heated workshop |

**The winter power squeeze:** solar drops in winter just as heating, freezers, and pumps need more power, and you still want to charge the truck. This is our equivalent of Frostpunk's generator.

*Built (M5, #35): the water ladder* (`src/sim/systems/water.lua`; objects in `data/content/objects.lua`, knobs in `data/tuning/water.lua`, journal nodes on the Water & Soil page). Each rung removes more of the bucket chore, and the routine and hand hauling keep working at every rung (D50):
- **Rung 0, creek.** The bucket is filled at the water's edge (under ice, at a cut hole).
- **Rung 1, dug well and hand pump.** Both need a tile with a high **water table** (a seeded per-tile value, higher near the creek and in groundwater pockets away from it; wells and pumps are refused elsewhere, and the tiles are tinted while placing). They are closer places to fill the bucket: the dug well (rope and bucket) is a bit faster than the creek, the hand pump faster still, and neither needs ice cutting or power.
- **Rung 2, solar pump and cistern.** The pump is a power sink in the pumps tier; while there is room in the cistern it draws power and adds water at a rate scaled by how well the tier is served. The cistern gives the shared `water` stock its capacity and is itself a (fastest) place to fill the bucket, so the walk to the creek is gone once it is built.
- **Rung 3, drip lines.** Not an actor: every tick a drip line waters thirsty crops within its radius from the cistern stock, at half a bucket-slot per crop, so a stocked line means no bucket trips at all. With the stock empty the zone is **dry** (red status light and zone tint, a toast, the object card says so) and the routine hauls by hand again.

---

## 6. Economy

### 6.1 Money vs. knowledge

| | **$ Money** | **Knowledge** |
|---|---|---|
| Is | What you *have* | What you *know* |
| Comes from | Selling goods (truck trips, roadside stand); a little from clearing junk | Doing things → Notes → Ideas → Study (§8) |
| Used for | Buying known items from the catalog | Deciding *what* is in the catalog, plus perks |
| Persists? | **No**, $0 each run | **Yes**, forever (per save slot) |

Knowledge is **not a currency**. It's never spent. You earn it by doing and choosing what to study.

### 6.2 Food flow: eat, preserve, or sell

```
                                    ┌─► PANTRY ────► eaten daily
 HARVEST / CATCH ─► fresh, spoils ──┼─► PRESERVE ──► smoked / canned / dried (keeps all winter; sells for more)
                                    └─► SELL CRATE ► roadside stand (trickle) or truck trip (all at once)
```

**Food rules** (the player sets two things, the idle homesteader follows them):
1. **Pantry reserve**: one slider, "keep **N days** of food". Fresh food fills the pantry first.
2. **Winter stock goal**: one slider, "aim to preserve **N days** for winter". Surplus goes to preservation while you're under the goal and own a processor that accepts it.
3. **Everything else → sell crate.**
4. **Per-item override** (optional): tap an item to pin it to *Keep*, *Preserve*, or *Sell* (e.g. always sell tomatoes, never sell trout).

Defaults are sensible, so a new player never has to touch this. The rules generate `process` and `haul` tasks for the task system (§7.4).

### 6.3 The catalog

- A modern off-grid supply catalog. Items come in three states: **unknown**, **idea** (visible, not yet studied), and **known** (buyable).
- A small **starter page** is always known: seeds, basic tools, basic bait.
- **Order anytime, it gets delivered.** Deliveries arrive after a delay (e.g. next morning) at the **drop-off point** where your road meets the plot. Where you build storage relative to the road matters. Small delivery fee. Snow can delay winter deliveries.
- **Pickup only:** animals and oversized items (and trailer-dependent ones) must be collected on a truck trip.
- **Random specials:** a few discounted or rare items each week. Some are **in-store only** (a reason to drive).

### 6.4 Selling

| Channel | How it works | Trade-off |
|---|---|---|
| **Truck trip** | Load the truck, drive to town (a menu), sell **the whole sell crate at once**, up to cargo capacity. Buy pickup-only items and in-store specials. No delivery fees. | Costs a big chunk of truck charge. Few trips early on. The big payday. |
| **Roadside stand** *(unlock)* | Sells **N items per day** from the sell crate automatically, cheapest goods first, at 60 percent of town price (D52). Idle-friendly income. A per-item "Truck" pin in the Pantry keeps a good off the stand (D62). | **Always capped.** Upgrades (sign, cooler, display) raise the cap but never remove it. |

Prices vary week to week. Some goods are in demand. Preserved goods sell for more than fresh.

**More power → more trips → more income.** Power is the economy's bottleneck.

---

## 7. Systems

### 7.1 Time & calendar
- Fixed-step simulation tick, separate from rendering. Time scale adjustable: a debug key, and a player speed button (paused / 1x / 2x / 4x, D42).
- **No offline progress.** Time only passes while the game is open. Keeps running when unfocused or minimized (desktop). Mobile suspends, so time pauses.
- Day/night cycle, seasons, weather. Weather affects crops, solar, wind, fish activity, and threats. Day-to-day weather (clear, cloudy, rain, windy, storm) is a seeded, season-weighted run of spells with an exact few-day forecast (D51).
- **Nights** are when studying happens (§8.3).

### 7.2 Resources
- A single **ledger** of typed resources: `water`, `wood`, `firewood`, `stone`, `scrap`, `seeds.*`, `crops.*`, `fish.*`, `preserved.*`, `eggs`, `milk`, `money`, `power`...
- **Storage limits** come from buildings (woodshed, cellar, battery bank, freezer).
- **Spoilage**: fresh food decays; preserved food doesn't.

### 7.3 Land, grid & placement
- **New random land every run**, generated from a seed: creek course, ponds, soil quality, trees, rocks, water table, wind and sun exposure, road / drop-off position. Every plot has trade-offs.
- **Starts messy** (§4.3).
- **Tile grid.** The sim knows only grid coordinates.
- **Free placement on the grid:** fields are tile areas. Buildings have footprints and placement rules.
- **Walking distance matters.**
- Buildings are composed from **components**: `Producer`, `Consumer`, `Storage`, `PowerSource`, `PowerSink`, `Battery`, `Upgradeable`, `Freezable`, `HeatSource`, `AreaOfEffect`, `Processor`, `Shop` (roadside stand)...

### 7.4 Tasks, actors & priorities (the systemic core)

Everything that needs doing is a **Task**. Everything that does work is an **Actor**. Manual play, idle play, and automation are the same system with different actors choosing tasks differently.

**Task categories:** `clear`, `water`, `plant`, `harvest`, `haul` (move goods to pantry / smoker / crate / stand), `process`, `fuel`, `animals`, `fish`, `maintenance`.

| Actor | Chooses tasks by | Capabilities / area |
|---|---|---|
| Homesteader (**active**) | Player click/tap | Everything; full efficiency + active bonus |
| Homesteader (**idle**) | **Priority list** | Everything; idle efficiency |
| **Auto-harvester** | Nearest in radius | `harvest`, within radius |
| **Sprinkler / drip line** | Not an actor; satisfies `water` tasks in its area (built: drip line, §5.3 and D50) | `water`, area |
| **Mini-tractor / robot** (late) | Its own priority list | Several categories, a zone |
| **The cat** | Its own logic | Mouse control (§7.7) |

*Built (M6, #42): the machine framework and the auto-harvester* (`src/sim/systems/machines.lua`, `Tasks.chooseAreaJob`, knobs `data/tuning/machines.lua`, D65). A placed object with a `machine` definition (capability set of task categories, optional task ids, a radius, a work speed) is a stationary actor: it claims the nearest doable target of its categories within its radius through the same reservations as the homesteader, works it in place, and draws power as a "demand" sink in the machines tier only while it has work. The auto-harvester ($150, Machines chapter) picks ripe crops within 3 tiles.

**Priorities v1:** the idle homesteader has an ordered list of categories (default from data). The player can **reorder** and **toggle** them. Later layers on the same list: thresholds, per-machine lists, rule cards. Within a category, tasks are scored by urgency and **walking distance**. The scoring function is swappable.

### 7.5 Power
- A **network**: sources produce, batteries buffer, sinks draw. Supply/demand → satisfaction ratio. Priority tiers (heating outranks the freezer).
- **The truck is a battery on the network**, the only one at first. Charging for a trip competes with homestead use.
- Sources: folding panel (tiny), solar array, wind, micro-hydro, generator.
- *Built (M5, #34):* the network lives in `src/sim/systems/power.lua` and is content-driven (`data/content/objects.lua`: `source`, `battery`, `sink`; knobs in `data/tuning/power.lua`).
  - **Sources** have an output curve: solar follows the sun's arc and the season (and cloud, via `Weather.powerInputs`), wind follows a seeded hourly wind model and is strongest in winter, micro-hydro is steady but seasonal and must touch the creek, a generator starts only when sinks are short after batteries and burns `fuel`.
  - **Sinks** name a priority tier and a draw in kW. Tiers: heating, pumps, freezer, lights, machines. A sink runs on a schedule: `always`, `dark` (outside daylight), `heat` (dark hours of cold seasons, until the night's warmth is made), `fill` (pumps, while the store has room) or `demand` (machines, while their owner asks, D65). Real sinks today: electric heater (turns kWh into warmth that replaces firewood at the night's accounting), work lamp (study speed), chest freezer (slows spoilage). Pumps (#35) and machines (#42) plug into the same tiers.
  - **Priority list** (D46): one ordered list of tiers plus two charge tiers (battery bank, truck). Generation is handed out in list order; a short sink tier is topped up from batteries and then a generator; every sink in a tier gets that tier's satisfaction ratio (`Power.sinkRatio`). The player can reorder the list, switch sinks and the generator off, and stop the truck lending power.
  - **The truck is a battery on the network** (D47). Homestead load is served before the truck charges (unless the player moves "Truck charging" up the list), and the truck lends charge to the homestead only above a trip reserve.
  - **The winter squeeze** is the balance target: a 3 kW array makes about a quarter of its summer energy in winter, wind helps, and a heater plus long dark hours triple the load, so heat, freezer, lights and truck trips compete.
  - UI: a Power panel (button under the speed controls, or tap any panel/battery/device) with generation, load, satisfaction, battery bars, the priority list, sources and a switch per device. Devices show a status light in the world.

### 7.6 The truck
- An **electric pickup**. At run start the battery is flat; it's shelter and storage. The **folding solar panel** trickle-charges it.
- **Truck trip** menu (§6.4) when charged enough. No driving gameplay.
- **Upgrades:** bigger battery, bed rack (cargo), trailer (animals, oversized items), bed-mounted solar.

### 7.7 Animals & wildlife

| Animal | Role | Unlock |
|---|---|---|
| **Cat** 🐈 | Companion. Wanders, naps in sunny spots, pettable. **Catches mice.** Without a cat, mice occasionally ruin a crop tile or nibble stores. | Early (cheap, or a stray that shows up) |
| **Fish** | Food, money, collection (§7.10). | Start |
| **Chickens** | Eggs, meat. Need feed, water, coop. Predators at night. | Year 1 |
| **Goats** | Milk → cheese, money. Fencing, shelter, winter hay. | Year 1–2 |
| **Cattle / bulls** | **The big payday.** Sell, or process for a winter of food. | Year 2+ |
| **Wild** | Foraging, trapping. Pests: mice, rabbits, deer, locusts. Predators for poultry. | Varies |

Slaughter / butchering is **off-screen**: a menu action that yields meat.

*Built (M5, #36): mice and the cat* (`src/sim/systems/cat.lua`, knobs `data/tuning/cat.lua`, D54). Each night a seeded roll may send mice to ruin a few units of stored fresh food; a cat (the catalog's Shelter cat, $12, or the stray cat find) catches most raids. The cat wanders, naps in sunny spots, sleeps by the truck at night, eats a fish a day, and can be petted with a tap.

*Built (M6, #40, part one): chickens* (`src/sim/systems/animals.lua`, knobs `data/tuning/animals.lua`, D63, D64). Goats, milk, cheese, hay and the trailer are the rest of #40 (issue #139).
- **Unlock**: the Chicken coop and Hens are journal ideas on the Animals page, written by the notes "First harvest" and "Town trip"; study 2 and 1 nights. The coop ($45, comes with a first sack of feed) is placed on the plot (not on the road); hens ($18 for three) are pickup only, bought on a truck trip, and need a coop with room.
- **The flock** is the ledger resource `hen` (capacity comes from placed coops, six each). Needs: feed from the feeder, water from the waterer, shelter at night. Winter is the pressure: in spring to autumn hens forage for part of their feed, in winter for none, so a winter flock eats more than twice what a summer one does and lays about a third as many eggs.
- **The chore**: the `animals` task category ("Tend animals", after harvest and water in the default routine) has one task, **Tend hens**: collect the eggs from the nest box, top up the feeder from the feed in the ledger, fill the waterer. The idle routine goes when three eggs wait or a bowl is half empty; a tap on the coop does it any time. An active or idle player never needs to do more than that.
- **Eggs** are a food resource (`egg`): they go through the pantry, crate, stand and truck like any other food. A full egg store keeps them in the nest box (D59); a full box stops the laying and says so.
- **Forgiving but real**: a day with under half the feed or water met is a hungry or dry day; four hungry days (two dry) in a row cost a hen each day after that. A fed day starts the count again.
- **Predators** (D64): once a night a seeded roll may bring a fox; the coop door, the learned Predator fence and the cat turn it back, bad weather makes it likelier; otherwise it takes a hen or two.

### 7.8 Characters (sparse)
The **cat**. **Town** (text only, via the truck and catalog). **Search & rescue** (a recurring rescuer: "You again?"). A **distant neighbor** on the radio (story fragments, weather hints).

### 7.9 Events & threats
- Data-driven random events weighted by season, year, and run seed: drought, early frost, hail, blight, locusts, storm damage, mice, predators, a stray cat.
- **Year 2+ threats** are scheduled escalations with countermeasures to learn and buy.

### 7.10 Fishing

A **headline activity**: a satisfying skill toy and a collection.

- **Tension meter mini-game (active):**
  1. **Cast**, then wait for a bite (a bobber dip and a sound cue; react in time to hook it).
  2. **Fight:** a tension gauge. **Hold** to reel (gains line, raises tension). **Release** to let the fish run (lowers tension, loses line). The fish has **stamina** and **surges**: reel when it tires, ease off when it pulls.
  3. Tension maxed too long → the fish **slips the hook** (gentle: no lost gear). Fully reeled in → caught.
  4. **Single input** (hold / release), so it works the same with mouse, key, or touch.
- **Gear** raises max tension, reel speed, and bite chance. **Fish** differ in strength, stamina, and surge pattern.
- **Idle:** auto-fishes at a lower rate, common fish only. **Rare fish require active play.**
- **Variety:** species vary by **spot** (creek, pond, lake, ice hole), **season**, **time of day**, **weather**, and **bait**.
- **Fish guide:** collection log. A first catch of each species writes a **Note** (§8.1).
- **Uses:** eat, **smoke** (preserves for winter, sells for more), sell.
- **Winter:** ice fishing.

### 7.11 Save slots
- **3 slots.** Each slot = its own knowledge (journal) + the current run.
- **Renameable**; the list shows **name, year, season, total playtime**.
- Autosave on a timer and on focus loss / suspend.

---

## 8. Knowledge: the Field Journal

### 8.1 Flow

```
 DO THINGS ─► NOTES ─► IDEAS ─► STUDY (nights) ─► KNOWN ─► catalog item buyable / perk active
             (what     (what you  (you choose     (permanent,
             happened)  could try) which one)      every future run)
```

| Stage | What it is | Example |
|---|---|---|
| **Note** | A specific thing you experienced. Written automatically by game events. One icon + one short line. | 🐟 *"Fish spoil in 2 days"* (triggered when a fish spoils) |
| **Idea** | A catalog item or perk whose **required Notes** you now have. Appears on the journal map as a sketch. | 💡 **Smoker** (needs: *first catch* + *fish spoil*) |
| **Study** | You choose one Idea to study. It progresses **at night** while the homesteader sleeps. Longer nights in winter = faster studying. A desk / lamp speeds it up. | Smoker: 2 nights |
| **Known** | Permanent. Catalog items become buyable; perks take effect. | Smoker in the catalog → order it → delivered tomorrow |

- **Nothing is spent.** Notes stay. One Note can feed several Ideas.
- **Choosing what to study is a decision**, so it's never automated. If nothing is queued, a gentle prompt shows. The **study queue** holds a few Ideas in order.
- **Notes and Known items persist** across runs (per slot). A study in progress when you fail finishes during recovery (§4.3).
- **How it's built (M3):** Notes are content (`data/content/notes.lua`): an event name, an optional field match, and an optional count ("10 fish caught"). Catalog entries list the Notes they need and their study length in nights. Study progress accrues while the homesteader is in bed: from `tuning.actors.eveningHours` after the season's sunset (`tuning.time.daylight`) until sunrise. One "night" is `tuning.study.nightHours` hours in bed, so a long winter night is worth more than one study night and a short summer night less (D34, D35). Equipment with a `studySpeed` modifier (desk, lamp) speeds it up.

### 8.2 What can be known

- **Catalog items**: gear, buildings, seeds, animals, machines.
- **Perks**:
  - **Starting gear**: "pack a better rod / an axe / a seed tin next time."
  - **Head starts**: truck partly charged, a little starting food.
  - **Habits** (idle): shorter idle takeover, better idle efficiency, more priority options.
  - **Weather sense**: earlier or more accurate forecasts.
  - **Discoveries**: new crops, fish, animals, events in future runs.
- *Built (M3):* perks are content (`data/content/perks.lua`) sharing one id space with the catalog as journal nodes. Run-start effects (`startingResources`, `startingEquipment`, `truckCharge`) are handed out once per run by `src/sim/systems/perks.lua`; `modifiers` (`idleTakeover`, `idleEfficiency`, `forecastLead`, ...) apply through `src/sim/stats.lua` like equipment. Discoveries are not in yet.

### 8.3 Journal UI: a visual map, not text

The journal is a **knowledge map**, not pages of prose. It's an interactive layout of nodes:

```
   ┌─ FISHING ───────────────────────────┐   ┌─ PRESERVING ─────────┐
   │  [🐟]──┐                            │   │                      │
   │  [🎣]──┼──► ( Better rod ✓ )        │   │  ( Smoker ✎ 1/2 )    │
   │  [🌙]──┘          │                 │   │    ▲     ▲           │
   │                   ▼                 │   │  [🐟]  [🦠]          │
   │            ( Fly reel ? )           │   └──────────────────────┘
   └─────────────────────────────────────┘
   [🐟] = Note stamp    ( ) = node    ✓ known   ✎ studying   💡 idea   ? unknown
```

- **Nodes** (items and perks) are grouped by **chapter regions**: Water & Soil, Power, Fishing, Animals, Preserving, Shelter, Weather, Habits, Machines.
- **Notes are small icon stamps** with **lines** to the nodes they unlock. Seeing which experiences led where *is* the tech tree.
- **Node states are visual**: unknown (faint "?" with silhouette), idea (pencil sketch), studying (progress ring), known (inked and colored), owned this run (badge).
- **Tap a node** → compact card: icon, name, one-line effect, required Note stamps (filled / empty), study time, price. Buttons: *Study* / *Buy*.
- **Tap a Note** → its one line plus when you got it. Longer flavor text is optional behind a "read more" tap.
- **Journal and catalog share the same nodes.** The catalog is the same data as a shop view (known items, prices, specials, cart). One data model, two views.
- **Text budget:** labels ≤ ~3 words, effect lines ≤ ~8 words, no paragraphs in menus.
- *Built (M3):* `src/scenes/journal.lua` draws a pannable map (drag, arrow keys / WASD, mouse wheel; clipped to its viewport). Chapters are content (`data/content/chapters.lua`: each lists the node `page`s it holds, empty chapters are hidden) and `src/ui/journal_map.lua` lays them out: each chapter is a region with its note stamps on the left, its nodes on the right and a line from each stamp to the nodes that need it; regions are packed into columns in chapter order, each column as tall as the map viewport. A study-queue strip sits above the map (with the "nothing queued" prompt) and a notes strip below it (tap a stamp for its line and when and in which run it was written). Tapping a node opens the card over the bottom of the map: icon, name, effect line, needed stamps (filled / blank), study nights, price, and *Study* / *Remove* / *Order* (known catalog items go through `Market.order`, so the catalog and the journal stay one data model). Starter items show as known nodes with no stamps. Unknown nodes show a silhouette and "???" and never their name.

### 8.4 Run variety (lean in, pull back if needed)
Land (§7.3), forecast and threat order, weekly catalog specials, "pick 1 of 3" finds, random events. All randomness uses a **seeded RNG per run** (reproducible for testing and bug reports).

*Built (M5, #38): finds* (`src/sim/systems/finds.lua`, content `data/content/finds.lua`, knobs `data/tuning/finds.lua`, modal `src/scenes/finds.lua`, D53). A daily seeded roll queues an offer, shown as a modal of three distinct finds when the homesteader is not resting or fishing; pick one and its data effects apply.

---

## 9. Presentation

### 9.1 View: top-down 3/4
Slight 3/4 perspective (Stardew-style). Camera pans and zooms. Not isometric for now. Grid-only sim keeps that option open.

### 9.2 Art & audio
- Pixel art, **16×16 tiles (tentative)**, a single config value. Virtual resolution ~640×360, integer-scaled.
- Asset packs and/or custom art. **Placeholders first.** All sprites go through an **asset manifest**, so swapping art never touches game code.
- Strong palette shifts by season and time of day. Winter looks cold, quiet, and blue.
- **Shaders carry the ambience.** A big share of the game's mood and texture comes from LÖVE shaders: animated water, time-of-day color grading, film grain, and later wind, cloud shadows, night lights, rain, snow and frost, mist, and fireflies. They stay pixel-art friendly (snapped to the art-pixel grid, banded rather than smooth). Parameters live in tuning data and reload live (F6). The full list is in [docs/ASSETS.md](ASSETS.md).
- Audio: nature ambience, crackling stove, inverter hum, purring cat, sparse music, a great fish-on sound.

### 9.3 Desktop companion mode (first playable, Windows only)
A toggle into a small, borderless, **always-on-top**, draggable window. **View-only**: a framed view of the homestead plus minimal status (season, day, winter readiness, pending decisions). Built with LuaJIT FFI → Win32. Hidden on platforms that don't support it.

---

## 10. Platforms & input

| Concern | Approach |
|---|---|
| **Input** | An **input abstraction** emits *actions* (`select`, `pan`, `zoom`, `context`, `cancel`, `hold`), not raw keys. Mouse, touch, and keyboard map onto actions. |
| **Control** | Click / tap a target → homesteader walks there and acts. |
| **No hover-only UI** | Everything reachable by tap. |
| **Touch targets** | Minimum touch-target size in virtual units. |
| **Pan / zoom** | Mouse drag + wheel; touch drag + pinch. |
| **Screens** | Virtual-resolution scaling; UI anchors to edges and safe areas; 16:9 to ~20:9; window resizing. |
| **Lifecycle** | Autosave on a timer and on focus loss / suspend. |
| **Platform features** | A `platform` module exposes capability flags (`widgetMode`, `quitButton`, ...). Never check OS names in features. |
| **Performance** | Sprite batches / atlases for low-end phones. |

---

## 11. Pacing sketch (first run)

| Time | Player is... |
|---|---|
| 0–5 min | Messy plot, dead truck, $0. Clearing tutorial (→ wood, stone, a few $). Set up the folding panel. First Notes. |
| 5–15 min | Haul water, till, plant starter seeds. Fishing tutorial (tension mini-game). Idle takeover introduced. First night: first study. |
| 15–25 min | First harvest. Order seeds/tools from the catalog (delivered next morning). Fish spoils → *Smoker* idea. |
| 25–35 min | Summer. Truck charged: first trip, sell everything, big payday. Expand the field. Firewood. |
| 35–45 min | Autumn. Forecast: "a hard winter." Smoke fish, preserve, stack wood. Food rules matter now. |
| 45–60 min | Winter. Long study nights. Ice fishing. Stockpiles falling. Probably fails around the cold snap. |
| After | Rescue → Field Journal (lots of new Notes and Ideas) → new plot with better knowledge. |

The **first run is meant to fail**, ideally while still feeling close. Runs 3–5 should be the first to clear Year 1.

---

## 12. Technical architecture (modularity pillar)

### 12.1 Principles
1. **Definitions vs. state.** Content lives in data files. Runtime state is plain tables that serialize directly. Systems never hard-code content IDs.
2. **Systems talk through shared interfaces only:** the **resource ledger**, the **task board**, and the **event bus**. A system's slice of `world.state` is private: other systems read it only through small accessor functions on the owner (`Food.crateOf`, `Crops.tileInUse`, `Land.truck`, `Actors.list`). `tests/test_architecture.lua` enforces this per state key; the grid is the one shared structure.
3. **Simulation is separate from presentation.** Fixed tick, no LÖVE graphics calls in the sim. Grid coordinates only; projection lives in the renderer.
4. **Components over inheritance.**
5. **No magic numbers in systems.** Every balance value lives in data (§12.3).
6. **Seeded randomness** through a per-run RNG service.
7. **Meta vs. run state are separate.** Slot = `{ meta = knowledge..., run = current run... }`. Failing discards `run`, keeps `meta`.
8. **Notes are event-driven.** Systems emit events (`fish.caught`, `food.spoiled`); the journal listens and writes Notes based on data rules. Systems never know the journal exists.
9. **If adding a crop requires touching more than one data file, that's a smell.**

### 12.2 Module layout

```
game/
  main.lua                 -- LÖVE callbacks → app
  conf.lua
  src/
    core/                  -- engine-ish, game-agnostic
      app.lua              -- scene stack, virtual resolution, lifecycle
      events.lua           -- pub/sub event bus
      clock.lua            -- fixed-step sim clock, time scale
      registry.lua         -- loads & validates content definitions
      tuning.lua           -- loads tuning, strict access
      rng.lua              -- seeded RNG streams
      save.lua             -- slots, serialize/deserialize, autosave
      input.lua            -- raw input → actions; idle timer
      camera.lua           -- pan/zoom, grid↔screen projection
      platform.lua         -- capability flags, OS hooks (widget mode)
      assets.lua           -- asset manifest, sprite lookup
    sim/                   -- game rules, no rendering
      world.lua            -- owns run state, ticks systems in order
      systems/             -- calendar, ledger, grid, landgen, tasks, actors, crops,
                           -- fishing, food, processing, animals, power, needs,
                           -- threats, market, delivery, ...
      components/
    meta/                  -- rescue, run setup (the journal itself is sim/systems/journal.lua, state in meta)
    ui/                    -- HUD, panels, journal map, catalog, widgets
    scenes/                -- title, slots, homestead, fishing, truck trip, journal, rescue, widget
  data/
    content/               -- WHAT exists: crops, fish, buildings, animals, items, notes, events
    tuning/                -- HOW MUCH: all balance knobs
  lib/                     -- third-party (minimal)
  assets/
tests/                     -- headless sim tests + balance harness
```

### 12.3 Tuning & balance data
1. **Per-thing values live with the thing** in `data/content/` (a carrot's grow time, seed price, sell price, and Note requirements are all in the carrot's definition).
2. **Global knobs** live in `data/tuning/<domain>.lua`: `time`, `idle`, `needs`, `economy`, `study`, `fishing`, `threats`, `power`, `animals`...
3. **No numeric literals in system code.** Systems read `tuning.idle.takeoverDelay`, never `30`.
4. **Strict access.** Unknown keys error at load. Typos never silently become `nil`.
5. **Every value commented** with unit and intent.
6. **Curves** (winter severity per year, price drift) are tables or small formulas in tuning.
7. Later: **hot-reload** tuning files and an in-game **tuning panel**.
8. The **balance harness** reads the same files.

### 12.4 Libraries
Minimal, vendored in `game/lib/`. Prefer small in-house modules for core systems.

### 12.5 Testing
Headless sim tests, plus a **balance harness** that simulates years with scripted, idle-only, and active-like play, reporting survival odds, money, and knowledge curves.

---

## 13. Milestones

**First playable** = M0–M4: messy land → farm & fish → sell → winter → fail → rescue → journal → new land, in a window or as a desktop widget.

| # | Milestone | Proves |
|---|---|---|
| **M0** | **Skeleton**: scene stack, virtual resolution, camera, input actions (mouse + touch), fixed-step clock, event bus, registry, strict tuning, RNG, ledger, save slots (3, renameable), debug overlay. | Architecture holds on desktop and mobile. |
| **M1** | **First season slice**: seeded land gen (messy plot, creek, road), click/tap-to-act with walking, clearing (→ resources, a few $), till/plant/water/harvest, task board + idle priorities, idle takeover, calendar + day/night, food need. | Core loop + active/idle + task system. |
| **M2** | **Fishing & economy**: tension mini-game, fish guide, spoilage, food rules, smoker, catalog with delivery, folding panel → truck charge → truck trip, sell crate. | Eat / preserve / sell and the money loop. |
| **M3** | **Knowledge, winter & failure**: Notes from events, Ideas, night study, journal map (v1), firewood & warmth, winter, condition, rescue, new run. | The full roguelite loop. |
| **M4** | **Desktop widget mode** (Windows). → **First playable** | Ornament pillar. |
| **M5** | Power network (array, battery), well + pump, cat & mice, roadside stand, weekly specials, finds. | Hands-on → hands-off. |
| **M6** | Chickens & goats, Year 2+ threats, auto-harvester, priority thresholds. | Second half of the game. |
| **M7** | Cattle, mini-tractor, more content, art pass, audio. | Depth and feel. |

---

## 14. Open questions (non-blocking)

| # | Question | Decide by |
|---|---|---|
| 1 | Exact tension mini-game feel (bite window, surge patterns, how much gear helps). | M2, by prototyping |
| 2 | ~~Journal map layout: fixed hand-placed node positions, or auto-layout from data?~~ **Decided: auto-layout from data (D41).** | M3 |
| 3 | Can studying also happen during the day (sitting at a desk instead of working)? | M3 |
| 4 | ~~Player time speed-up (2×, 3×)? Unlockable perk?~~ **Decided: always available, paused/1x/2x/4x (D42).** | M3 |
| 5 | Tile size final (16×16 vs. 32×32) once art direction / asset pack is chosen. | Before M7 art pass |
| 6 | Does the widget follow the homesteader, or show a pinned spot (or both)? | M4 |
| 14 | ~~Does reading a panel count as "active" for the takeover timer?~~ **Decided: no, browse panels do not reset it (D55).** | M5 |

---

## 15. Decision log

| # | Decision |
|---|---|
| D1 | **Modern off-grid.** The player arrives in an **electric pickup truck** that's out of charge. It unlocks truck trips and acts as a battery once charged. No driving gameplay. |
| D2 | **Top-down 3/4 view.** Not isometric for now; grid-only sim keeps it possible. |
| D3 | **Years escalate.** The first winter is the big gate. Later years add threats and harsher winters. A run ends only on failure. |
| D4 | **Active > idle, but idle matters.** Idle earns linearly; upgrades are manual; tuned via data. |
| D5 | **No offline progress.** |
| D6 | **Failure = search & rescue**, then new land. |
| D7 | **Lean into randomness.** Pull back if needed. |
| D8 | **Priorities v1:** reorderable, toggleable category list; expandable. |
| D9 | **Animals:** fishing, chickens, goats, cattle/bulls. **Cat** prevents mouse damage. Slaughter off-screen. |
| D10 | **Desktop widget mode in first playable**, Windows-only, view-only. |
| D11 | **All platforms viable from day one**; Windows priority. |
| D12 | **~15 min/season**; tuning organized per §12.3. |
| D13 | **Free placement on a tile grid.** |
| D14 | **Machines are actors** in the same task system. |
| D15 | **New random land every run**, starting messy (tutorial + starting resources). |
| D16 | **Click/tap control; walking distance matters.** |
| D17 | **No salvage between runs.** Only knowledge persists. |
| D18 | **Fishing:** headline feature, **tension meter** mini-game, fish guide, **smoker**. Rare fish need active play. |
| D19 | **16×16 tiles tentative**, asset manifest, placeholders first. |
| D20 | **3 save slots**, renameable, showing year, season, playtime. |
| D21 | **Economy = Option 3:** learn, then buy; core catalog always stocked, random specials on top. |
| D22 | **Knowledge is not a currency.** Doing → Notes → Ideas → Study at night → Known. Nothing is spent. |
| D23 | **Journal is a visual knowledge map** (notes as stamps linked to nodes); journal and catalog share one data model. Minimal text. |
| D24 | **Order anytime, delivered** next morning to the road drop-off (fee). Pickup-only items and in-store specials need a truck trip. |
| D25 | **Selling:** truck trip sells everything at once (big payday); **roadside stand** unlock sells a capped number per day, always capped. |
| D26 | **Start each run with $0.** Clearing junk gives a little money. |
| D27 | **Food rules:** pantry reserve slider + winter stock slider + optional per-item pin. |
| D28 | **Shaders are a core part of the look** (water, color grading, grain now; weather, lights, seasons later). Pixel-art friendly, parameters in tuning, live reload. |
| D29 | **Starter crops: radish** (fast, light) **and potato** (slow, calorie-dense). |
| D30 | **Seed in hand:** tapping open ground with a seed selected tills and plans it for that crop; with an empty hand you just walk. A **Plan field** tool marks rectangles for the idle routine to farm. |
| D31 | **The sell crate is a reservation on stock**, not a separate store: crated food stays edible and keeps spoiling; selling removes it. |
| D32 | **Equipment = catalog items with stat modifiers** (rods, big bucket). Systems combine a tuning base with the owned modifiers. |
| D33 | **Every plot guarantees a walkable path from the truck to the creek** (land generation clears blockers along it). |
| D34 | **Study happens during the dark hours** of the season's day/night cycle (seasonal sunrise/sunset in tuning; solar output follows the same daylight). Winter nights are longest, so winter is study season. The journal is a sim system whose state lives in the slot's `meta`. Early learnable items: smoker, sturdy rod, big bucket, used panel; seeds, canned food, bait and the basic rod stay starter stock. |
| D35 | **The homesteader sleeps.** Bedtime is a couple of hours after sunset until sunrise, in the nearest shelter (the truck at first). The routine stops at bedtime; a player order wakes them ("stay up"), and they go back to bed when it's done. Study only progresses while resting, so staying up costs study time. |
| D36 | **Firewood & warmth.** Trees and logs give wood; the routine splits it into green firewood at the chopping block (keeping a little for the smoker). A woodshed seasons green wood (heat 0.5 → 1) and stores more. Each night needs a season-dependent amount of warmth (none in summer), burned in the best placed heat source (campfire ×1, wood stove ×1.6). Condition only recovers on a day that is both fed and warm. The campfire and chopping block are starting kit; the axe, woodshed and stove are learned. |
| D37 | **Winter.** Each year rolls a winter: a severity multiplier on the warmth need (range grows each year) and a cold snap (a few nights at ×2). Autumn reveals the forecast in three pieces (severity word, snap timing, snap length); a `forecastLead` stat reveals them earlier. In frozen seasons nothing grows or is planted, the first frost kills crops still in the ground, solar output drops (`tuning.power.seasonalOutput`), and using the creek means cutting an ice hole first (holes stay open until the thaw; the routine reuses them). |
| D38 | **Food model shortcuts kept for now** (issue #11): spoilage stays aggregate (fraction of stock per day), smoked fish stays one generic resource, food rules re-sort on an hourly timer. Fresh food flagged `keepsForWinter` (potatoes) tops up the winter stock after the pantry, standing in for a root cellar until one exists. Revisit with the balance harness. |
| D39 | **Recovery is a saved state.** Failing discards `run` immediately and stores the run summary in `meta`; the slot shows "Recovering in town" until the player heads out. The free study during recovery learns one current idea instantly. Notes remember which run wrote them, for the run summary. |
| D40 | **Perks are journal nodes like catalog items** (needs + study nights), not a separate tree. Head starts apply once at the start of each run; habit and weather-sense perks are stat modifiers. |
| D41 | **The journal map is auto-laid-out from data**, not hand-placed. A chapter lists the `page`s it holds; a node lands in the chapter whose pages list its `page`. Inside a chapter, notes sit in a column left of the nodes, ordered to keep lines from crossing, and chapters pack into columns left to right in file order. New content therefore never needs a position, and an empty chapter (animals, machines) stays hidden until it holds a node. A node's card offers *Order* for any known catalog item, so the journal map doubles as the shop view. |
| D42 | **Player game speed** is a button (key Space) cycling `tuning.time.speedSteps` (paused, 1x, 2x, 4x), on the same sim time scale the F2 debug key uses (one mechanism: `Session:cycleSpeed`). Always available, not a perk. Paused stops the sim only: panels, the camera and orders still work (an order given while paused starts when you resume). Speed is runtime state, never saved: a new session (loading a slot, starting a new run after recovery) starts at `tuning.time.defaultSpeed`; opening panels keeps it; the fishing mini-game drops it back to default so the world doesn't race past a real-time minigame. The idle takeover delay counts real seconds, not game seconds, at every speed. |
| D43 | **Start routine now.** A button (key R) makes the routine take over immediately. It is refused while the homesteader is resting (asleep, walking to bed, or any bedtime, D35) and the button reads "Resting". Control returns to the player on any order (a world tap that starts a task), as with normal takeover, after which the usual takeover delay counts from that moment; panning, zooming and opening panels do not cancel it. Bedtime pauses it, and the morning resumes it if it was running (D55). Panels no longer count as "active" for takeover (D55, was open question 14). |
| D44 | **Action progress ring.** The sim exposes `Actors.progress(world, actor)` (task, target, fraction, duration, remaining) for the current timed action; walking and instant actions (work time 0) have none. Render draws a circle that fills over the target tile, in UI pixels (constant size at any zoom), tinted differently for player and routine actions. Actions shorter than `visuals.actionRing.minSeconds` (0.5s of work) show no ring, to avoid flicker. Sizes and colors are in `data/tuning/visuals.lua`. |
| D45 | **Full storage never destroys goods the player already has a claim on** (#52). Purchases and finished output wait: a catalog order stays queued (and paid) until its goods fit, in-town pickups are refused with "no room" before any money is taken, a finished smoker batch stays in the station (partly delivered as room appears) and blocks it, and a mature crop is not harvested while its produce or seeds could not fit. Where waiting makes no sense (fish landed, clearing yields, a harvest that overflows mid-job) the surplus is discarded but announced: `Ledger.addOrOverflow` emits `ledger.overflow` and the player sees "Storage full: lost N X". Follow-ups: D59 (hold instead of discard, HUD indicators) and D60 (orders that can never fit). |
| D46 | **Power priorities are one reorderable list** (#34). Sinks name a tier (heating, pumps, freezer, lights, machines); two charge tiers (battery bank, truck) sit in the same list and fill batteries from spare generation. Default order: heating, pumps, freezer, lights, machines, bank, truck ("heating outranks the freezer", §7.5). Generation is handed out in list order; a tier left short draws from batteries (home bank first) and then a generator; all sinks in a tier share its satisfaction ratio. The player can reorder tiers, switch any device or the generator off, and the saved order survives new tiers being added later. Chosen over per-device priorities to keep the panel to seven rows on a phone. |
| D47 | **The truck is a vehicle battery on the network** (#34, §7.6). It is charged by the "truck" tier, so the homestead's load (default order) is served before a trip is charged, and the player can move it up. It lends charge to the homestead only above `tuning.power.truckReserveKwh` (24 kWh, above the 20 kWh trip cost), and the player can switch lending off, so a heavy winter night cannot strand a planned trip but a full truck can ride out an outage. Truck charging is lossless; home batteries keep 90 percent of what they are charged with (content `efficiency`). Trips still drain the truck directly. |
| D48 | **Sources and weather hooks.** Solar = peak x sun arc x `seasonalOutput` x (1 - cloud). Wind = peak x seasonal curve x (floor + (1 - floor) x wind) x weather scale, with `wind` a seeded random target each hour that the wind eases toward (stream "wind", saved in state). Micro-hydro = peak x seasonal flow, needs a creek-adjacent tile (`placeNear = "water"`), and runs day and night. Generator = fuel source: runs only for the shortfall left after renewables and batteries, burning `fuelPerKwh` of the `fuel` resource (bought as "Fuel x5"); the player can switch it off. `Weather.powerInputs(world)` returns `{ cloud, wind, flow }` (tuning constants now) as the documented input for day-to-day weather (#39). |
| D49 | **Electric sinks do real work** (#34). Electric heater: while it is powered during the dark hours of a cold season it stores warmth (`warmthPerKwh`) toward the night's need and idles at a thermostat once the need is met; `Needs.warm` takes that warmth first and burns firewood only for the rest (a full-power heater makes most of a mild winter night's warmth, never a cold snap's). Work lamp: a powered lamp adds `studySpeed` while the homesteader studies. Chest freezer: a powered freezer divides daily spoilage (`spoilSlow`); it stays cold for `inertia` hours after losing power. Sinks report `Power.sinkRatio` so pumps (#35) and machines (#42) can scale their work. Catalog gating uses existing notes plus one new one ("Full battery", from `power.full`); prices (array $110, bank $80, turbine $140, hydro $160, generator $90, fuel x5 $15, heater $50, lamp $15, freezer $90) put each item a few truck trips out, and the balance harness shows no change because its policies do not buy them yet (see issues). |
| D50 | **Water automation ladder** (#35, §5.3). (1) **Water table**: a seeded per-tile value `grid.waterTable` (0..1; noise plus nearness to the creek, own RNG stream `watertable` so the plot is unchanged, and older saves get the table their seed makes). Wells, hand pumps and solar pumps (`placeOn = "waterTable"`) need a tile at or above `tuning.water.table.minForWell`; the value only gates placement for now (#96). (2) **One shared stock**: the cistern is storage capacity for the ledger resource `water` (one unit = one bucket slot); any pump fills it, the bucket and drip lines drain it, and there are no pipes or hose distances (#92). "Water jugs" in the task brief are the bucket (`actor.bucket`). (3) **Pumps are power sinks** in the `pumps` tier with a new schedule `fill`: the pump wants power only while the stock has room, and adds `pump.rate` units an hour times `Power.sinkRatio`, so a brownout slows it and a full cistern stops its draw. (4) **Bucket sources**: the creek, the dug well (1.2 s), the hand pump (0.6 s) and the cistern (0.4 s, draws the stock) are all `fetch_water` targets and the routine takes the nearest by walking distance; the creek still works, and the wells have no ice work in winter. (5) **Drip line** (radius 2, a 5x5 patch, placed on free ground beside the field): each tick it waters any thirsty crop in range at `dripUnitsPerWatering` (0.5) of the stock, in anchor then tile order, so overlapping lines never double-water; a watered crop is no longer thirsty, so the routine does not haul for it. With under half a unit in stock the zone is **dry** (red light, tinted zone, toast, card text) and hand hauling resumes. Nothing is dripped while the ground is frozen. (6) **Journal**: five items on the Water & Soil page, gated by two new notes, "Well water" (first bucket from a dug well) and "Full tank" (first pumped water); prices well $20, hand pump $40, cistern $55, solar pump $70, drip line $25. (7) The HUD shows the cistern fill once one is placed; the tile card shows water table, stock, pump state and drip state. Not built, tracked as issues: winter freezing of pipes (#91), harness policies that buy the rungs (#90, balance harness unchanged), cistern drained by buckets (#93), real art (#94), a drinking-water need (#95). |
| D51 | **Day-to-day weather** (#39, §7.1). (1) **The sky** is a queue of whole days (`state.weather.sky`), rolled ahead (`queueDays` 8) from its own RNG stream `sky` (so the winter rolls are unchanged and the run is deterministic per seed). Each spell is one kind of five (clear, cloudy, rain, windy, storm) lasting `days` {min, max}; the next kind is `seasonWeights[season] x transitions[last][next]`. Winter weights rain and storm at 0, and rain that runs into a frozen season is shown as cloudy (snow stays the existing winter logic, #103). A run starts clear. (2) **Effects**, all from `tuning.weather.kinds`: `cloud` cuts solar, `wind` scales turbines and `flow` micro-hydro (through `Weather.powerInputs`, now state-driven), `fish` scales routine catch odds (capped by `fishing.maxIdleChance`) and divides the mini-game bite delay, `rainfall` waters every crop for free while it rains and gathers `rainWaterRate` units an hour into a cistern if one exists. The routine skips watering and bucket-fetching in the rain (the crops are wet anyway); the player can still order either. Nothing new is needed from the player: rain never costs a need. (3) **Forecast** is exact: today plus `forecastHorizon` (3) days, +1 day per point of the weather-sense `forecastLead` stat; shown as a pill above the winter forecast, with a toast on rain, storm and windy mornings. (4) **Threat hook**: `Weather.threat(world)` returns the kind's `threat` multiplier (storm 2, windy 1.2); nothing reads it yet (#97). (5) **Presentation**: a grey-blue tint and darker light by kind (eased over `visuals.weather.blendSeconds`) and CPU-drawn rain streaks (`visuals.weather`); wind sway and cloud shadows stay with #49, ripples and wet ground are #98. Cloud values were kept mild (cloudy 0.4) so solar and the first truck trip stay inside their existing balance windows; balance harness on 5 seeds shows no regression (scripted policy loses fewer seeds, most likely from rain saving watering). Open: intra-day fronts (#99), turbine output vs the hourly wind model (#100), harness policies that use weather (#101), forecast icons/panel (#102), snow as precipitation (#103), audio (#104). |
| D52 | **Roadside stand** (#37, §6.4). (1) **Unlock**: a Preserving-chapter catalog node ($40, 2 study nights) needing the notes "Town trip" (first truck trip) and "Produce rots", so the player knows the big payday and has surplus that spoils before it gets a trickle channel. Placed with `placeNear = "road"`: a 2x1 object whose footprint touches the road but never covers it (a spot exists on every seed, tested). (2) **Stock**: the **sell crate** only (`Food.crateOf`), so pantry, winter stock, kept and preserve-pinned goods are never touched; the stand reads the crate through Food and writes through Ledger (reason "stand"), then re-sorts. (3) **Daily sale**: once a day at `tuning.stand.sellHour` (17), if a stand is placed (more than one add nothing), it sells up to the day's cap, **cheapest town price first** (ties in resource order) so valuable goods wait for the truck, at `priceFraction` (0.6) of the week's town price; the day's total is rounded once so $1 goods still pay. (4) **Cap**: `baseCap` 6 + `standCap` modifiers of owned upgrades, clamped to `maxCap` 18, which is under half a truck's cargo (40); the stand cannot replace a trip. Upgrades are equipment catalog items (painted sign +3, cooler +4, display rack +5; $25/$45/$70) gated by the note "Stand sale" (first sale) plus "Fish spoil" (cooler) or "Regulars" (display, seven selling days). (5) **Flow**: today's cap is scaled by `seasonFlow` (winter 0.5) x `weatherFlow` (rain 0.5, storm 0.25) read through `Weather.kind`; both tables are at most 1, so weather and season only ever lower the cap. (6) **Feedback**: a toast "Roadside stand sold N items for $X", and the object card shows the cap (today's cap when reduced), the price share and the last sale. Event `stand.sold { day, units, earned, cap }`. (7) The balance harness policies do not build or buy the stand, so harness numbers are unchanged (see issues). |
| D53 | **Finds: pick 1 of 3** (#38, §8.4). (1) **Content**: `data/content/finds.lua` (schema in `data/schemas.lua`), nine finds (heirloom seeds, used panel, rusty toolbox, bait tin, dusty cans, seasoned stack, old axe, jump pack, coffee can cash). Effects are a small data vocabulary applied by `src/sim/systems/finds.lua` through existing systems: `resources` (ledger, overflow lost), `objects` (inventory), `equipment` (catalog equipment, not offered if all owned), `truckCharge` (kWh). There is no per-find code. (2) **Roll**: once a day at `tuning.finds.rollHour` (9) a roll from its own seeded stream `finds` queues an offer with chance `chancePerDay` (0.2), only after `firstDay` (3) and `cooldownDays` (4) since the last pick; the stream is drawn every day regardless, so it does not depend on cooldowns. (3) **Offering**: a queued offer waits until the homesteader is not busy (bedtime or resting, or on a job listed in `busyJobs`, now just hand fishing), then 3 distinct finds are drawn by weight: content `weight` x `seasons[season]` x `lackBoost` (3) when its `lacks` condition holds (a resource below N, no object owned or placed, equipment not owned); `minYear`/`maxYear` gate by year. A paused game never rolls (no ticks); an offer already pending simply waits. (4) **UI**: the homestead pushes a small modal when an offer is pending and it is the top scene (so never over the fishing mini-game or a panel, and again after a load). It stops time while open (speed restored on close), cannot be dismissed without choosing, selects with a tap or keys 1-3, and takes with "Take it". A toast "Took: name, line" follows. (5) **State**: `state.finds = { rollDay, lastPick, due, pending = { day, choices }, history }` (history capped by `historyLimit`); pending and queued offers are saved, older saves get defaults. Events `finds.offered`, `finds.picked`. (6) **Cat**: added with the cat in D54 (the stray cat find). (7) **Harness**: policies take the first option automatically; effect on year 1, 3 seeds: survival unchanged, more winter fuel and money (issue #111). Open: richer offers and content (#109), art and audio (#110). |
| D54 | **Mice and the cat** (#36, §7.7; also closes #108). (1) **Mice**: once a night at `tuning.cat.mice.raidHour` (23) a roll from its own seeded stream `mice` brings a raid with chance `chancePerDay` (0.3) x a season multiplier (autumn 1.4, winter 1.2, summer 0.7, spring 0.8) x `Weather.threat` (storm 2, windy 1.2; this is the first reader of the #97 hook), clamped to 1, and never before `firstDay` (6). Both rolls (the raid and the cat's catch) are always drawn, so the stream does not depend on stores or the cat. A raid ruins `lossFraction` (10 percent) of the stored units of resources in `targetCategories` (only `food`: radishes and potatoes; cans, fish, smoked fish and seed are safe), clamped to 1..6 units, taken one unit at a time (weighted by stock) through `Ledger.remove` with reason `mice`, so storage and the sell crate stay consistent. An empty larder means no event. Events `mice.raided { day, lost, units }` and `mice.caught`. Raids on crop tiles are not built (issue #114); the GDD line "ruin a crop tile or nibble stores" is half done. (2) **The note**: the first raid writes the note "Mice" (`mice_raid`), which makes the catalog's Shelter cat an idea (1 study night, $12, page Supplies). (3) **The cat is equipment**: owning catalog equipment `shelter_cat` (no stat modifiers) is what brings the cat, so both acquisition routes need no new vocabulary: the catalog purchase and the **stray cat find** (`effects.equipment`, weight 0.7, boosted by `lacks`, never offered once owned). It arrives at the spawn tile on the next tick (`cat.arrived`, toast). (4) **Not an actor**: the cat is not in `state.actors` (the homesteader is `actors[1]` and much code assumes tasks and jobs); it is its own state `state.cat` with its own logic: walk on A* paths at `walkSpeed` 1.6, choose a goal by stream `cat`: at night it sleeps by the spawn tile, in rain and storms it shelters there, by day `napChance` (0.5) it heads for a sunny spot (open tile with no tree within `shadeRadius`, found by sampling `sunnyTries` tiles within `wanderRadius`) and naps, else strolls to a random open tile and sits. Rest times are in game seconds (a day is 128 s). (5) **Upkeep**: at `feedHour` (18) it eats `mealUnits` (1) of the cheapest stocked fish (ledger reason `cat`). With none it is hungry: no punishment other than a lower catch chance, and it never leaves or dies (idle-friendly; upkeep design is issue #118). (6) **Effect**: a raid is caught with `fedCatch` 0.8 (`hungryCatch` 0.4) plus `bondCatch` 0.02 per bond point, so a fed, well-petted cat stops 90 percent of raids. (7) **Petting**: tapping the cat's tile pets it from anywhere (no walking there; no range, so it works on touch and in idle play); the first pet each day adds a bond point up to `maxBond` 5; a toast says "Purr". (8) **Saves**: `state.cat` is created with defaults on older saves, an owned cat then moves in on the next tick; the state is plain tables. (9) **Presentation**: placeholder sprites `cat`, `cat_nap`, `icon_cat` (issue #116); the renderer draws the cat in the actor depth sort, with z's when asleep. Toasts for arrival, raids (queued) and catches. (10) **Harness**: the policies do not buy the cat (issue #115); a year-1 run on 3 seeds (scripted, active) is unchanged in survival. Open: crop ruin (#114), art and audio (#116), better sleep and sunny-spot logic (#117), upkeep design (#118). |
| D55 | **The routine survives the night; menus do not count as active** (#113, resolves open question 14). (1) **Resume**: the sim keeps a persisted `state.routine.wanted` flag (system `routine.lua`): by day it mirrors whether the routine is in charge (started with R, D43, or taken over after `tuning.idle.takeoverDelay`); the R key sets it at once; any player order clears it; at bedtime it freezes. When the homesteader wakes (the session sees resting end) with it set, the routine resumes by itself, forced like R (input alone does not hand control back, an order does). A save that was resting with it set resumes in the morning too; a save without the table (pre-D54) loads with it off. Not set if the player had taken control before bedtime, or a "stay up" order cleared it. (2) **Menus**: input while a browse panel is on top (`tuning.idle.browsePanels`: catalog, journal, pantry, power, guide, truck, routine) does not reset the takeover timer, so reading a panel is not directing the homesteader and the routine takes over after the usual delay; world input, the fishing mini-game and modals still count. The badge keeps showing "Routine in Ns" while in a panel. (3) **Idle hint**: if the homesteader is awake, in daylight hours, with no job or order and the routine off for `tuning.idle.hintAfter` game seconds (45, about a third of a day), the sim emits `routine.idleHint`; the homestead toasts "Homesteader is idle: press R or tap Start routine" if the world is on top, at most once per `hintInterval` game seconds (120). Counted in game seconds (not in-game minutes: a game minute is under a tenth of a second at the 128 s day). Tests in `tests/test_controls.lua`; screenshots `docs/screens/routine_*`. |
| D56 | **Longer days, fast sleep** (#112, first pass from playtest, to be revisited). (1) **Day length**: `tuning.time.dayLength` 128 to 320 game seconds (2.5x). Everything derived from it (crop growth and drying in days, hour-based power, pump, rain, study, processing, stand and cat hours, pantry sort) scales on its own. Saves record their day length in `calendar.dayLength`; a save without one is rescaled from `time.legacyDayLength` (128) so it keeps its date and hour. (2) **Real-time feel kept**: walk speed, task and work times, mini-game timings, the idle takeover and hint timers, and the cat's idle and nap seconds stay in seconds, so the player simply gets about 2.5x more actions per day. (3) **Demands raised to match**: the harness showed the extra labour per day made year 1 much easier (active fuel cover at winter start 0.69 to 1.51, food in stock 3x). `needs.dailyCalories` 2000 to 3000 and `needs.dailyWarmth` doubled (spring 1, autumn 4, winter 8) bring it back within noise of the old numbers (docs/BALANCE.md). Condition damage and recovery per day are unchanged. (4) **Fast sleep**: while the homesteader is *asleep* (in bed, not walking there) the session runs the sim at `time.sleepSpeed` (8x) unless the player's own speed is higher; a pause stays a pause. It goes through the same fixed-step clock, only more ticks per frame, so results are identical to 1x (tested). (5) **Skip night**: the control column's routine slot becomes "Skip night" while asleep (key N, tap friendly); it runs at `time.skipSpeed` (60x) and ends on the very tick the homesteader wakes (the fast leftover is dropped), then speed returns to the player's choice. It is runtime state, never saved. (6) **Indicator**: a banner "Sleeping, N h to morning, Nx" under the top bar and the speed button shows the real speed. (7) **Study** is per in-bed hour, so a night yields the same as before and winter stays study season. (8) A season is now 7 x 320 s, about 37 min at 1x or about 27 min with fast sleep; the "~15 min per season" target (D12) is exceeded, see the follow-up on trimming `daysPerSeason` or crop days. |
| D57 | **Balance harness policy features** (#80, #90, #101, #105, #111, #115; tooling only, no sim change). (1) **`features=`** on `lovec tools/balance` switches optional player behaviours: `cat`, `stand`, `water`, `power`, `finds`, `weather` (`all` is the default, `none` plays the harness as before). (2) **Shopping**: feature items go on a strict-priority list (cat, stand, well, cistern, sign, array, bank, heater near winter, solar pump, two drip lines, lamp, turbine near winter, stand upgrades, hand pump, freezer, generator and fuel as a heater fallback, micro-hydro): the policy saves for the first wanted item it cannot yet afford instead of skipping past it, and keeps `POLICY.featureReserve` ($8) back for seeds and bait. The old core buy list stays greedy and goes first, except the $12 cat which goes before it. (3) **Placement**: stand beside the road, wells, pumps and cisterns near the field centroid, a drip line where its 5x5 patch covers the most planned tiles, power items in rings around the truck, micro-hydro on the nearest creek-side tile. (4) **Switching**: the truck tier is served before the bank until one season before winter, then the bank comes first so the heater has stored sun. (5) **Finds** are scored by need (cat, fuel near winter, seeds in spring and summer, the axe, a panel, cash when poor) and ties keep the offer's order. (6) **Weather**: the active policy lets rain do the watering. (7) **Metrics**: income by source per year (truck vs stand), kWh made, wanted, served, shed and wasted, nights heated electrically, waterings by hand and drip, cistern units pumped and rained, mice raids and losses, finds picked, kit owned at the end. Results and open balance questions are in docs/BALANCE.md. |
| D58 | **Harness speed and sim object index** (#123; also #78 and part of #77; tooling plus result-neutral sim changes). (1) **Parallel seeds**: `lovec tools/balance jobs=N` plays (policy, seed) pairs on `love.thread` workers (default the CPU count, capped at 16; `jobs=1` is the old single-thread loop), each a separate Lua state, and builds the report from the results in the plain loop's order, so the report and `out=` files are byte-identical; tested in `tests/test_balance_smoke.lua`. Threads were chosen over child processes (no Windows quoting, no temp files, a real work queue). (2) **Profile first** (`profile=1`, LuaJIT `jit.profile`): the hot spot was not the idle search but per-tick scans of every placed object in power and water. **Sim rule**: code that needs "placed objects with field X" uses `Grid.anchorsWith(world, field)`, a runtime index (`world.objectIndex`, never saved) dropped by every object write in `Grid`, sorted by anchor like the scans it replaces. (3) **Terrain writes** go through `Grid.setTerrain`, which drops derived caches (bank tiles, #78). (4) Task types may declare `canDoCandidate` for the idle search (#77, first half; the per-recheck Dijkstra is unchanged). (5) **No fast mode option**: `set=time.tickRate=5` already gives about 1.8x with small but visible drift in medians, so it is documented as smoke-only rather than wrapped in a `fast=1` flag. (6) **Determinism is the bar** for any sim speed work: harness output before and after must be byte-identical (docs/BALANCE.md lists the checks). Result: about 6x faster per seed-year (scripted 12.5 s to 2 s), 18x on a 3-seed all-policy year with threads. |
| D59 | **Hold, don't destroy: work waits for room** (#74, #76; supersedes the "discard but announce" half of D45). (1) **Clearing** is blocked until the largest possible yield of the object fits (`canDo`; the routine skips it, a tap is refused), so a tree is not felled into a nearly full wood store. (2) **Fishing** never offers a fish whose store is full: the idle routine does not cast and an ordered cast is refused when every biting species is full; the mini-game rolls only species with room and says "No room to keep a catch" if none; a fish whose store fills while it is on the line gets away (`fish.lost` reason `full`, not counted as caught, not in the guide); `fish.caught` and its toast fire only for fish actually stored. (3) **Mid-job overflow**: `canDo` is re-checked every tick of a job, so a store that fills mid-job drops the job and the crop or object stays; harvest and clearing roll at most what was checked, so their `addOrOverflow` call is a same-tick safety net only. After this, `Ledger.addOrOverflow` is used where nothing can wait: finds and the safety nets. (4) **Refusal messages**: a task type may declare `blocked(world, actor, i, order)` returning the id of the full resource; `Tasks.taskForTile` then stops the search (so a rod tap on water does not quietly fall through to the bucket) and the tap shows "<Resource> storage is full". (5) **HUD**: the firewood chip turns red when either firewood store is full, and pills under the top bar list full stores ("Full: ..."), orders waiting for room (with "cancel in Catalog") and smoker batches waiting in their station. Water is never called full (a cistern at capacity is normal). (6) Balance harness: year-1 scripted and active output on 3 seeds is byte-identical to before (no capped resource binds), so survival is unchanged. Today only firewood, seasoned firewood and fuel are capped, so refusals show up once storage matters (M5) or a store is tightened. |
| D60 | **Orders that can never fit** (#75). (1) **Guard**: `Market.neverFits` (a `gives` amount above the resource's current capacity, storage buildings included) makes `cannotBuy` return "too big for storage" before any money is taken, for deliveries and town pickups. (2) **Refund**: an order already paid that can never fit is refunded in full when it falls due (`market.refunded`, queued toast), not left waiting forever; there is no partial delivery (all-or-nothing keeps D45). (3) **Cancel**: a held order (due, waiting for room) can be cancelled for a full refund (`Market.cancelHeld`, `market.cancelled`) from a row in the Catalog panel ("Refund $N"); orders record `paid` (older saves refund today's price and fee). (4) **Content test** (`tests/test_data.lua`): every catalog `gives`, every clearing yield, every crop's largest harvest and seed return must fit the resource's base capacity (storage buildings only add), and every recipe output must have a store; a smoker batch bigger than the store is still delivered in parts. |
| D61 | **The routine plans a starter field when nothing is planned** (#66; a deliberate, narrow exception to "decisions are never automated" in 5.2). (1) **When**: the routine is in charge (taken over after the delay, or R) and no tile is planned, tilled or growing. It runs on the takeover itself and again at the first working tick of each new day while the routine is on, so a start in winter, or a spell with no seed, still gets a field at the first chance. Never when anything is planned, tilled or growing: a player's layout, even one tile, is never added to or replaced, and a player who clears their plan while the routine runs gets a new starter field the next day. (2) **What**: `tuning.farming.starterField`, in order: 4 radish tiles, then 2 potato tiles, at most one tile per seed in stock. A crop is skipped when the ground is frozen or it could not ripen before the freeze (`Weather.daysToFreeze >= growDays + starterFrostMargin`), so a late-autumn start plants radishes only and a winter start plants nothing until spring. (3) **Where**: free tillable tiles within `starterRadius` (10) of the truck, scored by distance to water, then to the truck, minus soil quality (weights in tuning), best first, ties by tile index. No RNG, so a seed always gets the same field. The routine then tills, plants, waters and replants it like any plan. (4) **Feedback**: `crop.starterPlanned { tiles }` (no toast; the planned tiles show on the map as with the Plan tool). (5) **Balance**: the idle policy (never acts, routine from second one) goes from dying at day 6 in 10 of 10 seeds to a median of 26 days survived (cap 28) and 100 percent alive through autumn; it still dies in winter because nobody sells, buys or chops fuel. Scripted and active already planned a field, so their results are unchanged. Tests in `tests/test_starter_plan.lua`; screenshots `docs/screens/starter_*`. |
| D62 | **"Not at the stand" pin** (part of #106). (1) Each sellable resource in the Pantry gets a **Stand / Truck** toggle next to its Keep / Sell / Preserve rule (a 58 px wide button, same row height and touch sizing as the rule button; goods with no sale value have none). It is an independent flag, `state.food.truckOnly[id]`, not a fourth rule: a good can be pinned Sell and Truck together, meaning "always put in the crate, only ever sell it on a truck trip". (2) The stand's daily sale skips truck-only goods; they stay in the crate (and the truck still sells them), and when nothing else is in the crate the day's sale is simply empty. (3) Persisted in the run state; a save without the table loads with nothing pinned. API: `Food.setTruckOnly`, `Food.truckOnly`. Screenshots `docs/screens/standpin_*`. **Not decided / left open in #106**: customers spread through the day, the "highest price first" mode, the 60 percent / cap 6 / ceiling 18 tuning review, and weekly-demand prices. |
| D63 | **Chickens** (#40, part one; goats, milk, cheese, hay and the trailer are #139). (1) **Hens are a ledger count**, resource `hen` (category `animal`, base capacity 0); a placed coop adds capacity through `storage` (six hens), so buying hens uses the existing "no room" and held-order rules. `Market.cannotBuy` says "needs a coop" while none is placed. Hens are catalog items with `pickupOnly` (animals ride home in the truck, GDD §6.3). (2) **Coop state is flock-wide** in `world.state.animals`: feeder (12 units), waterer (4), nest box (12 eggs), the share of need met at the last evening, consecutive hungry and dry days. Several coops add capacity; there is one flock. (3) **One chore**, `tend_coop` in the new `animals` category (default priority after harvest and water, appended and on for older saves): collect the eggs that fit the egg store, move feed from the ledger into the feeder, fill the waterer. Water is free but for the chore time (shortcut: #140, the shared water stock). (4) **Daily rounds** from the one system tick: at 09:00 each hen rolls to lay on the seeded stream `eggs` (season chance 0.85 spring, 0.8 summer, 0.5 autumn, 0.25 winter, times a factor for the evening's feed and water); at 17:00 the flock eats `feedPerHen` (0.5/day) times a season share (0.5, 0.3, 0.5, 1 in winter; the rest is forage) and drinks 0.2/day. (5) **Winter is the pressure** (GDD §4.1): feed per hen more than triples and eggs drop to a third, so a winter flock about breaks even at the catalog's feed price (sack of ten $8; egg $2) and a summer one earns; `tests/test_animals.lua` guards the shape. (6) **Forgiving but real**: a hungry (or dry) day is under half the need met; after four hungry days (two dry) in a row one hen is lost each further day; a good day resets. Three days of full bowls and nobody home cost nothing. (7) **Eggs** are food (90 kcal, 14 days, $2, store of 40): the pantry, crate, stand and truck treat them like any food; a full store holds eggs in the nest and a full box (12) stops laying with a toast (D59 style). (8) **Gating** (Animals chapter, page `animals`): coop and hens need the notes First harvest and Town trip (study 2 and 1 nights; the coop comes with 10 feed); Chicken feed x10 ($8) needs the new note First eggs; the Predator fence ($30, equipment with `predatorGuard` +0.25) needs the new note Fox in the night (a raid that took hens). (9) **Placement**: new object rule `offRoad`; the coop is 2x1. (10) **Render**: the coop sprite, hens drift around its run by day (a pure function of the render clock, nothing is saved), cream dots show eggs in the nest box; the HUD gets a hens chip (red when short of feed or water, or under a day of feed) and an eggs chip once a coop is placed; the object card lists hens, nest, feed (with days left), water, fox guard. Placeholder art; real art and animation are #141. (11) **Idle-friendly**: the routine does the chore; the active harness policy does it directly. Balance harness: new feature `chickens` (buy coop, hens on trips, feed, fence), default on; chickens are slow to pay in year 1 (#143). Not built, tracked: goats and the rest (#139), meat, chicks and restocking (#142). |
| D64 | **Night predators** (#40, #97 in part). (1) Once a night at 23:00, if hens are kept, a seeded roll (stream `predators`) decides whether a predator comes: `chancePerDay` 0.25 times a season factor (spring 1, summer 0.8, autumn 1.2, winter 1.5) times **`Weather.threat`** (storm 2, windy 1.2: the first system to read it) times 0.6 while the cat is on the homestead. No raids in the first three days. (2) The **coop door** turns a raid back with probability 0.6 (`coop.guard`, content), the learned **Predator fence** adds 0.25 (equipment stat `predatorGuard`), capped at 0.95. Otherwise the raid takes 1 to 2 hens through the ledger (reason `predator`). A stopped raid still toasts ("the door held") and does not write a note; a raid that took hens writes the note Fox in the night, which unlocks the fence. (3) Both rolls and the loss are always drawn, so the stream does not depend on the defences; `Animals.dangerTonight` exposes the net chance for UI later. (4) Left open on #97: storm damage, hail, blight, and whether the forecast should let the player prepare (a night raid is not forecast). |
| D65 | **Machines are stationary task-board actors** (#42, D14, §7.4). (1) **Where they live**: a machine is a unit in `world.state.machines.units[anchor]` (owned by `machines.lua`), not an entry in `state.actors`, which stays the list of walking actors (the homesteader; `Actors.homesteader` now finds it by kind). What makes it an actor is the task board: it claims through `Tasks.reserve` with its own id (`machine:<anchor>`), calls the same `canDo`/`workTime`/`complete`, and emits `task.completed` with `machine = kind`. Chosen over adding machines to `state.actors` so walking, sleep, the bucket and the many `actors[1]` call sites stay untouched. (2) **Capability and area**: content `machine = { categories, tasks?, radius, workSpeed }`. `Tasks.allows(caps, taskType)` checks the categories (and task ids if listed); `Tasks.chooseAreaJob` picks, category by category in content order, the unclaimed doable target nearest the machine by Chebyshev distance within `radius`, ties by tile index (no RNG, no table-order dependence). No walking: a machine reaches its whole area. An idle machine searches again every `tuning.machines.recheckInterval` (1 s). (3) **No double booking**: reservations now name their holder (`job.holder`) and `Tasks.release` only frees a claim its job still holds, so a player order that takes a tile a machine is working leaves the homesteader's claim intact; the machine checks `Tasks.holder` every tick and lets go. The player always wins a tap; the idle routine and machines skip each other's claims. Claims are rebuilt on load from both actors' and machines' jobs. (4) **Power**: new sink schedule `demand`: the sink wants power only while its owner asks (`Power.request`, saved in `state.power.requests` so a loaded game draws identically). A machine with work asks; the network serves it from the next tick (status "starting" for that one tick); it works at `workSpeed x Power.sinkRatio`; below `tuning.machines.minPowerRatio` (0.25) it stops, drops its claim so the homesteader can take the job, keeps asking, and emits `machine.unpowered` at most once a day (toast). With nothing to do it asks for nothing, so idle machines draw 0. Switched off in the Power panel it is "off". (5) **Storage**: the task's `canDo` is checked every tick, so a full store (D59) drops the job and leaves the crop in the ground; when only held-back work is in reach the machine reports "full" with the resource. Produce goes through the ledger like a hand harvest, so the pantry, sell crate and stand flow are unchanged. (6) **The auto-harvester**: 1x1, radius 3 (7x7), work speed 0.6 (2 s a crop, the idle homesteader does 1.5 s plus walking), 0.5 kW while working (about 0.08 kWh a crop; a full 48-crop reach is a few kWh). It only harvests; replanting stays with the routine. Unlock: Machines chapter, notes "Sore back" (new: 40 harvests) and "Full battery", 3 study nights, $150 (above the array, below micro-hydro: a mid-game goal). (7) **UI**: a tap on a machine selects it (card and reach) instead of opening the Power panel; the card says Working / Slow / NO POWER / store full / Idle / Switched off, reach and draw, and crops picked. The renderer draws a status lamp, the arm to the target and the progress ring in machine yellow. (8) **Not built** (issues): wear, maintenance or fuel (#145), real art (#146), more machine kinds (#147); the harness policies get a `machines` feature but never reach the item in 1-2 years, so harness numbers are unchanged (#144). |
