-- Small correctness bundle (D101): the winter-readiness card counting electric heat (#175), the
-- trip-ready arrow over the truck (#185). (The Stand cooler line, #164, is checked by a test.) Stock, clock and
-- buildings are set through the sim (a scenario cannot wait for a season); the screens are the real ones.
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Land = require("src.sim.systems.land")
local Power = require("src.sim.systems.power")

local function jumpTo(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

return function(d)
  d:newGame()
  local world = d:world()
  local scene = d:scene()
  d:advance(1)
  local DPS = world.tuning.time.daysPerSeason
  local truck = Land.truck(world)

  -- The truck with a trip's charge in it, nobody in town: the arrow bobs over the cab.
  Power.add(world, truck, world.tuning.economy.tripCost + 2)
  d:frames(30)
  d:shot("truck_ready")
  Power.drain(world, truck, Power.charge(world, truck))
  d:frames(3)
  d:shot("truck_not_ready")
  Power.add(world, truck, world.tuning.economy.tripCost + 2)

  -- Winter readiness with a powered heater: panel, battery and heater near the homesteader.
  local grid = world.state.grid
  local hx, hy = d:homesteaderTile()
  for _, id in ipairs({ "solar_array", "battery_bank", "electric_heater" }) do
    Inventory.addObject(world, id)
    local placed = false
    for r = 2, 12 do
      for y = hy - r, hy + r do
        for x = hx - r, hx + r do
          if not placed and Grid.inBounds(grid, x, y) and Inventory.canPlace(world, id, Grid.index(grid, x, y)) then
            assert(Inventory.place(world, id, Grid.index(grid, x, y)))
            placed = true
          end
        end
      end
    end
    assert(placed, "no spot for " .. id)
  end
  jumpTo(world, 2 * DPS + 1, 10)
  world.state.ledger.amounts.canned_food = 6
  world.state.ledger.amounts.wood = 16
  world.state.needs.condition = 90
  d:frames(60)
  for _ = 1, 3 do
    if d:scene().name == "finds" then
      local first = d:scene().buttons.list[1] -- pick the first offer, then take it
      d:click(first.x + first.w / 2, first.y + first.h / 2)
      d:press("Take it")
      d:frames(3)
    end
  end
  scene.toast, scene.toastQueue = nil, {}
  d:frames(3)
  love.graphics.origin()
  d.game:draw() -- (the pill's tap target is laid out while drawing)
  local hit = scene.readinessHit
  assert(hit, "the readiness pill is up in autumn")
  d:click(hit.x + 20, hit.y + hit.h / 2)
  d:frames(3)
  d:shot("readiness_electric")
  d:press("Got it")
  d:frames(3)
end
