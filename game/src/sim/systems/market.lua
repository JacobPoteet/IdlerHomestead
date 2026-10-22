-- Market (GDD §6.3–6.5): catalog orders with next-morning delivery, weekly prices and specials,
-- and truck trips to town to sell the truck load and buy pickup-only items.
--
-- The truck load (D75, #196; replaces the sell crate of D31): before driving, the player loads the
-- truck with surplus goods (Food.surplus) up to its cargo capacity (tuning.economy.cargoCapacity plus
-- `cargo` modifiers of owned equipment, counted in plain units). Like the crate it is a count reserved
-- on ledger stock, so loaded goods stay at home, edible, aging and spoiling oldest first (D73) until
-- they are sold; a sale removes them oldest batch first. Loading below a keep target is refused unless
-- confirmed (the reserve guard). In town, Sell the load sells exactly what is loaded; everything else
-- stays home. Loaded goods are not offered at the roadside stand.
--
-- Saturation (D196, PLAN_DEPTH 9.1): the town's demand for each good is shared by the truck and the stand.
-- `sat[id]` is the units sold lately; past tuning.economy.saturation.freeUnits each unit sold takes `step` off
-- the price (never under `minMult`), and `recoveryPerDay` units are forgotten every morning. A load is priced
-- unit by unit, so one crop in bulk earns less than a mix, and Auto-load picks the best next unit, so it mixes.
-- Market day (D196, PLAN_DEPTH 9.4): on the last day of a season the truck pays `marketDay.truckPriceMult`
-- more (the stand's traffic is doubled in stand.lua); `marketDay.enabled` switches it off.
--
-- State: world.state.market = { orders = { { item, arriveDay } }, prices = { [resourceId] = mult },
--                               specials = { [catalogId] = true }, week, inTown, load = { [id] = n },
--                               sat = { [id] = units } }
-- Emits "market.ordered" { item }, "market.delivered" { item }, "market.sold" { earnings, units },
--       "market.trip" {}, "market.tripReady" {} (the truck's charge reached a full trip's worth),
--       "market.held" { item } (once per order, when a due delivery is waiting
--       for storage room; the order stays queued and is retried every tick),
--       "market.cancelled" { item, amount } (player cancelled a held order, refunded),
--       "market.refunded" { item, amount } (an order that could never fit its store, refunded).
-- Orders: { item, arriveDay, paid (money charged), held (due but no room) }.
-- Contracts (D197): the truck sale first fills the open contracts from the surplus (Market.fillContracts), so the default Auto-load
-- trip serves the board with no input; a contract's goods are not sold to the market.
-- Debug cheat mode (D126): `world.debugCheat` (a runtime flag, never saved) lists every catalog item and makes
-- Market.debugGrant hand an item over free and at once; it spends and earns nothing and emits no sale event.

local Calendar = require("src.sim.systems.calendar")
local Contracts = require("src.sim.systems.contracts")
local Ledger = require("src.sim.systems.ledger")
local Food = require("src.sim.systems.food")
local Footing = require("src.sim.systems.footing")
local Inventory = require("src.sim.systems.inventory")
local Journal = require("src.sim.systems.journal")
local Land = require("src.sim.systems.land")
local Power = require("src.sim.systems.power")
local Quality = require("src.sim.systems.quality")
local Sandbox = require("src.sim.systems.sandbox")
local Spoilage = require("src.sim.systems.spoilage")
local Stats = require("src.sim.stats")

local Market = {}

--- Is the item in the catalog? Starter items, plus everything learned in the Field Journal.
function Market.isKnown(world, id)
  return Journal.isKnown(world, id)
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
    state.market = { orders = {}, prices = {}, specials = {}, week = 1, inTown = false, load = {}, sat = {} }
    Market.rollWeek(world)
  end
  state.market.sat = state.market.sat or {}
  world.events:on("ledger.changed", function(e)
    -- Eating, spoiling or the stand can leave less stock than is loaded: the load follows the stock.
    local load = state.market.load
    if load[e.id] and load[e.id] > e.total then
      load[e.id] = e.total > 0 and e.total or nil
    end
  end)
  world.events:on("calendar.newDay", function(e)
    Market.recover(world)
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

--- Sale price of one unit of a resource at a quality tier this week (D182). Normal is the whole-dollar `sellPrice`; a
--- better tier is the unrounded price times the tier's multiplier (never under the normal price), so a $1 radish is worth
--- $1.25 or $1.60 and a line of units rounds once, in `Market.worth`, instead of every unit rounding the bonus away.
function Market.tierPrice(world, id, tier)
  local res = world.registry:get("resources", id)
  if not res.value then
    return 0
  end
  local normal = Market.sellPrice(world, id)
  if tier == world.tuning.quality.tiers[1] then
    return normal
  end
  local mult = world.tuning.quality.priceMult[tier]
  return math.max(normal, res.value * (world.state.market.prices[id] or 1) * mult)
end

--- What `n` units of a resource sell for, best (a truck sale) or worst (the stand) units first, each at its tier's
--- price, rounded once to whole dollars: returns the money and the tiers taken ({ [tier] = units }).
function Market.worth(world, id, n, order)
  local picked = Quality.pick(world, id, n, order)
  local total = 0
  for tier, units in pairs(picked) do
    total = total + units * Market.tierPrice(world, id, tier)
  end
  return math.floor(total + 0.5), picked
end

-- Saturation and market day ----------------------------------------------------------------------------

--- Price multiplier (0..1) for the next unit of a good when `sat` units have been sold lately.
local function satMult(world, sat)
  local cfg = world.tuning.economy.saturation
  return math.max(cfg.minMult, 1 - cfg.step * math.max(0, sat - cfg.freeUnits))
end

--- Units of a good sold lately (the town's saturation, shared by truck and stand).
function Market.saturation(world, id)
  return world.state.market.sat[id] or 0
end

--- Units of a good the town still takes at full price: where the price starts dropping.
function Market.freeUnits(world, id)
  return math.max(0, math.floor(world.tuning.economy.saturation.freeUnits - Market.saturation(world, id)))
end

--- Average price multiplier over the next `n` units of a good (1 when all fit under the free units).
function Market.satFactor(world, id, n)
  if n <= 0 then
    return 1
  end
  local sat = Market.saturation(world, id)
  local sum = 0
  for k = 0, n - 1 do
    sum = sum + satMult(world, sat + k)
  end
  return sum / n
end

--- Count `n` units sold of a good into the town's saturation.
function Market.addSaturation(world, id, n)
  local sat = world.state.market.sat
  sat[id] = (sat[id] or 0) + n
end

--- Each morning the town forgets some of what it was sold.
function Market.recover(world)
  local sat = world.state.market.sat
  local back = world.tuning.economy.saturation.recoveryPerDay
  for id, n in pairs(sat) do
    n = n - back
    sat[id] = n > 0 and n or nil
  end
end

--- Is today market day (the last day of the season, D196)?
function Market.isMarketDay(world)
  if not world.tuning.economy.marketDay.enabled then
    return false
  end
  return Calendar.now(world).dayOfSeason == world.tuning.time.daysPerSeason
end

function Market.itemPrice(world, id)
  local item = world.registry:get("catalog", id)
  local mult = world.state.market.specials[id] and world.tuning.economy.specialDiscount or 1
  return math.max(1, math.floor(item.price * mult + 0.5))
end

--- True if some resource in the item's `gives` is more than its store could hold even when empty
--- (counting any storage buildings now placed). Such an order could never be delivered.
function Market.neverFits(world, id)
  for res, amount in pairs(world.registry:get("catalog", id).gives or {}) do
    if amount > Ledger.capacity(world, res) then
      return true
    end
  end
  return false
end

--- The least a delivery order could cost now (price plus the delivery fee) among the items that are
--- only waiting on money, or nil when none is (the Catalog's "how do I earn" line, D88, #161).
function Market.cheapestOrder(world)
  local best
  for _, item in ipairs(world.registry:all("catalog")) do
    local reason = Market.cannotBuy(world, item.id, false)
    if reason == nil or reason == "not enough money" then
      local cost = Market.itemPrice(world, item.id) + world.tuning.economy.deliveryFee
      best = best and math.min(best, cost) or cost
    end
  end
  return best
end

--- Is cheat mode on (D126)? The debug toggle is a runtime flag on the world (not in the state, so never saved);
--- a sandbox slot (D134) is always in it.
function Market.cheatOn(world)
  return world.debugCheat == true or Sandbox.on(world)
end

--- Turn debug cheat mode on or off (D126).
function Market.setCheat(world, on)
  world.debugCheat = on and true or nil -- a sandbox slot stays in cheat mode whatever this says
end

--- The items the Catalog lists: the known ones, or every catalog item in cheat mode (D126).
function Market.catalogList(world)
  local list = {}
  local cheat = Market.cheatOn(world)
  for _, item in ipairs(world.registry:all("catalog")) do
    if cheat or Market.isKnown(world, item.id) then
      list[#list + 1] = item
    end
  end
  return list
end

--- Why an item can't be bought right now (nil if it can). pickup = buying in town. Cheat mode (D126) skips the
--- journal gate, the town-only rule and the money check, and counts as an on-the-spot handover.
function Market.cannotBuy(world, id, pickup)
  local item = world.registry:get("catalog", id)
  local cheat = Market.cheatOn(world)
  if cheat then
    pickup = true
  end
  if not cheat and not Market.isKnown(world, id) then
    return "unknown"
  end
  if item.pickupOnly and not pickup then
    return "pickup only"
  end
  -- A gated item is listed but cannot be bought until Footing is held (D164); cheat mode ignores the gate.
  if not cheat and not Footing.isOpen(world, item) then
    return "needs Footing"
  end
  -- Purchase limits (D114): equipment and `unique` items are one per run. Owned counts the inventory, the
  -- land and the orders still on their way; a better tier already owned (or on its way) makes the lower one
  -- unavailable too (D115).
  if item.equipment or item.unique then
    if Inventory.owns(world, id) then
      return "owned"
    end
    if Inventory.supersededBy(world, id) then
      return "replaced"
    end
    for _, order in ipairs(world.state.market.orders) do
      if order.item == id then
        return "ordered"
      end
      if world.registry:get("catalog", order.item).replaces == id then
        return "replaced"
      end
    end
  end
  -- Livestock need somewhere to live before they can be bought (D63): the hen store is the coop.
  for res in pairs(item.gives or {}) do
    local def = world.registry:get("resources", res)
    if def.category == "animal" and Ledger.capacity(world, res) <= 0 then
      return "needs a " .. (def.housing or "home")
    end
  end
  -- Some goods ride on other equipment: goats need the trailer (D71).
  if item.requires and not Inventory.hasEquipment(world, item.requires) then
    return "needs the " .. world.registry:get("catalog", item.requires).name:lower()
  end
  -- Goods that could never fit in their store, even empty, must not be sold (D60).
  if Market.neverFits(world, id) then
    return "too big for storage"
  end
  local cost = Market.itemPrice(world, id) + (pickup and 0 or world.tuning.economy.deliveryFee)
  if not cheat and Ledger.get(world, "money") < cost then
    return "not enough money"
  end
  -- Pickups are handed over on the spot, so they need room now; deliveries just wait for it.
  if pickup and not Ledger.canHold(world, item.gives or {}) then
    return "no room"
  end
  return nil
end

-- Hand over a purchase. All-or-nothing: if its goods don't fit in storage yet, nothing is
-- delivered and false is returned, so the caller can keep the order waiting.
local function deliver(world, id)
  local item = world.registry:get("catalog", id)
  local gives = item.gives or {}
  if not Ledger.canHold(world, gives) then
    return false
  end
  local keys = {}
  for res in pairs(gives) do
    keys[#keys + 1] = res
  end
  table.sort(keys)
  for _, res in ipairs(keys) do
    Ledger.add(world, res, gives[res], "delivery")
  end
  if item.object then
    Inventory.addObject(world, item.object)
  end
  if item.equipment then
    Inventory.addEquipment(world, id)
  end
  world.events:emit("market.delivered", { item = id })
  return true
end

--- Debug cheat (D126): hand `id` over free and at once, as a delivery would (storage limits, unique items and
--- upgrade chains behave as for a purchase). No money moves, so the income stats and sale events stay untouched.
--- Returns true, or false + the reason. Only works while cheat mode is on.
function Market.debugGrant(world, id)
  if not Market.cheatOn(world) then
    return false, "cheat off"
  end
  local reason = Market.cannotBuy(world, id, true)
  if reason then
    return false, reason
  end
  deliver(world, id)
  return true
end

--- Order from the catalog for delivery tomorrow morning. Returns true, or false + reason.
function Market.order(world, id)
  if Market.cheatOn(world) then
    return Market.debugGrant(world, id) -- free and at once (D126)
  end
  local reason = Market.cannotBuy(world, id, false)
  if reason then
    return false, reason
  end
  local paid = Market.itemPrice(world, id) + world.tuning.economy.deliveryFee
  Ledger.remove(world, "money", paid, "order")
  local orders = world.state.market.orders
  orders[#orders + 1] = { item = id, arriveDay = Calendar.now(world).day + 1, paid = paid }
  world.events:emit("market.ordered", { item = id })
  return true
end

-- Take order `index` off the list and give back what it cost.
local function refund(world, index, event)
  local orders = world.state.market.orders
  local order = table.remove(orders, index)
  local amount = order.paid
  Ledger.add(world, "money", amount, "refund")
  world.events:emit(event, { item = order.item, amount = amount })
  return amount
end

--- Paid orders that are due but waiting for storage room: list of { index, item, paid }.
function Market.heldOrders(world)
  local list = {}
  for index, order in ipairs(world.state.market.orders) do
    if order.held then
      list[#list + 1] = {
        index = index,
        item = order.item,
        paid = order.paid,
      }
    end
  end
  return list
end

--- Cancel a held order (one that is due but waiting for room) for a full refund. Returns the
--- refund, or nil if that order is not held. Emits "market.cancelled" { item, amount }.
function Market.cancelHeld(world, index)
  local order = world.state.market.orders[index]
  if not order or not order.held then
    return nil
  end
  return refund(world, index, "market.cancelled")
end

-- Emits "market.tripReady" {} each time the truck's charge climbs to a full trip (the edge, never
-- while it merely stays ready, and not for a truck that starts ready).
local function watchTripReady(world)
  local m = world.state.market
  local ready = Market.canTrip(world)
  local was = m.tripReady
  m.tripReady = ready
  if ready and was == false and not m.inTown then
    world.events:emit("market.tripReady", {})
  end
end

function Market.tick(world)
  watchTripReady(world)
  local orders = world.state.market.orders
  if #orders == 0 then
    return
  end
  local now = Calendar.now(world)
  local i = 1
  while i <= #orders do
    local order = orders[i]
    if now.day > order.arriveDay or (now.day == order.arriveDay and now.hour >= world.tuning.economy.deliveryHour) then
      if Market.neverFits(world, order.item) then
        -- Can never be delivered (the store is smaller than the order): give the money back.
        refund(world, i, "market.refunded")
      elseif deliver(world, order.item) then
        table.remove(orders, i)
      else
        -- No room yet: the order (already paid) stays on the truck's list and retries every tick.
        if not order.held then
          order.held = true
          world.events:emit("market.held", { item = order.item })
        end
        i = i + 1
      end
    else
      i = i + 1
    end
  end
end

-- Truck trips --------------------------------------------------------------------------

function Market.truckCharge(world)
  return Power.charge(world, Land.truck(world))
end

function Market.canTrip(world)
  return Market.truckCharge(world) >= world.tuning.economy.tripCost
end

--- The truck's readiness for a trip, for the home panel and the HUD (D72, #162): { ready, charge, cost,
--- capacity (kWh), hours (in-game hours to a full trip's charge at the current net rate: 0 when ready,
--- nil when the truck is not charging), units and value ($) of the truck load, cargo (units),
--- spare (surplus units not loaded yet) }.
function Market.tripStatus(world)
  local econ = world.tuning.economy
  local truck = Land.truck(world)
  local _, value, units = Market.loadQuote(world)
  return {
    ready = Market.canTrip(world),
    charge = Power.charge(world, truck),
    cost = econ.tripCost,
    capacity = Power.capacity(world, truck),
    hours = Power.hoursToCharge(world, truck, econ.tripCost),
    units = units,
    value = value,
    cargo = Market.cargoCapacity(world),
    spare = Market.spareUnits(world),
  }
end

--- Drive to town. Uses truck charge. Returns true if the trip started.
function Market.startTrip(world)
  if world.state.market.inTown or not Market.canTrip(world) then
    return false
  end
  Power.drain(world, Land.truck(world), world.tuning.economy.tripCost)
  world.state.market.inTown = true
  world.events:emit("market.trip", {})
  return true
end

function Market.endTrip(world)
  world.state.market.inTown = false
end

-- The truck load (D75) ------------------------------------------------------------------------------

--- Units of goods the truck carries to town: the tuning base plus `cargo` equipment modifiers.
function Market.cargoCapacity(world)
  return world.tuning.economy.cargoCapacity + Stats.modifier(world, "cargo")
end

--- Units of a resource loaded on the truck.
function Market.loaded(world, id)
  return world.state.market.load[id] or 0
end

--- Units loaded in all.
function Market.loadUnits(world)
  local n = 0
  for _, count in pairs(world.state.market.load) do
    n = n + count
  end
  return n
end

--- Cargo still free.
function Market.cargoLeft(world)
  return math.max(0, Market.cargoCapacity(world) - Market.loadUnits(world))
end

--- Surplus units of a resource not on the truck yet (what Auto-load and "All" may take).
function Market.spare(world, id)
  return math.max(0, Food.surplus(world, id) - Market.loaded(world, id))
end

--- Surplus units of every good not on the truck yet, in all.
function Market.spareUnits(world)
  local surplus = Food.surpluses(world)
  local n = 0
  for id, units in pairs(surplus) do
    n = n + math.max(0, units - Market.loaded(world, id))
  end
  return n
end

--- The reserve guard: would loading `units` of `id` dig into its keep target? Returns nil when the
--- load stays within surplus (or does not grow), else { id, units, below (units under the keep),
--- keep, kind = "fuel" | "food" | "stock" } for the confirmation the UI asks.
function Market.loadWarning(world, id, units)
  local surplus = Food.surplus(world, id)
  if units <= surplus or units <= Market.loaded(world, id) then
    return nil
  end
  local res = world.registry:get("resources", id)
  local kind = "stock"
  if res.heat then
    kind = "fuel"
  elseif res.calories then
    kind = "food"
  end
  return { id = id, units = units, below = units - surplus, keep = (Food.keep(world, id)), kind = kind }
end

--- Set the units of a resource loaded on the truck. The amount is clamped to the stock and to the cargo
--- left. Loading into the keep target needs `confirmed` (see Market.loadWarning). Returns the units
--- now loaded, plus a reason when the request was cut or refused: "in town" (the goods are at home),
--- "not sellable", "reserve" (unconfirmed, nothing changed), "cargo full", "stock".
function Market.setLoad(world, id, units, confirmed)
  local m = world.state.market
  local before = Market.loaded(world, id)
  if m.inTown then
    return before, "in town"
  end
  if not Food.sellable(world, id) then
    return before, "not sellable"
  end
  local reason
  units = math.max(0, math.floor(units))
  local stock = Ledger.get(world, id)
  if units > stock then
    units, reason = stock, "stock"
  end
  local most = before + Market.cargoLeft(world)
  if units > most then
    units, reason = most, "cargo full"
  end
  if not confirmed and Market.loadWarning(world, id, units) then
    return before, "reserve"
  end
  m.load[id] = units > 0 and units or nil
  return units, reason
end

--- Empty the truck (the goods stay home).
function Market.clearLoad(world)
  world.state.market.load = {}
end

--- Auto-load: fill the free cargo with spare surplus one unit at a time, always the unit that would sell
--- for the most now (saturation counted, D196, so a big crop is not loaded alone), then the food that spoils
--- soonest, then content order. Never loads into a keep target. Returns the units added.
function Market.autoLoad(world)
  if world.state.market.inTown then
    return 0
  end
  local surplus = Food.surpluses(world)
  local list = {}
  for index, res in ipairs(world.registry:all("resources")) do
    local spare = (surplus[res.id] or 0) - Market.loaded(world, res.id)
    if spare > 0 then
      local info = Spoilage.info(world, res.id)
      list[#list + 1] = {
        id = res.id,
        spare = spare,
        base = Market.sellPrice(world, res.id),
        sat = Market.saturation(world, res.id) + Market.loaded(world, res.id),
        days = info and info.daysLeft or math.huge,
        index = index,
      }
    end
  end
  local function better(a, b)
    if a.price ~= b.price then
      return a.price > b.price
    end
    if a.days ~= b.days then
      return a.days < b.days
    end
    return a.index < b.index
  end
  local added = 0
  while Market.cargoLeft(world) > 0 do
    local best
    for _, entry in ipairs(list) do
      if entry.spare > 0 then
        entry.price = entry.base * satMult(world, entry.sat)
        if not best or better(entry, best) then
          best = entry
        end
      end
    end
    if not best then
      break
    end
    best.spare, best.sat = best.spare - 1, best.sat + 1
    world.state.market.load[best.id] = Market.loaded(world, best.id) + 1
    added = added + 1
  end
  return added
end

--- What selling the load would do: list of { id, units, price, worth, tiers } in content order, total $, units. The best
--- units of a good are the ones sold (D182): `price` is the normal unit price, `worth` what the line pays with its tiers, saturation and market day,
--- `factor` the price multiplier on the line (under 1 when the town is saturated),
--- `tiers` the units at each tier.
function Market.loadQuote(world)
  local lines, total, units = {}, 0, 0
  for _, res in ipairs(world.registry:all("resources")) do
    local n = math.min(Market.loaded(world, res.id), Ledger.get(world, res.id))
    if n > 0 then
      local worth, tiers = Market.worth(world, res.id, n, "best")
      local factor = Market.satFactor(world, res.id, n)
      if Market.isMarketDay(world) then
        factor = factor * world.tuning.economy.marketDay.truckPriceMult
      end
      worth = math.floor(worth * factor + 0.5)
      lines[#lines + 1] = {
        id = res.id,
        units = n,
        price = Market.sellPrice(world, res.id),
        worth = worth,
        tiers = tiers,
        factor = factor,
      }
      total = total + worth
      units = units + n
    end
  end
  return lines, total, units
end

--- Fill contracts in town (D197): open contract `id`, or every one the surplus covers when `id` is nil. The goods come
--- off the surplus, and what a contract takes comes off the load too, so the load never grows into a keep target.
--- Returns the list of { item, amount, reward } filled (empty at home, or when nothing could be).
function Market.fillContracts(world, id)
  local m = world.state.market
  if not m.inTown then
    return {}
  end
  local before = {}
  for good, n in pairs(m.load) do
    before[good] = n
  end
  local filled = {}
  if id then
    local c = Contracts.find(world, id)
    local reward = c and Contracts.fill(world, id)
    if reward then
      filled[1] = { item = c.item, amount = c.amount, reward = reward }
    end
  else
    filled = Contracts.fillAll(world)
  end
  for _, f in ipairs(filled) do
    before[f.item] = before[f.item] and math.max(0, before[f.item] - f.amount) or nil
  end
  for good, n in pairs(before) do
    local left = math.min(n, Ledger.get(world, good))
    m.load[good] = left > 0 and left or nil
  end
  return filled
end

--- Sell the truck load (in town). Returns money earned. Everything not loaded stays home. Open contracts are filled first
--- (D197): they pay above the market and put nothing into its saturation.
function Market.sellLoad(world)
  if not world.state.market.inTown then
    return 0
  end
  Market.fillContracts(world)
  local lines, total, units = Market.loadQuote(world)
  for _, line in ipairs(lines) do
    Quality.take(world, line.id, line.units, "best") -- the best units go to town; the ledger then drops the count
    Ledger.remove(world, line.id, line.units, "sold")
    Market.addSaturation(world, line.id, line.units)
  end
  Market.clearLoad(world)
  if units == 0 then
    return 0
  end
  Ledger.add(world, "money", total, "sold")
  world.events:emit("market.sold", { earnings = total, units = units })
  return total
end

--- Buy in town: no delivery fee, pickup-only items allowed, applied immediately.
function Market.buyInTown(world, id)
  if not world.state.market.inTown then
    return false, "not in town"
  end
  if Market.cheatOn(world) then
    return Market.debugGrant(world, id)
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
