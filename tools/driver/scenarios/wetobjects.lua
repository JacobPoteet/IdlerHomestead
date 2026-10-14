-- Wet objects and game-time drying (#218, D124): rain darkens the yard and crops, then it dries on game
-- time (same shot at 1x and 4x, paused holds), and frost over snow gets a visible ice-blue crust.
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

  local session = d.game.app.ctx.session
  for _ = 1, 3 do -- clear the first-run tip cards
    local top = d.game.app:top()
    if top.select and top.take then
      top:select(1)
      top:take()
    end
    d:frames(2, 0.05)
  end
  local fx = scene.renderer.fx
  local function wetness()
    return (select(2, fx:rainAndWet()))
  end

  look(objectTile)
  zoomTo(2)
  sky("clear")
  d:frames(40, 0.05)
  d:shot("dry_yard")

  sky("rain")
  d:frames(200, 0.05)
  d:shot("rain_yard")
  assert(wetness() > 0.99, "soaked")

  -- Paused: the rain has stopped but nothing dries while the game stands still.
  sky("clear")
  session:setSpeed(0)
  d:frames(120, 0.1)
  local held = wetness()
  d:frames(120, 0.1)
  assert(wetness() == held, "paused wetness holds")
  d:shot("wet_paused")
  session:setSpeed(1)

  -- Dry-out at 1x versus 4x over the same real time: 4x runs at the effect clock's 2x cap.
  local function dryFor(speed, frames)
    session:setSpeed(speed)
    local before = wetness()
    d:frames(frames, 0.1)
    return before - wetness()
  end
  local base = wetness()
  local drop1 = dryFor(1, 100)
  d:shot("drying_1x")
  -- Re-soak, then repeat at 4x.
  sky("rain")
  session:setSpeed(1)
  d:frames(200, 0.05)
  sky("clear")
  session:setSpeed(0)
  d:frames(5, 0.1)
  local drop4 = dryFor(4, 100)
  d:shot("drying_4x")
  print(string.format("wetness dropped %.2f in 10 real s at 1x (from %.2f), %.2f at 4x", drop1, base, drop4))
  assert(drop4 > drop1 * 1.5, "4x dries faster than 1x")
  assert(drop4 < drop1 * 2.5, "but at the capped 2x rate, not 4x")
  session:setSpeed(1)

  -- Frost over snow: noon on the first frozen day, then a day later with snow fully down.
  local dayLength = world.tuning.time.dayLength
  while not Weather.isFrozen(world) do
    world.state.calendar.elapsed = world.state.calendar.elapsed + dayLength
  end
  world.state.calendar.elapsed = world.state.calendar.elapsed + (0.55 - Calendar.now(world).timeOfDay) * dayLength
  d:frames(90, 0.05)
  world.state.calendar.elapsed = world.state.calendar.elapsed + dayLength
  d:frames(30, 0.05)
  for _ = 1, 6 do -- dismiss any find cards the days brought
    local top = d.game.app:top()
    if top.select and top.take then
      top:select(1)
      top:take()
    end
    d:frames(2, 0.05)
  end
  session:setSpeed(1)
  d:frames(10, 0.05)
  look(waterTile)
  zoomTo(3)
  d:shot("frost_snow_zoom3")
  zoomTo(2)
  d:shot("frost_snow_zoom2")
end
