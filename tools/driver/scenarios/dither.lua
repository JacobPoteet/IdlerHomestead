-- Dithering experiments: the campfire at night (light pool falloff and heat-shimmer column) and the sun
-- shadows by day, as frame pairs so the shimmer is seen to move.
local Calendar = require("src.sim.systems.calendar")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")

return function(d)
  d:newGame()
  local world = d:world()
  local grid = world.state.grid
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
  local tile = world.tuning.display.tileSize
  local dayLength = world.tuning.time.dayLength
  local function at(hour)
    local now = Calendar.now(world)
    world.state.calendar.elapsed = world.state.calendar.elapsed + ((hour - now.hour) % 24) / 24 * dayLength
    d:frames(40, 0.05)
  end
  local function look(tx, ty, zoom)
    scene.camera.zoomIndex = zoom
    scene.camera:centerOn((tx - 0.5) * tile, (ty - 0.5) * tile, view)
    scene.camera:clamp(view)
    d:frames(2, 0.05)
  end
  local days = world.state.weather.sky.days
  for n = 1, #days do
    days[n] = "clear"
  end

  local sx, sy = Grid.coords(grid, Land.spawn(world))
  Ledger.add(world, "wood", 40, "driver")
  local fire
  for i = 1, #grid.terrain do
    local x, y = Grid.coords(grid, i)
    if Inventory.canPlace(world, "campfire", i) and (x - sx - 2) ^ 2 + (y - sy - 2) ^ 2 < 9 then
      fire = i
      break
    end
  end
  assert(fire, "no spot for the campfire")
  Inventory.addObject(world, "campfire")
  assert(Inventory.place(world, "campfire", fire))
  local fx, fy = Grid.coords(grid, fire)
  world.tuning.visuals.lights.heatNeedMin = 0 -- the fire burns whatever the weather

  at(22)
  for _, zoom in ipairs({ 3, 2 }) do
    look(fx, fy, zoom)
    d:shot(("fire_z%d_a"):format(zoom))
    d:frames(3, 0.05)
    d:shot(("fire_z%d_b"):format(zoom))
  end

  -- Sun shadows by day.
  at(16)
  look(sx, sy, 3)
  d:shot("shadows_afternoon")
end
