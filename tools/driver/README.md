# Screenshot driver

Plays the real game through scripted input and writes PNG screenshots, for visual smoke checks and
for docs. It needs a window and a GPU context (it renders for real), so it is not part of
`lovec tests`.

```
lovec tools/driver <scenario|all> [size=desktop|phone|landscape|both] [out=dir]
lovec tools/driver help=1            # lists scenarios
```

- `size`: `desktop` is 1280x720, `phone` is 390x844, `landscape` is 844x390 (phone on its side).
  Default (`both`) runs all three, so every scenario is also a phone-size run.
- `out`: output directory, which must already exist. Default `docs/screens`. Files are named
  `<scenario>_<size>_<NN>_<name>.png`.
- Exit code is non-zero if a scenario throws (a missing button, an assert, a game error).

Scenarios shipped: `overview` (title, slots, new game, homestead), `log` (D90: the message log with a coalesced line and the amber falling-health chip), `panels` (pantry, catalog,
journal, power, guide, town/truck), `clear` (order a clear and capture the progress ring), `stand` (roadside stand by the road, a day of sales with its toast, the object card), `weather` (clear, cloudy, rain and storm skies with the forecast pill), `finds` (the pick-1-of-3 modal, a card selected, the toast after taking it), `cat` (a mouse raid and its note, the cat arriving, napping in the sun, being petted), `routine` (routine on, asleep, resumed in the morning, the idle hint), `sleep` (fast sleep banner, the Skip night button, the morning after), `starter` (the routine planning, tilling and planting its starter field after a takeover), `standpin` (the Pantry "Stand/Truck" toggle and a pinned good surviving the stand's sale), `chickens` (a coop with hens roaming its run and the object card, eggs waiting in the nest box, a tap sending the homesteader to collect them, the Animals chapter of the journal), `storage` (a full firewood chip and pill, a tap refused with "Stone storage is full", a paid order held at the gate and its refund button in the Catalog), `machine` (the auto-harvester reach while placing it, working beside a grown field with its arm, ring and card, unpowered with a red reach and the card saying so, its node in the Machines chapter of the journal), `thresholds` (the routine panel with per-category conditions, then one condition edited with the stepper buttons), `spoilage` (the red spoilage chip when an old batch rots tonight, the Pantry with each food's shelf life and when its oldest batch spoils, the first-spoil explanation card, the next night's loss toast, the Pantry with surplus for sale under the automatic pantry), `threats` (a hail season and a coming locust swarm on the forecast pills with their warning toasts, then the storm's hail and its summary toast and note), `ftue` (the first-time tip cards: welcome, plant with a tile selected, queued water and food cards, routine and autumn, Skip tips, Menu > Tips with a replayed tip, Show all again).

Also `goats` (D71: a goat pen with goats browsing its yard and the object card, milk waiting in the pail, a tap sending the homesteader to milk with its toast, a cheese press loaded with milk, the animal-feed warning toast, the Animals chapter of the journal), and `uxbatch` (D70: the Pantry scrolled by drag and wheel, the amber and red chips with their warning toasts, the winter-readiness pill and card, the won't-ripen warning on a plan and on the tile card, the bedtime toast and the morning report card).

Also `clarity` (D72: the tap-to-explain chip cards and their shortcut, the Tools and More palettes on narrow views, the tool caption, the Journal unlock hint on a ??? idea and on a blank stamp, the truck panel charging and ready with the "ready" chip and toast).

Also `truckload` (D75: the Pantry keep list with Auto and a keep set by hand, the truck panel at home with an empty and a loaded truck, Load the truck before and after Auto-load, the reserve-guard confirmation when loading kept wood, and the town selling the load).

Also `smallbatch` (D76-D78: a long Power list scrolled by wheel and drag with a switch pressed while paused, the Plan button lit then plain after a plan, the town menu with game time paused and the drive home).

Also `place` (D79: the Untill tool and caption, a tilled tile turning back to grass, the placement preview and confirmation card over a tree and over a ripe crop with its warning, the queued order working and the finished building, a cancelled order).

Also `journal` (D81: the Journal overview grouped by area, a focused chapter, a node card beside the chapter on landscape, the filter, the Queue jump, and a 108-chapter journal scrolled by wheel and drag through the scene's test-only `chapterSource` hook).

Also `shelter` (D82: the camp preview with its heater slot, a stove placed beside it, the camp and shack object cards with insulation, rest and heater slot, and the night view).

Also `weatherworld` (D80: rain at three zooms, snow after a pan) and `shaderpass` (D83: cloud shadows with a pan pair proving they are world-anchored, a clear sky, rain with wet ground, puddles and creek rings, the ground drying, early frost on the creek bank, and a snowy yard with caps on the roofs). `shaderpass2` (D84: wind sway of crops, trees and brush as frame pairs in a breeze and a gale, morning mist at three zooms burning off by mid-morning and blown away on a windy day, and night lights from a campfire, lamp, wood stove and the shack window at dusk and at night).

Also `scroll` (D87: the Tools palette with 42 seeds scrolled by wheel and drag on narrow views, and the Catalog, Fish guide and town menu laid out for a short view so their lists clip and scroll; extra crops are cloned into the registry, and the short view is the open scene's own `resize`, because `d:resize` rebuilds the window and drops the sprites).

Also `shelf` (D73, D74: an out-of-date save planted in the in-memory store, listed as "can't be loaded", its Keep it / Delete save prompt and the second confirmation; then a Pantry with batches of different ages, "Oldest batch spoils in N days", no red chip while nothing rots, then the chip and the Pantry warning two nights later).

On narrow views some toolbar buttons live in the Tools or More palette: `d:pick(label)` presses a toolbar button wherever it is (it opens the palette when needed), `d:press` only sees what is on screen.

First-time tip cards (D69) are off in every scenario by default so they never cover a screenshot; `d:newGame({ tips = true })` starts the slot with them on.

## Safety and how it finds the game

- The game runs with an in-memory save backend (`Game.new({ backend = ... })`) and the driver has its
  own identity (`idlerhomestead-driver`), so your real saves are never read or written.
- LÖVE refuses to mount a folder outside the source, so `tools/driver/main.lua` adds `game/` to
  `package.path` and makes `love.filesystem.read/getInfo` and `love.graphics.newImage` fall back to
  reading `game/` with plain `io`. Nothing is copied. If the game starts reading other files through
  `love.filesystem` (for example audio), extend that shim in `main.lua`.

## Writing a scenario

Add `tools/driver/scenarios/<name>.lua`. It returns a function that gets a driver `d` (one fresh game
per window size):

```lua
return function(d)
  d:newGame()              -- Play > New > Start, leaves the homestead on top
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
| `d:pick(label)` | Press a toolbar button on the bar or inside the Tools / More palette (narrow views). |
| `d:click(vx, vy)`, `d:clickPixel(px, py)` | Click at a virtual or window position, through the real mouse handler. |
| `d:clickTile(tx, ty)` | Click a homestead tile, centring the camera on it if off screen. |
| `d:drag(x1, y1, x2, y2 [, steps])` | Swipe from one virtual position to another through the mouse handler (scrolls a list, never counts as a tap). |
| `d:wheel(notches, vx, vy)` | Turn the mouse wheel (positive = up) with the pointer at a virtual position. |
| `d:key(name)` | Press a key (`escape`, `space`, `r`, ...). |
| `d:resize(w, h)` | Change window size mid-scenario. |
| `d:shot(name)` | Capture the frame. |
| `d:world()`, `d:scene()`, `d:nearestObject(ids)`, `d:homesteaderTile()` | Read sim state to pick targets. |

Scenario code may read sim state (it is not part of `game/src/sim`), but should drive the game
through input rather than mutate it, so the screenshots show what a player could reach.

Also `money` (D88: the first-junk money card and the Catalog line when money is under the cheapest order); the `starter` scenario now also shoots the starter-field toast.
