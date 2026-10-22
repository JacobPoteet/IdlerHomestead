-- Weather nights (C5, D190, #359): an autumn dusk with a cold front drawn (the dusk sign on the Tonight card and the
-- raised warmth need), then a winter dusk with the pipe freeze drawn, the freeze landing, and the solar pump's tile card
-- saying it is frozen. The clock and stocks are set through the sim (a scenario cannot wait for a season); the card, the
-- toasts and the tile card are the real ones. At desktop and phone sizes.
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Land = require("src.sim.systems.land")
local Needs = require("src.sim.systems.needs")
local NightThreats = require("src.sim.systems.nightthreats")
local Weather = require("src.sim.systems.weather")

local function jumpTo(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

--- A random find can pop up after a long jump of the clock: take it so the homestead is on top again.
local function dismissFinds(d)
  for _ = 1, 3 do
    if d:scene().name == "finds" then
      local first = d:scene().buttons.list[1]
      d:click(first.x + first.w / 2, first.y + first.h / 2)
      d:press("Take it")
      d:frames(3)
    end
  end
end

local function hasLine(lines, text)
  for _, l in ipairs(lines) do
    if l:find(text, 1, true) then
      return true
    end
  end
  return false
end

--- Place `id` on the free tile nearest the spawn.
local function placeNear(world, id)
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, Land.spawn(world))
  local best, bestDist
  for i = 1, #grid.terrain do
    local x, y = Grid.coords(grid, i)
    local dist = (x - sx - 2) ^ 2 + (y - sy) ^ 2
    if (not bestDist or dist < bestDist) and Inventory.canPlace(world, id, i) then
      best, bestDist = i, dist
    end
  end
  assert(best, "no spot for " .. id)
  Inventory.addObject(world, id)
  assert(Inventory.place(world, id, best))
  return best
end

return function(d)
  d:newGame()
  local world = d:world()
  local scene = d:scene()
  local DPS = world.tuning.time.daysPerSeason
  local cfg = world.tuning.weather
  -- Only the weather nights have a chance, and each is certain in its own season.
  for _, id in ipairs({ "raccoon", "deer", "bear" }) do
    world.tuning.raiders[id].chancePerDay = 0
  end
  world.tuning.cat.mice.chancePerDay = 0
  cfg.coldFront.chance.autumn = 8
  cfg.coldFront.chance.winter = 0
  cfg.pipeFreeze.chance = 8
  d:frames(6)

  -- 1. An autumn dusk: the cold front is drawn, the card says so and the warmth row shows the raised need.
  local before = Needs.warmthNeeded(world)
  local day = 2 * DPS + 4
  jumpTo(world, day, world.tuning.time.daylight.autumn[2] + 0.3)
  d:frames(30)
  dismissFinds(d)
  scene.toast, scene.toastQueue = nil, {}
  local sign = NightThreats.sign(world)
  assert(sign and sign.id == "cold_front", "the cold front is drawn at sunset")
  assert(Weather.frontTonight(world), "the front is on from dusk")
  assert(Needs.warmthNeeded(world) > before, "tonight's need is higher")
  if not scene.tonight.open then
    d:key("t")
  end
  d:frames(10)
  assert(scene.tonight.open, "the Tonight card is up")
  d:shot("front_sign")
  d:key("t")

  -- 2. A winter dusk with a solar pump and a cistern: the pipe freeze is drawn and lands.
  placeNear(world, "cistern")
  local pump = placeNear(world, "dc_pump")
  local winter = 3 * DPS + 3
  jumpTo(world, winter, world.tuning.time.daylight.winter[2] + 0.3)
  d:frames(30)
  dismissFinds(d)
  scene.toast, scene.toastQueue = nil, {}
  sign = NightThreats.sign(world)
  assert(sign and sign.id == "pipe_freeze", "the pipe freeze is drawn at sunset")
  if not scene.tonight.open then
    d:key("t")
  end
  d:frames(10)
  d:shot("pipe_sign")
  d:key("t")
  jumpTo(world, winter, cfg.pipeFreeze.hour + 0.2)
  d:frames(30)
  dismissFinds(d)
  assert(Weather.pipesFrozen(world), "the pipes froze")
  local grid = world.state.grid
  local px, py = Grid.coords(grid, pump)
  local cx, cy = scene.camera:tileToWorld(px + 1, py + 1)
  scene.camera:centerOn(cx, cy, d.game.app.view)
  scene.selected = pump
  d:frames(12)
  assert(hasLine(scene:tileInfo(pump), "Frozen"), "the pump's card says it is frozen")
  d:shot("pump_frozen")
  scene.selected = nil
end
