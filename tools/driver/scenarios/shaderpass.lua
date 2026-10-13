-- Shader pass batch 1 (#193, D83): cloud shadows drifting over the land (a pan pair proves they are
-- anchored to the world), rain with wet ground, puddles and ripples on the creek, the ground drying,
-- then winter: snow on objects and frost creeping in from the creek bank.
local Calendar = require("src.sim.systems.calendar")
local Weather = require("src.sim.systems.weather")
local Grid = require("src.sim.grid")

return function(d)
  d:newGame()
  local world = d:world()
  d:advance(4)
  local scene, view = d:scene(), d.game.app.view
  local cam = scene.camera
  local grid = world.state.grid
  local tile = world.tuning.display.tileSize

  local function zoomTo(index)
    cam.zoomIndex = index
    cam:clamp(view)
    d:frames(2, 0.05)
  end

  -- The first water tile and the first object, to point the camera at.
  local waterTile
  for i = 1, grid.w * grid.h do
    local x, y = Grid.coords(grid, i)
    if not waterTile and Grid.terrain(world, i).water then
      waterTile = { x, y }
    end
  end
  -- Tidy the clutter round the truck and put a small yard there, so snow has roofs to land on.
  local tx, ty = Grid.coords(grid, world.state.land.truck)
  for anchor, obj in pairs(grid.objects) do
    local x, y = Grid.coords(grid, anchor)
    if world.registry:get("objects", obj.id).clearable ~= false and math.abs(x - tx) <= 9 and math.abs(y - ty) <= 7 then
      Grid.removeObject(world, anchor)
    end
  end
  for _, put in ipairs({ { "shack", 3, -2 }, { "camp", -4, -2 }, { "cistern", 3, 3 }, { "campfire", -1, 2 } }) do
    Grid.placeObject(world, put[1], tx + put[2], ty + put[3])
  end
  local objectTile = { tx + 1, ty }
  local function look(t)
    cam:centerOn((t[1] - 0.5) * tile, (t[2] - 0.5) * tile, view)
  end
  local function sky(kind)
    local days = world.state.weather.sky.days
    for n = 1, 4 do
      days[n] = kind
    end
  end

  -- Cloud shadows: an overcast morning, a pan pair at one zoom, then two more zooms.
  sky("cloudy")
  look(objectTile)
  d:frames(80, 0.05)
  zoomTo(2)
  d:shot("clouds_zoom2_a")
  cam:pan(-96, -40, view)
  d:frames(2, 0.05)
  d:shot("clouds_zoom2_b_panned")
  zoomTo(1)
  d:shot("clouds_zoom1")
  zoomTo(3)
  d:shot("clouds_zoom3")

  -- A clear day keeps a few passing shadows.
  sky("clear")
  d:frames(100, 0.05)
  zoomTo(2)
  d:shot("clear_zoom2")

  -- Rain: the ground darkens and puddles form, the creek fills with rings.
  sky("rain")
  d:frames(180, 0.05)
  assert(Weather.isRaining(world), "should be raining")
  look(waterTile)
  zoomTo(2)
  d:shot("rain_creek_zoom2")
  zoomTo(3)
  d:shot("rain_creek_zoom3")
  look(objectTile)
  zoomTo(2)
  d:shot("rain_yard_zoom2")
  zoomTo(1)
  d:shot("rain_yard_zoom1")

  -- The rain stops; the ground is still wet, then dries out.
  sky("clear")
  d:frames(120, 0.1)
  zoomTo(2)
  d:shot("drying_wet")
  d:frames(400, 0.1)
  d:shot("drying_dry")

  -- Winter: a day and a half into the frozen season, snow is fully down.
  local dayLength = world.tuning.time.dayLength
  while not Weather.isFrozen(world) do
    world.state.calendar.elapsed = world.state.calendar.elapsed + dayLength
  end
  -- Noon on the first frozen day: the creek has frozen and the frost has crept in over bare ground.
  world.state.calendar.elapsed = world.state.calendar.elapsed + (0.55 - Calendar.now(world).timeOfDay) * dayLength
  d:frames(90, 0.05)
  for _, label in ipairs({ "Rusty toolbox", "Old axe", "Take it" }) do
    d:tryPress(label)
    d:frames(1, 0.05)
  end
  look(waterTile)
  zoomTo(3)
  d:shot("frost_early_zoom3")
  zoomTo(2)
  d:shot("frost_early_zoom2")
  -- A day later the snow is fully down, with caps on the roofs.
  world.state.calendar.elapsed = world.state.calendar.elapsed + dayLength
  d:frames(30, 0.05)
  look(objectTile)
  zoomTo(3)
  d:shot("snow_objects_zoom3")
  zoomTo(2)
  d:shot("snow_objects_zoom2")
  look(waterTile)
  zoomTo(3)
  d:shot("frost_creek_zoom3")
  zoomTo(2)
  d:shot("frost_creek_zoom2")
end
