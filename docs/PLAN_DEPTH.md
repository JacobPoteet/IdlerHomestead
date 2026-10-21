# Plan: homestead depth (the core loop)

Status: approved; milestone and issues created (section 17). Nothing here is built. When approved it becomes milestone **M8: Homestead depth** (section 17), and the GDD (§4, §5, §6, §7, §8, §9, §11) and the decision log take the parts that are built, one slice at a time.

Why this exists: playtest feedback says the base systems are in but the loop is thin. Once the player has seeds they steamroll, there is little to manage, and the idle loop has nothing to do. A read of the design, content and balance notes agrees (section 1).

**Scope of balancing (decided after approval).** M8 only needs *playable* numbers: every rate below is a first guess, set once, commented in tuning, and listed in the PR under "Tuning guesses". The real balance pass is milestone **M9: Balance & pacing**, after the time model (slice T0) is decided and the M8 systems are in. The harness runs in M8 are smoke checks (it runs, it is deterministic, no new failure class), not target chases. The targets in section 15 are directional and are revised first in M9.

**Design review (D168).** A game-design review amended this plan (GDD decision D168). A Footing slip forgives instead of freezing (3.2); the levy and the bailiff are bounded (11.3); wake events never freeze time and ignore is always safe (6.2 to 6.5); mercy rules key on Footing state and reserves (6.5); there is one tiredness mechanism (5.2, 7, 10.4); guards cover only some threats (6.1, 10.3); every cadence is in days (3, 8.5); Careful respects keep targets (6.4); phone UI has an attention budget (4, 14); and section 17 is re-sequenced. Eight questions the review raised are left open (section 16, Q8 to Q15).

Time facts used throughout (from `data/tuning/time.lua`, GAMEPLAY_LOOP.md; **slice T0 may change the real-time length of a day**, which changes how much work a day holds): a day is 320 s, **a season is 7 days, a year is 28 days**, the first winter starts on day 22. Every rate below is per night or per day, so "about 0.3 a night" means about one event every three nights (two a season) and about eight a year. Every cadence in this plan is stated in days. All numbers are first guesses, they live in tuning (never in system code), and the M9 balance pass tunes them.

---

## 1. Diagnosis

| # | Finding | Evidence |
|---|---|---|
| F1 | **Money has no destination.** About 48 catalog items; nearly all are bought once (unique or a replacing upgrade). The buy list ends, and then money does nothing. | `data/content/catalog.lua`; GDD D114 |
| F2 | **Two crops.** Radish ($1) and potato ($2). There is nothing to choose, so more tiles is always better. | `data/content/crops.lua` |
| F3 | **Growth has no friction.** No fertility, weeds, pests, wear, tax or land limit. The routine does every chore and keep targets do every food decision. | GDD §5.2, §6.2 |
| F4 | **Pressure is flat.** Threats scale with the year, not with what you built. Winter is solved by chopping wood on demand. | BALANCE.md "Findings"; `data/tuning/threats.lua` |
| F5 | **Nights are free.** The player sleeps through them; the only night events are mice and a fox. | `systems/nightly.lua`, `data/tuning/cat.lua` |
| F6 | **One goal.** The first winter is the only wall; the days before it are chores. | GDD §4.1, §11 |
| F7 | **Idle play has no tension.** No bottleneck moves, no number to push. | GDD §5.2 |
| F8 | **Knowledge unlocks shopping, not strategy.** Run 3 is run 1 with a longer buy list. | GDD §8 |

The strongest system today is the power priority list (scarce supply, competing demands, a winter squeeze). This plan copies that pattern into survival, fields, the market and labour.

## 2. Goals and non-goals

Goals:
1. A pressing goal at every moment: first the night, then the season, then the year, then the run (section 3).
2. Real decisions every day that are not solved once: what to plant, what to sell, which risk to take.
3. Scarcity that moves: each upgrade shifts the bottleneck (water, then labour, then storage, then power, then market, then land).
4. Danger that scales with what you built, not only with the calendar.
5. Active play that is better in specific ways, idle play that is steady but wasteful, and neither is punished into uselessness.
6. Knowledge that opens strategies, not only catalog rows.

Non-goals: no offline progress (GDD §7.1), no multiplayer, no combat, no new graphics pipeline, no permanent death from an event alone (section 6.5), no save migrations (CLAUDE.md).

## 3. The goal ladder and Footing

| Horizon | Pressing goal | Leads |
|---|---|---|
| **Tonight** | Reach dusk with warmth, food and water for the night, and grow the woodpile and larder faster than you burn them | From run start until Footing, and again while slipped |
| **This season** (7 days, ending on market day) | Season targets: stock the cellar, finish a contract, pay the levy | After Footing |
| **This year** | The winter reserve target (forecast severity times nights ahead) | After Footing |
| **Run** | The year charter, land, contracts and the Great Winter | After Footing |

Survival is the base layer. The longer goals sit on top of it and cannot be reached by neglecting it.

**One rung, not two (D168).** At 7 days a season, a "This week" rung and a "This season" rung are the same span, so they are merged: the early woodpile-and-larder goal is the reserves half of the Tonight rung (nights of fuel and days of food, the same figures as the Footing tests), and the season rung ends on market day (9.4). No rung is defined in weeks.

### 3.1 Dusk check

About `tuning.night.duskLeadHours` before sunset a **Tonight card** shows: the warmth the night needs (the same figure `Needs.warmthNeeded` and `Readiness` compute), fuel in stock and what it covers, food for tomorrow, water, shelter and the risks ahead (a cold front, signs of an animal, section 6). It shows the gap and a one-tap action for each gap ("Chop 3 more logs", "Ask the routine to fish"). Today this data exists but is shown only in the morning report, after the fact. The card is a panel that can be dismissed and re-opened; it never blocks input and is not hover-only.

### 3.2 Footing

**Footing** is a state, not an unlock. (Not "Established": that stays the Great Winter milestone, GDD §4.4.)

- **Earned** when all hold at dusk: a shelter with a heat source (a camp with a campfire counts), a water source, at least `tuning.night.footing.fuelNights` nights of fuel and `foodDays` days of food in reserve, for `streakNights` nights in a row. First guess: 3, 3, 5. The food test counts the hired hand's meals (they eat from the ledger, 10.3) and excludes goods promised to an open contract (9.2), so filling a contract cannot cause a slip.
- **On gaining it:** a one-time card; the contracts board, land purchases, the year charter draft, tiered upgrades and the levy clock open (sections 9 to 11); the pressing goal becomes the winter reserve target.
- **Slipping forgives, it does not freeze (D168):** if reserves fall below one night of fuel or one day of food, Footing is marked **slipped**. The Tonight card returns as the lead goal. The longer goals are eased, and their clocks keep running: the levy stays calendar-fixed and is reduced (not paused) while slipped (11.3); contract deadlines keep running, but a miss while slipped costs no reputation, and no new contracts are offered while slipped (9.2); no charter draft is offered (12.2); no new bad events are drawn and threats are weaker (6.5). Regaining the reserves for two nights clears it.
- **The accessor:** `Footing.paused` (A2) keeps its name and means "slipped". It gates **offers** (contracts, charter drafts, new bad events), not timers; nothing in the sim stops a clock because of it.
- **Gating:** gated things are shown but locked ("opens at Footing"), so the player can see what they are working toward. A content flag `requiresFooting` marks them; there is no per-feature code.
- **Per slot:** Footing is run state, not meta. A new run starts without it.

Pacing target (harness): median time to Footing about day 12 of year 1, at least 85 percent of `active` runs reach it before the first winter, and the first-winter failure rate for `active` stays at the old target of 40 to 60 percent (BALANCE.md item 1).

## 4. Principles for everything below

1. **Choices over chores.** A new system must add a decision the routine cannot make for you, or a cost the player can see and trade off.
2. **Never a dead end.** Every bad outcome has a cheaper way out and a path to recover. Events can hurt, never end a run by themselves (section 6.5).
3. **Idle is steady, not stupid.** The routine handles chores. When it meets a decision it stops and asks; if the player is away, a defined **ignore** outcome applies: the cheap, safe, non-escalating option, a little worse in time or speed than the careful one, never a path to a worse status later (6.2, 6.5).
4. **Information first.** Risk is shown in words and icons before the choice ("a fall is twice as likely tomorrow"), and every first occurrence writes a Field Journal note.
5. **Knowledge opens options.** Journal learning gives a third option, a cheaper option, or an earlier warning, not just items.
6. **Data, not code.** Events, threats, crops, contracts, charters and statuses are content tables with tuning knobs. System code reads them.
7. **Existing rules hold.** Sim in `src/sim` with no `love.graphics`; systems talk through the ledger, task board and event bus; all randomness through named seeded RNG streams (new streams: `night`, `event`, `soil`, `market`, `charter`); sim state is plain serializable tables; input goes through actions.
8. **Attention budget (D168).** Phone first. Notices share one ranked queue (Tonight, then events, then contract and levy notices); at most one card is open at a time and the rest wait in the queue, and a card never opens over another. Wear, saturation and workload detail show only where the player can act on them (the pump panel, the truck screen), never as always-on chips. A new system says where its notice sits in the rank.

---

## 5. The night

The night stops being a skip. Every night from the third can bring one **night threat** (section 6.1) or one **misfortune event** (section 6.2), never both interrupting. **The night slot (D168):** there is one slot a night, shared by threats and events (designed together with the event engine, B3 and C1). A threat that is turned away still uses the slot, so no event is drawn on top of it; it counts as an event for the pity timer (6.5) and never starts the post-bad-event cooldown, which only a landed outcome does.

### 5.1 Exposure

Danger on a night is `base chance x season x weather x exposure`, where **exposure** is how much the homestead gives the night to work with:

- shelter: truck (highest), camp, shack (lowest);
- stores that attract animals: smoked fish, cheese, feed, an uncovered compost heap;
- livestock count, and field size for crop raiders;
- guards: cat, dog, fence, lantern, trip line;
- how much the player pushed: sleeping late, starting the night short of warmth.

Exposure is a single readable number on the Tonight card ("Exposure: high - smoker and 8 hens, no dog"). **Units (D168):** exposure points, 0 to 10, 5 neutral (`tuning.night.exposure`); each source adds points, each guard subtracts, and the total is clamped to 0..10. The chance multiplier runs linearly from about 0.4 at 0 to about 1.8 at 10 (first guesses). The card shows the word (low, medium, high) and the points. Clear nights are colder (the existing weather model), storms raise wind and fall risks.

### 5.2 Waking

Most threats resolve while the homesteader sleeps and appear in the **morning report** (`nightly.lua` already collects this). A few **wake** the homesteader with a choice (section 6.3). **One tiredness mechanism (D168).** A wake costs only that night's lost study and Condition recovery (cut by `tuning.night.wakePenalty`). **Tired** (the B1 status, section 7) is the carry-over, and the sleep debt of 10.4 *is* Tired, not a second counter: a wake or a late night applies or raises Tired, and nothing else tracks it. At most one wake per night, none in the first three nights, and none under the mercy rules of 6.5 (low Condition, Footing slipped, low reserves).

### 5.3 Light and watch

Cheap gear changes the odds and the options: a lantern by the door, a trip line with tin cans, a bell, a dog. They lower exposure and give an early warning at dusk ("fresh tracks by the shed"), which is the player's chance to act before bed. Gear is catalog items gated by journal notes (section 12.5).

---

## 6. Night threats, misfortune events and the choice rules

### 6.1 Night threats (animals, weather, fire)

A **night threat** is a content entry: `id`, `seasons`, `minDay`, `minYear`, `exposure` weights (what attracts it), `warn` (the dusk sign), `guard` (the stats that turn it away), `counter` (the item), `outcomes` for turned-away and landed, `wake` (may wake the player, with an event id) and a journal note. The fox and mice move into this framework unchanged in behaviour.

| Threat | When | Attracted by | Landed outcome | Counters |
|---|---|---|---|---|
| **Mice** (exists) | any, more in autumn | fresh food in store | ruin a few units of fresh food | cat, sealed bins |
| **Fox** (exists) | any, bolder in lean seasons | hens, goats | lose a hen or goat | coop door, fence, cat, dog |
| **Raccoon** | spring to autumn | open food stores, compost, feed | spoil a store of one food; scatter feed (a day of feed lost) | lidded bins, dog, lantern |
| **Skunk** | spring to autumn | coop eggs | hens stressed: no eggs for a day; a smell status (-warmth comfort, cosmetic) | dog, fence |
| **Deer and rabbits** | spring to autumn | tender crops (greens, beans), young orchard | eat a share of unripe tiles on the field edge | fence, dog, scarecrow item |
| **Black bear** | autumn only (feeding up), year 1 rare, year 2+ common | smoked fish, cheese, honey, feed | strips a store, wrecks the smoker or shed door | bear box, dog, noise, light, store away from bed |
| **Wolves and coyotes** | deep winter, year 2+ | goats, hens | lose a goat or several hens | dog, strong pen, fire and light |
| **Cold front** | autumn and winter | none (forecast miss) | tonight's warmth need rises by a share; fuel burns faster | the forecast (weather sense stat), spare fuel |
| **Windstorm** | any, more in autumn | canvas shelter, loose gear | camp canvas torn (insulation halved until patched); trees fall (free wood, or a wrecked fence) | proper shelter, guy lines |
| **Pipe freeze** | winter | exposed pipes and pump | no water in the morning | insulation, a heated pump house, burn fuel to thaw |
| **Power outage** | winter, storms | a small battery bank | heater and lights down for the night | bigger bank, generator |
| **Stove fire** | winter | a sooty stove run hot, wood piled close | scare (Fire event, 6.2) or the stove lost | sweep the flue (upkeep, section 10), water bucket by the door |

Rules: one threat per night at most; the dusk sign is shown when any threat is active that the player could still act on; a threat the player already countered (guard high enough) is reported as "turned away" so the work is visible (it uses the night slot, 5).

**Guards cover only some threats (D168).** Each guard lists the threats it covers (`covers`, content) and carries its own upkeep or wear, so no single item answers everything. First guesses: the **dog** (feed every day, 10.3) covers raccoon, skunk, deer and rabbits, fox, and partly bear and wolves, not weather or fire; the **cat** covers mice and partly the fox; the **fence** covers deer and rabbits, fox and partly raccoon, and takes wear from raids (10.1); the **lantern** covers fox and raccoon and partly bear, and burns fuel each night; the **trip line and bell** only move the dusk sign earlier. A few threats need their own counter: the **bear box** for a bear's store raid, a **strong pen** for wolves. Weather and fire threats are answered by shelter, insulation and upkeep, not guards.

### 6.2 Misfortune events: the two-option choice

A **misfortune event** is something that happens to a person living alone. It asks for a choice between two options with a real trade-off (neither is simply better). Each event is content:

```
id, title, line (one sentence), when (night | morning | day), seasons, conditions,
weight, exposure terms, cooldown, once (per run), journalNote,
options = {
  { label, cost = { wood = 2 }, effect = { status, resources, flags, workShare... }, risk = "words" },
  { label, cost, effect, risk },
},
ignore = { ... }     -- applies if nobody chooses within the window
```

Rules for every event: the card states each option's cost and effect in plain terms and the qualitative risk (never hidden odds on a coin flip); an option that costs a resource is disabled with a reason if the player lacks it; the **ignore** outcome is shown too. **The ignore outcome (D168)** is content, never derived from an option: it costs no resource, applies no status that can escalate or carries a delayed roll, and is a little worse in time or speed than the careful option. A gamble (Leave it, Push on, Power through) is something the player picks, never what ignore does. A content test walks the worst reachable chain of every ignore outcome (6.5).

**Direction of modifiers (D168).** Insulation modifiers (tarp halved, leak x0.7, torn canvas) multiply the *shelter's insulation value*, so a lower figure is a colder night and the warmth need rises through the existing formula. A status `warmthNeed` modifier multiplies the *warmth need itself* (x1.2 is 20 percent more). Both feed the capped product of 6.5.

**Example, in full (the one requested).**

> **Sprained ankle.** You slip on the wet rocks by the creek and your ankle gives. *(trigger: morning or day, wet or icy weather, carrying a heavy load, or Tired; weight raised by loose boots, lowered by heavy boots)*
>
> - **Splint it** (cost: 2 wood). Status **Hobbling** for the rest of today: work speed x0.5 and no fall risk change. Gone tomorrow morning.
> - **Power through.** No slowdown today. Status **Strained** tomorrow: fall chance x2. If a fall happens while Strained, the next result is **Torn** (below) and not a fresh sprain.
> - *Ignore (no choice made in the window, 6.3):* **Limped on**: work speed x0.6 for today and tomorrow, free, no Strained and no escalation; the journal notes you "limped on." (Under the first draft ignore meant Power through, which could escalate to Torn later; mercy rule 3 forbids that, D168.)
> - **Torn** (escalation): work speed x0.4 for 3 days, Condition -15 once, and the splint option now costs 3 wood and 1 canned food (broth) and shortens it to 2 days.

Full catalog (all two-option; a cost on one side is a risk on the other):

**Body**

| Event | Option A | Option B | Notes |
|---|---|---|---|
| **Sprained ankle** | Splint (2 wood): Hobbling today | Power through: Strained, fall x2 tomorrow | above |
| **Cut that festers** | Clean and bandage (1 water, 1 bandage or an hour of work): no effect | Leave it: 40 percent Infection in 2 days (Fever) | bandage from the first-aid kit; the ignore outcome is a rinse: free, work speed x0.9 for 2 days, no infection roll |
| **Fever after a cold night** | Rest a day: no work, double recovery, food and fuel still burn | Work through: speed x0.6 for 3 days, 30 percent it becomes Flu (Condition -20) | triggered by a night with a warmth shortfall; never fires on a night that already cost cold damage (6.5) |
| **Back strain** | Rest 3 hours: lose that work | Keep hauling: carry capacity x0.5 for 2 days | triggered by a heavy carry streak |
| **Burn from the stove** | Cold water compress (1 water): none | Shrug it off: hands slow, tool work x0.8 for 2 days | stove use |
| **Heat exhaustion** | Rest in the shade through noon (lose 3 work hours) | Push on: needs +50 percent water, 35 percent collapse (lose the afternoon, Condition -10) | summer, sun, dehydration |
| **Bad tooth** | Pain remedy from the kit (1 use) | Tough it out: study speed x0.7 for 3 nights (focus) | late-game flavor, optional |

**Home**

| Event | Option A | Option B | Notes |
|---|---|---|---|
| **Roof leak** | Patch it now (1 wood, 1 scrap) | Move your bed and set a pot: tonight's insulation x0.7, study speed x0.8 | rain or snow melt, shack or camp |
| **Flue clogged, smoke** | Douse the fire (1 water): stove cold tonight, fuel wasted | Let it burn out, windows open: 30 percent the stove is wrecked | links to stove fire threat |
| **Tarp torn** | Mend it tonight (1 wood, 1 scrap) | Sleep cold: insulation x0.5 until mended | camp |
| **Frozen pump or pipe** | Thaw it (burn 2 wood) | Wait for sun: no water until noon | winter |
| **Truck fault** | Fix it (scrap, or $) | Limp along: next trip costs +50 percent charge | any |
| **Tool breaks** | Mend with wood (an hour): same tool | Use the spare or bare hands: speed x0.7 until a new one | axe, hoe, rod |
| **Power surge** | Pull the breaker: lose a day of generation | Risk it: 30 percent a device is fried | storm + panels |

**Land**

| Event | Option A | Option B | Notes |
|---|---|---|---|
| **Livestock in the field** (neighbor's cow, deer) | Chase it off now: time and 15 percent trip | Let it graze: lose a share of a field | spring to autumn |
| **Late frost at dusk** | Cover crops (cloth, straw, or wood to smudge) | Gamble: lose unripe crops if it freezes | forecast miss |
| **Hornets** | Smoke them out (2 wood): tiles free again | Avoid the area for 3 days: those tiles locked | summer |
| **Creek bank washout** | Shore it up (3 stone): keep the tiles | Let it go: lose a few tiles | after heavy rain |
| **Storm-felled tree** | Buck it now: +wood, time, 10 percent a fall | Leave it: wood rots and blocks a path | after wind |

**Visitors and luck**

| Event | Option A | Option B | Notes |
|---|---|---|---|
| **Lost hiker at the door (night)** | Share a meal and a fire (1 day of food, a night of fuel): a gift, a tip or a reputation | Send them to the road: nothing gained, a small guilt note | wake event, from year 1 day 5 |
| **Traveling peddler** | Buy rare seeds or a tool ($) | Barter fish or eggs for it | day event |
| **Neighbor on the radio asks a favor** | Do it (a day trip's worth of labour): weather hints, a contract slot | Decline: nothing lost | needs a radio find |
| **Stray dog** | Feed and keep it (feed cost): a dog companion | Shoo it off | once per run |
| **Windfall (a stash, a shed clearing out)** | Haul it now (work, wood) | Mark it for later: it may be gone | rare luck |

About 24 entries at first; each in its own content table so more can be added by data only.

### 6.3 Which events wake you, and the cadence

- **Cadence:** base `tuning.events.chancePerNight` about 0.3 (about one event every 3 nights, two a season, about eight a year), shaped by the exposure terms; day and morning events draw from the same budget (`tuning.events.perDayBudget`, a count per day) so a season is never a pile-up.
- **Wake events:** the hiker, the stove-smoke event, bear and wolf threats (when active and not countered), the power surge. A wake event offers its card and **time keeps running (D168)**: nothing pauses the sim and the night does not wait on the card. If no choice is made, the ignore outcome applies (6.2).
- **The ignore window:** `tuning.events.ignoreHours` of game time *and* never less than `tuning.events.ignoreMinSeconds` of real time (first guess 45 s), so 8x speed cannot skip a card unseen. It counts down only while the player is present. While the player is truly away (the app unfocused, or past the takeover delay with no input) it waits: the card stays in the queue (principle 8) and no new event is offered behind it. Standing orders (6.4) answer for an away player who set them.
- **Quiet start:** no events and no wake events before day 3 (Q10 asks whether a grace after Footing is also needed); a gentler weight curve in year 1.

### 6.4 Standing orders (for idle play)

The Routine screen gets one setting per event class (body, home, land, visitors): **Ask me** (default), **Careful** (the safe-cost option when it is affordable), or **Bold** (the no-cost option). Careful and Bold are chosen by the content's `careful` and `bold` flags, so a designer decides which option each means. **Careful respects keep targets (D168):** if paying the option's cost would drop a stock below its keep target (or the winter reserve target), Careful falls back to the ignore outcome and adds a line to the morning report ("kept the wood, ignored the splint"). Bold costs nothing, so it needs no check. The setting is unlocked by a journal perk ("Rules of thumb"); until then the ignore outcome applies. This keeps GDD §5.2's rule that decisions are never automated unless the player has chosen the rule.

### 6.5 Mercy rules (so events never snowball)

The rules key on Footing state and reserves, not only Condition (D168).

1. An event can reduce Condition but never below `tuning.events.conditionFloor` (never the killing blow).
2. No event fires when Condition is under `lowCondition`, and at most `maxActiveStatuses` statuses are active; a new injury is replaced by a longer old one instead of stacking a third.
3. **While Footing is slipped:** no new bad events are drawn (luck and visitors that cost nothing can still come), threat strength is scaled down (`tuning.events.slippedThreatScale`), and no outcome may destroy capital (the stove, devices, livestock); such an outcome is swapped for its lesser form (a spoiled store, a damage flag).
4. **Lasting damage is capped:** `maxOpenDamage` limits open damage flags (torn canvas, wrecked fence, clogged flue) at once; at the cap, a new damaging outcome is replaced by a cheaper one. **Warmth need has a ceiling:** the combined multiplier (severity x snap x cold front x insulation loss x clothing x status) is clamped to `maxWarmthMultiplier` (first guess 2.0), so stacked bad luck cannot make a night unsurvivable. Fever never fires on a night that already cost cold damage.
5. **Ignore is judged by its worst reachable chain** (6.2): it is never worse than the worse of the two options, counting every later escalation it could lead to, not only the immediate result.
6. A pity timer: after `pityNights` nights without any event (a turned-away threat counts as an event, 5), the next night's chance rises; after a bad event, a cooldown holds the next.
7. Death still comes only from the existing needs model (hunger, cold). Injuries make survival harder, they do not kill.

---

## 7. Status effects (injury and condition model)

A **status** is a short list of modifiers on the homesteader, held in `world.state.status`. Statuses are content (`data/content/statuses.lua`):

```
id, family (ankle | fever | back | burn | tired | ...), severity (1..3),
duration (days or "until"), modifiers = { workSpeed, fallChance, carryCapacity,
  conditionRecovery, conditionDrain, studySpeed, warmthNeed, waterNeed },
escalatesTo, clearedBy (rest | item | time)
```

- **One tiredness mechanism (D168).** Tired is the single status that carries lost sleep over; sleep debt (10.4) is Tired, and wakes and late nights raise it.
- **Families escalate, not stack.** Hobbling, Strained and Torn are one ankle family at three severities. A second event of a family raises severity (to a cap); different families can coexist up to `maxActiveStatuses`.
- **Modifier floors:** work speed never goes under `minWorkSpeed` (about 0.35), so the game is slow, not stuck.
- **Integration:** work speed joins `Stats.modifier` and the actor's job multiplier (as the wardrobe's light-clothes bonus does); warmth need joins the same product as insulation and clothing, clamped by `maxWarmthMultiplier` (6.5), with the direction rule of 6.2; carry and fall modifiers are read by the actor system; Condition recovery joins `Needs.daily`.
- **Recovery:** time, rest (a day in the shelter), food, and warmth speed it; a first-aid kit (consumable) is the third option on body events and cheapens them; journal notes ("Bandaging", "Splinting") unlock better options or lower costs. The notes can also come from buying the first-aid kit or turning away a threat, not only from being injured (the #126 pattern, D168).
- **Wardrobe link:** heavy boots lower fall chance; light clothes raise heat-exhaustion weight; the garments already exist (GDD §7.8).
- **UI:** status chips under the Condition meter with the single most important effect and days left; tap for detail; the season progress card lists what injured you. Chips follow the attention budget (principle 8). Colour is never the only signal (icon and text).

---

## 8. Fields and soil

### 8.1 Crops

Crops widen from 2 to about 12, each with a different shape, so planting is a decision. Per crop in `data/content/crops.lua`: `season window`, `growDays`, `water appetite`, `fertility draw`, `family`, `yield`, `price`, `shelf life`, `frost tolerance`, `quality sensitivity`, `journal gate`.

| Crop | Role | Shape |
|---|---|---|
| Radish (exists) | fast filler | 2 days, cheap, spoils fast |
| Lettuce / greens | fast, thirsty | cold-tolerant, high spoilage, good early stand item |
| Potato (exists) | winter staple | 5 days, keeps, mid draw |
| Bush beans | **fixes nitrogen** | raises fertility; moderate food |
| Carrot | storage | slow, keeps all winter in the cellar |
| Onion / garlic | storage, flavor | garlic is planted in autumn and overwinters |
| Squash / pumpkin | storage, big yield | long grow, heavy draw, spreads |
| Tomato | high value, fragile | needs warmth and a stake, spoils, hail-vulnerable |
| Corn | heavy feeder, big yield | tall (blocks view), shades neighbours, heavy draw |
| Herbs | tiny space, high price | cheap to grow, good contract item |
| Berries (perennial) | long-run income | see 8.5 |
| Orchard trees (perennial) | long-run income | see 8.5 |

**Water priority (D168):** crop water appetite and drinking water draw on the same `water` stock. Drinking is served first (D160); irrigation takes what is left, and the water panel shows the split.

Seed return and heirloom lines (seed saving) are a later add (8.7).

### 8.2 Soil fertility

- Every tile has **fertility** 0..1 beside the existing soil quality and water table. A harvest draws fertility by the crop's `fertility draw`. Yield scales with fertility the way it scales with soil quality now.
- Recovery: **fallow** (a tile left unplanted regains slowly), **legumes** (beans add), **compost** and **manure** (fast, 8.4), and straw mulch (small).
- A tinted overlay shows fertility, as the placement overlay shows the water table. The Plan field tool shows the tile's expected yield before you commit.
- Neglected, drained land yields about `soilFloor` of base, never zero: the fix is cheap and visible.

### 8.3 Rotation, pests and weeds

- **Families** (roots, brassicas, nightshades, legumes, cucurbits). Planting the same family twice in a row builds **pest pressure** on the tile; high pressure invites a pest event or a yield cut. Rotating clears it.
- **Weeds** grow on tilled tiles on a timer and on neglected tiles; they cut yield and quality until pulled. A new task `weed` (category `maintenance` or its own) is routine-able. **Mulch** (straw) delays them.
- **Companions** (optional later): some pairs lower pest pressure.

### 8.4 Compost and manure loop

A **compost bin** takes crop residue, spoiled food and manure and returns compost over days; hens and goats produce manure into their pen, which the Tend chores can move to the bin. Animals now feed the farm, not only the larder. Spoiled food stops being pure loss.

### 8.5 Perennials

Berries and orchard trees cost a lot to start. In days (D168): planted in one season, they give a first, small yield in the *next* season and a full yield once they have come through one winter; then they pay for years. They are the long-term idle investment. **Built basic (D183):** no pruning or frost care, only water; a young plant is a deer and bear target (a data hook until phase C).

### 8.6 Quality

Tiers: normal, good, excellent. Quality comes from fertility, a weeded tile, timely water and **tending** (hand-watering or a tap at the right moment gives a "tended" mark). The routine reaches **good** at best; **excellent** needs active play. Sell value x1, x1.25, x1.6; contracts ask for a tier. This is the concrete answer to "what does active play give me".

### 8.7 Later additions

Seed saving and heirloom lines, a greenhouse (extends season windows, GDD §5.3 rung 2), a mill and oven for bread.

---

## 9. The market, contracts and town

### 9.1 Saturation

Each good has a **saturation** per channel. Every unit sold lowers its price by `saturationStep`, and it recovers `recoveryPerDay` toward base. The weekly price drift (`economy.lua`) stays. A load of 40 radishes sells poorly; a mixed load sells well. The Truck and Pantry screens show the price curve in one line ("radish: price drops after 12"). The stand uses the same model at its 60 percent rate.

### 9.2 Reputation and the contracts board (opens at Footing)

- **Reputation** with the town, levels 0 to 5, earned by finished contracts and visitors' help.
- **Board:** three offers every 7 days, each: item, amount, quality tier, deadline (3 to 10 days), reward (money, reputation, sometimes an item). Reward and tier rise with reputation. Visible and never forced.
- **Standing orders:** a repeating contract every 7 days (eggs, firewood) is the idle-friendly income. Missing one costs a small reputation and is explained; it is never a trap.
- **While Footing is slipped (D168):** no new contracts are offered; deadlines of open ones keep running, but a miss costs no reputation. Goods promised to an open contract are excluded from the Footing food test (3.2), so filling a contract cannot cause the slip. Auto-load and a shared town demand are open (Q8).
- Reputation unlocks bigger cargo offers, better special prices, rare catalog items and higher board tiers.

### 9.3 Processing chains

Processing gains margin and decisions, with shelf-life and fuel trade-offs: jam (berries), pickles (cucumbers, beans), dried fruit and herbs (dehydrator), cider (apples), bread (mill and oven, later), plus the existing smoker and cheese. Rule: a processed good is worth at least 1.5 times its inputs minus fuel and time. Jars and crocks are reusable supplies. New journal pages (Preserving) gate each station.

### 9.4 Market day and visitors

A **market day** on the last day of each season: stand traffic doubles, the truck trip sells at a bonus, a peddler may visit. It gives the week a rhythm and a reason to stock up (an active-play window the routine can partly use).

---

## 10. Labour, wear and upkeep

### 10.1 Wear

A **wear** meter (0..100) on durable things: solar panels (dust: output down until cleaned), the pump (filter), the stove (soot, fire risk), fences (damage after raids), canvas and roofs, tools (dulling: sharpened at a whetstone for speed), the truck (service interval). Wear is shown as a status light in the world, like power. The existing `maintenance` task category (GDD §7.4) becomes real: maintenance tasks appear on the task board by urgency; the routine does them in priority order (default after harvest and water, before clearing), and the player can pull them forward.

### 10.2 Workload

A **workload meter** compares work waiting (task board, scored in seconds) with hours of work left in the day. When the day is overbooked, the routine's priority list decides what is dropped, and the meter says what ("watering is falling behind"). This makes the priority list matter and shows the player what to automate next. The "what's limiting you" line names the current bottleneck.

### 10.3 Helpers

- **Farm dog:** covers some night threats, not all (6.1, D168); a stray-dog event; daily feed cost is its upkeep. Other guards have their own: fence wear from raids, lantern fuel.
- **Mule or donkey:** carry capacity and a haul chore.
- **Hired hand** (seasonal, costs money per day and food): an actor with its own priority list and a zone, using the existing actor framework; a limited number. **Eats from the ledger and counts in the Footing food days (D168)**, so hiring one cannot hide a food shortfall. Whether the hand is capped, unavailable while slipped, or the paid way out of a slip is open (Q11).
- The mini-tractor and auto-harvester (GDD §5.3) fit the same actor model.

### 10.4 Sleep debt

Sleep debt **is** the Tired status (D168), not a separate counter: waking and "stay up" apply or raise it (work speed down a little, study slower). It is the carry-over cost of wake events and late nights; the wake itself costs only that night's study and recovery (5.2).

---

## 11. Money sinks, land and tiers

### 11.1 Tiered upgrades

Convert one-shot items to tiers (I to V, exponential cost): the rod, bucket, axe, stove, cistern, smoker, panel array, stand, coop and pen. Each tier is a Journal node or a reputation gate. Money keeps meaning. Existing "replaces predecessor" items map onto tier I and II.

### 11.2 Owned land (opens at Footing)

The generated map is larger than the starting area. The homesteader begins with a **core area**; the rest is bought in chunks, prices rising with distance and with chunk quality (biome, water, trees). Only owned tiles are buildable. This gives a land goal, makes placement matter, and ties to run variety (plot traits, section 12).

### 11.3 Land levy

At the end of each autumn (before winter) a **levy** is due. It is announced at the start of autumn with its amount, so it is never a surprise. It scales with owned land, and with buildings only by footprint or tier, never with machines (D168), so adding panels, pumps or devices never raises it. Year 1 is exempt (the grace is announced). The levy is the year-end crunch the economy lacks.

- **Order of a season-end day (D168):** market day, then the levy, then the season change. The levy therefore never lands on the day winter starts; the market's income comes first.
- **Calendar-fixed, reduced while slipped:** the due day does not move. While Footing is slipped the amount is reduced (`tuning.land.slippedLevyScale`), never paused (3.2).
- **The bailiff takes nothing the run needs:** he never takes anything below a keep target or the winter reserve target. He sells only goods above them, at a poor rate.
- **An unpaid levy is a penalty, never a run end:** the shortfall becomes one of debt carried into spring, a lien on a land chunk (locked until the debt is paid), or a reputation hit. The player is offered the options that apply; the default is debt.

### 11.4 Recurring costs

Feed, fuel, jars, medicine, replacement parts: small, regular, visible in a ledger of upkeep so the player can see where money goes.

---

## 12. Run variety and the meta

### 12.1 Plot preview

At each new run, three plots are offered with visible traits (soil, water, wood, sun, a hazard) and a reward or risk tag. The choice is the run's first strategic decision.

### 12.2 Year charters (opens at Footing)

At the start of each spring after Footing the player drafts one of three **charters**, each a trade-off for the year. The draft is an offer, so it is not made while Footing is slipped (3.2); the year then runs with no charter until Footing is regained. For example:

| Charter | Plus | Minus |
|---|---|---|
| Market year | contract rewards +50 percent | hail and locusts stronger |
| Hermit year | no levy | stand and board closed |
| Winter prep | fuel and cellar capacity up | field size capped |
| Hands-on year | quality gains up | helpers disabled |

### 12.3 Starting loadouts

Loadouts unlocked by Journal learning: Angler (better rod and bait), Gardener (more seed types), Herder (a hen start), Lumberjack (axe and more wood), Tinkerer (better power start). Each is a bundle of existing items with a small penalty elsewhere.

### 12.4 Ascension

After Established, optional **mutators** (harsher winters, scarcer wood, more night threats) each add a score multiplier on "best year's income" (GDD §4.4). The game keeps a ladder past the soft win.

### 12.5 Journal "Techniques"

A new Journal page of strategy nodes: first-aid, tracking, rotation, trapping, bargaining. Each gives a third option on an event class, an earlier warning, or a cost cut. This is how knowledge changes play, not only the shopping list.

---

## 13. How the systems interact

| | Night | Events | Status | Soil | Market | Upkeep | Land | Charter |
|---|---|---|---|---|---|---|---|---|
| **Night** | | threats wake events | tired | raiders hit crops | spoiled stores | stove soot | exposure | winter stakes |
| **Events** | | | injuries | frost, deer | peddler, favors | tool, truck | washout | charter weights |
| **Status** | | | | work speed on tending | fewer deliveries | slower repair | | |
| **Soil** | | | | | quality prices | weeding load | owned chunks | crop focus |
| **Market** | | | | what sells | | spares cost | land price | reward mods |
| **Upkeep** | | | | | | | levy size | hermit/hands-on |

Three loops this creates:
1. **Safety loop:** reserves -> Footing -> open goals -> money -> better shelter and guards -> safer nights.
2. **Land loop:** fertility and rotation -> quality -> contract rewards -> reputation -> better tiers and land -> more to tend -> workload -> helpers.
3. **Risk loop:** exposure from growth -> more threats -> choices with costs -> statuses -> slower work -> reserves slip -> back to the safety loop.

## 14. Technical shape

- **New sim modules** (`src/sim/systems/`, each added to the `tests/test_architecture.lua` list if outside systems): `footing.lua`, `events.lua`, `status.lua`, `nightthreats.lua` (or inside `threats.lua`), `soil.lua`, `weeds.lua`, `compost.lua`, `contracts.lua`, `wear.lua`, `land.lua`, `levy.lua`, `charters.lua`.
- **New content files:** `statuses.lua`, `events.lua`, `night_threats.lua`, `contracts.lua`, `charters.lua`, `loadouts.lua`; `crops.lua` and `recipes.lua` expand.
- **New tuning domains:** `night.lua`, `events.lua`, `status.lua`, `soil.lua`, `market.lua`, `upkeep.lua`, `land.lua`, `charters.lua`. Every value commented with unit and intent; strict access.
- **Event bus names:** `footing.gained`, `footing.slipped`, `event.offered`, `event.chosen`, `event.ignored`, `status.applied`, `status.cleared`, `threat.landed`, `threat.turned`, `contract.done`, `levy.paid`.
- **Save:** several slices change run or meta state, so each bumps `Save.SAVE_COMPAT` once (one bump per PR, fingerprint in `tests/test_save_compat.lua`). No migrations (GDD D74).
- **Determinism:** every roll uses a named stream; the harness stays byte-identical across `jobs=` settings.
- **UI:** panels follow the MVP interface rules (GDD §9.4); events and the Tonight card work on touch and keyboard, are not hover-only, and have a phone layout. They follow the attention budget (principle 8): one ranked notice queue, at most one card at a time. Driver scenarios cover each new screen (`tools/driver`).

## 15. Balance targets (directional, pursued in M9)

These are not acceptance gates for M8 slices. M8 uses the smoke harness only; these numbers guide the M9 pass and are revised first if play disagrees. The time model (T0) kept the 320 s day (D159), so none moved.

| Metric | Target |
|---|---|
| Median day Footing is first reached (`active`, `scripted`) | 12, 16 |
| `active` first-winter failure | 40 to 60 percent |
| `scripted` first-winter failure | 60 to 80 percent |
| Events per year (all kinds) | 6 to 10, at most 1 wake per 3 nights |
| Days with an active status (`active` policy) | under 15 percent |
| Share of runs where an event alone forces a failure | 0 |
| Distinct crops planted by a year-2 `active` run | at least 4 |
| Money unspent at day 28 (shows sinks work) | under 35 percent of the year's income |
| Idle-routine run vs active, year-1 income | idle 40 to 60 percent of active |

**Restated against the review (D168).** These targets are directional and are measured *against* the harness's own bias: the harness is an upper bound (BALANCE.md caveat), so the numbers above are read together with a degraded policy and paired runs, not alone.

- **Spiral metrics** (reported, with no gate in M8): nights slipped per run, the share of slips that end in death (slip-to-death), lasting damage flags open at death, and money in hand on levy day.
- **A degraded `human` policy** (slower reaction, skips some chores, ignores some cards) beside `active`, `scripted` and `idle`, because a perfect policy hides the failures a person has.
- **Paired seeds, events on vs off:** the same seeds run with events disabled and enabled. The share of runs that fail with events on and survive with them off is the measure of event-caused failure; the target for it is directional (near zero for `active`, a small share for `human`), and replaces the unmeasurable "event alone forces a failure".
- **Event-choice policies** (careful, bold, ignore, random) land with B3 and B5, not I1a, so every smoke run exercises more than ignore, and they report per event class.

Targets move with real human play.

## 16. Risks and open questions

| # | Question | Default if not decided |
|---|---|---|
| Q1 | ~~Is a 28-day year too short for rotation and perennials to feel real?~~ | **Settled (D168):** keep the 28-day year; perennials are stated in days: a first yield the next season, a full yield after one winter (8.5) |
| Q2 | Do wake events annoy players who sleep at 8x speed? | At most one per 3 nights; time never freezes, ignore is safe, the window has a real-seconds floor (6.3); skippable via standing orders |
| Q3 | Should the levy exist at all, or is the land goal enough? | Include; soft failure only |
| Q4 | Should Footing be shown as a number to the player? | Yes, a clear checklist, not hidden |
| Q5 | Do hired hands break the "sparse characters" pillar (GDD §7.8)? | Keep them unnamed and unseen-in-dialogue, an actor type (see also Q11) |
| Q6 | Are events too many for phone play? | Cap the daily budget; Careful standing orders |
| Q7 | Content volume | Ship packs; each pack is data only |
| Q8 | Auto-load against market saturation: does the routine's auto-load dump goods into a saturated price, and should the stand and the truck share one town demand, so selling through both does not double the room? | **Settled (D170):** Shared town demand across stand and truck; auto-load sees saturation and spreads a load to avoid dumping into a saturated price |
| Q9 | Charter minuses that are free picks: if the player owns nothing a minus touches (no helpers, no stand), it costs nothing. Should the minus depend on what is owned? | **Settled (D170):** Charters are drafted only when their minus touches something the player owns (or is about to); the harness logs the win rate per charter |
| Q10 | A post-Footing grace of N nights before events start: events begin on day 3, Footing comes about day 7 to 10, so the first events land on a fragile run. | **Settled (D170):** No bad events before Footing is earned or day 10, whichever comes first (cutoff day in tuning); mild luck events may still run from day 3 |
| Q11 | The hired hand: capped, unavailable while slipped, or the paid way out of a slip? | **Settled (D170):** Hiring is available while slipped as a paid way out of a slip (ongoing food and wages), capped at one per season; the hand eats from the ledger and counts in the food days |
| Q12 | Does the land mask (G1) let players chop, clear or fish unowned tiles? It is the best lever for winter wood and early money, and without it owned land alone gates the winter. | **Settled (D170):** Gathering (chop, forage, fish) is allowed on any reachable unowned tile; building and planting only on owned land |
| Q13 | Which meta state survives a rescue (reputation, land, contracts, charter progress, Techniques, loadouts), and how early may Footing come by run 5? | **Settled (D170):** Only knowledge survives a rescue: Journal, Techniques, wardrobe and unlocked charters and loadouts. Reputation, land, contracts and money reset with the run |
| Q14 | Plot preview (12.1) on run 1: a first strategic choice before the player knows what a trait means? | **Settled (D170):** Plot preview starts on run 2; run 1 keeps the fixed first-time experience |
| Q15 | Loadouts, Techniques and Rules of thumb together may trivialise the early game. Do they need a combined budget? | **Settled (D170):** No combined budget now; build as designed and measure Footing day by run 5 in the harness during the M9 pass, adding a cap only if it trivialises |

Risks: scope (this is a large milestone); event fatigue; compounding statuses. Mitigations: slice order (section 17), the mercy rules, the budget, and harness gates before each phase merges.

## 17. Milestone and slices (M8: Homestead depth)

Issues are written to be done by an agent alone: each states its goal, design reference, scope, out of scope, likely files, acceptance, tests and docs. Labels: `enhancement` plus a topic label; `balance` where numbers move. Order (re-sequenced, D168): T0 first, then A. Then **B3, B4 and B6 ship together with a small first events pack** (B6, trimmed to events that need no later system). **C1 is designed together with B3** (shared exposure, nightly budget and slot rules, 5), and **C8 (#362) comes right after B3** (winter wood as a stockpile problem). Each later pack lands after the systems it uses: home events (B7) after F1 wear and G3 tiers; land events (B8) after D and possibly G1; C6 stove fire after F1; H2 charters after E, F and G. D and E can run in parallel, then F and G, then H, then I. The event-choice harness policies (careful, bold, ignore, random) move out of I1a into B3 and B5, with the spiral metrics, a degraded `human` policy and paired events-on/off seeds (15).

**Phase T: Time model (do first)**
- T0 (#395) Decide the time model: real-time length of a day, whether task times scale with it, and the resulting season and year length. Owner's decision. Blocks B3, F1 and F3. **Done (D159):** the 320 s day stays, no tuning moved; if the day is ever lengthened, task and walk times scale with it.

**Phase A: Tonight and Footing**
- A1 (#340) Dusk check: the Tonight card and a `Readiness.tonight` accessor. **Done (D161).**
- A2 (#341) Footing state machine (earned, slipped, regained), events, save. **Done (D162).**
- A3 (#342) Goal ladder in the HUD and Progress panel: the pressing goal line, locked gates. **Done (D163).**
- A4 (#343) Gate framework: a `requiresFooting` flag in content, read by Catalog, Contracts, Land, Charters.
- A5 (#344) Harness: Footing metrics and an early-game pacing report. **Done (D165).**

**Phase B: Status and events**
- B1 (#345) Status system (sim) and stat-modifier integration.
- B2 (#346) Status chips and detail UI.
- B3 (#347) **Done (D169).** Event engine: content schema, scheduler, exposure, mercy rules, pending queue, ignore window, `event` RNG stream, journal note on first. **Amended (D168):** designed with C1 (one exposure, one nightly slot, 5); mercy rules key on Footing and reserves (6.5); ignore window has a real-seconds floor and time never freezes (6.3); ships with the event-choice harness policies (careful, bold, ignore, random), the spiral metrics, a `human` policy and paired events-on/off seeds; C8 follows it.
- B4 (#348) **Done (D172).** Event card UI: two options, costs, risks, ignore line, touch and keyboard, phone layout. **Amended (D168):** ships with B3 and B6; one card at a time in the ranked notice queue (principle 8).
- B5 (#349) Standing orders (Ask, Careful, Bold) and the "Rules of thumb" perk. **Amended (D168):** Careful respects keep targets and falls back to ignore with a morning-report line (6.4); carries the careful/bold/random harness policies.
- B6 (#350) **Done (D173).** Body events pack. **Amended (D168):** the first events pack, shipped with B3 and B4; ignore outcomes are safe and non-escalating (6.2); Fever never fires on a night that already cost cold damage.
- B7 (#351) Home events pack. **Amended (D168):** lands after F1 wear and G3 tiers.
- B8 (#352) Land events pack. **Amended (D168):** lands after D, and possibly G1.
- B9 (#353) Visitors and luck events pack.
- B10 (#354) First-aid kit and Techniques notes for body events.

**Phase C: Night threats**
- C1 (#355) Night threat framework; move mice and fox into it; dusk signs; wake hook. **Amended (D168):** designed with B3 (shared exposure units 0 to 10, nightly slot, turned-away threats use the slot and the pity timer); per-guard `covers` and upkeep.
- C2 (#356) Raccoon, skunk, deer and rabbits.
- C3 (#357) Black bear and the bear box.
- C4 (#358) Wolves and coyotes; the dog companion.
- C5 (#359) Weather nights: cold front, windstorm, pipe freeze, power outage.
- C6 (#360) Stove fire and soot (links to F2). **Amended (D168):** lands after F1 wear; no stove loss while slipped.
- C7 (#361) Night gear: lantern, trip line, bell.
- C8 (#362) **Done (D171).** Winter wood is a stockpile problem, not an on-demand chop (tracked with #65, #202, #251). **Amended (D168):** pulled forward to right after B3. Unowned tiles can be chopped (Q12, D170). Built as a per-season allowance on wood from trees (`tuning.wood.fellAllowance`, winter 24, first guess), shown on the Tonight and readiness cards; the keep logic and the balance numbers of #202 and #251 are unchanged (M9).

**Phase D: Fields and soil**
- D1 (#363) Crop schema and 8 new crops (content, journal pages, seed items).
- D2 (#364) Soil fertility and the overlay.
- D3 (#365) Rotation families and pest pressure.
- D4 (#366) Weeds, weeding task, mulch.
- D5 (#367) Compost bin and manure loop.
- D6 (#368) Quality tiers and tended marks. **Done (D182).**
- D7 (#369) Perennials: berries and orchard. **Done (D183).**
- D8 (#370) Routine categories and conditions for the new tasks.

**Phase E: Market**
- E1 (#371) Saturation model for truck and stand.
- E2 (#372) Reputation and the contracts board; standing orders.
- E3 (#373) Processing recipes and stations.
- E4 (#374) Market day and the peddler.

**Phase F: Labour and upkeep**
- F1 (#375) Wear system and the maintenance task category.
- F2 (#376) Maintenance items: dust, filters, fences, tools, truck.
- F3 (#377) Workload meter and bottleneck line.
- F4 (#378) Hired hand actor.
- F5 (#379) Mule and sleep debt.

**Phase G: Money and land**
- G1 (#380) Owned-area mask and land purchase.
- G2 (#381) Land levy with soft failure.
- G3 (#382) Tiered upgrade framework; convert existing items.
- G4 (#383) Recurring costs and the upkeep ledger.

**Phase H: Run variety**
- H1 (#384) Plot preview.
- H2 (#385) Year charters. **Amended (D168):** lands after E, F and G; no draft while slipped.
- H3 (#386) Starting loadouts.
- H4 (#387) Ascension mutators.
- H5 (#388) Journal Techniques page.

**Phase I: Integration**
- I1a (#389) Harness policies for the new systems (smoke testing only). **Amended (D168):** the event-choice policies moved to B3 and B5. The full balance pass is I1b (#396) in M9.
- I2 (#390) FTUE and tip updates for each phase.
- I3 (#391) Merge into GDD, wiki and decision log.
- I4 (#392) Perf and save-size check.
- I5 (#393) Driver scenarios and screenshots.

Status: milestone **M8: Homestead depth** and issues #340 to #393 are created (one per slice, titled `[M8 <id>]`). Slice C8 (winter wood as a stockpile problem) was added during the issue review and is tracked by #65 with #202 and #251.

**Existing issues folded in** (review of the open backlog):

| Action | Issues |
|---|---|
| Closed as superseded | #235 (goal, answered by D117 and A3), #276 (into A3), #263 (into D1, E1, G3), #46 (into D1, D7, B3, B6 to B9), #145 (into F1) |
| Moved into M9 (Balance & pacing) | #124, #125, #202, #251, #280, #67, #150 (pure tuning, after T0 and the M8 systems) |
| Moved into M8 | #65 (C8, mechanism only); #91, #211 (pipe freezing); #95 (drinking water, before A1); #109 (event engine reuse); #114 (C2); #106 (E1); #154 (D3 and C5); #156 (I2); #153 (I1a); #213 (C5); #274 (C7); #7 (F3) |
| Commented as related | #126, #264, #148, #149, #150, #337, #338, #117, #118, #212, #215, #198, #44, #147, #99, #103, #6, #178, #169, #175, #273, #102, #121, #138, #131, #256 (sprinklers shipped; narrow or close) |

Each phase ends with a smoke harness run (it completes, deterministic, no new failure class). Target chasing waits for M9.

## 18. Proposed decisions (to number D158 onward when approved)

1. The goal ladder and Footing (3.2).
2. Night is never a free skip; exposure drives night danger (5).
3. Two-option misfortune events with an ignore outcome and mercy rules (6.2, 6.5).
4. Statuses escalate by family, with floors (7).
5. Crop, soil, rotation and quality model (8).
6. Saturation, reputation and contracts (9).
7. Wear, workload and helpers (10).
8. Tiers, owned land and the levy (11).
9. Plot preview, charters, loadouts and ascension (12).
10. Design review amendments (D168): a slip forgives, wake events never freeze time, ignore is safe, mercy rules key on Footing, one tiredness mechanism, cadences in days, a re-sequenced section 17.
