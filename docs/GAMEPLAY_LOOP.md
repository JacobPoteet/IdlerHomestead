# The gameplay loop, as it plays today (beginner notes)

Review of the game at commit 7916c44 (D67, threats), written from the code, the content and tuning files and screenshots from `tools/driver`. It exists for two reasons: the playtest reports that beginners lose produce to spoilage without understanding why or when (#151) and that nothing teaches a new player how to play (#152). The FTUE in section 4 is written against the real systems and event names so it can be implemented as data. Design intent stays in [GDD.md](GDD.md); this file records what a first-time player actually meets. Numbers are read from `game/data/tuning/` and `game/data/content/`; if a tuning file moves, the numbers here move too.

Time units used below: a day is `time.dayLength` = 320 s at 1x. A new run starts at 06:00. Bedtime is two hours after sunset until sunrise (spring 22:00 to 06:00), and sleeping runs at `sleepSpeed` 8x, so one spring day is about 213 s awake plus 13 s asleep, about 3.8 real minutes at 1x. A season is 7 days, about 26 minutes. The first winter starts on day 22, about 80 minutes in at 1x (GDD section 11 sketched winter at 45 to 60 minutes; see #121).

---

## 1. The core loop, by phase of the first run

What the player sees on arrival (`docs/screens/overview_*`): a top bar of icon-and-number chips (money, food days, condition, truck charge, crate count, wood, firewood nights), a date, a Menu button, a speed button (`1x`), a `Start routine` button and a `Power` button on the right, and a bottom toolbar: `Hand`, a seed button per crop (with the seed count), a rod icon, `Plan`, `Routine`, and on the right `Pantry`, `Catalog`, `Fish`, `Journal` (since D72 these read `Rod`, `Plan field`, `Routine list`, `Fish guide`, and a narrow view folds the tools into a `Tools` palette and the rest into `More`; the chips explain themselves when tapped). A grey badge says `Routine in 30s` (now `Routine starts in 30s if you stop tapping`). There is no tutorial, no help screen, no first-run state of any kind (nothing in `game/` mentions a tutorial or a first-run flag). Starting kit (`tuning.run`): 10 radish seeds, 6 potato seeds, 4 canned food, 4 bait, 3 seasoned firewood, a basic rod, and a folding solar panel, campfire and chopping block placed beside the dead truck. Money is $0 and the truck battery is flat.

### First 5 minutes (about day 1, 06:00 to bedtime)

- **Player does:** taps the ground to walk, taps trees, rocks, brush and junk to clear them (clearing yields wood, stone, and from junk $2 to $6 plus scrap), picks a seed button and taps open ground to till and plan it (D30), taps crops to water them (the homesteader fetches the bucket from the creek), taps water with the rod selected to open the fishing mini-game (hold to reel).
- **Game does for them:** after 30 s without input the routine takes over (`tuning.idle.takeoverDelay`). If nothing is planned it plans a starter field of 4 radish and 2 potato tiles near the truck (D61), tills, plants, waters, harvests, chops, clears and fishes in the order of the Routine list: harvest, water, animals, till and plant, preserve, firewood, clear, fish. Any tap hands control back (D43). The folding panel trickles charge into the truck (about 11 percent by evening).
- **Systems:** tasks and actors, crops, clearing, fishing, power, routine, calendar.
- **Hidden clock:** 4 cans of food are 4000 kcal against a need of 3000 a day (`needs.dailyCalories`). They are eaten at the first midnight (three cans) and the second (the last one, with a shortfall of 0.67 and 17 condition lost). Hunger damage is 25 condition per fully empty day (`needs.hungerDamage`), so a player who never harvests or fishes is dead on day 6. Radishes need 2 watered days (`crops.radish.growDays`), so a field planted and watered on day 1 is ripe on day 3. Nothing on screen says any of this except the food chip (`1.3d`).

### First day and night

- Evening: the sky darkens and at 22:00 (spring) the homesteader walks to the truck and sleeps. The routine never runs at bedtime (D35). The `Start routine` slot becomes `Skip night` (key N, 60x). A banner reads `Zzz Sleeping, 8 h to morning, 8x`. A tap on the world wakes the homesteader ("stay up", costs study time) and they go back to bed when idle.
- At midnight `calendar.newDay` fires. In system order (`systems/init.lua`): spoilage runs first (`Spoilage.daily`), then needs (`Needs.daily`: eat, then burn fuel for the night's warmth). The player is asleep and sees none of it except toasts that flash by during the fast-forward.
- Study only progresses while the homesteader is in bed (`tuning.study.nightHours` 8 hours in bed is one night). On night one there is usually nothing to study: an idea needs a note, and notes need events (section 2).
- Morning: the routine resumes by itself if it was running (D55).

### First week (days 1 to 7, which is all of spring)

- Player: first harvest (radishes day 3), first fish, first trip planning, first notes and ideas. Notes arrive as toasts (`New note: ...`, `New idea: ... see the Journal`) and the Journal button turns accent-coloured while an idea is waiting and nothing is queued.
- The first purchases are blocked by money. Income before the first truck trip is only junk ($2 to $6 each). The truck needs 20 kWh (`economy.tripCost`) and a folding panel makes about 2 to 8 kWh a day depending on season and cloud, so the first trip comes on a median of day 5 (BALANCE, #129). The trip sells the whole sell crate (cap 40 units).
- Systems: journal (notes, ideas, study), market (catalog orders delivered 07:00 next day for $3, truck trip), food (pantry, crate), spoilage, power, weather.
- Spring warmth need is 1 firewood a night, so the 3 seasoned logs cover three nights; the chopping block and the routine make more.

### First season beyond spring (summer and autumn)

- Summer: long days, strong sun. First growing-season threat (D67: hail or drought in year 1, 0.4 strength) arrives with a warning toast and a forecast pill. Power items and the water ladder (well, pump, cistern, drip) become affordable and unlockable. Roadside stand, chickens (needs a truck trip for hens) and the cat (after the first mice raid) arrive through the Journal.
- Autumn: the winter forecast is revealed in three pieces (severity word, cold snap timing, snap length) in a pill under the top bar. Firewood need rises to 4 a night. The routine chops and stocks wood and the player should smoke fish and stockpile. The food rules (section 2) start to matter.
- Systems: everything. The player is deciding what to buy, where to place it and what to study.

### First winter (days 22 to 28)

- The ground and creek freeze: nothing grows, crops still in the ground die when winter starts, and a hole must be cut in the ice to fish or fetch water. Warmth need is 8 a night times the winter's severity, with a cold snap of a few nights at 2x. Condition falls on any night without enough warmth (`needs.coldDamage` 20) or any day without food. Long nights (13 hours in bed) make winter study season. Solar drops to roughly a quarter, so truck trips are rare and heating, freezer and lamp compete for power (the winter squeeze).
- This is the designed gate. In harness runs a diligent player is not gated (BALANCE, active 97 percent), an unattended one dies (idle dies in winter, #138), and the scripted floor dies in winter 2.

### Years 2 and up

- Same loop with escalating threats (count 1, 2, 3, then flat; strength 0.4, 0.8, 1.0, +0.1 a year), harsher winters (+0.2 severity a year, cold snaps half a night longer a year), animals (hens, fox raids), machines (auto-harvester), and the threat countermeasures bought once a run. Knowledge persists; money, land and gear reset after a failed winter (rescue, then recovery with one free study, then new land).
- There is no win state. The loop is about stretching automation (routine thresholds, machines, drip, stand) until the homestead mostly runs itself.

---

## 2. The nested loops

### Knowledge loop: do things, notes, ideas, study at night, known, buy

```
do things --event--> Note (journal.note) --all `needs` met--> Idea (journal.idea)
   --player queues--> Study (only while asleep) --> Known (journal.learned) --> Catalog: Order (Market.order)
```

- Notes are data (`content/notes.lua`: an event name, an optional field match, an optional count). 30 notes today. A catalog item or perk lists the notes it needs and its study nights. Nothing is spent.
- Ideas appear on the Journal map as a sketch; unknown nodes are silhouettes and `???`. The player must pick what to study (never automated). The queue holds 3 (`study.queueSize`).
- What a beginner can reach early depends on accidents. One-note ideas: Axe (fell a tree), Woodshed (burn green wood), Big bucket (12 bucket trips), Well (12 bucket trips), Cat (first mice raid), Smoker (first catch and a fish spoiling), Sturdy rod (first catch and a fish getting away), Used panel (first truck trip). So the player's first idea is usually the Axe or Big bucket and arrives on day 2 to 4, not on night one.
- Some gates reward the wrong behaviour: Smoker, Chest freezer, Roadside stand and Stand cooler all need a "food spoiled" note (`fish_spoil`, `produce_spoils`); power items need "Full battery" (do not take a trip for a week); the stove, generator, heater need "Cold night" (shiver through a night); see #126.

### Food loop: grow or catch, pantry or crate, eat, sell, preserve, or spoil

```
crop.harvested / fish.caught / eggs --> ledger (one stock per resource)
  Food.sort (hourly) splits stock by the rules:  pantry (keep N days) > winter stock (preserved, potatoes) > held for smoker > sell crate
  midnight:  Spoilage.daily (fresh stock shrinks)  then  Needs.eat (3000 kcal, freshest first)
  sell:      truck trip (whole crate, cap 40)  |  roadside stand (6 to 18 a day, 60 percent price)
  preserve:  smoker (4 fish, 6 h, 2 wood) -> smoked fish (no spoilage, 700 kcal, $10)  |  canned food (bought)
```

Exact spoilage rules. Superseded on 2026-10-12 by shelf-life batches (GDD D73, #183); the aggregate rules first posted on #151 are summarised after the table.

| Rule | Source | Value |
|---|---|---|
| When | `Spoilage.daily`, on `calendar.newDay` (midnight), before `Needs.eat` | once a day |
| Batches | every harvest, catch or collection of a perishable is a batch with its own age; same-day additions merge; `world.state.spoilage.batches`, oldest first | the ledger still holds the amounts; batches follow `ledger.changed` |
| Shelf life | `tuning.food.shelfLife` (by resource id, then category) | fish 2 days, milk 2, radish 7, egg 14, potato 21; nothing spoils before it |
| After it | `tuning.food.rotShare` of a batch past its shelf life rots each night (rounded up) | half a night: 10 radishes go 5, 3, 1, 1 |
| Who takes what | eating, truck and stand sales, preserving, the cat, mice | the oldest batch first (FIFO); pantry vs crate does not change ages (D31) |
| Slows it | a powered chest freezer: a night ages food by `1 / keeps`, `keeps = 1 + Power.effect("spoilSlow")`, `spoilSlow = 3` scaled by how well it is powered | up to 4x the shelf life; the effect eases in and out over about 8 hours (`inertia`) |
| Does not slow it | winter or any season, pantry vs crate, the Stand cooler, cold weather | nothing |
| Immune | anything without a shelf life: `preserved` (smoked fish, cheese, canned food), non-food goods | never spoils |
| Randomness | none | deterministic |
| Event | `food.spoiled { resource, category, amount }` per resource, one `food.spoilReport` per night | toast and first-spoil card, morning report line; first spoil of each category writes a note |

What the player sees now: each perishable row in the Pantry says how long the food keeps and when its oldest batch spoils ("in 3 days", "tomorrow night", "tonight: 4 will rot"); the red chip and the Pantry warning appear only when something will actually rot tonight.

The model this review was written against (D38, D68): every resource with `spoilDays` lost about `1/spoilDays` of its whole stock each night (fish 50 percent, radish 25, egg 7, potato 5), rounded with a seeded draw, and new food rotted like old. Consequences a beginner could not see: stock was not per batch, so "days until this batch spoils" did not exist in the model, only a daily rate. Spoilage runs before eating, so a harvest is taxed before it is eaten. The default pantry keeps 3 days of food (9000 kcal, `food.defaultPantryDays`), but only 3000 kcal is eaten a day, so extra radishes sit in the pantry losing a quarter a night while the sell crate stays empty (rules 1 to 5 in `food.lua`; only food beyond the pantry, winter stock and held-for-smoker goes to the crate).

### Other loops, briefly

- **Power:** sources (panel, array, turbine, hydro, generator) fill batteries and sinks by priority tier; the truck is a battery that charges last by default. Truck charge gates trips; trips gate money and pickup-only items. Winter shrinks solar and raises heating, freezer and lamp load.
- **Water:** creek bucket (6 waterings, 1.5 s fill) to well to hand pump to cistern plus solar pump to drip lines. Crops grow only while moist; one watering lasts one day. Rain waters for free.
- **Animals:** hens need a coop (journal, then catalog), a pickup-only purchase on a truck trip, feed, water and a daily tend chore (routine does it). Fox raids at night. The cat catches mice and eats a fish a day.
- **Machines:** the auto-harvester is a stationary actor on the same task board, powered on demand.
- **Threats:** a seeded schedule per year, announced days ahead, countermeasures learned from the note a first strike writes, then bought each run.
- **Rescue loop:** condition 0, rescue, recovery (one free study), new land, same journal.

### Event bus names the player-facing systems already emit

`crop.planted`, `crop.harvested`, `crop.starterPlanned`, `task.completed { task, ordered }`, `object.cleared { object }`, `fish.caught`, `fish.lost`, `food.spoiled`, `needs.ate { calories, shortfall }`, `needs.warmed`, `sleep.started`, `sleep.woke`, `calendar.newDay`, `calendar.newSeason { season, year }`, `routine.idleHint`, `journal.note`, `journal.idea`, `journal.learned`, `market.ordered`, `market.delivered`, `market.trip`, `market.sold`, `object.placed`, `processing.done`, `stand.sold`, `power.full`, `weather.forecast`, `weather.froze`, `weather.coldSnap`, `threat.warned`, `threat.struck`, `finds.offered`, `needs.depleted`. Missing and needed for the FTUE: a "truck can make a trip" event (see section 4).

---

## 3. Beginner friction points

Severity: **High** loses the run or the player; **Medium** wastes time or hides a system; **Low** is polish. "Issue" shows where it is tracked: new issues opened with this review are listed in section 7.

| # | Friction | Evidence | Severity | Tracked |
|---|---|---|---|---|
| F1 | Spoilage is unexplained, invisible and silent in effect. No rate, no forecast of loss, no "what slows it"; the toast replaces any toast showing and appears at midnight while the player sleeps. | `spoilage.lua`, `homestead.lua` (`food.spoiled` uses `showToast`, not `queueToast`), pantry rows show only stock and crate counts | High | #151 |
| F2 | No first-run help at all: no tutorial, no help screen, no explanation of the toolbar. | no FTUE code in `game/`; `Menu` has Resume and Save & exit only; the only "Guide" scene is the fish guide | High | #152 |
| F3 | The food clock starts on day 1 and is not explained. 4 cans last 1.3 days; the first hunger damage is on night 2 to 3; there is no warning, no red chip, no toast for eating, hunger or condition falling (only the `Went hungry` note after the fact). | `tuning.run`, `needs.lua`, `homestead.lua stats()` (food and heart chips have no warning colour; no `needs.ate` subscriber) | High | new: low-stock warnings |
| F4 | Top-bar chips are bare icons with unexplained units: `1.3d` (days of food), `3.0n` (nights of firewood), crate count, truck %, heart 100, `1x`, `Power`. | `Homestead:stats()`; screenshot `overview_desktop_04` | Medium | new: HUD chips |
| F5 | The default pantry rule holds perishable food that spoils instead of selling it: radishes beyond the day's meal sit in a 3-day pantry at 25 percent loss a night; the crate stays empty, so the first trip sells little. | `food.lua` `sort`, `tuning.food.defaultPantryDays` 3, `resources.lua` | High | new: pantry default (rule), #151 (visibility) |
| F6 | Bedtime and morning are silent. The player is not told the day ended, that sleep is when study happens, that a tap at night costs study time, or what the midnight accounting did (ate, burned, spoiled, condition change, study progress). | no `sleep.*` or `needs.ate` handler in `Homestead:subscribe()`; `Sleep.lua` | Medium | new: bedtime and morning report |
| F7 | The Routine is two controls with similar names (`Routine` in the toolbar opens the priority list; `Start routine` in the right column starts it), a countdown badge with no explanation, and no statement of what it does not do (buy, sell, drive, choose study, place buildings). A tap cancels it, which looks like "the homesteader stopped". | `Homestead:layout()`, `layoutControls`, D43, D55, #138 | Medium | #152 (explain) plus new: toolbar labels |
| F8 | The Journal does not say how to unlock anything. Locked nodes are `???`, empty note stamps are a blank `?` square. The first useful ideas depend on specific accidents (fell a tree, 12 bucket trips, a fish spoiling). | `notes.lua`, `catalog.lua` `needs`, `journal_map.lua`, GDD 8.3 | Medium | new: unlock hints |
| F9 | Preservation unlocks require the player to have lost food: Smoker, Chest freezer, Roadside stand and Stand cooler need `fish_spoil` or `produce_spoils`. The Stand cooler's line ("Fish and greens keep on the table") is false: it only adds +4 sales cap. | `catalog.lua`, `spoilage.lua` | Medium | new: spoilage gates and text |
| F10 | Money is invisible and slow. $0 start; the only income before the first trip (median day 5) is junk at $2 to $6; the Catalog shows prices the player cannot meet and does not say how to earn. The trip itself has no preview of what the crate is worth, and the truck panel gives no time-to-ready. | `economy.lua`, `objects.lua` junk, #129, `truck.lua` | Medium | new: early money; new: truck panel |
| F11 | Planting too late. The Plan tool and seed taps never warn that a crop cannot ripen before winter, and crops in the ground die when winter starts (the routine's starter field checks this; a player plan does not). | `crops.lua` `planStarter` vs `Weather.daysToFreeze`; D37 | Medium | new: late planting warning |
| F12 | Winter readiness is not shown. The firewood chip is in "nights" with no target, the forecast pill gives severity words but no "you need N more", and no summary says whether food and fuel will last. | `Homestead:stats()`, `Forecast.summary`; GDD 9.3 names "winter readiness" as widget status | Medium | new: winter readiness |
| F13 | Toasts replace each other and vanish in 2.6 s; there is no message history. During fast sleep, on a phone, or while reading a panel, information is lost (spoilage, stand sales, caught fish, delivery). | `Homestead:showToast` vs `queueToast`, `TOAST_TIME` | Medium | new: message log |
| F14 | Starter field is planned without telling the player (and may be a thin strip). | D61 | Low | #137 |
| F15 | Sell crate vs pantry vs stand pin is three concepts introduced in one panel with no explanation. | `pantry.lua` | Medium | #151, #152 |
| F16 | Fishing: the rod is an icon-only toolbar button, the `Fish` button opens the guide, and the idle routine fishes last in priority, so a beginner sees neither. | `Homestead:layout()`, `task_categories.lua` | Low | new: toolbar labels |
| F17 | Pace: a season is about 26 minutes and winter is about 80 minutes in; the 4x speed exists but is never mentioned. | D56, #121 | Low | #121 |
| F18 | The first run is meant to fail (GDD 11), but the first death is usually from starvation on day 4 to 6 (idle) or in winter, with no "what killed you and what to try next" beyond the run summary. | `recovery.lua`, BALANCE | Low | open question |

---

## 4. Proposed FTUE step list

Design: first run of a slot only (`meta.career.runs == 1` and `meta.ftue.done` unset). State in the slot's `meta.ftue = { seen = { [stepId] = true }, off = bool }`. Steps are content (`data/content/ftue.lua`: id, trigger event, optional match, optional delay, text, optional `highlight` target) and the player-facing text lives there. A step is a small card above the bottom bar (touch friendly, no hover), non-blocking, with `Got it` and `Skip tips`. One at a time, queued. Never pauses or modal-blocks the fishing mini-game or the finds modal. It must not count as player input for the takeover timer (a card tap is a browse input like panels, D55). `Skip tips` sets `off`. Replay from the Menu ("Tips"), since the existing Guide is the fish guide. The doc and issue #152 call for tests of progression, skip and save/load and driver screenshots.

Each step shows at most once. Text is short and friendly; draft strings below.

| # | Step id | Trigger (event, match) | Prompt |
|---|---|---|---|
| 1 | `welcome` | homestead entered on a new first run (no event; scene `enter` plus `meta.ftue` unset) | "Your truck died here. Tap the ground to walk and tap trees, rocks and junk to clear them. Junk pays a few dollars." |
| 2 | `plant` | `object.cleared` first time, or 60 s with no `task.completed` | "Cleared! Pick a seed in the bottom bar, then tap open ground to till and plant it." |
| 3 | `water` | `crop.planted` first time | "Planted. Crops grow only while they are wet: tap a thirsty crop and the homesteader fetches water from the creek." |
| 4 | `food_clock` | `needs.ate` first time (day 2 morning), shown with the shortfall if any | "You ate 3000 calories a day. The food chip is days of food left. At zero your health (heart) drops. Harvest radishes (2 days) or catch fish." |
| 5 | `routine` | `routine.idleHint`, or the first time the takeover badge counts down | "Stop tapping for 30 seconds and the Routine takes over: watering, harvesting, planting, chopping, fishing. Tap anywhere to take over again. It will not sell, buy, drive or choose what to study." |
| 6 | `bedtime` | `sleep.started` first time | "Bedtime. The homesteader sleeps in the truck until sunrise. Sleeping is when the Journal studies. Tap Skip night to jump ahead. Anything you order wakes them." |
| 7 | `idea` | `journal.idea` first time | "A new idea! Open the Journal, pick one to study, and it finishes while you sleep. Then buy it in the Catalog." |
| 8 | `harvest` | `crop.harvested` first time | "First harvest. Food goes to the Pantry first, the extra to the sell crate. Open the Pantry to see the rules." |
| 9 | `spoil` | `food.spoiled` first time | "Fresh food spoils: fish about half a night, radishes a quarter, potatoes a twentieth. Eat it, sell it or smoke it. A powered chest freezer slows it." (text from #151's real rates) |
| 10 | `fish` | `fish.caught` first time | "Fish spoil in 2 days. Smoked fish keeps all winter. Keep an eye on the Journal for a smoker." |
| 11 | `delivery` | `market.delivered` first time | "Your order arrived at the road. Tap the Place button in the bottom bar, then tap where it should go." |
| 12 | `truck_ready` | needs a new event, `market.tripReady` (truck charge crosses `economy.tripCost`); until it exists, poll `Market.canTrip` | "The truck has enough charge for a trip. Tap the truck, Drive to town, and sell the crate." |
| 13 | `town` | `market.trip` first time | "Town buys what is in your sell crate (up to 40 items). You can also buy animals and pickup-only items here." |
| 14 | `autumn` | `calendar.newSeason`, `season == "autumn"` | "Autumn. Winter is coming: store firewood (the firewood chip counts nights), keep food, and watch the forecast under the top bar. Crops still in the ground die when winter starts." |
| 15 | `winter` | `weather.froze` (or `calendar.newSeason` winter) | "Winter. The creek froze: cut a hole to fish or fetch water. Long nights mean fast studying." |
| 16 | `threat` | `threat.warned` first time | "A threat is coming. The forecast shows when. The Journal learns a counter after the first strike." |

Open items for the implementer: the three Journal steps assume the first-run player sees a toast and the accent Journal button; steps 4, 8 and 9 reuse the sim's own numbers through accessors, never copies. The same prompts, with different copy, could be replayed in recovery after the first rescue (the rescuer's line already changes after the first rescue).

---

## 5. Gaps between GDD intent and the built game that affect the first hour

1. **GDD 3 pillar 8, "Show, don't tell":** there is also no "tell" for the systems that cannot be shown (spoilage, the routine, study, truck charge).
2. **GDD 11, 0 to 5 min:** the "clearing tutorial", "set up the folding panel" and "first Notes" steps are not guided; the panel is pre-placed. The "fishing tutorial" (5 to 15 min) does not exist.
3. **GDD 11, first night, first study:** the first idea is not available on night one; it needs a note that needs an event.
4. **GDD 6.2, "defaults are sensible, so a new player never has to touch this":** the 3-day pantry default makes beginners lose perishables (F5).
5. **GDD 8.1 and 8.3 note example "Fish spoil in two days":** the note exists, but the spoilage itself has no player-visible rule or rate (F1).
6. **GDD 5.2, "Pending decisions show as gentle notifications":** built only for the study choice (Journal button accent) and the find modal. There is no notification for a truck that can drive, for crops ripe, for winter prep, or for an idle food stock.
7. **GDD 4.2, drinking water, and 5.3, root cellar and cooler rungs:** not built (D38 shortcut: spoilage is aggregate; potatoes stand in for a cellar).
8. **GDD 9.3, "winter readiness" in the widget and HUD:** not shown anywhere.
9. **GDD 4.1 and 11, pacing:** about 80 minutes to the first winter, not 45 to 60 (D56, #121); a season is 26 minutes.
10. **GDD 3 pillar 2 and 11, "first run meant to fail around the first winter":** an engaged player is not gated (BALANCE), an unattended one dies in week one (before D61) or in winter (#138); the beginner's real failure is food in the first days.
11. **GDD 6.3, specials and in-store only items:** present but not introduced; a trip is the only way to see them.
12. **GDD 8.3, "Tap a Note, optional read more":** there is no hint on a locked node about what to do (F8).

---

## 6. Open design questions for the user

1. **Spoilage model.** Keep the aggregate daily rate (D38) and show the rate and tonight's expected loss, or move to batches with ages so "this batch spoils in N days" is exact? The aggregate model cannot answer the user's playtest ask literally.
2. **Pantry default.** Should the default pantry keep 3 days of everything, or a per-resource target that never exceeds what will be eaten before it spoils (and send the rest to the crate)? Should the first trip sell fresh produce at all?
3. **Early food.** Is 1.3 days of starting food plus a 2-day radish a deliberate scramble, or should the first run be gentler (a couple more cans, or an earlier first harvest)? The first death is currently starvation.
4. **FTUE style.** Contextual cards (this proposal), a short scripted first day, or both? Should a card pause the sim while open? Should the FTUE show once per slot (as proposed, so a new slot shows it again) or once per install?
5. **Where does Help live?** The Menu (Resume, Save & exit, and a new Tips entry), a toolbar button, or renaming `Guide`, which today is the fish guide.
6. **Routine scope for beginners.** The routine is allowed to plan a starter field (D61). Should it also fish early, or take an automatic truck trip when the crate is worth selling and the truck is full? Or is "decisions are never automated" absolute?
7. **Early money.** Should a run start with a few dollars so the first Catalog order is possible, or should junk pay more? Today nothing can be bought for the first 3 to 5 days.
8. **Neglect-gated unlocks.** Should "Fish spoil" and "Produce rots" stay as unlock gates (so the player learns by losing food), or should the smoker and freezer unlock from a different note (for example a first catch plus a day with fish in stock)? Same family as #126.
9. **Pace.** Is a 26-minute season right for a first run, and should the player be told about the 4x button?
10. **Messages.** Do we want a message log and a morning report as persistent UI, or should the FTUE cards carry the explanation and the rest stay as toasts?
11. **What killed you.** After the first rescue, should the recovery scene explain the cause (hunger or cold) and suggest a first change, since the run is meant to fail?

---

## 7. Issues opened from this review

Opened with `found-during-dev` plus a topic label:

- #157 Low-stock and survival warnings: food, firewood, condition (ux)
- #158 HUD chips are bare icons with unexplained units, tap to explain (ux)
- #159 Bedtime notice and morning report: sleep, study, eaten, burned (ux)
- #160 Journal: locked ideas give no hint how to unlock them (ux)
- #161 Early money is invisible: $0 start, junk only, first trip about day 5 (ux, balance)
- #162 Truck panel at home: crate value, time to charge, and a trip-ready event (ux)
- #163 Default pantry rule holds perishables that spoil instead of selling them (balance)
- #164 Spoilage gates and text: smoker, freezer, stand need food to rot; Stand cooler line is wrong (balance, ux)
- #165 Warn when planting a crop that cannot ripen before winter (ux)
- #166 Winter readiness: fuel and food against the forecast (ux)
- #167 Toasts replace each other and have no history: add a message log (ux)
- #168 Toolbar and control labels: Routine vs Start routine, rod, Plan, Fish (ux)

#151 (spoilage visibility) and #152 (FTUE) got comments with the exact rules (section 2) and the step list (section 4).
