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

Scenarios shipped: `overview` (title, slots, new game, homestead), `panels` (pantry, catalog,
journal, power, guide, town/truck), `clear` (order a clear and capture the progress ring), `stand` (roadside stand by the road, a day of sales with its toast, the object card), `weather` (clear, cloudy, rain and storm skies with the forecast pill), `finds` (the pick-1-of-3 modal, a card selected, the toast after taking it), `cat` (a mouse raid and its note, the cat arriving, napping in the sun, being petted), `routine` (routine on, asleep, resumed in the morning, the idle hint), `sleep` (fast sleep banner, the Skip night button, the morning after), `starter` (the routine planning, tilling and planting its starter field after a takeover), `standpin` (the Pantry "Stand/Truck" toggle and a pinned good surviving the stand's sale), `chickens` (a coop with hens roaming its run and the object card, eggs waiting in the nest box, a tap sending the homesteader to collect them, the Animals chapter of the journal), `storage` (a full firewood chip and pill, a tap refused with "Stone storage is full", a paid order held at the gate and its refund button in the Catalog), `machine` (the auto-harvester reach while placing it, working beside a grown field with its arm, ring and card, unpowered with a red reach and the card saying so, its node in the Machines chapter of the journal), `thresholds` (the routine panel with per-category conditions, then one condition edited with the stepper buttons), `spoilage` (the red spoilage chip, the Pantry with each food's rate, tonight's expected loss and a warning, the first-spoil explanation card, the next night's loss toast, the Pantry with surplus for sale under the automatic pantry), `threats` (a hail season and a coming locust swarm on the forecast pills with their warning toasts, then the storm's hail and its summary toast and note), `ftue` (the first-time tip cards: welcome, plant with a tile selected, queued water and food cards, routine and autumn, Skip tips, Menu > Tips with a replayed tip, Show all again).

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
| `d:click(vx, vy)`, `d:clickPixel(px, py)` | Click at a virtual or window position, through the real mouse handler. |
| `d:clickTile(tx, ty)` | Click a homestead tile, centring the camera on it if off screen. |
| `d:key(name)` | Press a key (`escape`, `space`, `r`, ...). |
| `d:resize(w, h)` | Change window size mid-scenario. |
| `d:shot(name)` | Capture the frame. |
| `d:world()`, `d:scene()`, `d:nearestObject(ids)`, `d:homesteaderTile()` | Read sim state to pick targets. |

Scenario code may read sim state (it is not part of `game/src/sim`), but should drive the game
through input rather than mutate it, so the screenshots show what a player could reach.
