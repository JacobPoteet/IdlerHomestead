-- Water reflections (D130): objects standing on the creek bank are mirrored in the water, shoved sideways
-- by the ripples; the water also takes on the sky. Noon, dusk, the rain and a frozen creek.
local Calendar = require("src.sim.systems.calendar")
local Grid = require("src.sim.grid")

return function(d)
  d:newGame()
  local world = d:world()
  d:advance(2)
  for _ = 1, 3 do -- a find popup can open on any day: take the first card
    local top = d.game.app:top()
    if top.select and top.take then
      top:select(1)
      top:take()
    end
    d:frames(2, 0.05)
  end
  local scene, view = d:scene(), d.game.app.view
  local grid = world.state.grid
  local tile = world.tuning.display.tileSize
  -- Stand a few things on the bank: land with open water straight below it.
  local first, placed = nil, 0
  local kinds = { "tree", "rock", "log", "tree", "rock" }
  for i = 1, grid.w * grid.h do
    local x, y = Grid.coords(grid, i)
    if placed < #kinds and y > 1 and Grid.inBounds(grid, x, y + 1) then
      local above = Grid.index(grid, x, y)
      local below = Grid.index(grid, x, y + 1)
      if not Grid.terrain(world, above).water and Grid.terrain(world, below).water and not grid.objects[above] and (not first or math.abs(x - first[1]) <= 8 and math.abs(y - first[2]) <= 4) then
        if Grid.placeObject(world, kinds[placed + 1], x, y) then
          first = first or { x, y }
          placed = placed + 1
        end
      end
    end
  end
  assert(first, "no bank tile found")
  scene.camera.zoomIndex = 3
  scene.camera:centerOn((first[1] - 0.5) * tile, (first[2] + 1.5) * tile, view)
  scene.camera:clamp(view)
  local dayLength = world.tuning.time.dayLength
  local function at(hour)
    local now = Calendar.now(world)
    world.state.calendar.elapsed = world.state.calendar.elapsed + ((hour - now.hour) % 24) / 24 * dayLength
    d:frames(40, 0.05)
  end
  local days = world.state.weather.sky.days
  for n = 1, 4 do
    days[n] = "clear"
  end
  at(12)
  d:shot("noon")
  at(18)
  d:shot("dusk")
  for n = 1, 4 do
    days[n] = "rain"
  end
  at(12)
  d:shot("rain")
end
