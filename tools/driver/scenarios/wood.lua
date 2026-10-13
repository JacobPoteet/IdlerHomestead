-- One wood (D104, #247): the wood chip with its nights, the winter-readiness card with the nightly
-- burn and the nights it carries, the Pantry's wood row, a woodshed's object card (the dry store that
-- raises the cap), and a cold night with too little wood. Stock and the clock are set through the sim
-- (a scenario cannot wait for a season); the screens, taps and cards are the real ones.
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Ledger = require("src.sim.systems.ledger")

--- Jump the sim clock to a day and hour (the calendar's day marker with it, so no day is announced).
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

--- Keep only the toasts that contain one of the plain patterns (staging for a screenshot).
local function keepOnly(scene, patterns)
  local function wanted(text)
    for _, p in ipairs(patterns) do
      if text:find(p, 1, true) then
        return true
      end
    end
    return false
  end
  local list = {}
  if scene.toast then
    list[#list + 1] = scene.toast.text
  end
  for _, text in ipairs(scene.toastQueue) do
    list[#list + 1] = text
  end
  scene.toast, scene.toastQueue = nil, {}
  for _, text in ipairs(list) do
    if wanted(text) then
      scene:queueToast(text)
    end
  end
end

return function(d)
  d:newGame()
  local world = d:world()
  local scene = d:scene()
  local DPS = world.tuning.time.daysPerSeason

  -- 1. Summer: no fire is needed, the chip is just the logs.
  jumpTo(world, DPS + 3, 10)
  world.state.ledger.amounts.wood = 22
  d:frames(60)
  dismissFinds(d)
  scene.toast, scene.toastQueue = nil, {}
  d:shot("chip_summer")

  -- 2. Late autumn: the chip counts nights, and the readiness pill opens the card with the burn.
  jumpTo(world, 3 * DPS - 1, 10)
  world.state.ledger.amounts.wood = 22
  world.state.ledger.amounts.canned_food = 8
  world.state.needs.condition = 90
  d:frames(60)
  dismissFinds(d)
  scene.toast, scene.toastQueue = nil, {}
  d:shot("chip_autumn")
  local hit = scene.readinessHit
  assert(hit, "the readiness pill is up in late autumn")
  d:click(hit.x + 20, hit.y + hit.h / 2)
  d:frames(3)
  d:shot("readiness_card")
  d:press("Got it")
  d:frames(3)

  -- 3. The Pantry: one wood row with its keep target, spare, and the nights left.
  d:press("Pantry")
  d:frames(3)
  d:shot("pantry_wood")
  d:key("escape")
  d:frames(3)

  -- 4. A woodshed raises the cap: its object card says how much, and the Pantry row shows the room.
  Inventory.addObject(world, "woodshed")
  local spot
  for _, off in ipairs({ { 3, 2 }, { 4, 3 }, { -4, 2 }, { 5, -2 }, { -5, -3 } }) do
    local x, y = d:freeTileNear(off[1], off[2])
    local i = Grid.index(world.state.grid, x, y)
    if Inventory.canPlace(world, "woodshed", i) then
      spot = i
      break
    end
  end
  assert(spot and Inventory.place(world, "woodshed", spot), "no spot for the woodshed")
  local tx, ty = Grid.coords(world.state.grid, spot)
  d:clickTile(tx, ty)
  d:frames(3)
  d:shot("woodshed_card")
  scene.selected = nil -- close the card (staging for the night shots)
  d:frames(2)

  -- 5. A cold winter night with two logs: the fire burns them, the rest is cold, health falls.
  jumpTo(world, 3 * DPS + 3, 22)
  world.state.ledger.amounts.wood = 2
  world.state.ledger.amounts.canned_food = 8
  world.state.needs.condition = 80
  d:frames(30)
  dismissFinds(d)
  scene.toast, scene.toastQueue = nil, {}
  d:shot("chip_winter_low")
  d:advance(4) -- across midnight
  dismissFinds(d)
  d:frames(5)
  assert(world.state.needs.condition < 80, "the cold night should cost health")
  d:shot("cold_night")
end
