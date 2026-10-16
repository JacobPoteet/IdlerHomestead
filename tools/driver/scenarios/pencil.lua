-- Plans drawn in pencil (GDD §9.4, D142, #292): a planned field half worked by the routine (real crops
-- beside sketched ones), a second field only planned, a woodshed ghost and a queued order, at zoom 1, 2
-- and 3; then the same at night (the chalk pass), a late-autumn plan that cannot ripen (amber pencil),
-- and the plans on snow.
local Calendar = require("src.sim.systems.calendar")
local Weather = require("src.sim.systems.weather")
local Crops = require("src.sim.systems.crops")
local Inventory = require("src.sim.systems.inventory")
local Grid = require("src.sim.grid")

return function(d)
  d:newGame()
  local world = d:world()
  local scene, view = d:scene(), d.game.app.view
  local grid = world.state.grid
  local tile = world.tuning.display.tileSize
  local dayLength = world.tuning.time.dayLength
  local function at(frac)
    local step = frac - Calendar.now(world).timeOfDay
    if step < 0 then
      step = step + 1
    end
    world.state.calendar.elapsed = world.state.calendar.elapsed + step * dayLength
    d:frames(20, 0.05)
  end
  local function planBlock(x0, y0, w, h)
    local n = 0
    for y = y0, y0 + h - 1 do
      for x = x0, x0 + w - 1 do
        if Grid.inBounds(grid, x, y) then
          local i = Grid.index(grid, x, y)
          if not grid.objects[i] and not world.occupancy[i] and Crops.setPlan(world, i, "radish") then
            n = n + 1
          end
        end
      end
    end
    return n
  end
  local function zoomTo(index)
    scene.camera.zoomIndex = index
    scene.camera:clamp(view)
    d:frames(2, 0.05)
  end

  local fx, fy = d:freeTileNear(2, 2)
  assert(planBlock(fx, fy, 3, 3) > 4, "pencil: too few plannable tiles")
  d:key("r")
  d:advance(1.2)
  at(0.36)
  local px, py = d:freeTileNear(-3, 3)
  planBlock(px, py, 5, 3)
  scene.camera:centerOn((fx + 0.5) * tile, (fy + 1.5) * tile, view)
  Inventory.addObject(world, "woodshed", 1)
  local gx, gy = d:freeTileNear(-4, -1)
  scene.mode, scene.placing = "place", "woodshed"
  scene.hover = Grid.index(grid, gx, gy)
  for _, z in ipairs({ 2, 1, 3 }) do
    zoomTo(z)
    d:shot("day_zoom" .. z)
  end
  zoomTo(2)
  scene.mode, scene.placing, scene.hover = "act", nil, nil
  at(0.93)
  d:shot("night_chalk")

  -- Late autumn: a fresh plan whose radishes cannot ripen before the freeze is drawn in amber.
  while Calendar.now(world).season ~= "autumn" do
    world.state.calendar.elapsed = world.state.calendar.elapsed + dayLength
  end
  while Crops.frostRisk(world, "radish") == nil and not Weather.isFrozen(world) do
    world.state.calendar.elapsed = world.state.calendar.elapsed + dayLength
  end
  local ax, ay = d:freeTileNear(4, -3)
  planBlock(ax, ay, 3, 2)
  at(0.45)
  scene.camera:centerOn((ax + 0.5) * tile, (ay + 0.5) * tile, view)
  d:frames(2, 0.05)
  d:shot("autumn_amber")

  -- Snow: the plans on white ground.
  while not Weather.isFrozen(world) do
    world.state.calendar.elapsed = world.state.calendar.elapsed + dayLength
  end
  world.state.calendar.elapsed = world.state.calendar.elapsed + dayLength
  for _, label in ipairs({ "Rusty toolbox", "Old axe", "Take it" }) do
    d:tryPress(label)
    d:frames(1, 0.05)
  end
  at(0.5)
  scene.camera:centerOn((px + 2) * tile, (py + 1) * tile, view)
  d:frames(2, 0.05)
  d:shot("snow")
end
