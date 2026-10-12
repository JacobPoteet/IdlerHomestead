-- Goats (GDD §7.7, D71): a goat pen near the truck with goats browsing its yard, the object card, milk
-- waiting in the pail (HUD chips and dots), a tap that sends the homesteader to milk with its toast, a
-- cheese press loaded with milk, a low-hay warning, and the Animals chapter of the journal. The
-- scenario places the pen and buys the goats directly (as if bought and hauled home on the trailer),
-- then plays through the real HUD and input.
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")

--- The free spot for `id` nearest (sx + dx, sy + dy), or nil.
local function spotNear(world, id, sx, sy, dx, dy)
  local grid = world.state.grid
  local best, bestDist
  for i = 1, #grid.terrain do
    local x, y = Grid.coords(grid, i)
    local dist = (x - sx - dx) ^ 2 + (y - sy - dy) ^ 2
    if (not bestDist or dist < bestDist) and Inventory.canPlace(world, id, i) then
      best, bestDist = i, dist
    end
  end
  return best
end

return function(d)
  d:newGame()
  local world = d:world()
  local grid = world.state.grid
  d:advance(1)

  local sx, sy = Grid.coords(grid, Land.spawn(world))
  local pen = spotNear(world, "goat_pen", sx, sy, 3, 0)
  assert(pen, "no spot for the pen")
  Inventory.addObject(world, "goat_pen")
  assert(Inventory.place(world, "goat_pen", pen))
  local px, py = Grid.coords(grid, pen)
  local press = spotNear(world, "cheese_press", px, py, 4, 1)
  assert(press, "no spot for the press")
  Inventory.addObject(world, "cheese_press")
  assert(Inventory.place(world, "cheese_press", press))
  local qx, qy = Grid.coords(grid, press)

  local scene = d:scene()
  local view = d.game.app.view
  local cx, cy = scene.camera:tileToWorld(px + 2, py + 1)
  scene.camera:centerOn(cx, cy, view)

  Ledger.add(world, "goat", 3, "driver")
  Ledger.add(world, "hay", 12, "driver")
  local g = world.state.animals.goats
  g.feed, g.water = 18, 6
  scene.selected = pen
  d:frames(3)
  d:shot("pen_card_goats")

  -- Milk piles up in the pail: white dots on the pen and the milk chip in the HUD.
  g.pail = 6
  scene.toast = nil
  d:frames(2)
  d:shot("milk_waiting")

  -- Tap the pen: the homesteader walks over, milks and fills the manger and trough.
  d:clickTile(px, py)
  local seconds = 0
  while g.pail > 0 and seconds < 60 do
    d:frames(20)
    seconds = seconds + 1
  end
  assert(g.pail == 0, "the milk was never collected")
  assert(Ledger.get(world, "milk") >= 6, "the milk did not reach the ledger")
  d:frames(2)
  d:shot("milked_toast")

  -- The cheese press: tap it and the homesteader loads the milk; the card shows the run.
  scene.selected = press
  d:clickTile(qx, qy)
  seconds = 0
  while not world.state.processing[press] and seconds < 60 do
    d:frames(20)
    seconds = seconds + 1
  end
  assert(world.state.processing[press], "the press was never loaded")
  scene.toast = nil
  scene.selected = press
  d:frames(3)
  d:shot("cheese_press")

  -- Low hay: the animal chip goes red and the warning toast says so.
  g.feed = 0
  Ledger.remove(world, "hay", Ledger.get(world, "hay"))
  scene.selected = pen
  scene.toast, scene.toastQueue = nil, {}
  local waited = 0
  while not scene.toast and waited < 20 do
    d:frames(30) -- the alert system looks once a second
    waited = waited + 1
  end
  assert(scene.toast, "no warning toast for the empty manger")
  d:shot("low_hay_warning")

  -- The Animals chapter of the Field Journal: the pen, goats and trailer appear once the notes are written.
  world.events:emit("animals.collected", { count = 1 })
  world.events:emit("weather.froze", {})
  world.events:emit("market.trip", {})
  world.events:emit("animals.milked", { count = 1 })
  scene.toast = nil
  d:press("Journal")
  d:frames(2)
  local journal = d:scene()
  journal:select("goat_pen") -- the node's card, scrolled into view
  local region = journal.map.nodes.goat_pen.region
  journal.offX, journal.offY = -region.x, -region.y
  journal:clampPan()
  journal:reveal("goat_pen")
  d:frames(3)
  d:shot("journal")
end
