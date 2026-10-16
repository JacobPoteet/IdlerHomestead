# Plan: the Wardrobe menu

Status: proposal, nothing built. Refines the sketch in [PLAN_WARDROBE.md](PLAN_WARDROBE.md) §5. The system rules (garments, weight classes, unlock families, the dawn rule, `meta.wardrobe`) stay as agreed there, with the amendments listed in §6.7.

Scope: a customization menu. The player switches between clothes they have earned. There is no character creation, no hair, no skin tone and no Look tab.

All sizes are UI pixels (virtual pixels). The driver's three views are: desktop 1280x720 at UI scale 2, a 640x360 view; phone 390x844 at scale 1, a 390x844 view; landscape 844x390 at scale 1, an 844x390 view (`src/core/ui_scale.lua`, `data/tuning/display.lua`).

## 1. Goals and non-goals

| Goals | Non-goals |
|---|---|
| The core flow in four taps: open, pick a slot, tap a garment, Wear | Character creation, hair, skin tone, a Look tab |
| A large live preview of the figure, changed by every tap | A walk cycle or turning figure |
| Two signed meters, Day work and Night heat, that make the trade-off readable without prose | Tooltips, stat sheets, comparison tables |
| A whole outfit swapped in two taps (Warm and Cold presets) | More than two presets, named or coloured outfits |
| Locked garments as a silhouette plus one hint line | Explaining unlock rules in paragraphs |
| The dawn rule visible before and after Wear | A way around the dawn rule mid-run |
| Desktop, phone and landscape; mouse, touch and keyboard | Controller support (the focus order is written so it can be added) |

## 2. Screen inventory

### 2.1 States

| # | State | When | What differs |
|---|---|---|---|
| S1 | Browse | Default on open | The draft equals what is committed. Preview shows it. State line "Wearing today". Wear disabled |
| S2 | Preview (draft) | A tile was tapped or focused | Preview, meters and the tile's accent outline follow the draft. State line "Preview". Wear and Reset enabled. The worn value shows as a tick on each meter |
| S3 | Locked tile focused | A locked tile was tapped or focused | The draft does not change. The garment's shape is drawn in ink over the preview figure. The detail line shows the hint. Wear keeps its state from the draft |
| S4 | Committed, waiting for dawn | Wear pressed while the dawn rule applies | State line "From dawn". The committed tile has a "Dawn" pill, today's tile keeps its "Today" pill. Toast "Laid out for dawn" |
| S5 | Committed now | Wear pressed between runs or on a run's first day | Preview equals the world figure at once. Toast "Changed clothes". No pills differ |
| S6 | Dawn passes while open | The sim swaps today's outfit | "Today" moves to the committed tile, "Dawn" pills go. A draft in progress is kept. See §3.4 |
| S7 | New garment | A garment earned and not yet looked at | Amber dot on the tile, amber dot on its slot tab. Focusing or tapping it clears both |
| S8 | Unlock toast and stamp | A garment is earned in play | World toast "New clothes: Straw hat". Left-edge stamp "New clothes" until the Wardrobe is next opened |
| S9 | Recovery variant | Opened from the recovery scene | Close reads "Done". Tag always "Takes effect now". No "Today" or "Dawn" pills (there is no run). Neutral daylight preview |
| S10 | Presets | Preset chips present (build step 4) | Tapping Warm or Cold loads that outfit into the draft (S2). With a preset selected, Save appears beside Wear |
| S11 | Empty preset | A preset never saved | Chip reads "Empty" in dim ink. Tap: the detail line says "Save an outfit here first" |
| S12 | Sandbox slot | `Sandbox.on(world)` | Every garment owned. No dots, no stamp, no toasts. The "SANDBOX" tag (`ui.sandbox.tag`) beside the title |
| S13 | Empty slot list | A slot whose only owned item is its default (for example Head with Bare head) | The default tile plus locked tiles. Never an empty grid: every slot has a starter or "none" entry |
| S14 | Error: unknown garment | `meta.wardrobe.worn` names an id not in content (a removed garment) | The sim's accessor returns the slot's starter. The menu never sees the bad id. One `print` warning in the sim, no crash |
| S15 | Error: no art | A garment whose look has no painter part | Tile thumbnail falls back to `icon_unknown`. The figure draws the slot's starter part. A test fails before this can ship (§7) |

### 2.2 Desktop (view 640x360, paper 600x344)

```
+-----------------------------------------------------------------------------+
| [hd Head][to Torso][lg Legs][ft Feet][ex Extra]                    [Close]  |
+----------------------------+------------------------------------------------+
| Wardrobe                   |  Torso                                 4 of 7  |
| Wearing today              |  +-------+ +-------+ +-------+ +-------+       |
| +------------------------+ |  |     oo| |o     *| |    ooo| |    ooo|       |
| |                        | |  | (fig) | | (fig) | | (fig) | | (sil) |       |
| |                        | |  |Flannel| |Linen  | |Sweater| |  ???  |       |
| |     figure x7          | |  | Today | |       | |       | |       |       |
| |     (140 x 154)        | |  +-------+ +-------+ +-------+ +-------+       |
| |                        | |  +-------+ +-------+ +-------+                 |
| |~~~~ ground swatch ~~~~~| |  |  ...  | |  ...  | |  ...  |                 |
| +------------------------+ |  +-------+ +-------+ +-------+                 |
| Day work   [....|##  ] +2% |                                                |
| Night heat [  ##|....] -3% |  Linen shirt  Light                            |
| [sun Warm] [snow Cold] [Auto]                                               |
|                            |  Takes effect at dawn       [Reset]  [ Wear ]  |
+----------------------------+------------------------------------------------+
```

`o` pips: the weight mark (1 Light, 2 Mid, 3 Heavy). `*` the new dot. `(sil)` a locked silhouette.

### 2.3 Phone portrait (view 390x844, paper 374x828)

```
+--------------------------------------------+
| [Head][Torso][Legs][Feet][Extra]   [Close] |
+--------------------------------------------+
| Wardrobe                                   |
| +----------------+  Wearing today          |
| |                |  Day work               |
| |   figure x8    |  [....|##    ]   +2%    |
| |   (160 x 176)  |  Night heat             |
| |                |  [  ##|....  ]   -3%    |
| |~~~ ground ~~~~~|                         |
| +----------------+  [Warm] [Cold] [Auto]   |
+--------------------------------------------+
| Torso                              4 of 7  |
| +------+ +------+ +------+ +------+ +------+
| | fig  | | fig  | | fig  | | sil  | | fig  |
| |Flanl | |Linen | |Swetr | | ???  | |Parka |
| +------+ +------+ +------+ +------+ +------+
| +------+ +------+                          |
| | ...  | | ...  |     (scrolls if needed)  |
| +------+ +------+                          |
|                                            |
| Linen shirt  Light                         |
+--------------------------------------------+
| Takes effect at dawn                       |
| [    Reset     ]  [         Wear         ] |
+--------------------------------------------+
```

The action bar sits at the bottom, in thumb reach. The meters sit beside the preview, as the earlier sketch asked.

### 2.4 Landscape (view 844x390, paper 600x374)

Same two columns as desktop, centred, with 30 px more height. The preview stays at 7x. Nothing scrolls at the current garment counts.

```
              +-----------------------------------------------------------+
              | [Head][Torso][Legs][Feet][Extra]                 [Close]  |
              +--------------------------+--------------------------------+
              | Wardrobe                 | Torso                  4 of 7  |
              | Wearing today            | [fig][fig][fig][sil][fig][fig] |
              | +--------------------+   | [fig]                          |
              | |    figure x7       |   |                                |
              | |~~~~ ground ~~~~~~~~|   | Linen shirt  Light             |
              | +--------------------+   |                                |
              | Day work   [..|## ] +2%  |                                |
              | Night heat [##|.. ] -3%  |                                |
              | [Warm] [Cold] [Auto]     | Takes effect at dawn [Reset][Wear]
              +--------------------------+--------------------------------+
```

### 2.5 Recovery variant (any size)

Pushed over the recovery scene. Same layout as the view's size. Differences only:

```
| ...                                    Takes effect now    [Reset] [ Wear ] |
| [Done] replaces [Close]; no Today / Dawn pills; ground is spring grass, day |
```

The recovery scene gains one row and one button:

```
| New clothes this run (2)  [fig][fig]                                        |
| New land, same knowledge...        [Change clothes]  [  Head out  ]         |
```

On a view narrower than `ui.wardrobe.recoveryStackWidth`, Change clothes sits above Head out instead of beside it.

### 2.6 Other surfaces

| Surface | Wireframe |
|---|---|
| Menu (`src/scenes/menu.lua`) | `Resume / Wardrobe / Tips / Settings / Save & exit`, one more 28 px row |
| Decision stamp (left edge) | `(*) New clothes`, icon-only `(*)` when compact (the HUD's existing rule) |
| Toast | `New clothes: Straw hat` |

## 3. Interaction spec

### 3.1 Actions by input

| Action | Mouse | Touch | Keyboard |
|---|---|---|---|
| Open | Menu plate, then Wardrobe; the stamp; Change clothes on recovery | Same taps | `C` (rebindable action `wardrobe`) |
| Switch slot | Click a tab | Tap a tab | Focus a tab with Up, then Left / Right (the slot shows as focus lands) |
| Preview a garment | Click its tile | Tap its tile | Arrow keys or WASD move focus; focus previews at once |
| See a locked hint | Click the locked tile | Tap it | Focus it |
| Long-press / right click a tile | Same as a click | Same as a tap | n/a |
| Wear the draft | Click Wear | Tap Wear | Enter (anywhere in the menu) |
| Reset the draft | Click Reset | Tap Reset | Backspace |
| Load a preset | Click Warm or Cold | Tap it | Focus it, Enter loads it (then Enter again wears) |
| Save to the selected preset | Click Save | Tap Save | Focus Save, Enter |
| Toggle Auto | Click Auto | Tap Auto | Focus Auto, Enter |
| Scroll the grid (phone only, if it overflows) | Wheel | Drag, fling | Focus movement scrolls it (`ScrollList:reveal`); Page Up / Down, Home / End |
| Close | Close / Done; click outside the paper | Same taps | Esc, or `C` again |

Rules:
- Hover is cosmetic only (`Buttons` hover fill). Hover never previews, so every input has the same model.
- Focus previews, tap previews. The only commit is Wear (or Enter).
- `space` (the `speed` action) and the tool keys do nothing while the Wardrobe is on top. Time keeps running, as under the books.
- The arrow keys and WASD also reach the scene as held `pan` actions (`Input:update`, `keys = true`). The Wardrobe ignores `pan` with `keys = true` and moves focus on the raw `keypressed` instead, as `JournalScene:action` already does.

### 3.2 Focus order

Focus is drawn only after a key press (keyboard mode) and hidden again on the next pointer press. Movement is spatial within a zone and jumps zone at an edge.

| Zone | Members, in order | Up | Down | Left / Right |
|---|---|---|---|---|
| Z1 Tabs | Head, Torso, Legs, Feet, Extra, Close | stays | Z2 (the worn tile of that slot) | Next tab; the slot changes with focus. Close at the end, no wrap |
| Z2 Tiles | The slot's tiles in content order, row by row | Previous row, or Z1 from the top row | Next row, or Z3 from the last row | Neighbour tile, no wrap |
| Z3 Actions | Reset, Wear (then Save when shown) | Z2 last row | Z4 | Neighbour |
| Z4 Presets | Warm, Cold, Auto | Z3 | stays | Neighbour |

Initial focus on open: the first new garment (S7) if any, else the committed tile of the slot shown. The slot shown on open: the slot of the first new garment, else the slot last shown this session (kept like `Books.remember`), else Head.

On phone the Z4 chips sit above the grid on screen. The order stays Z1 > Z2 > Z3 > Z4 so it is the same on every size; Up from Z2's top row still goes to Z1.

### 3.3 Back and close

| From | Esc / Close / Done / outside tap |
|---|---|
| Any state | Closes. The draft is not worn. The draft is kept for the session (`WardrobeState.remember`) and restored on the next open, with the "Preview" state line, so a careful five-slot outfit is never lost to a stray Esc |
| Recovery variant | Closes back to the recovery scene, which re-reads the worn outfit for its new-clothes row |
| A card or toast on top | The card closes first (normal app stack) |

There is no "discard changes?" dialog. Closing is cheap and reversible.

### 3.4 Dawn while the menu is open

The sim keeps running under the Wardrobe (`App:update` updates every scene in the stack).

| Case | Behaviour |
|---|---|
| Nothing pending | Nothing visible changes |
| A committed outfit waits for dawn | At dawn the sim copies it to today. The scene sees `Wardrobe.dressedKey(world)` change in `update` (the same polling the Catalog uses for money) and lays out again: "Today" moves to the committed tiles, "Dawn" pills go, the state line reads "Wearing today" if no draft is open |
| A draft is open at dawn | The draft is kept. The meters' worn ticks move to the new today. The state line stays "Preview" |
| A day-1 run passes the "now" window while the draft is open | The tag changes from "Takes effect now" to "Takes effect at dawn" on the next layout. Nothing was committed, so nothing is lost |
| The run fails while open | `App:switch` to the rescue scene exits the whole stack (as for the books). The draft is dropped with the run's session |

## 4. Visual spec

### 4.1 Frame

| Part | Spec | Reuses |
|---|---|---|
| Overlay | Dim the world | `Draw.overlay(view)` |
| Night lamp | Warm pool behind and on the paper at night | `Paper.drawPool`, `Paper.drawLamp` with `Motion.night()` |
| Paper | One sheet, dark kraft, fibre | `Paper.draw(tuning.ui.book, ...)` |
| Tab strip | Five slot tabs plus Close, same size and drawing as the Ledger | `Books.layoutTabs(tuning.ui.book, pages, selected, strip, minTouch, measure, iconW)` and a copy of `Book:drawTab` (stamp icon via `Paper.stamp`) |
| Dissolve | Opens and closes like a book | scene field `dissolve = "book"` |
| Title | "Wardrobe" in `body` size at the left column's top, the state line under it in `small`, dim | `Text.draw` |
| Buttons | Wear in the accent style; Reset, presets plain | `Buttons.new(minTouch)`, `Buttons:add` |

The Wardrobe is its own scene, not a third book or a book tab (PLAN_WARDROBE §5). It looks like a book page so it belongs with the Notebook and Ledger.

### 4.2 The preview

| Rule | Spec |
|---|---|
| Source | `Character.build(outfit)` (pure, `src/render/character.lua`) painted through an `Assets` painter into a 20x22 canvas, drawn with nearest filtering |
| Scale | The largest whole scale that fits the preview box, between `previewMinScale` (3) and `previewMaxScale` (desktop and landscape 7, phone 8). Never a fractional scale |
| Box | A paper inset (`Paper.draw` with `base = ui.wardrobe.previewBack`, no fibre), 6 px padding |
| Ground | A strip of `groundRows` art pixels under the feet, scaled with the figure: grass (`grass_1` sprite rows) in spring to autumn; flat snow (`ui.wardrobe.snowGround`) when the world's ground is white. The figure's own ground shadow ellipse stays (it is part of the sprite) |
| Day and night | The figure is never graded, like text and icons (D142): the point is to see the garment's colours. Night shows only through the paper lamp pool around the box. No day/night toggle |
| Season | Only the ground swatch follows the season. In the recovery variant the swatch is spring grass |
| Locked focus (S3) | The focused locked garment's pixels are drawn over the draft figure in the ink colour (`ui.wardrobe.silhouetteInk`), so the shape shows and the colours do not |
| Change | A preview change swaps the image at once. No animation (Reduce motion needs nothing special) |

### 4.3 Tile anatomy

```
+--------------------+   tileW 56 x tileH 70
|*                ooo|   * new dot (top left, 4x4 amber stamp)   ooo weight pips (top right)
|      +------+      |
|      | fig  |      |   thumbnail: the draft figure wearing this garment, 2x (40x44)
|      |  2x  |      |
|      +------+      |
|    Wool sweater    |   name, small, one line, clipped with "..." to the tile
|      [Today]       |   pill: "Today" or "Dawn" (never both on one tile)
+--------------------+
```

| Element | Owned | Locked |
|---|---|---|
| Plate | `Plate.draw` kind "button", like `Buttons:drawOne` | Same, `buttonDisabled` base |
| Thumbnail | The draft with this garment swapped in, 2x | The draft with this garment as an ink silhouette (only the garment's pixels), 2x |
| Name | Garment name | "???" |
| Weight pips | Filled pips: 1, 2 or 3 | Shown too (the class is not a secret; it says what to aim for) |
| Outline | Accent ink when it is the draft's choice for this slot (`selected`) | Never selected |
| Focus | A 1 px `colors.text` ring 2 px outside the plate | Same |
| New dot | Amber 4x4 stepped dot plus the calm amber glint (`Motion.signal("amber", ...)`) on the outline | n/a |

Weight is never colour alone: the pip count (1, 2, 3) carries it, the detail line spells it ("Light", "Mid", "Heavy"), and pips are drawn in one ink.

### 4.4 The meters

Two rows, each: label, a diverging bar, a signed number.

```
Day work    [........|######    ]  +4%
Night heat  [    ####|..........]  -6%
                     ^ centre tick (zero = Mid)        | worn tick when the draft differs
```

| Rule | Spec |
|---|---|
| What is shown | The draft's effect on that axis, as a fraction: `Wardrobe.effects(world, draft)` returns `{ work, cold }`. The meters never compute effects themselves |
| Zero | The centre tick. An all-Mid outfit shows no fill and "0%" |
| Full half-bar | The largest magnitude any outfit can reach on that axis, from `Wardrobe.scale(world)`: work = sum of slot weights x `light.work` (4%); heat = max of the full-light and full-heavy values (8%). So +4% work fills the right half; -8% heat fills the left half; +6% heat fills three quarters of the right half |
| Fill length | `round(abs(v) / scale * halfW)` px, at least 1 px when `v ~= 0`. Plus grows right of the tick, minus grows left |
| Benefit vs cost | Day work plus is a benefit. Night heat plus is a cost (more heat needed at night), Night heat minus a benefit. Benefit fill: solid cream (`ui.topChips.barOk`). Cost fill: amber (`colors.accent`) in a 1-in-2 checker dither. Shape differs as well as colour |
| Number | Signed percent: "+4%", "-8%", "0%". A whole number when it is one, else one decimal ("+0.5%"). Format in `WardrobeText.percent` |
| Worn tick | When the draft differs from the committed outfit, a 1 px `colors.text` line across the bar at the committed value. No extra text |
| Night heat out of season | Always the raw number. Summer has no warmth need (`needs.warmthCurve`), but the menu shows the garment's effect, not today's fuel. The trade-off is explained by play, not by a caveat |
| Size | Label column 62, bar 96 x 6, number column 34 (tuning) |

## 5. Copy

All interface strings live in `tuning.ui.wardrobe` (§6.5). Garment names and hints live in content (`game/data/content/garments.lua`), as Journal note hints do (`notes.hint`). Every string uses glyphs the pixel font has (`tests/test_pixel_font.lua` checks content and tuning).

### 5.1 Interface strings

| Key | Text | Where |
|---|---|---|
| `title` | Wardrobe | Left column title; Menu row; Controls name |
| `slots.head` .. `slots.extra` | Head, Torso, Legs, Feet, Extra | Tabs and the grid heading |
| `count` | %d of %d | Grid heading: owned of all in the slot |
| `close` | Close | Tab strip |
| `done` | Done | Tab strip, recovery variant |
| `wear` | Wear | Action |
| `reset` | Reset | Action |
| `save` | Save | Action, with a preset selected |
| `tagDawn` | Takes effect at dawn | Beside Wear |
| `tagNow` | Takes effect now | Beside Wear |
| `stateToday` | Wearing today | State line |
| `statePreview` | Preview | State line |
| `stateDawn` | From dawn | State line |
| `pillToday` | Today | Tile pill |
| `pillDawn` | Dawn | Tile pill |
| `locked` | ??? | Locked tile name |
| `weights.light`, `.mid`, `.heavy` | Light, Mid, Heavy | Detail line |
| `detail` | %s  %s | Detail line: name, weight |
| `meterWork` | Day work | Meter label |
| `meterHeat` | Night heat | Meter label |
| `presetWarm` | Warm | Preset chip (sun stamp) |
| `presetCold` | Cold | Preset chip (snowflake stamp) |
| `presetEmpty` | Empty | Unsaved preset chip |
| `presetEmptyHint` | Save an outfit here first | Detail line |
| `auto` | Auto | Toggle chip |
| `autoHint` | Wears Warm or Cold at dawn by the forecast | Detail line when Auto is focused or tapped |
| `toastUnlocked` | New clothes: %s | World toast |
| `toastDawn` | Laid out for dawn | World toast after Wear |
| `toastNow` | Changed clothes | World toast after Wear (now) |
| `toastAuto` | Auto: dressed for a %s night | Toast at dawn; %s is "warm" or "cold" |
| `toastAutoOff` | Auto is off: you chose an outfit | Toast when a manual Wear turns Auto off |
| `stamp` | New clothes | Decision stamp |
| `menuRow` | Wardrobe | Menu button |
| `recoveryButton` | Change clothes | Recovery scene |
| `recoveryRow` | New clothes this run (%d) | Recovery scene |
| Controls (`ControlsText.actions.wardrobe`) | Wardrobe / Open the wardrobe | Settings > Controls |

### 5.2 Garments and hints

Hints are an action, at most five words, no full stop (the `notes.hint` style). `%d` comes from the unlock's threshold in `tuning.wardrobe.unlocks`. Rows marked "new" have no unlock in PLAN_WARDROBE §4; they are proposals for the sim PR to confirm.

| Slot | Garment | Class | Family | Hint |
|---|---|---|---|---|
| Head | Bare head | Mid | Starter | none |
| Head | Straw hat | Light | Craft | Harvest %d kinds of crop |
| Head | Flat cap | Mid | Craft | Set up the truck charger |
| Head | Wool toque | Heavy | Seasons | Survive a winter |
| Head | Trapper hat | Heavy | Memories | Survive a cold snap |
| Torso | Tank top | Light | Seasons (new) | Live through %d summers |
| Torso | Linen shirt | Light | Seasons | Live through a summer |
| Torso | Flannel shirt | Mid | Starter | none |
| Torso | Denim jacket | Mid | Memories (new) | Take %d trips to town |
| Torso | Wool sweater | Heavy | Seasons | Survive %d winters |
| Torso | Oilskin coat | Heavy | Memories | Get rescued %d times |
| Torso | Down parka | Heavy | Seasons | Survive %d winters |
| Legs | Shorts | Light | Craft (new) | Harvest %d crops |
| Legs | Work pants | Mid | Starter | none |
| Legs | Overalls | Mid | Craft | Build the shack |
| Legs | Wool trousers | Heavy | Seasons (new) | Survive %d winters |
| Legs | Insulated bibs | Heavy | Memories (new) | Survive the Great Winter |
| Feet | Canvas shoes | Light | Craft | Catch %d kinds of fish |
| Feet | Work boots | Mid | Starter | none |
| Feet | Felt-lined boots | Heavy | Memories | Start run %d |
| Feet | Snow boots | Heavy | Seasons (new) | See %d snowy days |
| Extra | Bandana | Light | Memories | Get rescued once |
| Extra | None | Mid | Starter | none |
| Extra | Work gloves | Mid | Craft | Build %d machines |
| Extra | Scarf | Heavy | Memories (changed) | Live through a frost |
| Extra | Mittens | Heavy | Craft (new) | Fell %d trees |

Scarf changed: PLAN_WARDROBE ties it to "the radio neighbour", and the code has no radio (no match for `radio` in `game/src` or `game/data`). Insulated bibs reads `meta.established` (D117), which exists today.

## 6. Data and code design

### 6.1 New files

| File | Kind | Public functions |
|---|---|---|
| `game/data/content/garments.lua` | Content | `{ id, slot, class, name, hint?, starter?, default?, unlock = { kind, n? }, look = { ... } }`. `look` names the `Character` outfit fields this garment sets (for example `{ hat = "straw" }`, `{ top = "wool", sleeve = "wool" }`) |
| `game/data/tuning/wardrobe.lua` | Tuning | Sim numbers from PLAN_WARDROBE §4, `slots` order, `unlocks` thresholds |
| `game/src/sim/systems/wardrobe.lua` | Sim (PLAN_WARDROBE phase 3) | The accessors in §6.2 |
| `game/src/ui/focus_grid.lua` | UI, pure | `FocusGrid.new()`, `:set(items)` (each `{ id, zone, x, y, w, h }`), `:move(dir)` returns the new id, `:current()`, `:show(bool)`. Spatial nearest-in-direction within a zone, the zone table for edges |
| `game/src/ui/wardrobe_layout.lua` | UI, pure | `WardrobeLayout.rects(cfg, bookCfg, view, minTouch, tileCount)` returns `{ paper, strip, preview, ground, title, state, meters = {work, heat}, presets = {...}, grid, tiles = {...}, detail, tag, reset, wear, save, wide = bool }`; `WardrobeLayout.previewScale(cfg, box)`; `WardrobeLayout.columns(cfg, gridW)` |
| `game/src/ui/wardrobe_state.lua` | UI, pure | `WardrobeState.new(committed)`, `:preview(slot, id)`, `:reset()`, `:loadPreset(outfit, name)`, `:changed()`, `:draft()`, `WardrobeState.remember(state)` / `WardrobeState.last()` / `WardrobeState.reset()` (session memory, like `Books`) |
| `game/src/ui/wardrobe_text.lua` | UI, pure | `percent(v)`, `fill(v, scale, halfW)`, `stateLine(cfg, draft, committed, dressed)`, `tag(cfg, now)`, `pill(cfg, id, committed, dressed, slot)`, `hint(def, tuning)`, `detail(cfg, def, owned, tuning)` |
| `game/src/render/wardrobe_preview.lua` | Render | `Preview.figure(outfit)` returns a nearest-filtered 20x22 image, cached by outfit key; `Preview.silhouette(outfit, slot, id)`; `Preview.clear()`. Cache size from tuning |
| `game/src/scenes/wardrobe.lua` | Scene | `Wardrobe.new(world, opts)` with `opts = { variant = "play"|"recovery", onWorn = fn }`; `Wardrobe.open(app, opts)` (finds the homestead's toaster, like `Book.open`) |
| `tools/driver/scenarios/wardrobe.lua` | Driver | §7.2 |
| `tests/test_wardrobe_menu.lua` | Test | §7.1 |

### 6.2 What the scene reads from the sim

The scene reads only accessors of `src/sim/systems/wardrobe.lua`. It never indexes `world.meta.wardrobe` or `world.state.wardrobe`.

| Accessor | Returns |
|---|---|
| `Wardrobe.slots(world)` | `{ "head", "torso", "legs", "feet", "extra" }` from tuning |
| `Wardrobe.garments(world, slot)` | Garment defs for the slot, content order |
| `Wardrobe.owned(world, id)` | bool; true for everything in a sandbox |
| `Wardrobe.committed(world)` | `{ slot = id }`, the outfit chosen in meta (sanitised: unknown ids become the starter) |
| `Wardrobe.dressed(world)` | Today's outfit from the run snapshot; equals `committed` when there is no run |
| `Wardrobe.dressedKey(world)` | A string that changes whenever `dressed` does (the scene polls it) |
| `Wardrobe.appliesNow(world)` | true between runs (`world.state == nil`, the recovery `Run.metaWorld`) and in the run's opening window; false otherwise. The rule lives in the sim only |
| `Wardrobe.effects(world, outfit)` | `{ work, cold }` fractions, the same maths as `insulation` and `workBonus` |
| `Wardrobe.scale(world)` | `{ work, cold }` full half-bar values |
| `Wardrobe.isNew(world, id)`, `Wardrobe.newCount(world, slot?)` | New markers |
| `Wardrobe.stampDue(world)` | The decision stamp shows |
| `Wardrobe.earnedThisRun(world, run)` | ids, for the recovery row |
| `Wardrobe.preset(world, name)`, `Wardrobe.autoOn(world)` | Presets (step 4) |

### 6.3 How a change is routed

Scenes here mutate the sim by calling a system function directly: the Catalog calls `Market.order(world, id)`, the homestead calls `Ftue.dismiss(world, id)` and `Established.cardShown(meta)`, the recovery scene calls `Run.freeStudy(data, metaWorld, id)` and then `store:write(slot, data)`. There is no separate order queue for menu actions (the task board is for the homesteader's world jobs). The Wardrobe takes the same route.

| Player action | Call | Then |
|---|---|---|
| Wear | `Wardrobe.wear(world, draft)` returns `ok, reason`. It checks every id is owned and fits its slot, writes `meta.wardrobe.worn`, and when `appliesNow` also re-snapshots today and emits `wardrobe.dressed` | In play: the homestead's `wardrobe.dressed` listener calls `Assets.recomposite("homesteader", ...)` (PLAN_WARDROBE phase 2) and the scene raises the toast through the lent toaster. In recovery: `opts.onWorn()` runs `store:write(slot, data)`, as Learn does |
| Focus or tap a new tile | `Wardrobe.markSeen(world, id)` | Dot and tab dot go on next layout |
| Open the menu | `Wardrobe.stampSeen(world)` | The stamp goes; tile dots stay until seen |
| Save preset | `Wardrobe.savePreset(world, name, draft)` | |
| Toggle Auto | `Wardrobe.setAuto(world, bool)` | |

Guard: a new test in `tests/test_architecture.lua`, "only the wardrobe system touches meta.wardrobe", in the style of the `meta.ftue` test, over `scenes/wardrobe.lua`, `scenes/recovery.lua`, `scenes/homestead.lua`, `scenes/menu.lua`, the `ui/wardrobe_*.lua` files and every other system.

Saving: in play the session's autosave and focus-loss save cover meta (`Session:save`). The scene also calls `self.app.ctx.session:save()` on close when a Wear happened, so a quit right after cannot lose it.

### 6.4 Preview without touching the sim

| Step | Code |
|---|---|
| Outfit ids to a figure | `Character.outfitFor(registry, outfit)` (new, in `src/render/character.lua`): start from `Character.outfits.starter`, merge each garment's `look`. Pure |
| Figure to pixels | `Character.build(o)` (exists, pure) returns colours; it gains a second return, the part-id grid, so a garment's pixels can be found for the silhouette |
| Pixels to an image | `Assets.painter(ox, oy, w, h)` (new: makes the private `Painter` in `src/render/assets.lua` public), used inside a `love.graphics.setCanvas` on a small canvas, then `Character.paint(p, o, shadow)` |
| Cache | `wardrobe_preview.lua` keeps images by outfit key, at most `ui.wardrobe.previewCache` entries; cleared on close and on `d:resize` (sprites are rebuilt) |
| World sprite | Not touched by the menu. Only the `wardrobe.dressed` event leads to `Assets.recomposite` |

So the menu does not depend on the riskier atlas repaint. If `Assets.recomposite` slips, the menu still works and only the world figure lags.

### 6.5 Tuning keys (`tuning.ui.wardrobe`)

| Key | Start value | Unit and intent |
|---|---|---|
| `width` | 600 | UI px, widest paper |
| `margin` | 8 | UI px clear round the paper |
| `wideMin` | 560 | UI px; views at least this wide use two columns, narrower stack |
| `leftW` | 184 | UI px, left column on wide views |
| `colGap` | 12 | UI px between columns |
| `pad` | 8 | UI px inside the paper |
| `previewMinScale` | 3 | whole scale, smallest figure scale |
| `previewMaxScale` | 7 | whole scale, largest on wide views |
| `previewMaxScaleTall` | 8 | whole scale, largest on stacked (phone) views |
| `previewPad` | 6 | UI px inside the preview box |
| `previewBack` | `{ 0.16, 0.13, 0.10 }` | rgb, the preview inset paper |
| `groundRows` | 3 | art px of ground under the feet |
| `snowGround` | `{ 0.90, 0.93, 0.97 }` | rgb, the swatch when the ground is white |
| `silhouetteInk` | `{ 0.07, 0.08, 0.12 }` | rgb, locked garment shape (the world's outline ink) |
| `previewCache` | 24 | images kept (one per tile plus the figure) |
| `tileW`, `tileH` | 56, 70 | UI px, never below `input.minTouchTarget` |
| `tileGap` | 4 | UI px |
| `thumbScale` | 2 | whole scale of a tile's figure |
| `pipSize`, `pipGap` | 3, 1 | UI px, weight pips |
| `dotSize` | 4 | UI px, new dot |
| `focusGap` | 2 | UI px between a plate and its focus ring |
| `pillH` | 9 | UI px, Today / Dawn pill |
| `meterLabelW`, `meterW`, `meterH`, `meterNumW` | 62, 96, 6, 34 | UI px |
| `meterRowH` | 14 | UI px per meter row |
| `meterCostDither` | 2 | px period of the cost fill's checker |
| `presetW`, `presetH` | 56, 24 | UI px, preset chips |
| `actionH` | 26 | UI px, action buttons (raised to the touch target) |
| `wearW`, `resetW`, `saveW` | 72, 56, 56 | UI px on wide views; stacked views split the bar width |
| `recoveryStackWidth` | 420 | UI px; narrower recovery panels stack the two buttons |
| strings | §5.1 | copy |

The tab strip reads `tuning.ui.book` (`tabHeight`, `tabGap`, `tabPad`, `iconSize`, `iconGap`, `closeWidth`, `paper`, `tabIdle`, stamp inks) so it matches the Ledger exactly.

### 6.6 Changes to existing files

| File | Change |
|---|---|
| `game/src/scenes/menu.lua` | A "Wardrobe" row after Resume. Its geometry is hard-coded today (`w, h = 160, 184`, rows at +32..+140); move it to `tuning.ui.menu` (row height, gap, width) in the same PR |
| `game/src/scenes/homestead.lua` | `stampList()` gains `{ id = "wardrobe", icon = "icon_signal_clothes", label = cfg.stamp }` when `Wardrobe.stampDue(world)`; `action` handles `"wardrobe"`; `openWardrobe()`; listeners for `wardrobe.unlocked` (queued toast) and `wardrobe.dressed` (recomposite) |
| `game/src/scenes/recovery.lua` | "Change clothes" button beside Head out, the new-clothes row under the notes row (it shifts the blocks below, as `self.shift` already does), `Wardrobe.open(app, { variant = "recovery", onWorn = ... })` on `self.metaWorld` |
| `game/data/tuning/input.lua` | `c = "wardrobe"` in `keyActions`, `"wardrobe"` in `rebindable` |
| `game/src/ui/controls_text.lua` | `actions.wardrobe = { "Wardrobe", "Open the wardrobe" }` |
| `tests/test_key_bindings.lua` | The rebindable count goes from 13 to 14 |
| `game/src/render/assets.lua` | `Assets.painter(ox, oy, w, h)` |
| `game/src/render/character.lua` | `Character.outfitFor`, the part-id grid from `build` |
| `game/src/ui/plate.lua` | `Plate.snow()` getter for the ground swatch (the light table is private today) |
| `game/assets/manifest.lua`, `game/src/render/placeholders.lua` | `icon_signal_clothes` (round amber stamp with a shirt), `icon_slot_head`, `icon_slot_torso`, `icon_slot_legs`, `icon_slot_feet`, `icon_slot_extra` (one-ink tab stamps), `icon_preset_warm` (sun), `icon_preset_cold` (snowflake). All 12x12 on the D142 icon grid |
| `game/data/schemas.lua`, `game/data/content/init.lua` | The `garments` kind |
| `docs/ASSETS.md` | Actors heading says 16x20; it is 20x22 now. Add the new icons |

### 6.7 Conflicts with PLAN_WARDROBE.md, and the fix

| PLAN_WARDROBE says | The code or rules say | Fix |
|---|---|---|
| Look / Appearance tab, `meta.wardrobe.look`, layers fed by hair style and skin tone (§3, §5, §7, §8 phase 6) | Out of scope (customization only) | Drop the tab, the `look` field and phase 6's Look item. Hair and skin stay fixed in `Character.build` |
| Layers painted "in the same 16x24 box" (§3 Layers) | `Character.W = 20`, `Character.H = 22`; manifest `homesteader` is 20x22 | Say 20x22 |
| Phone "44 px minimum targets" (§5) | `input.minTouchTarget = 24` UI px; phone runs at scale 1 | Use `minTouchTarget` like every scene. Tiles are 56x70 anyway, well above both |
| "Arrows move across slots and tiles" (§5) | Arrows and WASD are pan keys and reserved (`input.panKeys`, `reservedKeys`); `Buttons` has no keyboard focus anywhere | New pure `src/ui/focus_grid.lua`; the scene uses raw `keypressed` and ignores key `pan` |
| Key `C` (§5) | Keys are actions in `tuning.input.keyActions`; the Controls test counts rebindables | Add a rebindable `wardrobe` action on `c` |
| "Change clothes button beside the new-garment list" (§5) | The recovery scene has no garment list | Add the "New clothes this run" row |
| Scarf: "hear the radio neighbour N times" (§4) | No radio exists | Scarf: live through a frost |
| Seven garments without an unlock (§4 table vs Unlocks) | n/a | The "new" rows in §5.2 |
| The wardrobe preview needs `Assets.recomposite` (§3, §8 phase 4 depends on 2) | `Character.build` is pure | The preview uses its own canvas; only the world figure needs `recomposite` |
| `meta.wardrobe.seen` (§7) | One flag cannot drive both a stamp that clears on open and dots that clear per tile | `fresh = { [id] = true }` for dots, `stamp = bool` for the stamp |
| Presets "Warm and Cold" (§5) | Ambiguous: clothes that are warm, or weather that is warm? | Keep the words, read with a sun and a snowflake stamp: the weather they are for. See §9 |

Proposed `meta.wardrobe` shape, all of it created in the sim PR so the menu PRs never touch `SAVE_COMPAT`:

```lua
meta.wardrobe = {
  owned = { [id] = true },
  fresh = { [id] = true },       -- earned, not yet looked at (tile dots)
  stamp = false,                 -- the "New clothes" stamp is due
  earned = { [id] = runNumber }, -- for the recovery row
  worn = { head, torso, legs, feet, extra },
  presets = { warm = nil, cold = nil },
  auto = false,
}
```

## 7. Test plan

### 7.1 Headless (`lovec tests wardrobe`)

| Test | File | Checks |
|---|---|---|
| Layout fits | `tests/test_wardrobe_menu.lua` | At 640x360, 390x844 and 844x390: every rect inside the paper, no two buttons overlap, every button at least `minTouchTarget`, preview scale whole and within limits, wide vs stacked switch at `wideMin`, a 7-tile slot fits without scrolling on all three, a 12-tile fixture scrolls on phone only |
| Tabs match the Ledger | same | `Books.layoutTabs` with five slot pages fits 374 px with labels |
| Focus graph | `tests/test_focus_grid.lua` | Zone order Z1 > Z2 > Z3 > Z4, no wrap, Up from the top tile row lands on that slot's tab, Down from the last row lands on Wear's zone, focus on a hidden (scrolled) tile reveals it |
| Draft model | `tests/test_wardrobe_menu.lua` | Preview sets one slot; Reset restores; a locked id never enters the draft; `changed()`; session memory restores the draft and `WardrobeState.reset()` forgets it |
| Meter maths | same | `fill` is 0 at 0, full half at `scale`, at least 1 px for any non-zero, symmetric; `percent` gives "+4%", "-8%", "+0.5%", "0%" |
| Meters agree with the sim | same | For all-light, all-mid, all-heavy and a mixed outfit, `Wardrobe.effects` equals what `Wardrobe.insulation` and `Wardrobe.workBonus` apply in a world wearing it |
| State line and pills | same | Every combination of draft, committed, dressed and `appliesNow` gives the expected line, tag and pills |
| Hints | same | Every non-starter garment has a hint, at most five words, with `%d` only when its unlock has `n` |
| Every garment paints | `tests/test_character.lua` (extend) | `Character.outfitFor` of every garment keeps the existing rules: fits, feet on one row, face kept, the red accent of at least 3 px |
| Silhouette | same | The part-id grid marks exactly the garment's pixels |
| Architecture | `tests/test_architecture.lua` | Only the wardrobe system touches `meta.wardrobe` |
| Keys | `tests/test_key_bindings.lua` | 14 rebindables, `wardrobe` named |
| Glyphs | `tests/test_pixel_font.lua` (no change) | New content and tuning strings have glyphs |
| Recovery route | `tests/test_run_loop.lua` (extend) | Wear on a `Run.metaWorld` applies now, survives `store:write`, and the next run's snapshot wears it |

### 7.2 Driver

Run only these while building: `lovec tools/driver wardrobe size=both`.

| Scenario | Shots (each at desktop, phone, landscape) |
|---|---|
| `wardrobe` | `01_open_head` (S1), `02_torso_preview_light` (S2, meters with worn tick), `03_locked_hint` (S3), `04_worn_dawn` (S4 pills and tag), `05_after_dawn` (S6, advanced to sunrise with the menu open), `06_winter_heavy` (snow ground, heavy outfit), `07_night` (lamp pool), `08_keyboard_focus` (C, arrows, Enter), `09_world_figure` (the homesteader on the land after dawn) |
| `wardrobe_unlock` | `01_toast`, `02_stamp`, `03_new_dot`, `04_recovery_row`, `05_recovery_wardrobe` (S9), `06_head_out_dressed` |
| `wardrobe_presets` (step 4) | `01_empty`, `02_saved_cold`, `03_load_cold`, `04_auto_toast` |
| `wardrobe_sandbox` | `01_all_owned` (S12) |

Driver hooks: tiles are buttons labelled by garment name ("Straw hat"; locked: "??? Straw hat" so scenarios can still find them), tabs by slot name, so `d:press` works. Unlocks in scenarios go through the sim's grant used by the Sandbox, never by writing meta.

## 8. Build order

These map onto PLAN_WARDROBE §8: steps A and B are its phase 4, step C its phase 5, step D its phase 6 (minus Look).

| Step | PR | Depends on | Parallel with | Done when |
|---|---|---|---|---|
| A | **Menu kit, pure**: `focus_grid`, `wardrobe_layout`, `wardrobe_state`, `wardrobe_text`, `Assets.painter`, `Character.outfitFor` and the part grid, the new icons, `tuning.ui.wardrobe`, tests in §7.1 that need no sim (with fixture garments) | PLAN phase 1 (done) | PLAN phase 2 and phase 3 | Tests pass headless; no scene yet; no save change |
| B | **The Wardrobe scene**: browse, preview, meters, Wear, Reset, dawn tag, Today and Dawn pills, live dawn refresh, Menu row (and `tuning.ui.menu`), `C` key, `wardrobe` driver scenario | A, PLAN phase 3 (accessors, `garments.lua`, `meta.wardrobe` shape), PLAN phase 2 for `09_world_figure` only | none | The core flow works by mouse, touch and keys at all three sizes; `wardrobe` shots reviewed |
| C | **Earning surfaces**: new dots, tab dots, the stamp, the unlock toast, locked silhouette on the preview, recovery row, Change clothes and the recovery variant, `wardrobe_unlock` and `wardrobe_sandbox` scenarios | B, PLAN phase 5 (unlock hooks) | D | Garments arrive by play and are found without reading anything |
| D | **Presets**: Warm and Cold chips, Save, Auto, the sim's dawn auto-switch and its toast, `wardrobe_presets` scenario | B | C | A whole outfit swaps in two taps; Auto switches at dawn by the forecast; a manual Wear turns it off |

A and PLAN phase 3 are the long poles and run side by side. C and D touch different parts of the scene and can run side by side after B (merge one, rebase the other).

## 9. Risks and open questions

| # | Risk or question | Recommendation |
|---|---|---|
| 1 | "Night heat +6%" may read as "6% warmer" | Keep the label, make the cost legible by shape: cost fill is dithered amber, benefit fill solid cream, and light tiles pair with a plus. Review `02` and `06` shots with someone new. If it still misreads, rename the tuning string to "Heat needed" (a one-line change) |
| 2 | Wear by day and nothing happens (dawn rule) feels broken | The tag sits beside Wear before the tap, the toast "Laid out for dawn" after, the "Dawn" pill stays on the tile and the state line says "From dawn". Keep the rule (PLAN_WARDROBE §9) |
| 3 | The "now" window on a fresh run | Let the sim own it in `Wardrobe.appliesNow`; start with "the first day of a run, before the first sunset", tuned in `tuning.wardrobe`. The menu only shows the tag it is given |
| 4 | Building up to 24 small canvases on open costs a frame on a phone | Build lazily, one per visible tile per frame, cache by outfit key, clear on close. Check with F3 and `lovec tools/driver perf`; it is 20x22 pixels each |
| 5 | Whole-figure thumbnails look alike for torso and legs (torso is 3 rows) | Accept it: the colour still reads at 2x, and the big preview resolves doubt. If a playtest says otherwise, crop each slot's thumbnail to its body band (a tuning table of rows per slot), no new art |
| 6 | Warm and Cold are ambiguous names | Keep them with sun and snowflake stamps (weather, not fabric). They match the Auto toggle's logic (the forecast). Do not use Light and Heavy, which are the weight classes |
| 7 | Auto at dawn fights a manual choice | A manual Wear turns Auto off, with the toast saying so. Auto only ever wears a saved preset, never edits one |
| 8 | Esc loses a careful draft | Keep the draft for the session (§3.3); no confirm dialog |
| 9 | Keyboard focus is new to the codebase | Build `focus_grid` generic and pure, use it only here now, and open a `found-during-dev` `ux` issue to adopt it in the books and Settings |
| 10 | The time keeps running under the menu, so a player may miss a night | Same as the books (consistent, and the game is idle by design). Do not pause |
| 11 | Showing locked weight classes spoils discovery | Show them. They tell the player what to work toward, and only the hint and silhouette are hidden |
| 12 | The menu needs the sim accessors before it can be built | Freeze the accessor names in §6.2 in the PLAN phase 3 PR description, so step A can use fixtures with the same shape |
| 13 | Save compat churn across four PRs | Create the whole `meta.wardrobe` shape (§6.7) in PLAN phase 3, bump `Save.SAVE_COMPAT` and the fingerprint once there; the menu PRs change no saved shape |
| 14 | Recovery has no world light or run | The recovery variant uses spring grass, daylight, and `appliesNow = true` from the sim; tested in `test_run_loop` |
| 15 | Menu's hard-coded geometry grows with every row | Move it to `tuning.ui.menu` in step B (small, contained) |
| 16 | `C` collides with a later feature | It is rebindable from day one (Settings > Controls) |
| 17 | Docs | On approval: GDD §9.4 (the Wardrobe as a paper page, its entries), §10 (keyboard focus), the decision log (check the next free number; D148 is the latest), `docs/ASSETS.md`, the wiki's Interface note; amend PLAN_WARDROBE.md per §6.7 |
