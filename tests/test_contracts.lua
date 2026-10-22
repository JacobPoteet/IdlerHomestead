-- The contracts board (D197, #372): weekly offers behind Footing, deadlines, rewards, reputation as a count, standing orders,
-- soft failure, the truck sale filling contracts with no input, and no touch on the market's saturation.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Contracts = require("src.sim.systems.contracts")
local Food = require("src.sim.systems.food")
local Footing = require("src.sim.systems.footing")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local CFG = tun.contracts
local WEEK = tun.economy.daysPerWeek

local function newWorld(footing)
  local world = World.new({ registry = reg, tuning = tun }, World.newState(1))
  world.state.footing.held = footing ~= false
  return world
end

local function setDay(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + (hour or 9) / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

local function stock(world, id, n)
  Ledger.add(world, id, n)
  Food.setKeep(world, id, 0)
end

--- Roll the board by hand on day `day` with a few goods held.
local function rolled(world, day)
  for _, id in ipairs({ "egg", "radish", "potato", "lettuce", "beans", "corn", "tomato" }) do
    stock(world, id, 1)
    Ledger.remove(world, id, 1)
  end
  setDay(world, day or 1)
  T.truthy(Contracts.roll(world))
end

local function offers(world)
  local n = 0
  for _, c in ipairs(Contracts.list(world)) do
    if not c.standing then
      n = n + 1
    end
  end
  return n
end

local function goTown(world)
  world.state.power.charge[world.state.land.truck] = tun.economy.tripCost
  T.truthy(Market.startTrip(world))
end

T.test("contracts: the content is well formed", function()
  for _, def in ipairs(reg:all("contracts")) do
    T.truthy(reg:get("resources", def.item).value, def.id .. " asks for a sellable good")
    T.truthy(def.min >= 1 and def.max >= def.min, def.id)
  end
end)

T.test("contracts: the board is closed and silent until Footing is held", function()
  local world = newWorld(false)
  T.falsy(Contracts.isOpen(world))
  setDay(world, 1)
  T.falsy(Contracts.roll(world))
  T.eq(#Contracts.list(world), 0)
  world.state.footing.held = true
  T.truthy(Contracts.isOpen(world))
  T.truthy(Contracts.roll(world), "open now")
  T.truthy(#Contracts.list(world) > 0)
end)

T.test(
  "contracts: a week offers the tuned number, deadlines inside the range, rewards from the good's value",
  function()
    local world = newWorld()
    rolled(world, 1)
    T.eq(offers(world), CFG.offersPerWeek)
    for _, c in ipairs(Contracts.list(world)) do
      local def = reg:get("contracts", c.def)
      local value = reg:get("resources", c.item).value
      T.truthy(c.amount >= def.min and c.amount <= def.max, "units in the content's range")
      if c.standing then
        T.eq(c.due - c.posted, CFG.standingDays)
      else
        T.truthy(c.due - c.posted >= CFG.deadlineMin and c.due - c.posted <= CFG.deadlineMax, "deadline 3..10 days")
      end
      T.eq(c.reward, math.floor(value * c.amount * Contracts.rewardMult(world, c.standing) + 0.5))
      T.truthy((def.minDone or 0) == 0, "nothing past reputation 0 is offered yet")
    end
  end
)

T.test("contracts: only goods the run has held are asked for", function()
  local world = newWorld()
  setDay(world, 1)
  Contracts.roll(world)
  for _, c in ipairs(Contracts.list(world)) do
    T.truthy(world.state.contracts.seen[c.item], c.item)
  end
  local bare = newWorld()
  bare.state.contracts.seen = {}
  setDay(bare, 1)
  Contracts.roll(bare)
  T.eq(#Contracts.list(bare), 0, "nothing held, nothing asked")
end)

T.test("contracts: the board rolls once a market week, on the day it turns", function()
  local world = newWorld()
  rolled(world, 1)
  local first = offers(world)
  setDay(world, 3)
  T.falsy(Contracts.roll(world), "same week")
  T.eq(offers(world), first)
  setDay(world, WEEK + 1)
  Contracts.expire(world)
  T.truthy(Contracts.roll(world))
  T.truthy(offers(world) >= CFG.offersPerWeek, "a new week of offers")
end)

T.test("contracts: a missed deadline just lapses, no penalty", function()
  local world = newWorld()
  rolled(world, 1)
  stock(world, "wood", 0)
  local money, done = Ledger.get(world, "money"), Contracts.reputation(world)
  local lapsed = 0
  world.events:on("contract.expired", function()
    lapsed = lapsed + 1
  end)
  local n = #Contracts.list(world)
  setDay(world, 1 + CFG.deadlineMax + 1)
  Contracts.expire(world)
  T.eq(#Contracts.list(world), 0)
  T.eq(lapsed, n)
  T.eq(Ledger.get(world, "money"), money, "no fine")
  T.eq(Contracts.reputation(world), done, "reputation untouched")
end)

T.test("contracts: filling pays the reward, takes the goods and counts one toward reputation", function()
  local world = newWorld()
  rolled(world, 1)
  local c = Contracts.list(world)[1]
  stock(world, c.item, c.amount + 3)
  local money = Ledger.get(world, "money")
  T.eq(Contracts.reputation(world), 0)
  local reward = Contracts.fill(world, c.id)
  T.eq(reward, c.reward)
  T.eq(Ledger.get(world, c.item), 3)
  T.eq(Ledger.get(world, "money"), money + c.reward)
  T.eq(Contracts.reputation(world), 1)
  T.eq(Contracts.find(world, c.id), nil)
  local again, why = Contracts.fill(world, c.id)
  T.eq(again, nil)
  T.eq(why, "gone")
end)

T.test("contracts: short of goods nothing moves; a kept reserve is never touched", function()
  local world = newWorld()
  rolled(world, 1)
  local c = Contracts.list(world)[1]
  stock(world, c.item, c.amount)
  Food.setKeep(world, c.item, 2)
  local reward, why, missing = Contracts.fill(world, c.id)
  T.eq(reward, nil)
  T.eq(why, "short")
  T.eq(missing, 2)
  T.eq(Ledger.get(world, c.item), c.amount)
  T.eq(Contracts.reputation(world), 0)
end)

T.test("contracts: reputation (a count) raises the pay and opens richer goods, up to a cap", function()
  local world = newWorld()
  local base = Contracts.rewardMult(world, false)
  world.state.contracts.done = 4
  T.near(Contracts.rewardMult(world, false), base + 4 * CFG.rewardPerDone, 1e-9)
  world.state.contracts.done = CFG.doneCap + 20
  T.near(Contracts.rewardMult(world, false), base + CFG.doneCap * CFG.rewardPerDone, 1e-9, "capped")
  -- richer goods: with enough finished, a minDone good can be posted
  local rich = newWorld()
  rich.state.contracts.done = 5
  rich.state.contracts.seen = { cheese = true }
  setDay(rich, 1)
  Contracts.roll(rich)
  local found
  for _, c in ipairs(Contracts.list(rich)) do
    found = found or c.item == "cheese"
  end
  T.truthy(found, "cheese is offered at five contracts finished")
  local poor = newWorld()
  poor.state.contracts.seen = { cheese = true }
  setDay(poor, 1)
  Contracts.roll(poor)
  T.eq(#Contracts.list(poor), 0, "and not before")
end)

T.test("contracts: a standing order renews on its own cadence, filled early or lapsed", function()
  local world = newWorld()
  rolled(world, 1)
  local standing
  for _, c in ipairs(Contracts.list(world)) do
    standing = standing or (c.standing and c)
  end
  T.truthy(standing, "a standing order is posted for a held good")
  stock(world, standing.item, standing.amount)
  T.truthy(Contracts.fill(world, standing.id))
  setDay(world, 3)
  Contracts.rollStanding(world)
  T.eq(Contracts.promised(world, standing.item), 0, "not again before its week is out")
  setDay(world, 1 + CFG.standingDays)
  Contracts.rollStanding(world)
  T.truthy(Contracts.promised(world, standing.item) > 0, "a new one a week after the last")
end)

T.test("contracts: no new offers while Footing is slipped, an open one can still be filled", function()
  local world = newWorld()
  rolled(world, 1)
  local c = Contracts.list(world)[1]
  world.state.footing.slipped = true
  setDay(world, WEEK + 1)
  Contracts.roll(world)
  Contracts.rollStanding(world)
  for _, open in ipairs(Contracts.list(world)) do
    T.truthy(open.posted == 1, "nothing new was posted")
  end
  stock(world, c.item, c.amount)
  T.truthy(Contracts.fill(world, c.id), "slipped does not close the board")
  world.state.footing.slipped = false
  T.truthy(Contracts.roll(world), "offers return when steady")
end)

T.test("contracts: the truck sale fills what the surplus covers, with no input, and leaves saturation alone", function()
  local world = newWorld()
  world.state.market.prices = {}
  rolled(world, 1)
  local c
  for _, open in ipairs(Contracts.list(world)) do
    c = c or (reg:get("resources", open.item).value and Footing.held(world) and open)
  end
  stock(world, c.item, c.amount + 4)
  Market.setLoad(world, c.item, c.amount + 4)
  goTown(world)
  local money = Ledger.get(world, "money")
  Market.sellLoad(world)
  T.eq(Contracts.find(world, c.id), nil, "filled in town by the sale")
  T.eq(Contracts.reputation(world) >= 1, true)
  T.eq(Ledger.get(world, c.item), 0, "the contract took its units, the market the rest")
  T.eq(Market.saturation(world, c.item), 4, "only the four sold to the market count")
  T.truthy(Ledger.get(world, "money") >= money + c.reward)
end)

T.test("contracts: a contract takes its units from the load, never growing it into a keep target", function()
  local world = newWorld()
  world.state.market.prices = {}
  rolled(world, 1)
  local c = Contracts.list(world)[1]
  stock(world, c.item, c.amount + 10)
  Food.setKeep(world, c.item, 4)
  Market.setLoad(world, c.item, c.amount + 6)
  goTown(world)
  local filled = Market.fillContracts(world, c.id)
  T.eq(#filled, 1)
  T.eq(Ledger.get(world, c.item), 10)
  T.eq(Market.loaded(world, c.item), 6, "the load keeps what the contract did not take")
  T.eq(Market.fillContracts(newWorld(), c.id)[1], nil, "nothing is filled at home")
end)

T.test("contracts: contract money counts as sales income", function()
  local world = newWorld()
  rolled(world, 1)
  local c = Contracts.list(world)[1]
  stock(world, c.item, c.amount)
  Contracts.fill(world, c.id)
  T.eq(require("src.sim.systems.income").total(world), c.reward)
end)

T.test("contracts: the same seed posts the same board", function()
  local a, b = newWorld(), newWorld()
  rolled(a, 1)
  rolled(b, 1)
  local la, lb = Contracts.list(a), Contracts.list(b)
  T.eq(#la, #lb)
  for i = 1, #la do
    T.eq(la[i].def, lb[i].def)
    T.eq(la[i].amount, lb[i].amount)
    T.eq(la[i].due, lb[i].due)
  end
end)
