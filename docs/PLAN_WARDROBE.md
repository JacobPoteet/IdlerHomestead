# Plan: the homesteader's wardrobe

Status: implemented in #328 (the character and the plans), #329 (the sim: garments, weight classes, dawn snapshot, unlocks), #330 (the menu), #332 (earning surfaces and the recovery variant) and #334 (presets and Auto). Changed or dropped on the way: the Look / Appearance tab and hair and skin choices were dropped (customization only, see PLAN_WARDROBE_MENU §6.7); seven garments without an unlock in §4 got one, and the Scarf unlock is "live through a frost" because the game has no radio neighbour; the menu key is a rebindable `C` action; Auto reads `Weather.warmthNeed` against `tuning.wardrobe.autoColdNeed` and wears a saved preset at dawn, off by default. Covers a redrawn character, clothes with a small day/night trade-off, how clothes are earned, and the menu that puts them on.

## 1. What the system has to do

| # | Requirement | Source |
|---|---|---|
| R1 | A redrawn homesteader with sane proportions | Request |
| R2 | A catalog of garments, each with a weight class | Request |
| R3 | Light garments: a small work-speed bonus, a slightly larger warmth need at night | Request |
| R4 | Heavy garments: no bonus, a slightly smaller warmth need at night | Request |
| R5 | Garments are unlocked and then kept across runs, but each save slot has its own wardrobe | Request, GDD pillar 3 |
| R6 | A menu to preview, wear and swap garments | Request |
| R7 | Boosts stay small: the feeling of getting better slowly | Request |
| R8 | Fits the existing rules: sim has no drawing, tuning and content are data, input has a touch and a keyboard path, nothing hover-only | CLAUDE.md, GDD §10, §12 |

Where the code already helps:

| Need | Existing hook |
|---|---|
| Night warmth multiplier | `Shelter.insulation(world)` multiplies `Weather.warmthNeed` in `Needs.warmthNeeded`, the power thermostat (`power.lua`) and the readiness forecast (`readiness.lua`). Clothes join the same product. |
| Work-speed bonus | `actors.lua` (line 121) already computes the homesteader's job multiplier from `idle.activeWorkMultiplier` / `idleWorkMultiplier` plus `Stats.modifier`. |
| Per-slot persistent state | `world.meta` (journal, career, fish guide, ftue). A new `meta.wardrobe` sits beside them. |
| Unlock hints | The Field Journal's "???" nodes with a hint of what is missing (D72). Locked garments reuse the idea. |
| Where a player already looks | Decision stamps on the left edge, the recovery scene, the Menu plate. |

## 2. Rules

1. **Clothes live in `meta`, per slot.** Run state never holds an unlock. A failed run keeps every garment (GDD §4.3). A new slot starts with the starter outfit. Nothing is shared between slots.
2. **One outfit applies for a whole day and the night after it.** The wardrobe can be edited any time, but a change takes effect at the next dawn (a new run applies at once). Without this, players wear light clothes by day and heavy by night and the trade-off vanishes. This also reads naturally: you dress when you get up.
3. **The weight trade-off only bites when it is cold.** Summer has no warmth need (`needs.warmthCurve` is 0 from 0.20 to 0.50 of the year), so light clothes are free then. In autumn and winter the choice is real. The swap-by-season rhythm is the intended play, and gives returning players a reason to open the menu.
4. **Bonuses are tiny and capped.** Numbers in section 5. A full light outfit is worth about 4% work speed. A full heavy outfit saves about 8% of the night's heat. For scale: the shack is 40% and the camp 15%.
5. **Earned, never bought.** No money, no catalog entry. Money and the catalog reset every run, so they cannot carry an unlock. Each garment ties to something the player did.
6. **Sandbox slots** (D134) have no career, so they unlock nothing. Proposal: a Sandbox slot has every garment available, effects on. Cheap, and consistent with the Debug catalog idea.
7. **No effect on appearance rules elsewhere.** The portrait, shadow, rim light and sleep state all read the same sprite, so they follow the outfit for free (section 3).

## 3. Redesigning the character

The old sprite was a prototype placeholder, so nothing of its art or style carries over. The new character is drawn to the style the world has since settled on (D136, D142, `docs/ASSETS.md`), not to the old sprite.

### What is wrong with the current sprite

`P.homesteader` in `game/src/render/placeholders.lua` is 16x20, one static frame, drawn as flat rectangles.

| Problem | Detail |
|---|---|
| Proportions | Head narrower than a square torso, 1 px stick arms, legs 2 px wide and 4 tall (22% of height) |
| Missing parts | No neck, hands, sleeves or feet, so there is nothing to dress |
| Wrong language | Straight rectangles and one flat shade. Every other sprite now has rounded lit clumps, a three-step ramp and an ink outline, so the figure looks pasted in |
| Scale | About the size of a rock next to chunky bushes and 32 px trees |

There is no facing and no walk cycle (the world renderer draws `Assets.sprite(actor.kind)` unflipped), which keeps the art budget small. It is also the biggest constraint on clothing: every garment is one extra picture, not one per frame.

### The style the world already has

Read from `ASSETS.md`, the recent screenshots (`docs/screens/uxproto_*`) and the placeholder painters for trees, shrubs and rocks.

| Rule | What it means for the character |
|---|---|
| Chunky, rounded silhouettes | Shrubs and rocks are blobs with the four corner pixels cut. Head and torso are rounded blocks, not hard rectangles |
| Lit from the top left | Each part gets a light edge on its top and left and a dark edge on its bottom and right. Overlaps give the shading for free (the head's lower edge shades the chin) |
| Three-step ramp per material | Light, base, dark, with the dark hue-shifted cooler and redder, not just darker. Never pure black |
| 1 px cool ink outline | `outline = { 0.07, 0.08, 0.12 }`, the same as crops and trees |
| Value plan | Calm light ground, deep cool foliage, and strong red kept for the homesteader. A figure has to read at a glance among shrubs and shadows |
| Shaders finish the job | Cast shadow, contact shadow, rim light and form shade come from the sprite's silhouette. Do not paint a shadow or rim into the art, only the ellipse the other actors already carry |
| Readable at night | The night grade multiplies colour, so contrast comes from value and silhouette, not hue |

Two rules added for clothes:

1. **The red travels.** Because strong red is the homesteader's identity, every outfit keeps one saturated warm accent of at least 3 px (hat band, scarf, mitten cuff, flannel). Otherwise a grey winter outfit vanishes in snow and forest.
2. **Garments follow the same ramps.** A garment is a part with its own three-step ramp and gets its shading from the same top-left rule, so a new garment needs only a shape and a palette, not hand-shaded pixels.

### The body: D, the mascot chibi (decided)

Chosen from four options (3.2, 2.4 and 2.0 heads, with the mockups `docs/screens/wardrobe_character_mockup*.png`).

| Part | Spec |
|---|---|
| Sprite | 20x22 (was 16x20): 3 rows of margin above for hats and the hair tuft, the last row holds the ground shadow |
| Head | 14 wide x 10 tall, corners rounded. 2x2 eyes with a one pixel glint, blush, a two pixel mouth, hair fringe, sideburns and a cowlick |
| Torso and arms | Torso 6x3, arms 2 px wide, one row of hand |
| Legs and boots | Legs 2 rows, boots 2 rows with a toe overhang |
| Proportion | About 2 heads tall. The head carries the character, and hats, scarves and toques are big enough to tell apart |

Trade-off to keep in mind: the torso is only 3 rows tall, so torso garments (sweater, jacket, tank) show as a colour, a sleeve and a pattern, not a cut. Hats, scarves and mittens do the visual work. Garment designs should lean on the head, neck and hands.

Built in `game/src/render/character.lua` (phase 1, done in this branch): parts with three-step ramps, shaded top-left, ink outline, the same rule as the world. In the engine it reads cleanly on grass, at golden hour, at night by a fire and on snow (`lovec tools/driver character`, shots `docs/screens/character_desktop_*`). The summer and winter outfits already paint and are covered by `tests/test_character.lua` (fit, feet on one row, keeps the face and the red accent).

### Layers (paperdoll)

Back to front, each layer a placeholder painter in the same 16x24 box:

| Order | Layer | Fed by |
|---|---|---|
| 1 | Back (scarf tail) | Extra slot |
| 2 | Legs | Legs garment |
| 3 | Feet | Feet garment |
| 4 | Body (skin: head, neck, hands) | Skin tone |
| 5 | Torso and sleeves | Torso garment |
| 6 | Belt | Torso garment |
| 7 | Face | Fixed |
| 8 | Hair | Fixed |
| 9 | Head garment | Head slot |
| 10 | Extra (scarf front, gloves) | Extra slot |

Hats hide the hair layer where they cover it. Each garment is a data entry plus a painter, with an `art` file path later (the same `placeholder` to real art swap the manifest already supports).

### Putting it on screen without touching the renderer

Every consumer (world draw, cast shadow, badge portrait, sleep, wardrobe preview) asks `Assets.sprite("homesteader")` for an atlas rectangle. The atlas is built once in `Assets.load`.

Plan: add `Assets.recomposite(id, painter)` that clears the sprite's atlas rectangle and repaints it from the layer stack into the existing canvas. Call it when the dressed outfit changes (dawn, new run, wardrobe confirm), which is rare. Everything downstream is unchanged, and a hat automatically changes the cast shadow.

Risk to prototype first: repainting a sub-rectangle of the atlas canvas with the right blend mode (replace, not alpha-over). The wardrobe preview can use a separate scaled canvas, so a failure here does not block the menu.

Hair, skin and face are fixed. This is a wardrobe, not a character creator.

## 4. Garments

Five slots: Head, Torso, Legs, Feet, Extra (neck and hands). Three weight classes: Light, Mid, Heavy. Mid is the neutral baseline and carries no bonus and no penalty. The starter outfit is all Mid and matches today's flannel, jeans and boots, so a new slot plays exactly as the game does now.

| Slot | Light (work up, more heat at night) | Mid (baseline) | Heavy (less heat at night) |
|---|---|---|---|
| Head | Straw hat | Bare head, Flat cap | Wool toque, Trapper hat |
| Torso | Tank top, Linen shirt | Flannel shirt (start), Denim jacket | Wool sweater, Oilskin coat, Down parka |
| Legs | Shorts | Work pants (start), Overalls | Wool trousers, Insulated bibs |
| Feet | Canvas shoes | Work boots (start) | Felt-lined boots, Snow boots |
| Extra | Bandana | None, Work gloves | Scarf, Mittens |

About 20 garments, 5 of them starter or default. Each slot has at least one choice in every class so every slot offers the trade-off.

### Unlocks

Three families, spread so the wardrobe grows through the whole career, not just the first run.

| Family | Idea | Garments (proposed) | Condition |
|---|---|---|---|
| Seasons | Your time on the land | Linen shirt: finish your first summer. Wool toque: survive your first winter. Wool sweater: survive winter 2. Down parka: survive winter 4 | Winters survived in this slot (`meta.established` already records the first) |
| Craft | Things you got good at | Straw hat: harvest 3 different crops. Canvas shoes: catch 5 fish species (fish guide). Overalls: own the shack. Work gloves: build 3 machines. Flat cap: place the truck charger | Counters already in the fish guide, journal and built objects. Some need a small counter added |
| Memories | People and events | Bandana: be rescued once. Oilskin coat: be rescued 3 times (the rescuer: "You again?"). Scarf: hear the radio neighbour N times. Felt-lined boots: reach 5 runs. Trapper hat: survive a cold snap year | Career history, rescue count, radio events |

Why these: the Memories family turns failure into progress, which is the game's third pillar. Heavy pieces cluster in the Seasons and Memories families, which are the survivors of hard winters, so heavy clothes feel like hard-won knowledge. Light pieces come from craft, so a productive farmer looks productive.

Locked garments show as a dark silhouette with one icon and one short hint line ("Survive a winter"). Never a paragraph (pillar 8). A just-earned garment shows a small amber dot on the tile and a toast; the left-edge decision stamp ("New clothes") opens the wardrobe.

### Weight classes in numbers

All values go in `data/tuning/wardrobe.lua`, each with a unit and intent comment (CLAUDE.md). Starting proposal, to be tuned with the balance harness:

| Tuning key | Start value | Meaning |
|---|---|---|
| `slotWeight` | head 1, torso 3, legs 2, feet 1, extra 1 (total 8) | How much each slot counts toward the outfit |
| `light.work` | +0.005 per weight point | Added to the homesteader's work multiplier. A full light outfit is +4% |
| `light.cold` | +0.0075 per weight point | Added to the night's warmth need. A full light outfit is +6% |
| `heavy.cold` | -0.010 per weight point | A full heavy outfit is -8% |
| `heavy.work` | 0 | The request says heavy gives no boost |
| `mid` | 0 / 0 | Baseline |
| `insulationFloor` | 0.85 | Clothes alone never cut the need by more than 15% |

Outfit insulation = `1 + sum(weight * cold)`, multiplied into the shelter's insulation. Outfit work bonus = `1 + sum(weight * work)`, multiplied into the job multiplier.

Worked example in deep winter (need 8 heat at severity 1, camp 0.85): all light 8 x 0.85 x 1.06 = 7.2, all heavy 8 x 0.85 x 0.92 = 6.3, a gap of about 0.9 heat (about one fire-log) a night and 4% work speed by day. Visible in the numbers, never decisive. A player in a mixed outfit sits between, so the 5 slots give about 3^5 combinations on the same two axes.

Checks before locking numbers:
- Add an `outfit=light|mid|heavy` option to `tools/balance` and compare survival, income and fuel use over 20 seeds. Neither extreme should win outright.
- Confirm a full light outfit can still survive a deep winter without extra fuel stockpiling (it must be a small cost, not a trap).

## 5. The wardrobe menu

### Where it lives

| Entry | Why |
|---|---|
| Menu plate, "Wardrobe" | Always reachable, works on touch |
| Key `C` | Keyboard path |
| Recovery scene, "Change clothes" button beside the new-garment list | The natural moment: you just failed, you just earned something, you are about to start fresh. A new outfit applies at once here |
| Left-edge decision stamp "New clothes" | Only when something unlocked and has not been seen |

The homesteader badge keeps its single job (toggling the routine), so it does not gain a second tap target.

It is a paper-style page (D140), so it matches the Notebook and Ledger. It is not a third tab on either book: the Notebook is what you know and the Ledger is what you run, and clothes are neither.

### Layout (desktop)

```
+-----------------------------------------------------------+
| Wardrobe                                            [ X ] |
+--------------------+--------------------------------------+
|                    |  [Head][Torso][Legs][Feet][Extra]
|   big preview      |  +------+ +------+ +------+ +------+  |
|   (x8, pixel)      |  | hat  | | cap  | |toque | | ???  |  |
|                    |  | LIGHT| | MID  | |HEAVY | | lock |  |
|   Flannel + jeans  |  +------+ +------+ +------+ +------+  |
|                    |  Tile: icon, name, weight pips,        |
+--------------------+  locked: silhouette + one hint line    |
| Day work    +2%  ####-----                                  |
| Night heat  +3%  --###----     Takes effect at dawn         |
|            [ Wear ]   [ Reset ]                              |
+-----------------------------------------------------------+
```

- **Preview.** The sprite at 8x with nearest filtering, on a plain ground tile. Tapping or focusing a tile previews it on the character at once, before anything is committed.
- **Slot tabs.** Five icons. Big touch targets, same size as the Ledger tabs.
- **Tiles.** Icon, short name, a three-pip weight mark (feather for light, plain for mid, snowflake for heavy). No hover text. Locked tiles show a silhouette and one hint line.
- **Two meters.** "Day work" and "Night heat", each a small signed bar with a number, recomputed live for the previewed outfit against the worn one. This is the "show, don't tell" rule: the player reads the trade-off from the bars, not from a description.
- **Commit.** "Wear" applies the staged outfit. A one-line tag says "Takes effect at dawn" (or "Now" in the recovery scene and on a fresh run). "Reset" returns to the worn outfit.
- **Phone.** Preview on top, meters beside it, slot tabs and a scrolling tile grid below. One column, 44 px minimum targets, same layout rules as the Ledger.
- **Input.** Mouse, touch and keyboard (arrows move across slots and tiles, Enter wears, Esc closes). Nothing is hover-only.
- **Presets (phase 2).** Two saved outfits, Warm and Cold, with an "auto by forecast" toggle that switches at dawn when the coming night needs heat. For an idle game people watch, this removes the chore of swapping each season. Default off.

## 6. How other games handle it

I could not find an earlier discussion of clothing in this project's saved sessions, and the games in the GDD reference table (§2) give little. Stardew Valley is the only one that customizes a character, and it is purely cosmetic. The rest below come from general knowledge of those games, not from a lookup this session.

| Game | What it does | Take | Avoid |
|---|---|---|---|
| Stardew Valley | Shirts, pants, hats, hair, shoes are cosmetic and layered. Stats come from rings and tools, not clothes | The layered paperdoll and a wardrobe page | Pure cosmetics gives no reason to open the menu again |
| Don't Starve | Hats and coats carry insulation and heat or cool, with a seasonal rhythm (winter hat, summer hat) | The seasonal swap: the right item changes with the weather | Clothes break and are crafted from loot, so they do not persist |
| The Long Dark | Layered clothing with warmth and wetness, plus condition decay | Cold-weather clothing as a quiet survival dial | Heavy clothing is a real danger or a hard requirement |
| Project Zomboid | Many body slots with insulation and wind chance, plus layering | A clear slot model | Too many slots and stats for a game people watch |
| RimWorld | Apparel has a comfy temperature range, and colonists re-dress by season | Auto-dress by temperature | A full temperature-range model is far too heavy for one homesteader |
| Terraria | Vanity slots separate looks from stats | Keep what you wear apart from what it does (relevant if power creeps later) | Armor stats dominate the game |
| Scritchy Scratchy | Permanent small upgrades that make each run start faster | The slow, steady feeling of getting better | None specific |

The distinct bit here: the stat is two small linked numbers (work and heat) read from one weight class, and the whole outfit is one choice per season.

## 7. Technical design

### Content and tuning

- `game/data/content/garments.lua`: `{ id, slot, class = "light"|"mid"|"heavy", name, icon, art, unlock = { kind, n | id } , starter = bool }`. Validated by a schema entry in `data/schemas.lua`.
- `game/data/tuning/wardrobe.lua`: the table in section 4, plus the unlock thresholds so they can be tuned without code.

### State

| Where | Shape | Notes |
|---|---|---|
| `meta.wardrobe` | `{ owned = { [id] = true }, seen = { [id] = true }, worn = { head, torso, legs, feet, extra }, presets = {} }` | The player's chosen outfit, kept across runs and per slot |
| run slice `wardrobe` | `{ dressed = { head, torso, legs, feet, extra } }` | Snapshot taken at dawn and at run start; the numbers read this, not `meta.worn`, so a mid-day edit cannot change today |

Optional new fields with a nil default, so the save format may not need a `SAVE_COMPAT` bump. Run `lovec tests save_compat` to find out, bump only if it fails (a breaking change needs the bump and the fingerprint update).

### Code

| Piece | Where | What |
|---|---|---|
| `systems/wardrobe.lua` | `game/src/sim/systems/` | Accessors `insulation(world)` and `workBonus(world)`; dawn snapshot; unlock evaluation on events. Added to `systems/init.lua` and `tests/test_architecture.lua` |
| Hook points | `needs.lua:117`, `power.lua:620`, `readiness.lua:34` and `:121`, `actors.lua:121` | Multiply in the wardrobe values. Prefer one `Needs.insulation(world)` helper so the four warmth sites stay in step |
| Unlock events | event bus | The wardrobe system listens for winter survived, rescue, run started, fish guide entry, object built, and so on, then marks `owned` and raises a toast and a decision stamp |
| `render/character.lua` | `game/src/render/` | The layer painters and `compose(world)` that returns the layers; read-only |
| `Assets.recomposite` | `game/src/render/assets.lua` | Repaints the homesteader's atlas rectangle (section 3) |
| `scenes/wardrobe.lua` | `game/src/scenes/` | The page, using the paper and tab helpers of the Ledger |
| Tuning for the UI | `data/tuning/ui.lua` | Sizes, tile grid, meter colours, hint copy, as for the other pages |

### Tests

- Unit: unlock rules, accessor maths (clamp at the floor, mid is exactly 1.0), dawn snapshot, a mid-day edit not changing today, per-slot isolation, save round trip, sandbox behaviour.
- Balance harness: `outfit=` option as in section 4.
- Screenshot driver: a `wardrobe` scenario (desktop and phone, locked and unlocked tiles, preview) and a `character` scenario (old versus new on each ground).

## 8. Build order

Each step is one PR, merged green, in this order.

| Phase | Work | Depends on | Done when |
|---|---|---|---|
| 1 | New base sprite and the character driver scenario | none | **Built, awaiting review.** You like the proportions on every ground |
| 2 | Layer painters, starter outfit, `Assets.recomposite` | 1 | Starter outfit identical to today's look, new base |
| 3 | Content, tuning, `meta.wardrobe`, accessors, dawn snapshot, hooks, tests, harness option | none (can run beside 1 and 2) | Numbers verified headless, no visual change at the starter outfit |
| 4 | Wardrobe scene, Menu entry, key, preview, meters | 2, 3 | Outfit change works end to end on desktop and phone |
| 5 | Unlock hooks, toasts, decision stamp, recovery scene button | 3, 4 | Garments arrive by play |
| 6 | Art pass for the remaining garments, presets and auto-dress | 4 | Full catalog |

Phase 1 should go first and alone: if the base still looks wrong, every later layer inherits the problem.

## 9. Open questions

| Question | Recommendation |
|---|---|
| Is dawn-commit too strict for a game people leave running? | Keep it. Presets with auto-dress remove the chore |
| Should heavy clothes slow the homesteader a little? | No. The request says no boost, and a penalty would feel like punishment |
| Do the numbers need to be larger to be noticed? | Start small as asked. The two meters make 2 to 4% legible |
| A walk cycle? | Not now. Layers are per picture, so frames multiply every garment. Revisit after the catalog exists |
| Sandbox: every garment available? | Yes |

## 10. Docs to update on approval

GDD §7.8 (new "Wardrobe" paragraph), §9.2 (character art spec) and §9.4 (the new page and entries), the decision log (dawn-commit, meta-per-slot, weight classes, earned-not-bought), `docs/ASSETS.md` (sprite size and layer rule), the wiki notes for Run Loop, Shelter and Winter, Meta and Run State, and the Interface section. Check the next free decision number first (D148 is the latest I saw).
