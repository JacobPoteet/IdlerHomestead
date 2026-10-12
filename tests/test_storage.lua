-- Storage capacity: nothing the player paid for or produced may vanish when Ledger.add hits a
-- capacity limit (orders and batches wait; harvests wait; unavoidable losses are announced).
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Grid = require("src.sim.grid")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Inventory = require("src.sim.systems.inventory")
local Processing = require("src.sim.systems.processing")
local Fishing = require("src.sim.systems.fishing")
local Food = require("src.sim.systems.food")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate
local HOUR = tun.time.dayLength / 24

local function newWorld(seed)
  return World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
end

local function run(world, seconds)
  for _ = 1, math.floor(seconds / STEP) do
    world:tick(STEP)
  end
end

local function collect(world, name)
  local seen = {}
  world.events:on(name, function(e)
    seen[#seen + 1] = e
  end)
  return seen
end

local function onlyCategory(world, category)
  for _, e in ipairs(world.state.priorities) do
    e.enabled = e.category == category
  end
end

local function freeTileNearSpawn(world, objectId)
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, world.state.land.spawn)
  for r = 1, 8 do
    for y = sy - r, sy + r do
      for x = sx - r, sx + r do
        if Grid.inBounds(grid, x, y) then
          local i = Grid.index(grid, x, y)
          if Inventory.canPlace(world, objectId, i) then
            return i
          end
        end
      end
    end
  end
end

T.test("ledger: room, canHold and addOrOverflow", function()
  local world = newWorld()
  Ledger.setCapacity(world, "scrap", 5)
  Ledger.add(world, "scrap", 3)
  T.eq(Ledger.room(world, "scrap"), 2)
  T.truthy(Ledger.canHold(world, { scrap = 2 }))
  T.falsy(Ledger.canHold(world, { scrap = 3 }))
  local lost = collect(world, "ledger.overflow")
  local added, dropped = Ledger.addOrOverflow(world, "scrap", 4, "test")
  T.eq(added, 2)
  T.eq(dropped, 2)
  T.eq(#lost, 1)
  T.eq(lost[1].lost, 2)
  T.eq(lost[1].id, "scrap")
  Ledger.addOrOverflow(world, "scrap", 0, "test")
  T.eq(#lost, 1, "nothing lost, nothing announced")
end)

T.test("market: a paid order waits at the gate until storage has room", function()
  local world = newWorld(3)
  Ledger.add(world, "money", 50)
  T.truthy(Market.order(world, "radish_seeds"))
  local paid = Ledger.get(world, "money")
  local seeds = Ledger.get(world, "seed_radish")
  Ledger.setCapacity(world, "seed_radish", Ledger.get(world, "seed_radish") + 2) -- the order brings 5
  local held = collect(world, "market.held")
  local delivered = collect(world, "market.delivered")
  run(world, tun.time.dayLength * 2)
  T.eq(Ledger.get(world, "seed_radish"), seeds, "nothing partially delivered")
  T.eq(#world.state.market.orders, 1, "order still queued")
  T.eq(#delivered, 0)
  T.eq(#held, 1, "the player is told once")
  T.eq(Ledger.get(world, "money"), paid, "no refund and no second charge")
  Ledger.setCapacity(world, "seed_radish", nil)
  run(world, 1)
  T.eq(Ledger.get(world, "seed_radish"), seeds + 5)
  T.eq(#world.state.market.orders, 0)
  T.eq(#delivered, 1)
end)

T.test("market: pickup purchases need room now and charge nothing without it", function()
  local world = newWorld(3)
  Ledger.add(world, "money", 500)
  world.state.market.inTown = true
  Ledger.setCapacity(world, "seed_radish", Ledger.get(world, "seed_radish"))
  T.eq(Market.cannotBuy(world, "radish_seeds", true), "no room")
  local before = Ledger.get(world, "money")
  local ok, reason = Market.buyInTown(world, "radish_seeds")
  T.falsy(ok)
  T.eq(reason, "no room")
  T.eq(Ledger.get(world, "money"), before)
end)

T.test("processing: a finished batch waits in the station until the output fits", function()
  local world = newWorld(6)
  world.control = "idle"
  onlyCategory(world, "process")
  Inventory.addObject(world, "smoker")
  local tile = freeTileNearSpawn(world, "smoker")
  T.truthy(Inventory.place(world, "smoker", tile))
  Ledger.add(world, "creek_chub", 6)
  Ledger.add(world, "wood", 10)
  Food.sort(world)
  run(world, 30)
  local _, anchor = Grid.object(world, tile)
  local batch = Processing.batch(world, anchor)
  T.truthy(batch, "smoker loaded")
  local count = batch.count
  T.eq(count, 4)
  local blocked = collect(world, "processing.blocked")
  local done = collect(world, "processing.done")
  Ledger.setCapacity(world, "smoked_fish", 1)
  run(world, reg:get("recipes", "smoke_fish").hours * HOUR + 1)
  T.eq(Ledger.get(world, "smoked_fish"), 1, "what fits is delivered")
  batch = Processing.batch(world, anchor)
  T.truthy(batch, "the rest is still in the smoker")
  T.eq(batch.count, count - 1)
  T.eq(#blocked, 1, "blocked is announced once")
  T.eq(blocked[1].count, count - 1)
  T.eq(#done, 1)
  Ledger.setCapacity(world, "smoked_fish", nil)
  run(world, 1)
  T.eq(Ledger.get(world, "smoked_fish"), count, "nothing was lost")
  T.falsy(Processing.batch(world, anchor), "station is free again")
  T.eq(#done, 2)
end)

T.test("harvest: a mature crop stays in the ground while its produce has no room", function()
  local world = newWorld(5)
  world.control = "idle"
  onlyCategory(world, "harvest")
  local tile = freeTileNearSpawn(world, "smoker")
  world.state.crops[tile] = { id = "radish", growth = 1, moisture = 1 }
  local harvested = collect(world, "crop.harvested")
  Ledger.setCapacity(world, "radish", 0)
  run(world, 60)
  T.truthy(world.state.crops[tile], "not harvested into a full store")
  T.eq(Ledger.get(world, "radish"), 0)
  Ledger.setCapacity(world, "radish", nil)
  run(world, 300)
  T.eq(#harvested, 1, "harvested once there is room")
end)

T.test("fishing: a catch that can't be stored is announced, not silently dropped", function()
  local world = newWorld(2)
  Ledger.setCapacity(world, "creek_chub", 0)
  local lost = collect(world, "ledger.overflow")
  Fishing.land(world, "creek_chub", 12, "active")
  T.eq(#lost, 1)
  T.eq(lost[1].id, "creek_chub")
  T.eq(lost[1].lost, 1)
end)
