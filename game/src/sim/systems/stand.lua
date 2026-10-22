-- Roadside stand (GDD §6.4, D52, D75): a placed stand sells up to a daily cap of surplus goods (stock
-- above its keep target, Food.surplus) on its own, at a fraction of the town price. Goods loaded on the
-- truck and goods pinned "not at the stand" (D62) are left alone. The truck trip stays the big payday.
--
-- The cap is tuning.stand.baseCap plus the `standCap` modifiers of owned upgrades (catalog
-- equipment), never above tuning.stand.maxCap, scaled down by season and weather. Cheapest goods
-- go first so the valuable ones wait for the truck. One stand counts; extra ones add nothing.
--
-- The stand shares the town's demand with the truck (D196, see market.lua): units it sells count toward each
-- good's saturation and its price follows. Market day (last day of a season) multiplies its cap. The stand
-- needs no input: cheapest-first plus the "not at the stand" pin is the whole control (#106, D196).
--
-- State: world.state.stand = { lastDay = day of the last sale run,
--                              last = { day, units, earned, cap } or nil, total = { units, earned } }
-- Emits "stand.sold" { day, units, earned, cap } (only when something sold).

local Calendar = require("src.sim.systems.calendar")
local Food = require("src.sim.systems.food")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Quality = require("src.sim.systems.quality")
local Spoilage = require("src.sim.systems.spoilage")
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
  return #Grid.anchorsWith(world, "stand") > 0
end

--- Items per day the stand can sell at best (upgrades included, weather and season not).
function Stand.cap(world)
  local cfg = world.tuning.stand
  return math.min(cfg.maxCap, cfg.baseCap + Stats.modifier(world, "standCap"))
end

--- The stand's tiers (D116): the catalog equipment whose `upgrades` names the stand, in catalog order, as a list
--- of { id, name, owned }. The stand is one fixed building; owning a tier changes how it looks (the item's
--- `overlay` sprite, drawn by the renderer) and raises its cap (the `standCap` modifier).
function Stand.tiers(world)
  local list = {}
  for _, item in ipairs(world.registry:all("catalog")) do
    if item.upgrades then
      list[#list + 1] = { id = item.id, name = item.name, owned = Inventory.hasEquipment(world, item.id) }
    end
  end
  return list
end

--- Today's cap after season and weather.
function Stand.todayCap(world)
  local cfg = world.tuning.stand
  local flow = cfg.seasonFlow[Calendar.now(world).season] * cfg.weatherFlow[Weather.kind(world)]
  local day = Market.isMarketDay(world) and world.tuning.economy.marketDay.standTrafficMult or 1
  return math.floor(Stand.cap(world) * flow * day + 0.5)
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

--- Units of a good the stand may sell: its surplus (Food.surplus) less what is loaded on the truck,
--- or 0 for goods pinned "not at the stand" (D62).
function Stand.forSale(world, id)
  if Food.truckOnly(world, id) then
    return 0
  end
  return math.max(0, Food.surplus(world, id) - Market.loaded(world, id))
end

-- Surplus goods in selling order: cheapest town price first, then the food that spoils soonest, then
-- registry order (D75). Goods pinned "not at the stand" and units loaded on the truck are skipped.
local function sellingOrder(world)
  local surplus = Food.surpluses(world)
  local list = {}
  for index, res in ipairs(world.registry:all("resources")) do
    local n = (surplus[res.id] or 0) - Market.loaded(world, res.id)
    if n > 0 and not Food.truckOnly(world, res.id) then
      local info = Spoilage.info(world, res.id)
      list[#list + 1] = {
        id = res.id,
        n = n,
        price = Market.sellPrice(world, res.id),
        days = info and info.daysLeft or math.huge,
        index = index,
      }
    end
  end
  table.sort(list, function(a, b)
    if a.price ~= b.price then
      return a.price < b.price
    end
    if a.days ~= b.days then
      return a.days < b.days
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
    local n = math.min(entry.n, cap - units)
    if n > 0 then
      taken[#taken + 1] = { id = entry.id, n = n }
      -- the stand sells the worst units (the ledger drops them first) at the tier's price (D182)
      raw = raw
        + Stand.unitPrice(world, entry.id)
          * Quality.worth(world, entry.id, n, "worst")
          * Market.satFactor(world, entry.id, n)
      units = units + n
    end
  end
  if units == 0 then
    return 0, 0
  end
  for _, line in ipairs(taken) do
    Ledger.remove(world, line.id, line.n, "stand")
    Market.addSaturation(world, line.id, line.n)
  end
  local earned = math.floor(raw + 0.5)
  Ledger.add(world, "money", earned, "stand")
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
