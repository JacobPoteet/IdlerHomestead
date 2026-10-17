# Screenshot driver

Plays the real game through scripted input and writes PNG screenshots, for visual smoke checks and
for docs. It needs a window and a GPU context (it renders for real), so it is not part of
`lovec tests`.

```
lovec tools/driver <scenario|all> [size=desktop|phone|landscape|both] [out=dir] [seed=N] [jobs=N]
lovec tools/driver help=1            # lists scenarios
```

- `seed`: run seed for every scenario. By default each scenario gets a fixed seed (a hash of its
  name), so two runs play the same world and give the same outcomes (#188). `d:newGame({ seed = N })`
  overrides it for one game. Pick tiles with `d:freeTileNear(dx, dy)` or `d:nearestObject`, not
  fixed offsets from the homesteader, which may land on a building.

- `jobs`: how many (scenario, size) runs go at once, each in its own `lovec` child process; the output
  is printed in order and the exit code is still non-zero if any run failed. Default `min(4, CPUs)`;
  `jobs=1` plays everything in this process (use it to debug a scenario). A full `all size=both` takes
  about 3.5 minutes at the default, 9.5 on one process. `all` leaves out the frame-cost benchmarks
  `perf` and `wall` (no screenshots; they time the frame, so they always run alone): name them to run them.
  For a UI change, run the scenarios that touch it (`lovec tools/driver stand panels`), not `all`.
- `size`: `desktop` is 1280x720, `phone` is 390x844, `landscape` is 844x390 (phone on its side).
  Default (`both`) runs all three, so every scenario is also a phone-size run.
- `out`: output directory, which must already exist. Default `docs/screens`. Files are named
  `<scenario>_<size>_<NN>_<name>.png`.
- Exit code is non-zero if a scenario throws (a missing button, an assert, a game error).

Scenarios shipped: `overview` (title, slots, new game, homestead), `log` (D90: the message log with a coalesced line and the amber falling-health chip), `panels` (pantry, catalog,
journal, power, guide, town/truck), `clear` (order a clear and capture the progress ring), `stand` (roadside stand by the road, a day of sales with its toast, the object card), `weather` (clear, cloudy, rain and storm skies with the forecast pill), `finds` (the pick-1-of-3 modal, a card selected, the toast after taking it), `cat` (a mouse raid and its note, the cat arriving, napping in the sun, being petted), `routine` (routine on, asleep, resumed in the morning, the idle hint), `sleep` (fast sleep banner, the morning after), `starter` (the routine planning, tilling and planting its starter field after a takeover), `standpin` (the Pantry "Stand/Truck" toggle and a pinned good surviving the stand's sale), `chickens` (a coop with hens roaming its run and the object card, eggs waiting in the nest box, a tap sending the homesteader to collect them, the Animals chapter of the journal), `storage` (a full wood chip and pill, a tap refused with "Stone storage is full", a paid order held at the gate and its refund button in the Catalog), `machine` (the auto-harvester reach while placing it, working beside a grown field with its arm, ring and card, unpowered with a red reach and the card saying so, its node in the Machines chapter of the journal), `thresholds` (the routine panel with per-category conditions, then one condition edited with the stepper buttons), `spoilage` (the red spoilage chip when an old batch rots tonight, the Pantry with each food's shelf life and when its oldest batch spoils, the first-spoil explanation card, the next night's loss toast, the Pantry with surplus for sale under the automatic pantry), `threats` (a hail season and a coming locust swarm on the forecast pills with their warning toasts, then the storm's hail and its summary toast and note), `ftue` (the first-time tip cards: welcome, plant with a tile selected, queued water and food cards, routine and autumn, Skip tips, Menu > Tips with a replayed tip, Show all again).

Also `drinking` (D160: the drink chip on the bar full, low, thirsty and refilled by the routine, with its modal in each state).

Also `goats` (D71: a goat pen with goats browsing its yard and the object card, milk waiting in the pail, a tap sending the homesteader to milk with its toast, a cheese press loaded with milk, the animal-feed warning toast, the Animals chapter of the journal), and `uxbatch` (D70: the Pantry scrolled by drag and wheel, the amber and red chips with their warning toasts, the winter-readiness pill and card, the won't-ripen warning on a plan and on the tile card, the bedtime toast and the morning report card).

Also `clarity` (D72: the tap-to-explain chip cards and their shortcut, the Tools and More palettes on narrow views, the tool caption, the Journal unlock hint on a ??? idea and on a blank stamp, the truck panel charging and ready with the "ready" chip and toast).

Also `truckload` (D75: the Pantry keep list with Auto and a keep set by hand, the truck panel at home with an empty and a loaded truck, Load the truck before and after Auto-load, the reserve-guard confirmation when loading kept wood, and the town selling the load).

Also `wood` (D104: the wood chip in summer, late autumn and a cold winter, the winter-readiness card with the nightly burn and the nights carried, the Pantry wood row, a woodshed's object card with its dry store, and a cold night with no wood; the finals are copied to `docs/screens/wood-*`).

Also `smallbatch` (D76-D78: a long Power list scrolled by wheel and drag with a switch pressed while paused, the Plan button lit then plain after a plan, the town menu with game time paused and the drive home).

Also `effectspeed` (#265: the effect clock moves 1, 2 and 2 seconds per real second at 1x, 2x and 4x, with shots), `place` (D79: the Untill tool and caption, a tilled tile turning back to grass, the placement preview and confirmation card over a tree and over a ripe crop with its warning, the queued order working and the finished building, a cancelled order).

Also `journal` (D81: the Journal overview grouped by area, a focused chapter, a node card beside the chapter on landscape, the filter, the Queue jump, and a 108-chapter journal scrolled by wheel and drag through the scene's test-only `chapterSource` hook).

Also `shelter` (D82: the camp preview with its heater slot, a stove placed beside it, the camp and shack object cards with insulation, rest and heater slot, and the night view).

Also `purchase` (D114-D116: the roadside stand bare and with the sign, cooler and rack as visible tiers with its panel, the Catalog with Owned labels, and the item cards of an owned building, the sturdy rod, the shack, the big bucket and a repeatable coop) and `shack` (D115: the shack held, refused away from the camp, the ghost labelled "replaces camp" with the camp outlined, the confirm card, Cancel keeping the camp, Go ahead putting the shack over it).

Also `weatherworld` (D80: rain at three zooms, snow after a pan) and `shaderpass` (D83: cloud shadows with a pan pair proving they are world-anchored, a clear sky, rain with wet ground, puddles and creek rings, the ground drying, early frost on the creek bank, and a snowy yard with caps on the roofs). `shaderpass2` (D84: wind sway of crops, trees and brush as frame pairs in a breeze and a gale, morning mist at three zooms burning off by mid-morning and blown away on a windy day, and night lights from a campfire, lamp, wood stove and the shack window at dusk and at night).

Also `lightpolish` (D132, #283: leaf dapple under a tree as frame pairs at mid-morning and late afternoon, hens and goats with their shadows, the warm night light pools by the campfire, the autumn rim light at three views and at noon, and the optional depth of field on and off).

Also `dither` (D134: the campfire at night as frame pairs, the light pool in every dither pattern, afternoon shadows, and the F8 editor opened, driven through time, weather, freeze and compare, and closed).

Also `scroll` (D87: the Tools palette with 42 seeds scrolled by wheel and drag on narrow views, and the Catalog, Fish guide and town menu laid out for a short view so their lists clip and scroll; extra crops are cloned into the registry, and the short view is a real `d:resize` of the window, restored afterwards).

Also `shelf` (D73, D74: an out-of-date save planted in the in-memory store, listed as "can't be loaded", its Keep it / Delete save prompt and the second confirmation; then a Pantry with batches of different ages, "Oldest batch spoils in N days", no red chip while nothing rots, then the chip and the Pantry warning two nights later).

Also `wardrobe` (D154: the Wardrobe menu, its preview, locked hints, the dawn rule and keyboard focus), `wardrobe_unlock` (D155: the unlock toast, the New clothes stamp, the dot on a new tile and tab, the recovery scene's clothes row, the Wardrobe opened from recovery, and the next run dressed in the choice) and `wardrobe_sandbox` (D155: a Sandbox slot owns every garment, with no dots, stamp or toast), and `wardrobe_presets` (D156: the Warm and Cold chips empty, a cold outfit saved with Save then a chip, an outfit loaded whole from a chip, Auto switched on and a winter dawn on which it dresses the Cold preset with its toast, a manual Wear turning Auto off).

On narrow views some toolbar buttons live in the Tools or More palette: `d:pick(label)` presses a toolbar button wherever it is (it opens the palette when needed), `d:press` only sees what is on screen.

First-time tip cards (D69) are off in every scenario by default so they never cover a screenshot; `d:newGame({ tips = true })` starts the slot with them on.

## Safety and how it finds the game

- The game runs with an in-memory save backend (`Game.new({ backend = ... })`) and the driver has its
  own identity (`idlerhomestead-driver`), so your real saves are never read or written.
- LÖVE refuses to mount a folder outside the source, so `tools/driver/main.lua` adds `game/` to
  `package.path` and makes `love.filesystem.read/getInfo` and `love.graphics.newImage` fall back to
  reading `game/` with plain `io`. Nothing is copied. If the game starts reading other files through
  `love.filesystem`, extend that shim in `main.lua`. (#87: `love.audio.newSource` and
  `love.sound.newSoundData` are shimmed the same way; the shim stays because LÖVE 11.5 cannot mount a
  folder outside the source, and moving the entry point into `game/` would break `lovec game`.)
- Audio is silent by default: the game gets the recording null backend (`audioBackend`) and every play
  lands in `d.audioLog` (`{ what, volume, pitch, loop }`), so scenarios can assert on sound. Pass
  `audio=1` to hear it (real LÖVE audio, shimmed paths). Scenario `audio` shows the Settings sliders and
  the sound test.

## Writing a scenario

Add `tools/driver/scenarios/<name>.lua`. It returns a function that gets a driver `d` (one fresh game
per window size):

```lua
return function(d)
  d:newGame()              -- Play > New > Next > Normal (or Sandbox), leaves the homestead on top
  d:advance(3)             -- 3 in-game hours at the current speed
  d:press("Catalog")       -- press a button by label (errors and lists the labels if missing)
  d:shot("catalog")        -- writes <out>/<name>_<size>_01_catalog.png
  d:key("escape")          -- cancel / close
end
```

Helper API (`tools/driver/driver.lua`):

| Call | What it does |
| --- | --- |
| `d:newGame()` | Title to a started homestead. |
| `d:advance(hours)` | Run the update loop for that much game time (errors while paused). |
| `d:frames(n [, dt])` | Run n update frames. |
| `d:setSpeed(scale)` | Set game speed, 0 pauses. |
| `d:press(label)`, `d:tryPress(label)` | Click a button on the top scene by label (case-insensitive). |
| `d:labels()` | Labels on the top scene, handy while writing a scenario. |
| `d:pick(label)` | Press a HUD button, a tool, or a tab or button of the Notebook or Ledger (it opens the book that has it, D143). `d:scene()` returns the page showing in an open book; `d:book()` the book. |
| `d:click(vx, vy)`, `d:clickPixel(px, py)` | Click at a virtual or window position, through the real mouse handler. |
| `d:hold(vx, vy, seconds)` | Press, hold for scripted seconds, release (hold-to-repeat steppers). |
| `d:clickTile(tx, ty)` | Click a homestead tile, centring the camera on it if off screen. |
| `d:drag(x1, y1, x2, y2 [, steps])` | Swipe from one virtual position to another through the mouse handler (scrolls a list, never counts as a tap). |
| `d:wheel(notches, vx, vy)` | Turn the mouse wheel (positive = up) with the pointer at a virtual position. |
| `d:key(name)` | Press a key (`escape`, `space`, `r`, ...). |
| `d:text(str)` | Type text (the `textinput` event) into a focused text field. |
| `d:resize(w, h)` | Change window size mid-scenario (sprites are rebuilt, so they keep drawing). |
| `d:freeTileNear(dx, dy)` | A walkable, object-free tile nearest the homesteader offset by (dx, dy), for safe clicks. |
| `d:shot(name)` | Capture the frame. |
| `d:world()`, `d:scene()`, `d:nearestObject(ids)`, `d:homesteaderTile()` | Read sim state to pick targets. |

Scenario code may read sim state (it is not part of `game/src/sim`), but should drive the game
through input rather than mutate it, so the screenshots show what a player could reach.

Also `move` (D98: the object card with Pick up and Move, the move preview over a tree and its confirmation, the finished move, a refused pick up, a battery asking first) and `plan` (D92: a field planned with the Routine off is tilled and planted at once, tilled bare with no seeds, left by a far tap and finished on return) and `plantip` (a tip card holds game time: Paused button and badge).

Also `fixbatch` (D93: Pantry rows with clear buttons, a station's waiting output with its Discard button and confirm, the "Full" pill listing only blocking stores, the idle nudge held behind a panel with the pulsing Routine button).

Also `crops` (D102: a field with every growth stage, thirsty and ripe crops, bare and tilled plans and ground sprites at zoom 1 and 2 in day, night, rain and snow).

Also `perf` (D103: no screenshots; prints the CPU milliseconds of a busy frame, update and draw submit, at each zoom in clear weather and rain, from the F3 overlay's probes; compare `size=desktop|phone|landscape`).

Also `money` (D88: the first-junk money card and the Catalog line when money is under the cheapest order); the `starter` scenario now also shoots the starter-field toast.

Also `topbar` (D112, #267: the top-bar chips with their fill bars, level marks, trend arrows and weather glyphs in a mixed, a fine and a short state, and the short modal of every chip; finals are `docs/screens/topbar_*`).

Also `greatwinter` (D117, #277: the full, named forecast pill on the first day of autumn of the Great Winter's year, the winter itself, and the one-time Established card on the first thaw; finals are `docs/screens/greatwinter-*`).

Also `controls` (D121, #237: Settings > Controls, a rebind with "Press a key...", a reserved key, a conflict with Swap and Keep, per-row and global reset; finals are `docs/screens/controls-*`).

Also `sandbox` (D134: the Normal / Sandbox choice after naming a homestead, the SANDBOX tag in the slot list and on the homestead screen, the Catalog free with no Debug toggle, and a hungry, cold sandbox homesteader staying alive; `d:newGame({ sandbox = true })` starts a sandbox slot).

Also `wardrobe` (D154: the Wardrobe from the Menu row and the C key, a light torso previewed with its meters, a locked garment's hint and shape, a Wear that waits for dawn, the menu open through a dawn, a heavy outfit on snow, the night lamp pool, keyboard focus, and the homesteader in the world in the chosen clothes; finals are `docs/screens/wardrobe_*`).
