# Screenshot driver

Plays the real game through scripted input and writes PNG screenshots, for visual smoke checks and
for docs. It needs a window and a GPU context (it renders for real), so it is not part of
`lovec tests`.

```
lovec tools/driver <scenario|all> [size=desktop|phone|both] [out=dir]
lovec tools/driver help=1            # lists scenarios
```

- `size`: `desktop` is 1280x720, `phone` is 390x844. Default runs both, so every scenario is also
  a phone-size run.
- `out`: output directory, which must already exist. Default `docs/screens`. Files are named
  `<scenario>_<size>_<NN>_<name>.png`.
- Exit code is non-zero if a scenario throws (a missing button, an assert, a game error).

Scenarios shipped: `overview` (title, slots, new game, homestead), `panels` (pantry, catalog,
journal, power, guide, town/truck), `clear` (order a clear and capture the progress ring).

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
