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

**Pacing:** ~15 real minutes per season at 1× (~1 hour for Year 1). All season lengths are tuning values (§12.3).

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
| **Decisions** (build, choose study, buy, plan fields, food rules, truck trips) | Player | **Never automated.** Pending decisions show as gentle notifications. |
| **Efficiency** | Base × active multiplier | Base × idle multiplier (raised by upgrades) |

Any input instantly hands control back. A **Start routine** button (key R) skips the wait and hands over at once (D43). All multipliers live in tuning (§12.3) and will be iterated on heavily.

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
| **Roadside stand** *(unlock)* | Sells **N items per day** from the sell crate automatically. Idle-friendly income. | **Always capped.** Upgrades (sign, cooler, display) raise the cap but never remove it. |

Prices vary week to week. Some goods are in demand. Preserved goods sell for more than fresh.

**More power → more trips → more income.** Power is the economy's bottleneck.

---

## 7. Systems

### 7.1 Time & calendar
- Fixed-step simulation tick, separate from rendering. Time scale adjustable: a debug key, and a player speed button (paused / 1x / 2x / 4x, D42).
- **No offline progress.** Time only passes while the game is open. Keeps running when unfocused or minimized (desktop). Mobile suspends, so time pauses.
- Day/night cycle, seasons, weather. Weather affects crops, solar, wind, fish activity, and threats.
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
| **Sprinkler / drip line** | Not an actor; satisfies `water` tasks in its area | `water`, area |
| **Mini-tractor / robot** (late) | Its own priority list | Several categories, a zone |
| **The cat** | Its own logic | Mouse control (§7.7) |

**Priorities v1:** the idle homesteader has an ordered list of categories (default from data). The player can **reorder** and **toggle** them. Later layers on the same list: thresholds, per-machine lists, rule cards. Within a category, tasks are scored by urgency and **walking distance**. The scoring function is swappable.

### 7.5 Power
- A **network**: sources produce, batteries buffer, sinks draw. Supply/demand → satisfaction ratio. Priority tiers (heating outranks the freezer).
- **The truck is a battery on the network**, the only one at first. Charging for a trip competes with homestead use.
- Sources: folding panel (tiny), solar array, wind, micro-hydro, generator.

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
2. **Systems talk through shared interfaces only:** the **resource ledger**, the **task board**, and the **event bus**.
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
| D43 | **Start routine now.** A button (key R) makes the routine take over immediately. It is refused while the homesteader is resting (asleep, walking to bed, or any bedtime, D35) and the button reads "Resting". Control returns to the player on any order (a world tap that starts a task), as with normal takeover, after which the usual takeover delay counts from that moment; panning, zooming and opening panels do not cancel it. Bedtime ends it too, and the morning does not restart it (normal takeover applies). Whether reading a panel counts as "active" for the normal takeover is still open (#14). |
| D44 | **Action progress ring.** The sim exposes `Actors.progress(world, actor)` (task, target, fraction, duration, remaining) for the current timed action; walking and instant actions (work time 0) have none. Render draws a circle that fills over the target tile, in UI pixels (constant size at any zoom), tinted differently for player and routine actions. Actions shorter than `visuals.actionRing.minSeconds` (0.5s of work) show no ring, to avoid flicker. Sizes and colors are in `data/tuning/visuals.lua`. |
