-- Market (GDD §6.3–6.5): catalog orders with next-morning delivery, weekly prices and specials,
-- and truck trips to town to sell the crate and buy pickup-only items.
--
-- State: world.state.market = { orders = { { item, arriveDay } }, prices = { [resourceId] = mult },
--                               specials = { [catalogId] = true }, week, inTown }
-- Emits "market.ordered" { item }, "market.delivered" { item }, "market.sold" { earnings, units },
--       "market.trip" {}.

local Calendar = require("src.sim.systems.calendar")
local Ledger = require("src.sim.systems.ledger")
local Food = require("src.sim.systems.food")
local Inventory = require("src.sim.systems.inventory")
local Power = require("src.sim.systems.power")

local Market = {}

--- Is the item in the catalog for this run? (M3: also items learned in the Field Journal.)
function Market.isKnown(world, id)
  return world.registry:get("catalog", id).starter == true
end

function Market.rollWeek(world)
  local cfg = world.tuning.economy
  local rng = world:rng("market")
  local m = world.state.market
  m.prices = {}
  for _, res in ipairs(world.registry:all("resources")) do
    if res.value then
      m.prices[res.id] = math.floor(rng:range(cfg.priceDriftMin, cfg.priceDriftMax) * 100 + 0.5) / 100
    end
  end
  m.specials = {}
  local pool = {}
  for _, item in ipairs(world.registry:all("catalog")) do
    if Market.isKnown(world, item.id) then
      pool[#pool + 1] = item.id
    end
  end
  rng:shuffle(pool)
  for n = 1, math.min(cfg.specialsPerWeek, #pool) do
    m.specials[pool[n]] = true
  end
end

local function weekOf(world, day)
  return math.floor((day - 1) / world.tuning.economy.daysPerWeek) + 1
end

function Market.init(world)
  local state = world.state
  if not state.market then
    state.market = { orders = {}, prices = {}, specials = {}, week = 1, inTown = false }
    Market.rollWeek(world)
  end
  world.events:on("calendar.newDay", function(e)
    local w = weekOf(world, e.day)
    if w ~= state.market.week then
      state.market.week = w
      Market.rollWeek(world)
    end
  end)
end

--- Sale price of one unit of a resource this week (0 if it can't be sold).
function Market.sellPrice(world, id)
  local res = world.registry:get("resources", id)
  if not res.value then
    return 0
  end
  return math.max(1, math.floor(res.value * (world.state.market.prices[id] or 1) + 0.5))
end

function Market.itemPrice(world, id)
  local item = world.registry:get("catalog", id)
  local mult = world.state.market.specials[id] and world.tuning.economy.specialDiscount or 1
  return math.max(1, math.floor(item.price * mult + 0.5))
end

--- Why an item can't be bought right now (nil if it can). pickup = buying in town.
function Market.cannotBuy(world, id, pickup)
  local item = world.registry:get("catalog", id)
  if not Market.isKnown(world, id) then
    return "unknown"
  end
  if item.pickupOnly and not pickup then
    return "pickup only"
  end
  if item.equipment and Inventory.hasEquipment(world, id) then
    return "owned"
  end
  if item.equipment then
    for _, order in ipairs(world.state.market.orders) do
      if order.item == id then
        return "ordered"
      end
    end
  end
  local cost = Market.itemPrice(world, id) + (pickup and 0 or world.tuning.economy.deliveryFee)
  if Ledger.get(world, "money") < cost then
    return "not enough money"
  end
  return nil
end

local function deliver(world, id)
  local item = world.registry:get("catalog", id)
  local keys = {}
  for res in pairs(item.gives or {}) do
    keys[#keys + 1] = res
  end
  table.sort(keys)
  for _, res in ipairs(keys) do
    Ledger.add(world, res, item.gives[res], "delivery")
  end
  if item.object then
    Inventory.addObject(world, item.object)
  end
  if item.equipment then
    Inventory.addEquipment(world, id)
  end
  world.events:emit("market.delivered", { item = id })
end

--- Order from the catalog for delivery tomorrow morning. Returns true, or false + reason.
function Market.order(world, id)
  local reason = Market.cannotBuy(world, id, false)
  if reason then
    return false, reason
  end
  Ledger.remove(world, "money", Market.itemPrice(world, id) + world.tuning.economy.deliveryFee, "order")
  local orders = world.state.market.orders
  orders[#orders + 1] = { item = id, arriveDay = Calendar.now(world).day + 1 }
  world.events:emit("market.ordered", { item = id })
  return true
end

function Market.tick(world)
  local orders = world.state.market.orders
  if #orders == 0 then
    return
  end
  local now = Calendar.now(world)
  local i = 1
  while i <= #orders do
    local order = orders[i]
    if now.day > order.arriveDay or (now.day == order.arriveDay and now.hour >= world.tuning.economy.deliveryHour) then
      table.remove(orders, i)
      deliver(world, order.item)
    else
      i = i + 1
    end
  end
end

-- Truck trips --------------------------------------------------------------------------

function Market.truckCharge(world)
  return Power.charge(world, world.state.land.truck)
end

function Market.canTrip(world)
  return Market.truckCharge(world) >= world.tuning.economy.tripCost
end

--- Drive to town. Uses truck charge. Returns true if the trip started.
function Market.startTrip(world)
  if world.state.market.inTown or not Market.canTrip(world) then
    return false
  end
  Power.drain(world, world.state.land.truck, world.tuning.economy.tripCost)
  world.state.market.inTown = true
  world.events:emit("market.trip", {})
  return true
end

function Market.endTrip(world)
  world.state.market.inTown = false
end

--- What selling the crate would do: list of { id, units, price }, total $, units (cargo-limited).
function Market.crateQuote(world)
  local cargo = world.tuning.economy.cargoCapacity
  local lines, total, units = {}, 0, 0
  for _, res in ipairs(world.registry:all("resources")) do
    local n = math.min(world.state.food.crate[res.id] or 0, cargo - units)
    if n > 0 then
      local price = Market.sellPrice(world, res.id)
      lines[#lines + 1] = { id = res.id, units = n, price = price }
      total = total + n * price
      units = units + n
    end
  end
  return lines, total, units
end

--- Sell the crate (in town). Returns money earned.
function Market.sellCrate(world)
  if not world.state.market.inTown then
    return 0
  end
  local lines, total, units = Market.crateQuote(world)
  for _, line in ipairs(lines) do
    Ledger.remove(world, line.id, line.units, "sold")
  end
  Ledger.add(world, "money", total, "sold")
  Food.sort(world)
  world.events:emit("market.sold", { earnings = total, units = units })
  return total
end

--- Buy in town: no delivery fee, pickup-only items allowed, applied immediately.
function Market.buyInTown(world, id)
  if not world.state.market.inTown then
    return false, "not in town"
  end
  local reason = Market.cannotBuy(world, id, true)
  if reason then
    return false, reason
  end
  Ledger.remove(world, "money", Market.itemPrice(world, id), "bought")
  deliver(world, id)
  return true
end

return Market
