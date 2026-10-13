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


-- Hold, don't destroy (D59, D60): work waits for room, orders can be refunded, nothing vanishes. ----

local Clearing = require("src.sim.systems.clearing")
local Actors = require("src.sim.systems.actors")
local Tasks = require("src.sim.systems.tasks")
local serialize = require("src.core.serialize")

local function waterTile(world)
  for i = 1, #world.state.grid.terrain do
    if Grid.terrain(world, i).water then
      return i
    end
  end
end

-- A rock the homesteader can walk up to (sorted, so the pick is stable).
local function rockTile(world)
  local anchors = {}
  for anchor, obj in pairs(world.state.grid.objects) do
    if obj.id == "rock" then
      anchors[#anchors + 1] = anchor
    end
  end
  table.sort(anchors)
  for _, anchor in ipairs(anchors) do
    if Tasks.jobForOrder(world, Actors.homesteader(world), anchor, {}) then
      return anchor
    end
  end
end

-- Counts everything the ledger reports as discarded from now on.
local function lostCounter(world)
  local lost = 0
  world.events:on("ledger.overflow", function(e)
    lost = lost + e.lost
  end)
  return function()
    return lost
  end
end

T.test("clearing: holds back when the yield would not fit, and loses nothing", function()
  local world = newWorld(4)
  world.control = "idle"
  onlyCategory(world, "clear")
  local lost = lostCounter(world)
  Ledger.setCapacity(world, "wood", Ledger.get(world, "wood") + 5) -- a tree yields up to 9
  local def = reg:get("objects", "tree")
  T.eq(Ledger.shortfall(world, Clearing.mostYield(def)), "wood", "a tree would not fit")
  local cleared = collect(world, "object.cleared")
  run(world, 400)
  T.eq(lost(), 0, "nothing was discarded")
  for _, e in ipairs(cleared) do
    T.truthy(e.object ~= "tree" and e.object ~= "log", "no wood-heavy object cleared into a full store")
  end
  T.truthy(Ledger.get(world, "wood") <= Ledger.capacity(world, "wood"))
end)

T.test("clearing: a tap with a full store is refused and names the store", function()
  local world = newWorld(4)
  local tile = rockTile(world)
  T.truthy(tile, "the start has a rock")
  Ledger.setCapacity(world, "stone", Ledger.get(world, "stone") + 2) -- a rock yields up to 3
  local hs = Actors.homesteader(world)
  local taskType, full = Actors.order(world, hs, tile, {})
  T.falsy(taskType)
  T.eq(full, "stone")
  Ledger.setCapacity(world, "stone", nil)
  taskType, full = Actors.order(world, hs, tile, {})
  T.truthy(taskType)
  T.eq(taskType.id, "clear")
  T.eq(full, nil)
end)

T.test("clearing: a job drops if the store fills mid-job and the object stays", function()
  local world = newWorld(4)
  local tile = rockTile(world)
  T.truthy(Actors.order(world, Actors.homesteader(world), tile, {}))
  Ledger.setCapacity(world, "stone", Ledger.get(world, "stone")) -- fills while the job runs
  local lost = lostCounter(world)
  run(world, 60)
  T.truthy(Grid.object(world, tile), "the rock is still there")
  T.eq(lost(), 0)
end)

T.test("harvest: a refused tap names the full store", function()
  local world = newWorld(5)
  local tile = freeTileNearSpawn(world, "smoker")
  world.state.crops[tile] = { id = "radish", growth = 1, moisture = 1 }
  Ledger.setCapacity(world, "radish", 0)
  local taskType, full = Actors.order(world, Actors.homesteader(world), tile, {})
  T.falsy(taskType)
  T.eq(full, "radish")
end)

T.test("fishing: no cast while every biting fish has a full store", function()
  local world = newWorld(2)
  Inventory.addEquipment(world, "basic_rod")
  local biting = Fishing.available(world, false)
  T.truthy(#biting > 0, "something bites at the start")
  T.truthy(Fishing.canStore(world, "active"))
  for _, fish in ipairs(biting) do
    Ledger.setCapacity(world, fish.id, 0)
  end
  local ok, full = Fishing.canStore(world, "active")
  T.falsy(ok)
  T.truthy(full)
  local fish, why = Fishing.rollFish(world, "active")
  T.eq(fish, nil)
  T.eq(why, "full")
  local task, hs, water = Tasks.get(world, "fish"), Actors.homesteader(world), waterTile(world)
  T.falsy(task.canDo(world, hs, water, { tool = "rod" }))
  T.eq(task.blocked(world, hs, water, { tool = "rod" }), full)
  T.eq(task.blocked(world, hs, water, {}), nil, "only a rod in hand is refused")
end)

T.test("fishing: a full species is never rolled while another has room", function()
  local world = newWorld(2)
  local biting = Fishing.available(world, false)
  T.truthy(#biting >= 2, "two species bite at the start")
  Ledger.setCapacity(world, biting[1].id, 0)
  for _ = 1, 40 do
    local fish = Fishing.rollFish(world, "active")
    T.truthy(fish and fish.id ~= biting[1].id)
  end
end)

T.test("fishing: a catch whose store fills on the line gets away, unclaimed", function()
  local world = newWorld(2)
  Ledger.setCapacity(world, "creek_chub", 0)
  local caught = collect(world, "fish.caught")
  local lost = collect(world, "fish.lost")
  local overflow = collect(world, "ledger.overflow")
  T.falsy(Fishing.land(world, "creek_chub", 12, "idle"))
  T.eq(#caught, 0, "never announced as caught")
  T.eq(#lost, 1)
  T.eq(lost[1].reason, "full")
  T.eq(#overflow, 0)
  T.eq((world.meta.fishGuide or {}).creek_chub, nil, "not in the fish guide")
end)

T.test("fishing: the idle routine never casts into full stores", function()
  local world = newWorld(2)
  world.control = "idle"
  onlyCategory(world, "fish")
  Inventory.addEquipment(world, "basic_rod")
  for _, fish in ipairs(world.registry:all("fish")) do
    Ledger.setCapacity(world, fish.id, 0)
  end
  local done = collect(world, "task.completed")
  run(world, 600)
  for _, e in ipairs(done) do
    T.truthy(e.task ~= "fish", "no fishing job completed")
  end
end)

T.test("ledger: isFull and shortfall", function()
  local world = newWorld()
  T.falsy(Ledger.isFull(world, "wood"), "unlimited is never full")
  T.falsy(Ledger.isFull(world, "water"), "capacity 0 is no store, not a full one")
  Ledger.setCapacity(world, "scrap", 2)
  Ledger.add(world, "scrap", 2)
  T.truthy(Ledger.isFull(world, "scrap"))
  T.eq(Ledger.shortfall(world, { scrap = 1, wood = 5 }), "scrap")
  T.eq(Ledger.shortfall(world, { wood = 5 }), nil)
end)

T.test("market: an order that can never fit is refused up front, and refunded if it got through", function()
  local world = newWorld(3)
  Ledger.add(world, "money", 100)
  Ledger.setCapacity(world, "seed_radish", 3) -- the order brings 5
  T.truthy(Market.neverFits(world, "radish_seeds"))
  T.eq(Market.cannotBuy(world, "radish_seeds", false), "too big for storage")
  -- An order placed before the store shrank is refunded when it falls due.
  Ledger.setCapacity(world, "seed_radish", nil)
  T.truthy(Market.order(world, "radish_seeds"))
  local money = Ledger.get(world, "money")
  local paid = world.state.market.orders[1].paid
  T.truthy(paid and paid > 0)
  Ledger.setCapacity(world, "seed_radish", 3)
  local refunded = collect(world, "market.refunded")
  run(world, tun.time.dayLength * 2)
  T.eq(#world.state.market.orders, 0)
  T.eq(#refunded, 1)
  T.eq(refunded[1].amount, paid)
  T.eq(Ledger.get(world, "money"), money + paid)
end)

T.test("market: a held order can be cancelled for a full refund", function()
  local world = newWorld(3)
  Ledger.add(world, "money", 50)
  T.truthy(Market.order(world, "radish_seeds"))
  local paid = world.state.market.orders[1].paid
  local afterPaying = Ledger.get(world, "money")
  T.eq(Market.cancelHeld(world, 1), nil, "not held yet, so it cannot be cancelled")
  Ledger.setCapacity(world, "seed_radish", Ledger.get(world, "seed_radish") + 2)
  run(world, tun.time.dayLength * 2)
  local held = Market.heldOrders(world)
  T.eq(#held, 1)
  T.eq(held[1].paid, paid)
  local cancelled = collect(world, "market.cancelled")
  T.eq(Market.cancelHeld(world, held[1].index), paid)
  T.eq(Ledger.get(world, "money"), afterPaying + paid)
  T.eq(#world.state.market.orders, 0)
  T.eq(#cancelled, 1)
  T.eq(#Market.heldOrders(world), 0)
end)

T.test("market: held and paid state survives a save round-trip", function()
  local world = newWorld(3)
  Ledger.add(world, "money", 50)
  Market.order(world, "radish_seeds")
  Ledger.setCapacity(world, "seed_radish", Ledger.get(world, "seed_radish") + 2)
  run(world, tun.time.dayLength * 2)
  T.eq(#Market.heldOrders(world), 1)
  local restored = World.new({ registry = reg, tuning = tun }, serialize.decode(serialize.encode(world.state)))
  T.eq(#Market.heldOrders(restored), 1)
  local money = Ledger.get(restored, "money")
  local expected = restored.state.market.orders[1].paid
  T.eq(Market.cancelHeld(restored, 1), expected)
  T.eq(Ledger.get(restored, "money"), money + expected)
end)

T.test("processing: blockedBatches lists what waits in a station", function()
  local world = newWorld(6)
  world.control = "idle"
  onlyCategory(world, "process")
  Inventory.addObject(world, "smoker")
  local tile = freeTileNearSpawn(world, "smoker")
  T.truthy(Inventory.place(world, "smoker", tile))
  Ledger.add(world, "creek_chub", 6)
  Ledger.add(world, "wood", 10)
  run(world, 30)
  T.eq(#Processing.blockedBatches(world), 0)
  Ledger.setCapacity(world, "smoked_fish", 0)
  run(world, reg:get("recipes", "smoke_fish").hours * HOUR + 1)
  local list = Processing.blockedBatches(world)
  T.eq(#list, 1)
  T.eq(list[1].output, "smoked_fish")
  T.eq(list[1].count, 4)
end)

T.test("storage: a run with tight stores is deterministic and the idle routine discards nothing", function()
  local function play()
    local world = newWorld(9)
    world.control = "idle"
    Ledger.setCapacity(world, "wood", 12)
    Ledger.setCapacity(world, "stone", 6)
    local lost = lostCounter(world)
    run(world, tun.time.dayLength * 3)
    return Ledger.get(world, "wood"), Ledger.get(world, "stone"), world.state.tick, lost()
  end
  local w1, s1, t1, l1 = play()
  local w2, s2, t2, l2 = play()
  T.eq(w1, w2)
  T.eq(s1, s2)
  T.eq(t1, t2)
  T.eq(l1, 0, "no overflow with idle clearing")
  T.eq(l2, 0)
  T.truthy(w1 <= 12 and s1 <= 6)
end)
