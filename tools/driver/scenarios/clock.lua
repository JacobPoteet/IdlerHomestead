-- Effect clock (D97, #236): flames, clouds, wind and water stand still while the game is paused and run
-- on game speed otherwise. Two frames a real moment apart while paused must be byte-identical PNGs; at
-- 1x and 4x the same real moment shows different phases.
local Calendar = require("src.sim.systems.calendar")
local Grid = require("src.sim.grid")
local Ledger = require("src.sim.systems.ledger")

local function slurp(path)
  local f = assert(io.open(path, "rb"))
  local data = f:read("*a")
  f:close()
  return data
end

return function(d)
  d:newGame()
  local world = d:world()
  d:advance(4)
  local function dismissFinds()
    for _ = 1, 3 do
      local top = d.game.app:top()
      if top.select and top.take then
        top:select(1)
        top:take()
      end
      d:frames(2, 0.05)
    end
  end
  dismissFinds()
  local scene, view = d:scene(), d.game.app.view
  local cam = scene.camera
  local grid = world.state.grid
  local tile = world.tuning.display.tileSize
  local dayLength = world.tuning.time.dayLength
  local session = d.game.app.ctx.session

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

  local tx, ty = Grid.coords(grid, world.state.land.truck)
  for anchor, obj in pairs(grid.objects) do
    local x, y = Grid.coords(grid, anchor)
    if world.registry:get("objects", obj.id).clearable ~= false and math.abs(x - tx) <= 10 and math.abs(y - ty) <= 8 then
      Grid.removeObject(world, anchor)
    end
  end
  for _, put in ipairs({ { "shack", 3, -2 }, { "wood_stove", 7, -1 }, { "lamp", 2, 1 }, { "campfire", -2, 2 }, { "tree", -5, -2 }, { "tree", -6, 1 }, { "brush", -3, -2 }, { "brush", 6, 2 } }) do
    Grid.placeObject(world, put[1], tx + put[2], ty + put[3])
  end
  for fy = 4, 6 do
    for fx = -3, 2 do
      local i = Grid.index(grid, tx + fx, ty + fy)
      world.state.fields.tilled[i] = true
      world.state.crops[i] = { id = (fx + fy) % 2 == 0 and "radish" or "potato", growth = 0.5, moisture = 1 }
    end
  end
  world.state.power.charge[world.state.land.truck] = 50
  for _, id in ipairs({ "wood" }) do
    Ledger.add(world, id, 20, "scenario")
  end
  cam:centerOn((tx + 1.5 - 0.5) * tile, (ty + 1.5 - 0.5) * tile, view)
  cam.zoomIndex = 3
  cam:clamp(view)

  --- Let real-time UI (toasts) run out while paused, so only world effects can differ between frames.
  local function settle()
    d:frames(600, 0.05) -- also lets the weather look finish easing in (real time, converges)
  end

  --- Two frames `frames` x 50 ms apart; returns whether the PNGs are byte-identical.
  local function pair(name, frames)
    settle()
    dismissFinds()
    local a = d:shot(name .. "_a")
    d:frames(frames, 0.05)
    local b = d:shot(name .. "_b")
    return slurp(a) == slurp(b)
  end

  -- Night, windy: lit stove, campfire and lamp, swaying crops. Paused: nothing moves.
  local _, sunset = Calendar.daylight(world)
  sky("windy")
  session:setSpeed(1)
  at(sunset + 1, 60) -- still awake: asleep the sim runs 8x and both comparisons below would sit on the cap
  dismissFinds()
  d:tryPress("Start routine") -- the idle-nudge pulse on that button is a real-time UI pulse on purpose; settle it
  d:frames(10, 0.05)
  session:setSpeed(0)
  d:frames(4, 0.05)
  assert(pair("night_paused", 37), "paused night frames differ: an effect ignores the pause")

  -- The same real moment at 1x and at 4x, from the same starting phase.
  session:setSpeed(1)
  d:frames(20, 0.05)
  d:shot("night_1x")
  session:setSpeed(4)
  d:frames(20, 0.05)
  d:shot("night_4x")

  -- Day, cloudy and breezy: cloud shadows, sway and the creek, paused.
  sky("cloudy")
  session:setSpeed(1)
  at(12, 80)
  dismissFinds()
  session:setSpeed(0)
  d:frames(4, 0.05)
  assert(pair("day_paused", 37), "paused day frames differ: an effect ignores the pause")

  -- A tip card or a town trip holds game time through the same effectiveSpeed() = 0 (D78, D92), so it
  -- freezes the effects the same way (see the plantip scenario for the card itself).
end
