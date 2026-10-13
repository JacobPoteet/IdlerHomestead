-- Crop and small-sprite readability (#20, D102): a field with every growth stage, thirsty and ready
-- crops and planned tiles (bare and tilled), with a few ground sprites beside it, at zoom 1 and 2 in
-- day, night, rain and snow.
local Calendar = require("src.sim.systems.calendar")
local Grid = require("src.sim.grid")
local Weather = require("src.sim.systems.weather")

return function(d)
  d:newGame()
  local world = d:world()
  d:advance(4)
  for _ = 1, 3 do -- a find popup can open on any day: take the first card
    local top = d.game.app:top()
    if top.select and top.take then
      top:select(1)
      top:take()
    end
    d:frames(2, 0.05)
  end
  d:setSpeed(0) -- the plans below must stay plans while we shoot
  local scene, view = d:scene(), d.game.app.view
  local cam = scene.camera
  local grid = world.state.grid
  local tile = world.tuning.display.tileSize
  local dayLength = world.tuning.time.dayLength

  local tx, ty = Grid.coords(grid, world.state.land.truck)
  local function zoomTo(index)
    cam.zoomIndex = index
    cam:centerOn((tx + 2.5) * tile, (ty + 3) * tile, view)
    d:frames(2, 0.05)
  end
  local function sky(kind)
    local days = world.state.weather.sky.days
    for n = 1, 4 do
      days[n] = kind
    end
  end
  local function at(hour, frames)
    local now = Calendar.now(world)
    world.state.calendar.elapsed = world.state.calendar.elapsed + ((hour - now.hour) % 24) / 24 * dayLength
    d:frames(frames or 60, 0.05)
  end

  for anchor, obj in pairs(grid.objects) do
    local x, y = Grid.coords(grid, anchor)
    if world.registry:get("objects", obj.id).clearable ~= false and math.abs(x - tx) <= 10 and math.abs(y - ty) <= 8 then
      Grid.removeObject(world, anchor)
    end
  end
  for _, put in ipairs({ { "junk", -4, 1 }, { "rock", -2, 1 }, { "log", 0, 1 }, { "brush", 2, 1 }, { "junk", 4, 1 } }) do
    Grid.placeObject(world, put[1], tx + put[2], ty + put[3])
  end
  local fields = world.state.fields
  local function put(fx, fy, cropId, growth, moisture)
    local i = Grid.index(grid, tx + fx + 3, ty + fy)
    fields.tilled[i] = true
    world.state.crops[i] = { id = cropId, growth = growth, moisture = moisture }
  end
  local function plan(fx, fy, cropId, tilled)
    local i = Grid.index(grid, tx + fx + 3, ty + fy)
    fields.tilled[i] = tilled or nil
    fields.plan[i] = cropId
  end
  for row, id in ipairs({ "radish", "potato" }) do
    local fy = 3 + (row - 1) * 2
    put(-4, fy, id, 0.1, 1) -- stage 1, 2, 3 watered
    put(-3, fy, id, 0.6, 1)
    put(-2, fy, id, 1, 1)
    put(-1, fy, id, 0.1, 0) -- thirsty, stage 1 and 2
    put(0, fy, id, 0.6, 0)
    plan(1, fy, id, false) -- planned, bare ground
    plan(2, fy, id, true) -- planned, tilled
    plan(3, fy, id, false)
  end
  cam:centerOn((tx + 2.5) * tile, (ty + 3) * tile, view)

  local function round(tag, hour)
    at(hour, 90)
    for _, z in ipairs({ 1, 2 }) do
      zoomTo(z)
      d:shot(tag .. "_zoom" .. z)
    end
  end
  sky("clear")
  round("day", 12)
  round("night", 1)
  sky("rain")
  round("rain", 12)
  sky("clear")
  while not Weather.isFrozen(world) do
    world.state.calendar.elapsed = world.state.calendar.elapsed + dayLength
  end
  world.state.calendar.elapsed = world.state.calendar.elapsed + dayLength
  round("snow", 12)
end
