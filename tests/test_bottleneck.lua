-- What is limiting the homestead (D202, #377): the ladder water, labour, storage, power, market, asked in that order,
-- each test reading its own system's figures; and the Progress panel's words for it.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Bottleneck = require("src.sim.systems.bottleneck")
local Calendar = require("src.sim.systems.calendar")
local Crops = require("src.sim.systems.crops")
local Grid = require("src.sim.grid")
local GoalText = require("src.ui.goal_text")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Weather = require("src.sim.systems.weather")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local cfg = tun.progress.bottleneck

-- A fresh world under a clear sky, with the stores that a new run starts with emptied of produce.
local function newWorld(seed)
  local world = World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
  Weather.force(world, "clear")
  for _, res in ipairs(reg:all("resources")) do
    if res.category ~= "currency" then
      Ledger.remove(world, res.id, Ledger.get(world, res.id))
    end
  end
  return world
end

-- `n` free tillable tiles, tilled, in tile order.
local function field(world, n)
  local tiles = {}
  for i = 1, #world.state.grid.terrain do
    if #tiles >= n then
      break
    end
    if Grid.terrain(world, i).tillable and not world.occupancy[i] and not Crops.hasCropAt(world, i) then
      world.state.fields.tilled[i] = true
      tiles[#tiles + 1] = i
    end
  end
  T.eq(#tiles, n, "room for the field")
  return tiles
end

-- The first `n` of a list.
local function first(list, n)
  local out = {}
  for k = 1, n do
    out[k] = list[k]
  end
  return out
end

-- Plant radishes on the tiles: `moisture` 0 is dry, `growth` 1 is ripe.
local function plant(world, tiles, moisture, growth)
  for _, i in ipairs(tiles) do
    local crop = Crops.newCrop(world, reg:get("crops", "radish"))
    crop.moisture, crop.growth = moisture, growth or 0.2
    world.state.crops[i] = crop
  end
end

T.test("bottleneck: a new homestead has nothing holding it back", function()
  local world = newWorld(1)
  T.eq(Bottleneck.current(world), nil)
  T.eq(#Bottleneck.all(world), 0)
end)

T.test("bottleneck: water is the limit when enough of the growing crops are dry, but not while it rains", function()
  local world = newWorld(2)
  local tiles = field(world, 10)
  plant(world, tiles, 1)
  T.eq(Bottleneck.current(world), nil, "all watered")
  local dry = math.max(cfg.minCrops, math.ceil(#tiles * cfg.waterShare))
  plant(world, first(tiles, dry), 0)
  local limit = Bottleneck.current(world)
  T.eq(limit and limit.id, "water")
  T.eq(limit.dry, dry)
  T.eq(limit.growing, #tiles)
  plant(world, { tiles[1] }, 1)
  T.eq(Bottleneck.current(world), nil, "one fewer dry crop is under the share")
  plant(world, { tiles[1] }, 0)
  Weather.force(world, "rain")
  T.truthy(Weather.isRaining(world))
  T.eq(Bottleneck.current(world), nil, "the rain waters them")
end)

T.test("bottleneck: fewer dry crops than the minimum never make water the limit", function()
  local world = newWorld(3)
  local tiles = field(world, cfg.minCrops - 1)
  plant(world, tiles, 0)
  T.eq(Bottleneck.current(world), nil)
end)

T.test("bottleneck: labour is the limit when ripe crops and weeds wait on enough of the field", function()
  local world = newWorld(4)
  local tiles = field(world, 12)
  plant(world, tiles, 1)
  local ripe = math.max(cfg.minJobs, math.ceil(#tiles * cfg.labourShare))
  plant(world, first(tiles, ripe), 1, 1)
  local limit = Bottleneck.current(world)
  T.eq(limit and limit.id, "labour")
  T.eq(limit.ripe, ripe)
  T.eq(limit.weeds, 0)
  T.eq(limit.tiles, #tiles)
  -- weeds past the routine's pull level count as work too
  plant(world, { tiles[1] }, 1)
  T.eq(Bottleneck.current(world), nil, "one job short")
  world.state.soil.weeds[tiles[#tiles]] = tun.soil.weedPullAt
  limit = Bottleneck.current(world)
  T.eq(limit and limit.id, "labour")
  T.eq(limit.weeds, 1)
end)

T.test("bottleneck: a ripe crop held back by a full store is storage's, not labour's", function()
  local world = newWorld(5)
  local tiles = field(world, 8)
  plant(world, tiles, 1, 1)
  T.eq(Bottleneck.current(world).id, "labour")
  Ledger.setCapacity(world, "radish", 4)
  Ledger.add(world, "radish", 4)
  local limit = Bottleneck.current(world)
  T.eq(limit and limit.id, "storage", "the harvest waits on room")
  T.eq(limit.resource, "radish")
  T.eq(limit.name, "Radish")
  T.eq(limit.capacity, 4)
end)

T.test("bottleneck: a full woodpile is the storage limit; seeds and supplies are not", function()
  local world = newWorld(6)
  Ledger.add(world, "fuel", Ledger.capacity(world, "fuel"))
  T.eq(Bottleneck.current(world), nil, "a full fuel can is a supply, not a store the homestead fills")
  Ledger.add(world, "wood", Ledger.capacity(world, "wood"))
  local limit = Bottleneck.current(world)
  T.eq(limit and limit.id, "storage")
  T.eq(limit.resource, "wood")
end)

T.test("bottleneck: a sink tier short today is the power limit; the charging tiers are not", function()
  local world = newWorld(7)
  local today = Calendar.now(world).day
  world.state.power.warned.bank = today
  world.state.power.warned.truck = today
  T.eq(Bottleneck.current(world), nil, "batteries filling slowly is not a shortage")
  world.state.power.warned.pumps = today - 1
  T.eq(Bottleneck.current(world), nil, "yesterday's shortage is over")
  world.state.power.warned.pumps = today
  local limit = Bottleneck.current(world)
  T.eq(limit and limit.id, "power")
  T.eq(limit.tier, "pumps")
  T.eq(limit.name, tun.power.tierNames.pumps)
end)

T.test("bottleneck: spare produce past a truckload, or a tired town price, is the market limit", function()
  local world = newWorld(8)
  local cargo = Market.cargoCapacity(world)
  Ledger.add(world, "stone", cargo * 3)
  T.eq(Bottleneck.current(world), nil, "stone from clearing is not produce")
  Ledger.add(world, "potato", cargo * cfg.marketLoads + 1 + 50)
  local limit = Bottleneck.current(world)
  T.eq(limit and limit.id, "market")
  T.truthy(limit.spare >= cargo * cfg.marketLoads)
  T.eq(limit.good, nil)

  world = newWorld(9)
  Ledger.add(world, "potato", 60)
  if Market.spare(world, "potato") >= cargo * cfg.marketLoads then
    Ledger.remove(world, "potato", Market.spare(world, "potato") - cargo + 1)
  end
  T.truthy(Market.spare(world, "potato") > 0, "some potatoes are spare")
  T.eq(Bottleneck.current(world), nil, "a fresh town pays full price")
  world.state.market.sat.potato = 1000
  limit = Bottleneck.current(world)
  T.eq(limit and limit.id, "market")
  T.eq(limit.good, "potato")
  T.truthy(limit.factor < cfg.marketPrice)
end)

T.test("bottleneck: the ladder asks water before storage and lists every limit that holds", function()
  local world = newWorld(10)
  local tiles = field(world, 6)
  plant(world, tiles, 0)
  Ledger.add(world, "wood", Ledger.capacity(world, "wood"))
  T.eq(Bottleneck.current(world).id, "water")
  local ids = {}
  for _, l in ipairs(Bottleneck.all(world)) do
    ids[#ids + 1] = l.id
  end
  T.eq(table.concat(ids, ","), "water,storage")
end)

T.test("bottleneck: reading it changes nothing", function()
  local world = newWorld(11)
  plant(world, field(world, 6), 0)
  local before = require("src.core.serialize").encode(world.state)
  Bottleneck.current(world)
  Bottleneck.all(world)
  T.eq(require("src.core.serialize").encode(world.state), before)
end)

T.test("bottleneck text: each limit has a line with its figures and a hint; nothing holding is one dim line", function()
  local none = GoalText.limitRows(nil)
  T.eq(#none, 1)
  T.truthy(none[1].dim)
  local cases = {
    { id = "water", dry = 4, growing = 9 },
    { id = "labour", ripe = 3, weeds = 2, jobs = 5, tiles = 10 },
    { id = "storage", resource = "wood", name = "Wood", have = 60, capacity = 60 },
    { id = "power", tier = "pumps", name = "Pumps" },
    { id = "market", spare = 40, cargo = 20 },
    { id = "market", spare = 5, cargo = 20, good = "potato", name = "Potato", factor = 0.55 },
  }
  local want = {
    "Water: 4 of 9 crops are dry.",
    "Labour: the work is outrunning you (3 ripe crops, 2 weedy beds waiting).",
    "Storage: the wood store is full (60).",
    "Power: pumps ran short today.",
    "Market: 40 spare goods wait, more than the truck carries (20).",
    "Market: the town pays 55% for potato now.",
  }
  for n, limit in ipairs(cases) do
    local rows = GoalText.limitRows(limit)
    T.eq(#rows, 2)
    T.eq(rows[1].text, want[n])
    T.eq(rows[1].level, 1)
    T.truthy(rows[2].dim and #rows[2].text > 0, limit.id .. " has a hint")
  end
end)
