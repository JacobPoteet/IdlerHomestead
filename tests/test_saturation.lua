-- Market saturation (D196, PLAN_DEPTH 9.1): the town's demand for a good is shared by the truck and the stand;
-- a monoculture load earns less than a mixed one, demand recovers by the day, and market day pays more.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Food = require("src.sim.systems.food")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Stand = require("src.sim.systems.stand")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate
local DPS = tun.time.daysPerSeason
local SAT = tun.economy.saturation
local CARGO = tun.economy.cargoCapacity

local function newWorld()
  local world = World.new({ registry = reg, tuning = tun }, World.newState(1))
  world.state.market.prices = {} -- plain prices
  return world
end

local function setTime(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

local function stock(world, id, n)
  Ledger.add(world, id, n)
  Food.setKeep(world, id, 0)
end

local function goTown(world)
  world.state.power.charge[world.state.land.truck] = tun.economy.tripCost
  T.truthy(Market.startTrip(world))
end

--- Load `n` of each good named and sell the truck; returns the money earned.
local function sellLoad(world, goods)
  for id, n in pairs(goods) do
    stock(world, id, n)
    Market.setLoad(world, id, n)
  end
  goTown(world)
  return Market.sellLoad(world)
end

T.test("saturation: a monoculture load earns less than a mixed one", function()
  local mono, mixed = newWorld(), newWorld()
  local n = SAT.freeUnits * 2
  local a = sellLoad(mono, { radish = CARGO })
  local b = sellLoad(mixed, { radish = n / 2, potato = n / 2 })
  local priceR, priceP = Market.sellPrice(mono, "radish"), Market.sellPrice(mono, "potato")
  T.truthy(a < CARGO * priceR, "40 radishes sell for less than the sticker")
  T.eq(b, n / 2 * priceR + n / 2 * priceP, "twelve of each good: under the saturation start, full price")
  local mono2 = newWorld()
  local c = sellLoad(mono2, { radish = n })
  T.truthy(c / (n * priceR) < b / (n / 2 * priceR + n / 2 * priceP), "the same count of one crop pays a smaller share")
end)

T.test("saturation: under freeUnits there is no cut, and the price never falls under minMult", function()
  local world = newWorld()
  T.eq(Market.satFactor(world, "radish", SAT.freeUnits), 1)
  T.eq(Market.freeUnits(world, "radish"), SAT.freeUnits)
  world.state.market.sat.radish = 1000
  T.eq(Market.satFactor(world, "radish", 5), SAT.minMult, "the floor")
  T.eq(Market.freeUnits(world, "radish"), 0)
end)

T.test("saturation: selling fills it and each morning forgets recoveryPerDay units", function()
  local world = newWorld()
  sellLoad(world, { radish = 20 })
  T.eq(Market.saturation(world, "radish"), 20)
  Market.recover(world)
  T.eq(Market.saturation(world, "radish"), 20 - SAT.recoveryPerDay)
  for _ = 1, 10 do
    Market.recover(world)
  end
  T.eq(Market.saturation(world, "radish"), 0, "back to full price")
  T.eq(world.state.market.sat.radish, nil, "and not kept in the save")
end)

T.test("saturation: a good already sold pays less on the next trip", function()
  local world = newWorld()
  local first = sellLoad(world, { radish = 20 })
  Market.endTrip(world)
  local second = sellLoad(world, { radish = 20 })
  T.truthy(second < first)
end)

T.test("saturation: auto-load mixes goods instead of loading one crop alone", function()
  local world = newWorld()
  stock(world, "radish", 60)
  stock(world, "potato", 60)
  Market.autoLoad(world)
  T.eq(Market.loadUnits(world), CARGO)
  T.truthy(Market.loaded(world, "radish") > 0 and Market.loaded(world, "potato") > 0, "both are on the truck")
  local dear = Market.sellPrice(world, "radish") > Market.sellPrice(world, "potato") and "radish" or "potato"
  T.truthy(Market.loaded(world, dear) < CARGO, "the dearer one does not take every place")
end)

T.test("saturation: the stand and the truck share the town's demand", function()
  local world = newWorld()
  local spot
  for i = 1, #world.state.grid.terrain do
    if Inventory.canPlace(world, "roadside_stand", i) then
      spot = i
      break
    end
  end
  Inventory.addObject(world, "roadside_stand")
  T.truthy(Inventory.place(world, "roadside_stand", spot))
  T.truthy(Grid.anchorsWith(world, "stand")[1])
  setTime(world, DPS + 1, tun.stand.sellHour + 0.25)
  world.state.weather.sky.days[1] = "clear"
  stock(world, "radish", 6)
  world:tick(STEP)
  T.eq(Stand.last(world).units, 6)
  T.eq(Market.saturation(world, "radish"), 6, "stand sales count toward the town's demand")
  T.eq(Market.freeUnits(world, "radish"), SAT.freeUnits - 6)
end)

T.test("market day: the last day of a season pays the truck more and doubles the stand", function()
  local world = newWorld()
  setTime(world, DPS - 1, 9)
  T.falsy(Market.isMarketDay(world))
  local plain = Stand.todayCap(world)
  setTime(world, DPS, 9)
  T.truthy(Market.isMarketDay(world))
  T.eq(Stand.todayCap(world), plain * tun.economy.marketDay.standTrafficMult)
  stock(world, "radish", 5)
  Market.setLoad(world, "radish", 5)
  local _, onDay = Market.loadQuote(world)
  setTime(world, DPS - 1, 9)
  local _, offDay = Market.loadQuote(world)
  T.truthy(onDay > offDay)
  world.tuning.economy.marketDay.enabled = false
  setTime(world, DPS, 9)
  T.falsy(Market.isMarketDay(world), "the tuning switch")
  world.tuning.economy.marketDay.enabled = true
end)
