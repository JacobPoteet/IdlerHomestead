-- Roadside stand (GDD §6.4, D52): a placed stand sells up to a daily cap of goods from the sell
-- crate on its own, at a fraction of the town price. The truck trip stays the big payday.
--
-- The cap is tuning.stand.baseCap plus the `standCap` modifiers of owned upgrades (catalog
-- equipment), never above tuning.stand.maxCap, scaled down by season and weather. Cheapest goods
-- go first so the valuable ones wait for the truck. One stand counts; extra ones add nothing.
--
-- State: world.state.stand = { lastDay = day of the last sale run,
--                              last = { day, units, earned, cap } or nil, total = { units, earned } }
-- Emits "stand.sold" { day, units, earned, cap } (only when something sold).

local Calendar = require("src.sim.systems.calendar")
local Food = require("src.sim.systems.food")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Stats = require("src.sim.stats")
local Weather = require("src.sim.systems.weather")

local Stand = {}

function Stand.init(world)
  local state = world.state
  state.stand = state.stand or { lastDay = 0 }
  state.stand.total = state.stand.total or { units = 0, earned = 0 }
end

--- Is a stand placed on the homestead?
function Stand.isOpen(world)
  for _, obj in pairs(world.state.grid.objects) do
    if world.registry:get("objects", obj.id).stand then
      return true
    end
  end
  return false
end

--- Items per day the stand can sell at best (upgrades included, weather and season not).
function Stand.cap(world)
  local cfg = world.tuning.stand
  return math.min(cfg.maxCap, cfg.baseCap + Stats.modifier(world, "standCap"))
end

--- Today's cap after season and weather.
function Stand.todayCap(world)
  local cfg = world.tuning.stand
  local flow = cfg.seasonFlow[Calendar.now(world).season] * cfg.weatherFlow[Weather.kind(world)]
  return math.floor(Stand.cap(world) * flow + 0.5)
end

--- What the stand pays for one unit of a resource (fractional dollars).
function Stand.unitPrice(world, id)
  return Market.sellPrice(world, id) * world.tuning.stand.priceFraction
end

--- The last sale { day, units, earned, cap }, or nil before the first one.
function Stand.last(world)
  return world.state.stand.last
end

--- Lifetime { units, earned } sold at the stand this run.
function Stand.total(world)
  return world.state.stand.total
end

-- Crate goods in selling order: cheapest town price first, then registry order.
local function sellingOrder(world)
  local list = {}
  for index, res in ipairs(world.registry:all("resources")) do
    if Food.crateOf(world, res.id) > 0 then
      list[#list + 1] = { id = res.id, price = Market.sellPrice(world, res.id), index = index }
    end
  end
  table.sort(list, function(a, b)
    if a.price ~= b.price then
      return a.price < b.price
    end
    return a.index < b.index
  end)
  return list
end

--- Run one day's sale now. Returns units sold, money earned.
function Stand.sell(world)
  local state = world.state.stand
  local now = Calendar.now(world)
  state.lastDay = now.day
  local cap = Stand.todayCap(world)
  local units, raw = 0, 0
  local taken = {}
  for _, entry in ipairs(sellingOrder(world)) do
    local n = math.min(Food.crateOf(world, entry.id), cap - units)
    if n > 0 then
      taken[#taken + 1] = { id = entry.id, n = n }
      raw = raw + n * Stand.unitPrice(world, entry.id)
      units = units + n
    end
  end
  if units == 0 then
    return 0, 0
  end
  for _, line in ipairs(taken) do
    Ledger.remove(world, line.id, line.n, "stand")
  end
  local earned = math.floor(raw + 0.5)
  Ledger.add(world, "money", earned, "stand")
  Food.sort(world)
  state.last = { day = now.day, units = units, earned = earned, cap = cap }
  state.total.units = state.total.units + units
  state.total.earned = state.total.earned + earned
  world.events:emit("stand.sold", { day = now.day, units = units, earned = earned, cap = cap })
  return units, earned
end

function Stand.tick(world)
  local now = Calendar.now(world)
  if now.hour >= world.tuning.stand.sellHour and world.state.stand.lastDay < now.day and Stand.isOpen(world) then
    Stand.sell(world)
  end
end

return Stand
